import CryptoKit
import Foundation

/// What a confirmed Trade Republic web session is allowed to do on its own.
/// Refresh runs only when a button calls it. A dead session does not sign in again.
enum TradeRepublicRefresh {
    static let onLaunch = false
    static let onTimer = false
    static let onFinanceOpen = false
    static let manualOnly = true
    static let usesStoredPIN = false
    static let storesSession = false
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
    case notStarted
    case sessionNotKept
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
        case .notStarted:
            L(
                "Trade Republic hat die Anmeldung nicht gestartet. Es kam keine Bestätigung. Die PIN ist dieselbe wie beim Öffnen der App.",
                "Trade Republic did not start the sign-in. No confirmation was sent. The PIN is the same one that opens the app."
            )
        case .sessionNotKept:
            L(
                "Die Bestätigung in der App ist da, die Sitzung kam aber nicht an. Bitte noch einmal anmelden.",
                "The confirmation in the app arrived, but the session did not. Please sign in again."
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
                "Es gibt mehrere Depots. Verknüpfe das Trade-Republic-Konto in den Konten mit einem Depot und melde dich danach an.",
                "There is more than one depot. Link the Trade Republic account to one depot under Accounts, then sign in."
            )
        }
    }
}

enum TradeRepublicSample {
    static let revisionKey = "lifify.tradeRepublic.sampleRevision"
    static let clipsExtract = false
    static let alwaysStores = true
    static let storesExtractInUserDefaults = false
    static let showsFullExtractText = false
    static let exportFilenamePrefix = "TradeRepublic-Auszug"
    static let previewCharacterLimit = 1600
    static let legacyKey = "lifify.tradeRepublic.sample"

