import Foundation

/// The private web session Trade Republic uses: phone, PIN, then confirmation in the app.
/// The PIN is not stored. A saved session is used only when a button asks for it.
struct TradeRepublicClient: Sendable {
    private let session: URLSession

    /// One cookie jar for the whole sign-in. A new session on the next call drops the cookie the confirmation needs.
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    func begin(phone: String, pin: String) async throws -> TradeRepublicChallenge {
        var request = URLRequest(url: TradeRepublicRequest.loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = TradeRepublicRequest.body(phone: TradeRepublicRequest.canonicalPhone(phone), pin: pin)
        TradeRepublicRequest.headers().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, http) = try await Self.response(for: request, session: session)
        let cookies = keptCookies(http, url: TradeRepublicRequest.loginURL)
        if http.statusCode >= 400 {
            throw TradeRepublicRequest.failure(statusCode: http.statusCode, errorCode: TradeRepublicRequest.errorCode(from: data))
                ?? .rejected
        }
        guard let parsed = TradeRepublicRequest.challenge(from: data) else {
            throw TradeRepublicFailure.unreadable
        }
        return TradeRepublicChallenge(
            processId: parsed.processId,
            countdownSeconds: parsed.countdown,
            cookies: cookies
        )
    }

    func poll(processId: String, cookies: String) async throws -> TradeRepublicPoll {
        guard let url = TradeRepublicRequest.processURL(processId) else {
            throw TradeRepublicFailure.unreadable
        }
        return try await get(url, cookies: cookies)
    }

