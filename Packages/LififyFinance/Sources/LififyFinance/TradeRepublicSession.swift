import CryptoKit
import LififyCore
import Foundation

/// The ways a Trade Republic sign-in can fail.
public enum TradeRepublicFailure: Error, Equatable {
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

    public var message: String {
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

/// Keeps a local text extract of the loaded Trade Republic data for diagnosing an import.
public enum TradeRepublicSample {
    public static let revisionKey = "lifify.tradeRepublic.sampleRevision"
    public static let exportFilenamePrefix = "TradeRepublic-Auszug"
    public static let previewCharacterLimit = 1600
    public static let legacyKey = "lifify.tradeRepublic.sample"

    public static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("traderepublic.extract.txt")
    }

    public static var exportFilename: String {
        "\(exportFilenamePrefix)-\(Date.now.dayKey)"
    }

    public static var leftoversInPreferences: Bool {
        AppDefaults.store.object(forKey: legacyKey) != nil
    }

    public static var byteCount: Int {
        purgeLegacyPreferences()
        return fileByteCount()
    }

    public static var hasContent: Bool { byteCount > 0 }

    public static var text: String {
        purgeLegacyPreferences()
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Returns the start of the extract.
    public static func preview(limit: Int = previewCharacterLimit) -> String {
        purgeLegacyPreferences()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limit)
        let snippet = String(decoding: data, as: UTF8.self)
        if fileByteCount() > data.count { return snippet + "\n…" }
        return snippet
    }

    /// Returns the whole extract.
    public static func exportData() -> Data {
        purgeLegacyPreferences()
        return (try? Data(contentsOf: fileURL)) ?? Data()
    }

    /// Starts a new extract.
    public static func begin() {
        replace("Trade Republic\n")
        bumpRevision()
    }

    /// Adds a named section.
    public static func add(name: String, body: String) {
        append("\n===== \(name) =====\n\(body)\n")
    }

    /// Signals that the extract is complete.
    public static func finish() {
        bumpRevision()
    }

    /// Replaces the extract with an imported one.
    public static func replaceWithImported(_ value: String) {
        replace(value)
        bumpRevision()
    }

    /// Deletes the extract.
    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        AppDefaults.store.removeObject(forKey: legacyKey)
        AppDefaults.store.set(0, forKey: revisionKey)
    }

    /// Removes an older extract from the preferences.
    public static func purgeLegacyPreferences() {
        guard let leftover = AppDefaults.store.string(forKey: legacyKey) else { return }
        if fileByteCount() == 0, !leftover.isEmpty {
            try? leftover.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        AppDefaults.store.removeObject(forKey: legacyKey)
    }

    /// Returns the size of the extract file.
    private static func fileByteCount() -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        else { return 0 }
        return size.intValue
    }

    /// Writes the extract file.
    private static func replace(_ value: String) {
        try? value.write(to: fileURL, atomically: true, encoding: .utf8)
        AppDefaults.store.removeObject(forKey: legacyKey)
    }

    /// Appends to the extract file.
    private static func append(_ value: String) {
        let data = Data(value.utf8)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            AppDefaults.store.removeObject(forKey: legacyKey)
            return
        }
        replace(((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "") + value)
    }

    /// Signals that the extract changed.
    private static func bumpRevision() {
        let revision = AppDefaults.store.integer(forKey: revisionKey) + 1
        AppDefaults.store.set(revision, forKey: revisionKey)
    }

