import Foundation

/// What a confirmed Trade Republic web session is allowed to do on its own.
/// Refresh runs only when a button calls it. A dead session does not sign in again.
enum TradeRepublicRefresh {
    static let onLaunch = false
    static let onTimer = false
    static let onFinanceOpen = false
    static let manualOnly = true
    static let usesStoredPIN = false
}

/// The login call from this environment. A fake number is rejected before any session exists.
enum TradeRepublicGap {
    static let probedStatus = 400
    static let probedCode = "NUMBER_INVALID"
    static let deviceConfirmationRequired = true
    static let completedOnThisMachine = false
}

enum TradeRepublicFailure: Error, Equatable {
    case invalidPhone
    case invalidPin
    case notConfirmed
    case sessionDead
    case rejected
    case busy
    case invalidCode
    case unreadable
    case transport
    case noSingleDepot

    var message: String {
        switch self {
        case .invalidPhone:
            L("Die Telefonnummer wurde nicht angenommen.", "The phone number was not accepted.")
        case .invalidPin:
            L("Die PIN wurde nicht angenommen.", "The PIN was not accepted.")
        case .notConfirmed:
            L("Die Anmeldung wurde nicht rechtzeitig bestätigt.", "The sign-in was not confirmed in time.")
        case .sessionDead:
            L(
                "Die Sitzung ist abgelaufen. Bitte in der Trade-Republic-App erneut bestätigen.",
                "The session has expired. Confirm again in the Trade Republic app."
            )
        case .rejected:
            L("Die Anmeldung wurde abgelehnt.", "The sign-in was rejected.")
        case .busy:
            L("Zu viele Versuche. Bitte kurz warten.", "Too many attempts. Please wait a moment.")
        case .invalidCode:
            L("Der Code wurde nicht angenommen.", "The code was not accepted.")
        case .unreadable:
            L("Die Antwort von Trade Republic ließ sich nicht lesen.", "The Trade Republic reply could not be read.")
        case .transport:
            L("Trade Republic ist gerade nicht erreichbar.", "Trade Republic could not be reached.")
        case .noSingleDepot:
            L(
                "Es gibt mehrere Depots. Verknüpfe das Trade-Republic-Konto in den Konten mit einem Depot und aktualisiere danach.",
                "There is more than one depot. Link the Trade Republic account to one depot under Accounts, then refresh."
            )
        }
    }
}

enum TradeRepublicCopy {
    static var signIn: String { L("Bei Trade Republic anmelden", "Sign in to Trade Republic") }
    static var refresh: String { L("Depot aus der Sitzung aktualisieren", "Refresh the depot from the session") }
    static var signInAgain: String { L("Erneut anmelden", "Sign in again") }
    static var waiting: String {
        L(
            "Bestätige die Anmeldung in der Trade-Republic-App.",
            "Confirm the sign-in in the Trade Republic app."
        )
    }
    static var codePrompt: String {
        L("Code aus der Authenticator-App", "Code from the authenticator app")
    }
    static var sessionSaved: String { L("Sitzung gespeichert", "Session saved") }
    static var noSession: String { L("Keine Sitzung", "No session") }
    static var noPositions: String {
        L("Angemeldet. Die Sitzung hat keine Positionen geliefert.", "Signed in. The session returned no positions.")
    }
    static var importedFormat: String {
        L("%d Depotpositionen übernommen.", "%d portfolio positions imported.")
    }
    static var skip: String { L("Ohne Anmeldung fortfahren", "Continue without signing in") }
    static var cancel: String { L("Abbrechen", "Cancel") }
    static var confirmCode: String { L("Code senden", "Send code") }
    static var phone: String { L("Telefonnummer", "Phone number") }
    static var pin: String { L("PIN", "PIN") }
    static var footnote: String {
        L(
            "Nur wenn du hier tippst. Die PIN wird nicht gespeichert. Ist die Sitzung abgelaufen, bestätigst du sie in der Trade-Republic-App erneut.",
            "Only when you tap here. The PIN is not saved. When the session has expired, you confirm it again in the Trade Republic app."
        )
    }
}

struct TradeRepublicChallenge: Equatable {
    var processId: String
    var countdownSeconds: Int
    var cookies: String
}

struct TradeRepublicPoll: Equatable {
    var status: String
    var needsCode: Bool
    var cookies: String
    var confirmed: Bool
}

struct TradeRepublicPosition: Equatable, Sendable {
    var isin: String
    var name: String
    var quantity: Double
    var averageBuyInCents: Int?
}

enum PortfolioRead: Equatable {
    case positions([TradeRepublicPosition])
    case unreadable
}

