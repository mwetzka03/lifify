import Foundation

/// The private web session Trade Republic uses: phone, PIN, then confirmation in the app.
/// The PIN is not stored. A saved session is used only when a button asks for it.
struct TradeRepublicClient: Sendable {
    func begin(phone: String, pin: String) async throws -> TradeRepublicChallenge {
        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: TradeRepublicRequest.loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = TradeRepublicRequest.body(phone: phone, pin: pin)
        TradeRepublicRequest.headers().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, http) = try await send(request, session: session)
        let cookies = TradeRepublicCookies.header(from: session.configuration.httpCookieStorage)
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
        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = TradeRepublicRequest.codeBody(code)
        TradeRepublicRequest.headers().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if !cookies.isEmpty {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        let (data, http) = try await send(request, session: session)
        let merged = TradeRepublicCookies.merging(previous: cookies, storage: session.configuration.httpCookieStorage)
        if http.statusCode >= 400 {
            throw TradeRepublicRequest.failure(statusCode: http.statusCode, errorCode: TradeRepublicRequest.errorCode(from: data))
                ?? .invalidCode
        }
        return merged
    }

    func positions(cookies: String) async throws -> [TradeRepublicPosition] {
        try await Self.withTimeout(seconds: 25) {
            try await Self.loadPositions(cookies: cookies)
        }
    }

    private func get(_ url: URL, cookies: String) async throws -> TradeRepublicPoll {
        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        TradeRepublicRequest.headers().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if !cookies.isEmpty {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        let (data, http) = try await send(request, session: session)
        let merged = TradeRepublicCookies.merging(previous: cookies, storage: session.configuration.httpCookieStorage)
        if http.statusCode >= 400 {
            throw TradeRepublicRequest.failure(statusCode: http.statusCode, errorCode: TradeRepublicRequest.errorCode(from: data))
                ?? .rejected
        }
        guard let poll = TradeRepublicRequest.poll(from: data, cookies: merged) else {
            throw TradeRepublicFailure.unreadable
        }
        return poll
    }

    private static func loadPositions(cookies: String) async throws -> [TradeRepublicPosition] {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let account = try await accountLookup(cookies: cookies, session: session)
        if account.dead { throw TradeRepublicFailure.sessionDead }
        let socket = session.webSocketTask(with: websocketRequest(cookies: cookies))
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
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
        if payload.contains(" E ") { throw TradeRepublicFailure.unreadable }
        switch TradeRepublicPortfolio.read(text: payload) {
        case .positions(let positions):
            return positions
        case .unreadable:
            throw TradeRepublicFailure.unreadable
        }
    }

    private static func accountLookup(cookies: String, session: URLSession) async throws -> (dead: Bool, number: String?) {
        var request = URLRequest(url: TradeRepublicRequest.accountURL)
        request.timeoutInterval = 20
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue(TradeRepublicRequest.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, http) = try await send(request, session: session)
        if http.statusCode == 401 || http.statusCode == 403 { return (true, nil) }
        if http.statusCode == 200 {
            return (false, TradeRepublicPortfolio.securitiesAccountNumber(from: data))
        }
        return (false, nil)
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TradeRepublicFailure.transport }
            return (data, http)
        } catch let failure as TradeRepublicFailure {
            throw failure
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