    /// Rebuilds a snapshot from a copied sample or a pasted timeline JSON.
    public static func snapshot(from text: String) -> TradeRepublicSnapshot? {
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

    /// Splits an extract into its named sections.
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

    /// Merges detail sections into the activities.
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

    /// Applies one detail section.
    private static func applyDetail(_ body: String, name: String, to activities: inout [TradeRepublicActivity]) {
        let token = name.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard token.count == 36, token.filter({ $0 == "-" }).count == 4 else { return }
        guard let index = activities.firstIndex(where: { $0.id == token }) else { return }
        activities[index] = TradeRepublicTimeline.enrich(activities[index], detail: body)
    }
}

/// Texts of the Trade Republic flow.
public enum TradeRepublicCopy {
    public static var signIn: String { L("Bei Trade Republic anmelden", "Sign in to Trade Republic") }
    public static var waiting: String {
        L(
            "Bestätige die Anmeldung in der Trade-Republic-App.",
            "Confirm the sign-in in the Trade Republic app."
        )
    }
    public static var codePrompt: String {
        L("Code aus der Authenticator-App", "Code from the authenticator app")
    }
    public static var noPositions: String {
        L("Angemeldet. Trade Republic hat keine Positionen geliefert.", "Signed in. Trade Republic returned no positions.")
    }
    public static var importedFormat: String {
        L("%d Depotpositionen übernommen.", "%d portfolio positions imported.")
    }
    public static var skip: String { L("Ohne Anmeldung fortfahren", "Continue without signing in") }
    public static var cancel: String { L("Abbrechen", "Cancel") }
    public static var confirmCode: String { L("Code senden", "Send code") }
    public static var phone: String { L("Telefonnummer", "Phone number") }
    public static var pin: String { L("PIN", "PIN") }
    public static var loading: String {
        L(
            "Das Depot wird aktualisiert. Das dauert einen Moment.",
            "The depot is being updated. This takes a moment."
        )
    }
    public static var close: String { L("Schließen", "Close") }
    public static var balanceSave: String { L("Kontostand speichern", "Save the balance") }
    /// Asks for the balance on a date.
    public static func balancePrompt(_ date: String) -> String {
        L(
            "Kontostand auf Trade Republic am \(date). Das ist der Start des ersten Zeitraums, damit das Konto nicht ins Minus rutscht.",
            "Cash balance on Trade Republic on \(date). That is the start of the first period, so the account does not go negative."
        )
    }
    public static var sample: String { L("Antwort kopieren", "Copy the response") }
    public static var extract: String { L("Trade-Republic-Auszug", "Trade Republic extract") }
    public static var saveExtract: String { L("Auszug speichern", "Save extract") }
    public static var loadExtract: String { L("Auszug laden", "Load extract") }
    public static var pasteExtract: String { L("Auszug einfügen", "Paste extract") }
    public static var emptyExtract: String {
        L(
            "Noch kein Auszug. Melde dich zuerst bei Trade Republic an. Danach liegt die Datei hier. Speichern geht wie bei Finanzen exportieren, in die Dateien-App.",
            "There is no extract yet. Sign in to Trade Republic first. The file is then here. Saving works like Export finance, into the Files app."
        )
    }
    /// Reports the size of the prepared extract.
    public static func extractReady(_ bytes: Int) -> String {
        L(
            "\(bytes) Bytes. Auszug speichern schreibt die Datei in die Dateien-App, wie Finanzen exportieren. Der ganze Text liegt nicht auf diesem Bildschirm.",
            "\(bytes) bytes. Save extract writes the file into the Files app, like Export finance. The whole text is not on this screen."
        )
    }
    public static var pasteFailed: String {
        L(
            "Der Text ist kein Trade-Republic-Auszug. Das ist nicht die Lifify-Sicherung. Nach der Anmeldung den Auszug speichern, wie bei Finanzen exportieren.",
            "That text is not a Trade Republic extract. That is not the Lifify backup. After signing in, save the extract the same way as Export finance."
        )
    }
    public static var pasteWasBackup: String {
        L(
            "Das ist eine Lifify-Sicherung, kein Trade-Republic-Auszug. Nach der Anmeldung hier Auszug speichern und diese Datei schicken.",
            "That is a Lifify backup, not a Trade Republic extract. After signing in, save the extract here and send that file."
        )
    }
    /// Says whether a pasted text is a Lifify backup.
    public static func looksLikeBackup(_ text: String) -> Bool {
        text.contains("backupScope") || text.contains("\"type\" : \"account\"") || text.contains("\"type\":\"account\"")
    }
    /// Reports the applied extract.
    public static func appliedExtract(_ count: Int) -> String {
        L(
            "\(count) Buchungen aus dem Auszug übernommen.",
            "\(count) bookings taken from the extract."
        )
    }
    public static var sampleNote: String {
        L(
            "Nach der Anmeldung liegt die komplette Timeline hier als Datei. Auszug speichern schreibt sie in die Dateien-App, wie Finanzen exportieren. Das ist die Datei zum Schicken. Auszug laden oder einfügen liest einen Trade-Republic-Auszug in Lifify, keine Lifify-JSON-Sicherung.",
            "After signing in, the complete timeline sits here as a file. Save extract writes it to the Files app, like Export finance. That is the file to send. Load extract or paste reads a Trade Republic extract into Lifify, not a Lifify JSON backup."
        )
    }
    public static var copied: String { L("Kopiert", "Copied") }
    public static var twoUpdatePaths: String {
        L(
            "Zwei Wege zum selben Stand: Auszug oder Anmeldung.",
            "Two ways to the same data: statement or sign-in."
        )
    }
    public static var variantA: String { L("Variante A", "Option A") }
    public static var variantB: String { L("Variante B", "Option B") }
    public static var variantAHint: String {
        L("PDF-Umsatzübersicht einlesen.", "Read the PDF statement.")
    }
    public static var variantBHint: String {
        L("Live-Depot und aktuellen Cash-Stand holen.", "Fetch the live depot and current cash.")
    }
    public static var statementCaption: String {
        L(
            "PDF-Umsatzübersicht einlesen.",
            "Read the PDF statement."
        )
    }
    public static var footnote: String {
        L(
            "PIN wie in der Trade-Republic-App. Sie wird nicht gespeichert.",
            "PIN as in the Trade Republic app. It is not stored."
        )
    }
}

/// The open sign-in process.
public struct TradeRepublicChallenge: Equatable {
    public var processId: String
    public var countdownSeconds: Int
    public var cookies: String

