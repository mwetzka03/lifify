import Foundation

enum DashboardPeriodMode: String, CaseIterable, Identifiable {
    case calendarMonth
    case salaryPeriod

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendarMonth: L("Kalendermonat", "Calendar month")
        case .salaryPeriod: L("Seit letztem Gehalt", "Since last salary")
        }
    }
}

enum IncomeAssignmentStore {
    static func setPrimary(iban: String, forecastID: UUID) {
        let normalized = normalize(iban)
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: "primaryIncomeIBAN")
        } else {
            UserDefaults.standard.set(normalized, forKey: "primaryIncomeIBAN")
        }
        UserDefaults.standard.set(forecastID.uuidString, forKey: "primaryIncomeForecastID")
    }

    static func setSecondary(_ values: [(iban: String, forecastID: UUID)]) {
        let pairs = values.compactMap { value -> (String, String)? in
            let iban = normalize(value.iban)
            return iban.isEmpty ? nil : (iban, value.forecastID.uuidString)
        }
        let mapping = Dictionary(pairs, uniquingKeysWith: { _, newest in newest })
        UserDefaults.standard.set(mapping, forKey: "secondaryIncomeMappings")
    }

    static func forecastID(for iban: String) -> UUID? {
        let normalized = normalize(iban)
        guard !normalized.isEmpty else { return nil }
        if UserDefaults.standard.string(forKey: "primaryIncomeIBAN") == normalized,
           let value = UserDefaults.standard.string(forKey: "primaryIncomeForecastID") {
            return UUID(uuidString: value)
        }
        let mapping = UserDefaults.standard.dictionary(forKey: "secondaryIncomeMappings") as? [String: String]
        return mapping?[normalized].flatMap(UUID.init(uuidString:))
    }

    static func assign(entryID: UUID, to forecastID: UUID) {
        var mapping = UserDefaults.standard.dictionary(forKey: "incomeEntryAssignments") as? [String: String] ?? [:]
        mapping[entryID.uuidString] = forecastID.uuidString
        UserDefaults.standard.set(mapping, forKey: "incomeEntryAssignments")
    }

    static func ibans(for forecastID: UUID) -> [String] {
        var values: [String] = []
        if UserDefaults.standard.string(forKey: "primaryIncomeForecastID") == forecastID.uuidString,
           let iban = UserDefaults.standard.string(forKey: "primaryIncomeIBAN") {
            let normalized = normalize(iban)
            if !normalized.isEmpty { values.append(normalized) }
        }
        let mapping = UserDefaults.standard.dictionary(forKey: "secondaryIncomeMappings") as? [String: String] ?? [:]
        for (iban, identifier) in mapping where identifier == forecastID.uuidString {
            let normalized = normalize(iban)
            if !normalized.isEmpty, !values.contains(normalized) { values.append(normalized) }
        }
        return values
    }

    static func forecastID(forEntryID entryID: UUID) -> UUID? {
        let mapping = UserDefaults.standard.dictionary(forKey: "incomeEntryAssignments") as? [String: String]
        return mapping?[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func reset() {
        ["primaryIncomeIBAN", "primaryIncomeForecastID", "secondaryIncomeMappings", "incomeEntryAssignments"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(UserDefaults.standard.string(forKey: "primaryIncomeIBAN"))
        hasher.combine(UserDefaults.standard.string(forKey: "primaryIncomeForecastID"))
        let secondary = UserDefaults.standard.dictionary(forKey: "secondaryIncomeMappings") as? [String: String] ?? [:]
        for pair in secondary.sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        let assigned = UserDefaults.standard.dictionary(forKey: "incomeEntryAssignments") as? [String: String] ?? [:]
        for pair in assigned.sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    private static func normalize(_ iban: String) -> String {
        iban.replacingOccurrences(of: " ", with: "").uppercased()
    }
}

/// Links a refund booking to the expense it pays back. The map is refund id → original id.
enum RefundLinkStore {
    private static let key = "lifify.refundLinks"

    static func link(refundID: UUID, to originalID: UUID) {
        guard refundID != originalID else { return }
        var map = mapping()
        map[refundID.uuidString] = originalID.uuidString
        save(map)
    }

    static func originalID(for refundID: UUID) -> UUID? {
        mapping()[refundID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func refundIDs(for originalID: UUID) -> [UUID] {
        let token = originalID.uuidString
        return mapping().compactMap { key, value in
            guard value == token else { return nil }
            return UUID(uuidString: key)
        }
    }

    static func isRefund(_ entryID: UUID) -> Bool {
        mapping()[entryID.uuidString] != nil
    }

    static func isRefunded(_ originalID: UUID) -> Bool {
        mapping().values.contains(originalID.uuidString)
    }

    static func unlink(refundID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: refundID.uuidString) != nil else { return }
        save(map)
    }

    static func removeAll(touching id: UUID) {
        let token = id.uuidString
        let map = mapping().filter { $0.key != token && $0.value != token }
        save(map)
    }

    /// What still counts as an expense. A partial refund leaves the remainder.
    static func countedExpenseCents(of entry: LedgerEntry, entries: [LedgerEntry]) -> Int {
        max(0, abs(entry.amountCents) - refundedCents(for: entry.id, entries: entries))
    }

    /// Signed remainder shown under the original expense. Nil when nothing is linked or the refunds are not in `entries`.
    static func realExpenseCents(of entry: LedgerEntry, entries: [LedgerEntry]) -> Int? {
        let ids = Set(refundIDs(for: entry.id))
        guard !ids.isEmpty else { return nil }
        let linked = entries.filter { ids.contains($0.id) }
        guard !linked.isEmpty else { return nil }
        let refunded = linked.reduce(0) { $0 + abs($1.amountCents) }
        return -max(0, abs(entry.amountCents) - refunded)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    private static func refundedCents(for originalID: UUID, entries: [LedgerEntry]) -> Int {
        let ids = Set(refundIDs(for: originalID))
        guard !ids.isEmpty else { return 0 }
        return entries.reduce(0) { total, entry in
            ids.contains(entry.id) ? total + abs(entry.amountCents) : total
        }
    }

    private static func mapping() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func save(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: key)
    }
}

struct TransferForecastRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amountCents: Int
    var fromAccountID: UUID?
    var toAccountID: UUID?
    var cadenceRaw: String
    var firstDate: Date
    var endDate: Date?
    var dueRuleRaw: String
    var dayOfMonth: Int
    var active: Bool

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int,
        fromAccountID: UUID? = nil,
        toAccountID: UUID? = nil,
        cadence: Cadence = .monthly,
        firstDate: Date = .now,
        endDate: Date? = nil,
        dueRule: DueRule = .calendarDay,
        dayOfMonth: Int = 1,
        active: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.cadenceRaw = cadence.rawValue
        self.firstDate = firstDate
        self.endDate = endDate
        self.dueRuleRaw = dueRule.rawValue
        self.dayOfMonth = dayOfMonth
        self.active = active
    }
}

enum TransferForecastStore {
    private static let key = "lifify.transferForecasts"

    static func all() -> [TransferForecastRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TransferForecastRecord].self, from: data) else { return [] }
        return decoded
    }

    static func upsert(_ record: TransferForecastRecord) {
        var records = all()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        save(records)
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
        TransferForecastAssignmentStore.removeForecast(id)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        TransferForecastAssignmentStore.reset()
    }

    private static func save(_ records: [TransferForecastRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// One real transfer in a period stands in for every occurrence of its forecast in that period.
enum TransferForecastAssignmentStore {
    private static let key = "lifify.transferForecastAssignments"

    static func assign(entryID: UUID, forecastID: UUID) {
        var map = mapping()
        map[entryID.uuidString] = forecastID.uuidString
        save(map)
    }

    static func forecastID(for entryID: UUID) -> UUID? {
        mapping()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    static func removeForecast(_ forecastID: UUID) {
        let token = forecastID.uuidString
        save(mapping().filter { $0.value != token })
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    private static func mapping() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func save(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: key)
    }
}

enum RewardPolicyStore {
    static func allowsMultiplePurchases(for rewardID: UUID) -> Bool {
        let key = key(for: rewardID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setAllowsMultiplePurchases(_ allowed: Bool, for rewardID: UUID) {
        UserDefaults.standard.set(allowed, forKey: key(for: rewardID))
    }

    static func remove(for rewardID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: rewardID))
    }

    private static func key(for rewardID: UUID) -> String {
        "reward.multiple.\(rewardID.uuidString)"
    }
}