    func submit(code: String, processId: String, cookies: String) async throws -> String {
        guard let url = TradeRepublicRequest.codeURL(processId) else {
            throw TradeRepublicFailure.unreadable
        }
        install(cookies, url: url)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = TradeRepublicRequest.codeBody(code)
        TradeRepublicRequest.headers().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, http) = try await Self.response(for: request, session: session)
        let kept = keptCookies(http, url: url, previous: cookies)
        if http.statusCode >= 400 {
            throw TradeRepublicRequest.failure(
                statusCode: http.statusCode,
                errorCode: TradeRepublicRequest.errorCode(from: data),
                duringProcess: true
            ) ?? .invalidCode
        }
        return kept
    }

    func snapshot(cookies: String) async throws -> TradeRepublicSnapshot {
        try await Self.withTimeout(seconds: 180) {
            try await Self.loadSnapshot(cookies: cookies)
        }
    }

    private func get(_ url: URL, cookies: String) async throws -> TradeRepublicPoll {
        install(cookies, url: url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        TradeRepublicRequest.headers().forEach { key, value in
            if key.caseInsensitiveCompare("Content-Type") == .orderedSame { return }
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, http) = try await Self.response(for: request, session: session)
        let kept = keptCookies(http, url: url, previous: cookies)
        if http.statusCode >= 400 {
            throw TradeRepublicRequest.failure(
                statusCode: http.statusCode,
                errorCode: TradeRepublicRequest.errorCode(from: data),
                duringProcess: true
            ) ?? .rejected
        }
        guard let poll = TradeRepublicRequest.poll(from: data, cookies: kept) else {
            throw TradeRepublicFailure.unreadable
        }
        return poll
    }

    /// Puts a saved cookie header into an empty jar. A jar that already has the login cookie is left as the server set it.
    private func install(_ header: String, url: URL) {
        let storage = session.configuration.httpCookieStorage
        if storage?.cookies(for: url)?.isEmpty == false { return }
        TradeRepublicCookies.store(header, url: url, storage: storage)
    }

    /// The jar is the source of the cookie. An explicit Cookie header would replace it.
    private func keptCookies(_ response: HTTPURLResponse, url: URL, previous: String = "") -> String {
        let fromResponse = TradeRepublicCookies.header(
            from: response,
            url: url,
            storage: session.configuration.httpCookieStorage
        )
        return TradeRepublicCookies.merging(previous: previous, fresh: fromResponse)
    }

    private static func loadSnapshot(cookies: String) async throws -> TradeRepublicSnapshot {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let account = try await accountLookup(cookies: cookies, session: session)
        if account.dead { throw TradeRepublicFailure.sessionDead }
        let socket = session.webSocketTask(with: websocketRequest(cookies: cookies))
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        TradeRepublicSample.begin()
        try await socket.send(.string(connectMessage))
        let hello = try await text(from: socket)
        guard hello == "connected" else { throw TradeRepublicFailure.sessionDead }
        var number = account.number
        if number == nil {
            try await socket.send(.string(subscribe(1, ["type": "accountPairs"])))
            let pairs = try await text(from: socket)
            if pairs.contains(" E ") { throw TradeRepublicFailure.unreadable }
            number = TradeRepublicPortfolio.securitiesAccountNumber(fromAccountPairs: pairs)
        }
        guard let number, !number.isEmpty else { throw TradeRepublicFailure.unreadable }
        try await socket.send(.string(subscribe(2, [
            "type": "compactPortfolioByType",
            "secAccNo": number
        ])))
        let payload = try await text(from: socket)
        TradeRepublicSample.add(name: "compactPortfolio", body: payload)
        if payload.contains(" E ") { throw TradeRepublicFailure.unreadable }
        let positions: [TradeRepublicPosition]
        switch TradeRepublicPortfolio.read(text: payload) {
        case .positions(let rows):
            positions = rows
        case .unreadable:
            throw TradeRepublicFailure.unreadable
        }
        let history = await timeline(on: socket, startingAt: 3)
        return TradeRepublicSnapshot(positions: positions, activities: history.items, plans: history.plans)
    }

    private static func timeline(on socket: URLSessionWebSocketTask, startingAt first: Int) async -> (items: [TradeRepublicActivity], plans: [TradeRepublicPlan]) {
        var page = first
        var after: String?
        var seen = Set<String>()
        var all: [TradeRepublicActivity] = []
        for _ in 0..<40 {
            var payload = ["type": "timelineTransactions"]
            if let after { payload["after"] = after }
            do {
                try await socket.send(.string(subscribe(page, payload)))
                let text = try await text(from: socket)
                if page == first { TradeRepublicSample.add(name: "timelineTransactions", body: text) }
                if text.contains(" E ") { break }
                let parsed = TradeRepublicTimeline.read(text: text)
                for item in parsed.items where seen.insert(item.id).inserted {
                    all.append(item)
                }
                guard let next = parsed.after, !next.isEmpty, next != after else { break }
                after = next
                page += 1
            } catch {
                break
            }
        }
        let pending = all.enumerated().filter { $0.element.trade && $0.element.quantity == nil }
            .sorted { $0.element.date > $1.element.date }
            .prefix(300)
        var keptBuyDetail = false
        var keptSavingsDetail = false
        for item in pending {
            let payload = ["type": "timelineDetailV2", "id": item.element.id]
            do {
                try await socket.send(.string(subscribe(page, payload)))
                let text = try await text(from: socket)
                page += 1
                let savings = item.element.savingsPlan
                if savings, !keptSavingsDetail {
                    TradeRepublicSample.add(name: "timelineDetailV2 savings \(item.element.eventType)", body: text)
                    keptSavingsDetail = true
                } else if !savings, !keptBuyDetail {
                    TradeRepublicSample.add(name: "timelineDetailV2 \(item.element.eventType)", body: text)
                    keptBuyDetail = true
                }
                if text.contains(" E ") { continue }
                all[item.offset] = TradeRepublicTimeline.enrich(item.element, detail: text)
            } catch {
                break
            }
        }
        var plans: [TradeRepublicPlan] = []
        do {
            try await socket.send(.string(subscribe(page, ["type": "savingsPlans"])))
            let text = try await text(from: socket)
            TradeRepublicSample.add(name: "savingsPlans", body: text)
            if !text.contains(" E ") {
                plans = TradeRepublicPlans.read(text: text)
            }
        } catch {
            plans = []
        }
        let sized = all.filter { ($0.quantity ?? 0) > 0.0000005 }.count
        TradeRepublicSample.add(
            name: "summary",
            body: "items \(all.count)\nwith quantity \(sized)\nplans \(plans.count)"
        )
        return (all, plans)
    }

    private static func accountLookup(cookies: String, session: URLSession) async throws -> (dead: Bool, number: String?) {
        var request = URLRequest(url: TradeRepublicRequest.accountURL)
        request.timeoutInterval = 20
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue(TradeRepublicRequest.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, http) = try await Self.response(for: request, session: session)
        if http.statusCode == 401 || http.statusCode == 403 { return (true, nil) }
        if http.statusCode == 200 {
            return (false, TradeRepublicPortfolio.securitiesAccountNumber(from: data))
        }
        return (false, nil)
    }

    private static func response(for request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TradeRepublicFailure.transport }
            return (data, http)
        } catch let failure as TradeRepublicFailure {
            throw failure
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TradeRepublicFailure.transport
        }
    }

    private static func text(from task: URLSessionWebSocketTask) async throws -> String {
        do {
            switch try await task.receive() {
            case .string(let text):
                return text
            case .data(let data):
                return String(decoding: data, as: UTF8.self)
            @unknown default:
                throw TradeRepublicFailure.unreadable
            }
        } catch let failure as TradeRepublicFailure {
            throw failure
        } catch {
            throw TradeRepublicFailure.transport
        }
    }

    private static func websocketRequest(cookies: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "wss://api.traderepublic.com")!)
        request.timeoutInterval = 20
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue(TradeRepublicRequest.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static var connectMessage: String {
        let payload = #"{"locale":"de","platformId":"webtrading","platformVersion":"chrome - 146.0.0.0","clientId":"app.traderepublic.com","clientVersion":"5582"}"#
        return "connect 31 \(payload)"
    }

    private static func subscribe(_ id: Int, _ payload: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let json = String(decoding: data, as: UTF8.self)
        return "sub \(id) \(json)"
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TradeRepublicFailure.transport
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw TradeRepublicFailure.transport }
            return value
        }
    }
}
