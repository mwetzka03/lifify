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
        try await Self.withTimeout(seconds: 300) {
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
        let inbox = SocketInbox()
        TradeRepublicSample.begin()
        defer { TradeRepublicSample.finish() }
        try await socket.send(.string(connectMessage))
        let hello = try await text(from: socket)
        guard hello == "connected" else { throw TradeRepublicFailure.sessionDead }
        var number = account.number
        if number == nil {
            let id = inbox.take()
            try await socket.send(.string(subscribe(id, ["type": "accountPairs"])))
            let pairs = try await inbox.next(on: socket, id: id)
            guard pairs.ok else { throw TradeRepublicFailure.unreadable }
            number = TradeRepublicPortfolio.securitiesAccountNumber(fromAccountPairs: pairs.body)
        }
        guard let number, !number.isEmpty else { throw TradeRepublicFailure.unreadable }
        let portfolioID = inbox.take()
        try await socket.send(.string(subscribe(portfolioID, [
            "type": "compactPortfolioByType",
            "secAccNo": number
        ])))
        let payload = try await inbox.next(on: socket, id: portfolioID)
        TradeRepublicSample.add(name: "compactPortfolio", body: payload.body)
        guard payload.ok, !payload.body.isEmpty else { throw TradeRepublicFailure.unreadable }
        let positions: [TradeRepublicPosition]
        switch TradeRepublicPortfolio.read(text: payload.body) {
        case .positions(let rows):
            positions = rows
        case .unreadable:
            throw TradeRepublicFailure.unreadable
        }
        let history = await timeline(on: socket, inbox: inbox, positions: positions)
        return TradeRepublicSnapshot(positions: positions, activities: history.items, plans: history.plans)
    }

    /// Answers are matched by subscription id. A following C is only the end of that answer, not the next page.
    private final class SocketInbox: @unchecked Sendable {
        private var nextID = 1
        private var payloads: [Int: String] = [:]

        func take() -> Int {
            let id = nextID
            nextID += 1
            return id
        }

        func next(on socket: URLSessionWebSocketTask, id: Int) async throws -> (ok: Bool, body: String) {
            if let ready = payloads.removeValue(forKey: id) { return (true, ready) }
            while true {
                let text = try await TradeRepublicClient.text(from: socket)
                let parsed = TradeRepublicClient.frame(text)
                guard let messageID = parsed.id else { continue }
                if parsed.code == "E" {
                    if messageID == id { return (false, parsed.payload) }
                    continue
                }
                if parsed.code == "C" {
                    if messageID == id { return (true, "") }
                    continue
                }
                if parsed.code == "A" || parsed.code == "D" {
                    if messageID == id { return (true, parsed.payload) }
                    payloads[messageID] = parsed.payload
                }
            }
        }
    }

    private static func frame(_ text: String) -> (id: Int?, code: String, payload: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(of: " ") else { return (nil, "", trimmed) }
        let head = trimmed[..<space]
        let rest = trimmed[trimmed.index(after: space)...]
        let id = Int(head)
        if let codeEnd = rest.firstIndex(of: " ") {
            let code = String(rest[..<codeEnd])
            let payload = String(rest[rest.index(after: codeEnd)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (id, code, payload)
        }
        return (id, String(rest), "")
    }

    private static func timeline(
        on socket: URLSessionWebSocketTask,
        inbox: SocketInbox,
        positions: [TradeRepublicPosition]
    ) async -> (items: [TradeRepublicActivity], plans: [TradeRepublicPlan]) {
        var after: String?
        var seen = Set<String>()
        var all: [TradeRepublicActivity] = []
        var indexLines: [String] = []
        var pages = 0
        for _ in 0..<120 {
            var payload = ["type": "timelineTransactions"]
            if let after { payload["after"] = after }
            let id = inbox.take()
            do {
                try await socket.send(.string(subscribe(id, payload)))
                let reply = try await inbox.next(on: socket, id: id)
                guard reply.ok, !reply.body.isEmpty else { break }
                pages += 1
                TradeRepublicSample.add(name: "timelineTransactions \(pages)", body: reply.body)
                indexLines.append(contentsOf: TradeRepublicTimeline.indexLines(from: reply.body))
                let parsed = TradeRepublicTimeline.read(text: reply.body)
                for item in parsed.items where seen.insert(item.id).inserted {
                    all.append(item)
                }
                guard let next = parsed.after, !next.isEmpty, next != after else { break }
                after = next
            } catch {
                break
            }
        }
        if !indexLines.isEmpty {
            TradeRepublicSample.add(name: "timelineIndex", body: indexLines.joined(separator: "\n"))
        }
        let unexplained = Set(positions.compactMap { position -> String? in
            let bought = all.contains {
                $0.isin.caseInsensitiveCompare(position.isin) == .orderedSame
                    && TradeRepublicSync.purchase($0, averageCents: position.averageBuyInCents ?? 0)
            }
            return bought ? nil : position.isin.uppercased()
        })
        let pending = all.enumerated().filter { item in
            let row = item.element
            if row.quantity == nil && (row.trade || row.isGrant) { return true }
            if unexplained.contains(row.isin.uppercased()) { return true }
            if row.isin.isEmpty && row.amountCents == 0 && TradeRepublicTimeline.mightBeGrant(row.eventType) {
                return true
            }
            return false
        }
            .sorted { $0.element.date > $1.element.date }
            .prefix(800)
        var keptBuyDetail = false
        var keptSavingsDetail = false
        var detailed = 0
        for item in pending {
            let id = inbox.take()
            let payload = ["type": "timelineDetailV2", "id": item.element.id]
            do {
                try await socket.send(.string(subscribe(id, payload)))
                let reply = try await inbox.next(on: socket, id: id)
                guard reply.ok, reply.body.contains("{") else { continue }
                detailed += 1
                let savings = item.element.savingsPlan
                if item.element.isGrant {
                    TradeRepublicSample.add(name: "timelineDetailV2 grant \(item.element.id)", body: reply.body)
                } else if savings, !keptSavingsDetail {
                    TradeRepublicSample.add(name: "timelineDetailV2 savings \(item.element.eventType)", body: reply.body)
                    keptSavingsDetail = true
                } else if !savings, !keptBuyDetail {
                    TradeRepublicSample.add(name: "timelineDetailV2 \(item.element.eventType)", body: reply.body)
                    keptBuyDetail = true
                }
                all[item.offset] = TradeRepublicTimeline.enrich(item.element, detail: reply.body)
            } catch {
                break
            }
        }
        var plans: [TradeRepublicPlan] = []
        let planID = inbox.take()
        do {
            try await socket.send(.string(subscribe(planID, ["type": "savingsPlans"])))
            let reply = try await inbox.next(on: socket, id: planID)
            TradeRepublicSample.add(name: "savingsPlans", body: reply.body)
            if reply.ok, !reply.body.isEmpty {
                plans = TradeRepublicPlans.read(text: reply.body)
            }
        } catch {
            plans = []
        }
        let sized = all.filter { ($0.quantity ?? 0) > 0.0000005 }.count
        TradeRepublicSample.add(
            name: "summary",
            body: "pages \(pages)\nitems \(all.count)\nindex \(indexLines.count)\ndetails \(detailed)\nwith quantity \(sized)\nplans \(plans.count)"
        )
        TradeRepublicSample.finish()
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