enum TradeRepublicCookies {
    static func header(from storage: HTTPCookieStorage?) -> String {
        let cookies = (storage?.cookies ?? []).filter {
            $0.domain.isEmpty || $0.domain.localizedCaseInsensitiveContains("traderepublic.com")
        }
        var names: [String] = []
        var values: [String: String] = [:]
        for cookie in cookies where values[cookie.name] == nil {
            names.append(cookie.name)
            values[cookie.name] = cookie.value
        }
        return names.map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "; ")
    }

    static func merging(previous: String, storage: HTTPCookieStorage?) -> String {
        let fresh = header(from: storage)
        if fresh.isEmpty { return previous }
        if previous.isEmpty { return fresh }
        var order: [String] = []
        var values: [String: String] = [:]
        func absorb(_ header: String) {
            for part in header.split(separator: ";") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                guard let eq = piece.firstIndex(of: "=") else { continue }
                let name = String(piece[..<eq])
                let value = String(piece[piece.index(after: eq)...])
                guard !name.isEmpty else { continue }
                if values[name] == nil { order.append(name) }
                values[name] = value
            }
        }
        absorb(previous)
        absorb(fresh)
        return order.map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "; ")
    }

    static func keepsSession(_ header: String) -> Bool {
        header.split(separator: ";").contains { part in
            let name = part.split(separator: "=").first?
                .trimmingCharacters(in: .whitespaces)
                .lowercased() ?? ""
            return name == "tr_session" || (name.contains("session") && !name.contains("waf"))
        }
    }
}

enum TradeRepublicSessionStore {
    static func save(_ header: String) {
        guard TradeRepublicCookies.keepsSession(header) else { return }
        KeychainStore.set(
            header,
            account: KeychainStore.tradeRepublicAccount,
            service: KeychainStore.tradeRepublicService
        )
    }

    static func cookies() -> String? {
        KeychainStore.string(
            account: KeychainStore.tradeRepublicAccount,
            service: KeychainStore.tradeRepublicService
        )
    }

    static var hasSession: Bool {
        guard let value = cookies() else { return false }
        return TradeRepublicCookies.keepsSession(value)
    }

    static func clear() {
        KeychainStore.remove(
            account: KeychainStore.tradeRepublicAccount,
            service: KeychainStore.tradeRepublicService
        )
    }
}

enum TradeRepublicRequest {
    static let host = "https://api.traderepublic.com"
    static let appVersion = "2.2631.13"
    static let platform = "web-pro"
    static let userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    static let loginURL = URL(string: "\(host)/api/v2/auth/web/login")!
    static let accountURL = URL(string: "\(host)/api/v2/auth/account")!

    static func processURL(_ processId: String) -> URL? {
        guard isProcessID(processId) else { return nil }
        return URL(string: "\(host)/api/v2/auth/web/login/processes/\(processId)")
    }

    static func codeURL(_ processId: String) -> URL? {
        guard isProcessID(processId) else { return nil }
        return URL(string: "\(host)/api/v2/auth/web/login/processes/\(processId)/authenticator-verification")
    }

    static func isProcessID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil
    }

    static func body(phone: String, pin: String) -> Data {
        let object = ["phoneNumber": phone, "pin": pin]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func codeBody(_ code: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["code": code])) ?? Data()
    }

    static func headers() -> [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": userAgent,
            "X-TR-Device-Info": deviceInfo(),
            "X-TR-App-Version": appVersion,
            "X-Tr-Platform": platform,
            "Accept-Language": "de"
        ]
    }

    static func deviceInfo() -> String {
        let offset = TimeZone.current.secondsFromGMT() / 60
        let device: [String: Any] = [
            "stableDeviceId": UUID().uuidString,
            "browser": "Chrome",
            "browserVersion": "146.0.0.0",
            "os": "iOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "timezone": TimeZone.current.identifier,
            "timezoneOffset": -offset,
            "screen": "390x844x24",
            "preferredLanguages": ["de"],
            "numberOfCores": ProcessInfo.processInfo.processorCount
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: device) else { return "" }
        return data.base64EncodedString()
    }

    static func challenge(from data: Data) -> (processId: String, countdown: Int)? {
        guard let object = jsonObject(data),
              let processId = object["processId"] as? String,
              isProcessID(processId)
        else { return nil }
        return (processId, intValue(object["countdownInSeconds"]) ?? 120)
    }

    static func poll(from data: Data, cookies: String) -> TradeRepublicPoll? {
        guard let object = jsonObject(data) else { return nil }
        let status = (object["status"] as? String) ?? ""
        let action = object["requiredAction"] as? String
        let confirmed = status == "CONFIRMED" || status == "COMPLETED"
        return TradeRepublicPoll(
            status: status,
            needsCode: action == "AUTHENTICATOR_VERIFICATION" && !confirmed,
            cookies: cookies,
            confirmed: confirmed
        )
    }

    static func errorCode(from data: Data) -> String? {
        guard let object = jsonObject(data),
              let errors = object["errors"] as? [[String: Any]],
              let code = errors.first?["errorCode"] as? String
        else { return nil }
        return code
    }

    static func failure(statusCode: Int, errorCode: String?) -> TradeRepublicFailure? {
        if statusCode == 401 || statusCode == 403 { return .sessionDead }
        switch errorCode {
        case "NUMBER_INVALID": return .invalidPhone
        case "PIN_INVALID", "WRONG_PIN", "INVALID_PIN": return .invalidPin
        case "PROCESS_GONE", "NOT_FOUND": return .notConfirmed
        case "ALREADY_PROCESSED": return .rejected
        case "TOO_MANY_REQUESTS": return .busy
        case "VALIDATION_CODE_INVALID", "VALIDATION_CODE_ALREADY_USED": return .invalidCode
        case "MISSING_REQUIRED_HEADER": return .rejected
        default:
            return statusCode >= 400 ? .rejected : nil
        }
    }

    static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }
}