    public init(processId: String, countdownSeconds: Int, cookies: String) {
        self.processId = processId
        self.countdownSeconds = countdownSeconds
        self.cookies = cookies
    }
}

/// The result of polling a sign-in.
public struct TradeRepublicPoll: Equatable {
    public var status: String
    public var needsCode: Bool
    public var cookies: String
    public var confirmed: Bool

    public init(status: String, needsCode: Bool, cookies: String, confirmed: Bool) {
        self.status = status
        self.needsCode = needsCode
        self.cookies = cookies
        self.confirmed = confirmed
    }
}

/// One depot position from Trade Republic.
public struct TradeRepublicPosition: Equatable, Sendable {
    public var isin: String
    public var name: String
    public var quantity: Double
    public var averageBuyInCents: Int?

    public init(isin: String, name: String, quantity: Double, averageBuyInCents: Int? = nil) {
        self.isin = isin
        self.name = name
        self.quantity = quantity
        self.averageBuyInCents = averageBuyInCents
    }
}

/// The result of reading the portfolio.
public enum PortfolioRead: Equatable {
    case positions([TradeRepublicPosition])
    case unreadable
}

/// Reads and merges session cookies.
public enum TradeRepublicCookies {
    /// Stores a cookie header in a cookie store.
    public static func store(_ header: String, url: URL, storage: HTTPCookieStorage?) {
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

    /// Builds a header from a cookie store.
    public static func header(from storage: HTTPCookieStorage?) -> String {
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

    /// Reads the cookies of a response.
    public static func header(from response: HTTPURLResponse, url: URL, storage: HTTPCookieStorage?) -> String {
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

    /// Merges earlier cookies with a store.
    public static func merging(previous: String, storage: HTTPCookieStorage?) -> String {
        merging(previous: previous, fresh: header(from: storage))
    }

    /// Merges two headers. Newer values win.
    public static func merging(previous: String, fresh: String) -> String {
        if fresh.isEmpty { return previous }
        if previous.isEmpty { return fresh }
        var order: [String] = []
        var values: [String: String] = [:]
        /// Adds the parts of a header.
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

    /// Says whether the header holds a session cookie.
    public static func keepsSession(_ header: String) -> Bool {
        header.split(separator: ";").contains { part in
            let name = part.split(separator: "=").first?
                .trimmingCharacters(in: .whitespaces)
                .lowercased() ?? ""
            return name == "tr_session" || name == "tr_refresh"
        }
    }
}

/// The session store. By design it keeps no session.
public enum TradeRepublicSessionStore {
    /// Ignores the header, because sessions are not stored.
    public static func save(_ header: String) {
        _ = header
        clear()
    }

    /// Reads a session left by an older version.
    public static func cookies() -> String? {
        KeychainStore.string(
            account: KeychainStore.tradeRepublicAccount,
            service: KeychainStore.tradeRepublicService
        )
    }

    public static var hasSession: Bool {
        guard let value = cookies() else { return false }
        return TradeRepublicCookies.keepsSession(value)
    }

    /// Removes a session left by an older version.
    public static func clear() {
        KeychainStore.remove(
            account: KeychainStore.tradeRepublicAccount,
            service: KeychainStore.tradeRepublicService
        )
    }
}

/// Builds and reads the sign-in requests.
public enum TradeRepublicRequest {
    public static let host = "https://api.traderepublic.com"
    public static let appVersion = "2.2631.13"
    public static let platform = "web-pro"
    public static let userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    public static let loginURL = URL(string: "\(host)/api/v2/auth/web/login")!
    public static let accountURL = URL(string: "\(host)/api/v2/auth/account")!

    /// Returns the status URL of a process.
    public static func processURL(_ processId: String) -> URL? {
        guard isProcessID(processId) else { return nil }
        return URL(string: "\(host)/api/v2/auth/web/login/processes/\(processId)")
    }

    /// Returns the code URL of a process.
    public static func codeURL(_ processId: String) -> URL? {
        guard isProcessID(processId) else { return nil }
        return URL(string: "\(host)/api/v2/auth/web/login/processes/\(processId)/authenticator-verification")
    }

    /// Checks a process ID before it goes into a URL.
    public static func isProcessID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil
    }

    /// A local German number starting with 0 is sent as +49. A number that already has + is kept.
    public static func canonicalPhone(_ raw: String) -> String {
        let compact = raw.filter { $0.isNumber || $0 == "+" }
        if compact.hasPrefix("+") { return compact }
        if compact.hasPrefix("00") { return "+" + compact.dropFirst(2) }
        if compact.hasPrefix("0") { return "+49" + compact.dropFirst() }
        return compact
    }

    /// Encodes phone number and PIN.
    public static func body(phone: String, pin: String) -> Data {
        let object = ["phoneNumber": phone, "pin": pin]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Encodes the confirmation code.
    public static func codeBody(_ code: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["code": code])) ?? Data()
    }

    /// Returns the request headers.
    public static func headers() -> [String: String] {
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
    public static func deviceInfo() -> String { deviceInfoToken }

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

    /// Reads the process ID and countdown.
    public static func challenge(from data: Data) -> (processId: String, countdown: Int)? {
        guard let object = jsonObject(data),
              let processId = object["processId"] as? String,
              isProcessID(processId)
        else { return nil }
        return (processId, intValue(object["countdownInSeconds"]) ?? 120)
    }

    /// Reads the status of a sign-in.
    public static func poll(from data: Data, cookies: String) -> TradeRepublicPoll? {
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

    /// Reads an error code.
    public static func errorCode(from data: Data) -> String? {
        guard let object = jsonObject(data),
              let errors = object["errors"] as? [[String: Any]],
              let code = errors.first?["errorCode"] as? String
        else { return nil }
        return code
    }

    /// Maps a failed response to a failure.
    public static func failure(
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

    /// Parses a JSON object.
    public static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Reads an integer from JSON.
    public static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }
}

/// Reads depot positions from responses.
public enum TradeRepublicPortfolio {
    /// Reads positions from data.
    public static func read(_ data: Data) -> PortfolioRead {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .unreadable }
        return read(object: object)
    }

    /// Reads positions from text that may hold a prefix.
    public static func read(text: String) -> PortfolioRead {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return .unreadable }
        return read(Data(text[start...].utf8))
    }

    /// Reads the securities account number from data.
    public static func securitiesAccountNumber(from data: Data) -> String? {
        guard let object = TradeRepublicRequest.jsonObject(data) else { return nil }
        return string(object["securitiesAccountNumber"]) ?? string(object["secAccNo"])
    }

    /// Reads the securities account number from account pairs.
    public static func securitiesAccountNumber(fromAccountPairs text: String) -> String? {
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

    /// Reads positions from parsed JSON.
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

    /// Converts list rows to positions.
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

    /// Reads a non-empty string.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads a number.
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

    /// Reads a non-negative amount in cents.
    private static func cents(_ value: Any?) -> Int? {
        guard let number = doubleValue(value), number >= 0 else { return nil }
        return Int((number * 100).rounded())
    }
}

/// The stored values of a holding, for planning edits.
public struct HoldingSeed: Equatable {
    public var symbol: String
    public var name: String
    public var quantity: Double
    public var purchasePriceCents: Int

    public init(symbol: String, name: String, quantity: Double, purchasePriceCents: Int) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.purchasePriceCents = purchasePriceCents
    }
}

/// A planned change to a holding.
public struct HoldingEdit: Equatable {
    public var symbol: String
    public var name: String
    public var quantity: Double
    public var purchasePriceCents: Int
    public var isNew: Bool

    public init(symbol: String, name: String, quantity: Double, purchasePriceCents: Int, isNew: Bool) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.purchasePriceCents = purchasePriceCents
        self.isNew = isNew
    }
}

/// Compares live positions with stored holdings.
public enum TradeRepublicDepotPlan {
    /// Lists the needed holding changes.
    public static func edits(positions: [TradeRepublicPosition], holdings: [HoldingSeed]) -> [HoldingEdit] {
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

/// An account reduced to what target selection needs.
public struct NamedAccount: Equatable {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var isMain: Bool

    public init(id: UUID, name: String, kind: AccountKind, isMain: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isMain = isMain
    }
}

/// The depot an import writes to.
public enum DepotChoice: Equatable {
    case existing(UUID)
    case create
    case ambiguous
}

/// Selects the depot for an import.
public enum TradeRepublicDepotTarget {
    /// Picks the linked or only depot, or asks for a new one.
    public static func choose(accounts: [NamedAccount], linkedPortfolioID: UUID?) -> DepotChoice {
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