    static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("traderepublic.extract.txt")
    }

    static var exportFilename: String {
        "\(exportFilenamePrefix)-\(Date.now.dayKey)"
    }

    static var leftoversInPreferences: Bool {
        UserDefaults.standard.object(forKey: legacyKey) != nil
    }

    static var byteCount: Int {
        purgeLegacyPreferences()
        return fileByteCount()
    }

    static var hasContent: Bool { byteCount > 0 }

    static var text: String {
        purgeLegacyPreferences()
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    static func preview(limit: Int = previewCharacterLimit) -> String {
        purgeLegacyPreferences()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limit)
        let snippet = String(decoding: data, as: UTF8.self)
        if fileByteCount() > data.count { return snippet + "\n…" }
        return snippet
    }

    static func exportData() -> Data {
        purgeLegacyPreferences()
        return (try? Data(contentsOf: fileURL)) ?? Data()
    }

    static func begin() {
        replace("Trade Republic\n")
        bumpRevision()
    }

    static func add(name: String, body: String) {
        append("\n===== \(name) =====\n\(body)\n")
    }

    static func finish() {
        bumpRevision()
    }

    static func replaceWithImported(_ value: String) {
        replace(value)
        bumpRevision()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        UserDefaults.standard.set(0, forKey: revisionKey)
    }

    static func purgeLegacyPreferences() {
        guard let leftover = UserDefaults.standard.string(forKey: legacyKey) else { return }
        if fileByteCount() == 0, !leftover.isEmpty {
            try? leftover.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func fileByteCount() -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        else { return 0 }
        return size.intValue
    }

    private static func replace(_ value: String) {
        try? value.write(to: fileURL, atomically: true, encoding: .utf8)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func append(_ value: String) {
        let data = Data(value.utf8)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }
        replace(((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "") + value)
    }

    private static func bumpRevision() {
        let revision = UserDefaults.standard.integer(forKey: revisionKey) + 1
        UserDefaults.standard.set(revision, forKey: revisionKey)
    }

    /// Rebuilds a snapshot from a copied sample or a pasted timeline JSON.
    static func snapshot(from text: String) -> TradeRepublicSnapshot? {
        var positions: [TradeRepublicPosition] = []
        var activities: [TradeRepublicActivity] = []
        var plans: [TradeRepublicPlan] = []
        var cashCents: Int?
        let sections = sections(in: text)
        if sections.isEmpty {
            merge(text, positions: &positions, activities: &activities, plans: &plans)
        } else {
            for (name, body) in sections {
                let heading = name.lowercased()
                if heading.hasPrefix("timelineindex") {
                    for item in TradeRepublicTimeline.activities(fromIndex: body) where !activities.contains(where: { $0.id == item.id }) {
                        activities.append(item)
                    }
                } else if heading.hasPrefix("timelinedetail") {
                    applyDetail(body, name: name, to: &activities)
                } else if heading == "cash" {
                    cashCents = TradeRepublicCash.cents(from: body) ?? cashCents
                } else {
                    merge(body, positions: &positions, activities: &activities, plans: &plans)
                }
            }
        }
        guard !positions.isEmpty || !activities.isEmpty else { return nil }
        return TradeRepublicSnapshot(positions: positions, activities: activities, plans: plans, cashCents: cashCents)
    }

    private static func sections(in text: String) -> [(name: String, body: String)] {
        let pattern = try? NSRegularExpression(pattern: #"^===== (.+?) =====\s*$"#, options: .anchorsMatchLines)
        guard let pattern else { return [] }
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }
        var result: [(String, String)] = []
        for (index, match) in matches.enumerated() {
            let name = ns.substring(with: match.range(at: 1))
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append((name, body))
        }
        return result
    }

    private static func merge(
        _ text: String,
        positions: inout [TradeRepublicPosition],
        activities: inout [TradeRepublicActivity],
        plans: inout [TradeRepublicPlan]
    ) {
        if case .positions(let rows) = TradeRepublicPortfolio.read(text: text), !rows.isEmpty {
            positions = rows
        }
        let parsed = TradeRepublicTimeline.read(text: text)
        for item in parsed.items where !activities.contains(where: { $0.id == item.id }) {
            activities.append(item)
        }
        let found = TradeRepublicPlans.read(text: text)
        if !found.isEmpty { plans = found }
    }

    private static func applyDetail(_ body: String, name: String, to activities: inout [TradeRepublicActivity]) {
        let token = name.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard token.count == 36, token.filter({ $0 == "-" }).count == 4 else { return }
        guard let index = activities.firstIndex(where: { $0.id == token }) else { return }
        activities[index] = TradeRepublicTimeline.enrich(activities[index], detail: body)
    }
}

enum TradeRepublicCopy {
    static var signIn: String { L("Bei Trade Republic anmelden", "Sign in to Trade Republic") }
    static var waiting: String {
        L(
            "Bestätige die Anmeldung in der Trade-Republic-App.",
            "Confirm the sign-in in the Trade Republic app."
        )
    }
    static var codePrompt: String {
        L("Code aus der Authenticator-App", "Code from the authenticator app")
    }
    static var noPositions: String {
        L("Angemeldet. Trade Republic hat keine Positionen geliefert.", "Signed in. Trade Republic returned no positions.")
    }
    static var importedFormat: String {
        L("%d Depotpositionen übernommen.", "%d portfolio positions imported.")
    }
    static var skip: String { L("Ohne Anmeldung fortfahren", "Continue without signing in") }
    static var cancel: String { L("Abbrechen", "Cancel") }
    static var confirmCode: String { L("Code senden", "Send code") }
    static var phone: String { L("Telefonnummer", "Phone number") }
    static var pin: String { L("PIN", "PIN") }
    static var loading: String {
        L(
            "Das Depot wird aktualisiert. Das dauert einen Moment.",
            "The depot is being updated. This takes a moment."
        )
    }
    static var close: String { L("Schließen", "Close") }
    static var balanceSave: String { L("Kontostand speichern", "Save the balance") }
    static func balancePrompt(_ date: String) -> String {
        L(
            "Kontostand auf Trade Republic am \(date). Das ist der Start des ersten Zeitraums, damit das Konto nicht ins Minus rutscht.",
            "Cash balance on Trade Republic on \(date). That is the start of the first period, so the account does not go negative."
        )
    }
    static var sample: String { L("Antwort kopieren", "Copy the response") }
    static var extract: String { L("Trade-Republic-Auszug", "Trade Republic extract") }
    static var saveExtract: String { L("Auszug speichern", "Save extract") }
    static var loadExtract: String { L("Auszug laden", "Load extract") }
    static var pasteExtract: String { L("Auszug einfügen", "Paste extract") }
    static var emptyExtract: String {
        L(
            "Noch kein Auszug. Melde dich zuerst bei Trade Republic an. Danach liegt die Datei hier. Speichern geht wie bei Finanzen exportieren, in die Dateien-App.",
            "There is no extract yet. Sign in to Trade Republic first. The file is then here. Saving works like Export finance, into the Files app."
        )
    }
    static func extractReady(_ bytes: Int) -> String {
        L(
            "\(bytes) Bytes. Auszug speichern schreibt die Datei in die Dateien-App, wie Finanzen exportieren. Der ganze Text liegt nicht auf diesem Bildschirm.",
            "\(bytes) bytes. Save extract writes the file into the Files app, like Export finance. The whole text is not on this screen."
        )
    }
    static var pasteFailed: String {
        L(
            "Der Text ist kein Trade-Republic-Auszug. Das ist nicht die Lifify-Sicherung. Nach der Anmeldung den Auszug speichern, wie bei Finanzen exportieren.",
            "That text is not a Trade Republic extract. That is not the Lifify backup. After signing in, save the extract the same way as Export finance."
        )
    }
    static var pasteWasBackup: String {
        L(
            "Das ist eine Lifify-Sicherung, kein Trade-Republic-Auszug. Nach der Anmeldung hier Auszug speichern und diese Datei schicken.",
            "That is a Lifify backup, not a Trade Republic extract. After signing in, save the extract here and send that file."
        )
    }
    static func looksLikeBackup(_ text: String) -> Bool {
        text.contains("backupScope") || text.contains("\"type\" : \"account\"") || text.contains("\"type\":\"account\"")
    }
    static func appliedExtract(_ count: Int) -> String {
        L(
            "\(count) Buchungen aus dem Auszug übernommen.",
            "\(count) bookings taken from the extract."
        )
    }
    static var sampleNote: String {
        L(
            "Nach der Anmeldung liegt die komplette Timeline hier als Datei. Auszug speichern schreibt sie in die Dateien-App, wie Finanzen exportieren. Das ist die Datei zum Schicken. Auszug laden oder einfügen liest einen Trade-Republic-Auszug in Lifify, keine Lifify-JSON-Sicherung.",
            "After signing in, the complete timeline sits here as a file. Save extract writes it to the Files app, like Export finance. That is the file to send. Load extract or paste reads a Trade Republic extract into Lifify, not a Lifify JSON backup."
        )
    }
    static var copied: String { L("Kopiert", "Copied") }
    static var twoUpdatePaths: String {
        L(
            "Zwei Wege, denselben Stand zu holen: den Kontoauszug hochladen oder dich bei Trade Republic anmelden.",
            "Two ways to fetch the same data: upload the statement, or sign in to Trade Republic."
        )
    }
    static var statementCaption: String {
        L(
            "Nur die Umsatzübersicht. Das Girokonto wird über die IBAN wiederverwendet oder neu angelegt, das Depot hängt daran. Buchungen vor dem Start des ersten Zeitraums vom Hauptkonto werden nicht angelegt, spätere schon. Die Depotstände aus dem ganzen Auszug werden übernommen. Der Startsaldo ist der Saldo am Starttag, sonst vom letzten Tag davor.",
            "Only the transaction overview. The checking account is reused by IBAN or created, and the portfolio is linked to it. Transactions before the start of the main account’s first period are not booked; later ones are. Portfolio positions from the whole statement are imported. The opening balance is the balance on the start day, or the previous day."
        )
    }
    static var footnote: String {
        L(
            "Die PIN ist dieselbe wie beim Öffnen der Trade-Republic-App, kein Code per SMS. Eine 0 am Anfang wird zu +49. Nur wenn du hier tippst. PIN und Sitzung werden nicht gespeichert. Jedes Mal neu anmelden.",
            "The PIN is the same one that opens the Trade Republic app, not a code sent by text. A leading 0 becomes +49. Only when you tap here. The PIN and the session are not saved. Sign in each time."
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
    static func store(_ header: String, url: URL, storage: HTTPCookieStorage?) {
        guard let storage else { return }
        let host = url.host ?? "api.traderepublic.com"
        for part in header.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let name = String(piece[..<eq])
            let value = String(piece[piece.index(after: eq)...])
            guard !name.isEmpty,
                  let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: host,
                    .path: "/"
                  ])
            else { continue }
            storage.setCookie(cookie)
        }
    }

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

    static func header(from response: HTTPURLResponse, url: URL, storage: HTTPCookieStorage?) -> String {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            fields[name] = text
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return merging(previous: header(from: storage), fresh: parsed)
    }

    static func merging(previous: String, storage: HTTPCookieStorage?) -> String {
        merging(previous: previous, fresh: header(from: storage))
    }

    static func merging(previous: String, fresh: String) -> String {
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
            return name == "tr_session" || name == "tr_refresh"
        }
    }
}