enum TradeRepublicPortfolio {
    static func read(_ data: Data) -> PortfolioRead {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .unreadable }
        return read(object: object)
    }

    static func read(text: String) -> PortfolioRead {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return .unreadable }
        return read(Data(text[start...].utf8))
    }

    static func securitiesAccountNumber(from data: Data) -> String? {
        guard let object = TradeRepublicRequest.jsonObject(data) else { return nil }
        return string(object["securitiesAccountNumber"]) ?? string(object["secAccNo"])
    }

    static func securitiesAccountNumber(fromAccountPairs text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [String: Any],
              let accounts = object["accounts"] as? [[String: Any]]
        else { return nil }
        let numbered = accounts.compactMap { account -> (String, Bool)? in
            guard let number = string(account["securitiesAccountNumber"]) else { return nil }
            return (number, (account["productType"] as? String) == "DEFAULT")
        }
        return numbered.first(where: \.1)?.0 ?? numbered.first?.0
    }

    private static func read(object: Any) -> PortfolioRead {
        if let list = object as? [Any] {
            return .positions(positions(in: list))
        }
        guard let object = object as? [String: Any] else { return .unreadable }
        if object["categories"] != nil || object["positions"] != nil {
            var found: [TradeRepublicPosition] = []
            if let categories = object["categories"] as? [[String: Any]] {
                for category in categories {
                    found.append(contentsOf: positions(in: category["positions"] as? [Any] ?? []))
                }
            }
            if let positions = object["positions"] as? [Any] {
                found.append(contentsOf: positions(in: positions))
            }
            return .positions(found)
        }
        return .unreadable
    }

    private static func positions(in list: [Any]) -> [TradeRepublicPosition] {
        list.compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            let isin = (string(row["isin"]) ?? string(row["instrumentId"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !isin.isEmpty, let quantity = doubleValue(row["netSize"] ?? row["quantity"]) else { return nil }
            let name = string(row["name"]) ?? string(row["shortName"]) ?? string(row["instrumentName"]) ?? ""
            return TradeRepublicPosition(
                isin: isin,
                name: name,
                quantity: quantity,
                averageBuyInCents: cents(row["averageBuyIn"])
            )
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        case let text as String:
            return Double(text.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private static func cents(_ value: Any?) -> Int? {
        guard let number = doubleValue(value), number >= 0 else { return nil }
        return Int((number * 100).rounded())
    }
}

struct HoldingSeed: Equatable {
    var symbol: String
    var name: String
    var quantity: Double
    var purchasePriceCents: Int
}

struct HoldingEdit: Equatable {
    var symbol: String
    var name: String
    var quantity: Double
    var purchasePriceCents: Int
    var isNew: Bool
}

enum TradeRepublicDepotPlan {
    static func edits(positions: [TradeRepublicPosition], holdings: [HoldingSeed]) -> [HoldingEdit] {
        positions.compactMap { position in
            let isin = position.isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !isin.isEmpty else { return nil }
            if let existing = holdings.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame }) {
                return HoldingEdit(
                    symbol: isin,
                    name: position.name.isEmpty ? existing.name : position.name,
                    quantity: position.quantity,
                    purchasePriceCents: position.averageBuyInCents ?? existing.purchasePriceCents,
                    isNew: false
                )
            }
            guard position.quantity > 0 else { return nil }
            return HoldingEdit(
                symbol: isin,
                name: position.name.isEmpty ? isin : position.name,
                quantity: position.quantity,
                purchasePriceCents: position.averageBuyInCents ?? 0,
                isNew: true
            )
        }
    }
}

struct NamedAccount: Equatable {
    var id: UUID
    var name: String
    var kind: AccountKind
    var isMain: Bool
}

enum DepotChoice: Equatable {
    case existing(UUID)
    case create
    case ambiguous
}

enum TradeRepublicDepotTarget {
    static func choose(accounts: [NamedAccount], linkedPortfolioID: UUID?) -> DepotChoice {
        let portfolios = accounts.filter { $0.kind == .portfolio }
        if let linkedPortfolioID, portfolios.contains(where: { $0.id == linkedPortfolioID }) {
            return .existing(linkedPortfolioID)
        }
        if portfolios.count == 1, let only = portfolios.first {
            return .existing(only.id)
        }
        if portfolios.isEmpty { return .create }
        return .ambiguous
    }
}