enum TradeRepublicSessionStore {
    static func save(_ header: String) {
        _ = header
        clear()
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

    /// A local German number starting with 0 is sent as +49. A number that already has + is kept.
    static func canonicalPhone(_ raw: String) -> String {
        let compact = raw.filter { $0.isNumber || $0 == "+" }
        if compact.hasPrefix("+") { return compact }
        if compact.hasPrefix("00") { return "+" + compact.dropFirst(2) }
        if compact.hasPrefix("0") { return "+49" + compact.dropFirst() }
        return compact
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

    /// One device description for the whole process, so the login and the poll name the same device.
    static func deviceInfo() -> String { deviceInfoToken }

    private static let deviceInfoToken: String = {
        let digest = SHA512.hash(data: Data(UUID().uuidString.utf8))
        let stableId = digest.map { String(format: "%02x", Int($0)) }.joined()
        let offset = TimeZone.current.secondsFromGMT() / 60
        let device: [String: Any] = [
            "stableDeviceId": stableId,
            "browser": "Chrome",
            "browserVersion": "146.0.0.0",
            "os": "Linux",
            "osVersion": "6.12.0",
            "timezone": TimeZone.current.identifier,
            "timezoneOffset": -offset,
            "screen": "1920x1080x24",
            "preferredLanguages": ["de"],
            "numberOfCores": ProcessInfo.processInfo.processorCount
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: device) else { return "" }
        return data.base64EncodedString()
    }()

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
        let confirmed = status == "CONFIRMED" || status == "COMPLETED" || TradeRepublicCookies.keepsSession(cookies)
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

    static func failure(
        statusCode: Int,
        errorCode: String?,
        savedSession: Bool = false,
        duringProcess: Bool = false
    ) -> TradeRepublicFailure? {
        switch errorCode {
        case "NUMBER_INVALID": return .invalidPhone
        case "PIN_INVALID", "WRONG_PIN", "INVALID_PIN": return .invalidPin
        case "PROCESS_GONE", "NOT_FOUND": return .notConfirmed
        case "ALREADY_PROCESSED": return .rejected
        case "TOO_MANY_REQUESTS": return .busy
        case "VALIDATION_CODE_INVALID", "VALIDATION_CODE_ALREADY_USED": return .invalidCode
        case "MISSING_REQUIRED_HEADER": return .rejected
        default: break
        }
        if statusCode == 401 || statusCode == 403 {
            if savedSession { return .sessionDead }
            return duringProcess ? .sessionNotKept : .notStarted
        }
        return statusCode >= 400 ? .rejected : nil
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
            if let rows = object["positions"] as? [Any] {
                found.append(contentsOf: Self.positions(in: rows))
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
