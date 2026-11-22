import Foundation
import SwiftData

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

@MainActor
enum IncomeAssignmentStore {
    private static let ibanKey = "iban"
    private static let forecastKey = "forecastID"

    static var primaryForecastID: UUID? {
        LinkTable.map(.incomePrimary)[forecastKey].flatMap(UUID.init(uuidString:))
    }

    static func setPrimary(iban: String, forecastID: UUID) {
        let normalized = normalize(iban)
        var values = [forecastKey: forecastID.uuidString]
        if !normalized.isEmpty { values[ibanKey] = normalized }
        LinkTable.replace(.incomePrimary, with: values)
    }

    static func setSecondary(_ values: [(iban: String, forecastID: UUID)]) {
        let pairs = values.compactMap { value -> (String, String)? in
            let iban = normalize(value.iban)
            return iban.isEmpty ? nil : (iban, value.forecastID.uuidString)
        }
        LinkTable.replace(.incomeSecondary, with: Dictionary(pairs, uniquingKeysWith: { _, newest in newest }))
    }

    static func secondaryMappings() -> [String: String] {
        LinkTable.map(.incomeSecondary)
    }

    static func addSecondary(iban: String, forecastID: UUID) {
        guard !iban.isEmpty else { return }
        LinkTable.set(.incomeSecondary, key: iban, value: forecastID.uuidString)
    }

    static func entryAssignments() -> [String: String] {
        LinkTable.map(.incomeEntry)
    }

    static var primaryIBAN: String? {
        LinkTable.map(.incomePrimary)[ibanKey]
    }

    static func forecastID(for iban: String) -> UUID? {
        let normalized = normalize(iban)
        guard !normalized.isEmpty else { return nil }
        if primaryIBAN == normalized, let primaryForecastID {
            return primaryForecastID
        }
        return secondaryMappings()[normalized].flatMap(UUID.init(uuidString:))
    }

    static func assign(entryID: UUID, to forecastID: UUID) {
        LinkTable.set(.incomeEntry, key: entryID.uuidString, value: forecastID.uuidString)
    }

    static func clear(entryID: UUID) {
        LinkTable.set(.incomeEntry, key: entryID.uuidString, value: nil)
    }

    static func ibans(for forecastID: UUID) -> [String] {
        var values: [String] = []
        if primaryForecastID == forecastID, let iban = primaryIBAN {
            let normalized = normalize(iban)
            if !normalized.isEmpty { values.append(normalized) }
        }
        for (iban, identifier) in secondaryMappings() where identifier == forecastID.uuidString {
            let normalized = normalize(iban)
            if !normalized.isEmpty, !values.contains(normalized) { values.append(normalized) }
        }
        return values
    }

    static func forecastID(forEntryID entryID: UUID) -> UUID? {
        entryAssignments()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func reset() {
        [.incomePrimary, .incomeSecondary, .incomeEntry].forEach(LinkTable.clear)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(primaryIBAN)
        hasher.combine(primaryForecastID)
        for pair in secondaryMappings().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        for pair in entryAssignments().sorted(by: { $0.key < $1.key }) {
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
@MainActor
enum RefundLinkStore {

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
        LinkTable.clear(.refund)
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
        LinkTable.map(.refund)
    }

    private static func save(_ map: [String: String]) {
        LinkTable.replace(.refund, with: map)
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

@MainActor
enum TransferForecastStore {
    static let backupType = "transferForecast"
    private static var cached: [TransferForecastRecord]?

    static func clearCache() {
        cached = nil
    }

    static func all() -> [TransferForecastRecord] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredTransferForecast>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.map(\.record)
        cached = decoded
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
        LififyDatabase.deleteAll(StoredTransferForecast.self)
        cached = []
        TransferForecastAssignmentStore.reset()
    }

    static func exportRecords() -> [BackupRecord] {
        all().compactMap { record in
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            return BackupRecord(type: backupType, id: record.id, strings: [String(decoding: data, as: UTF8.self)])
        }
    }

    static func restore(_ record: BackupRecord) {
        guard let text = record.strings.first,
              let value = try? JSONDecoder().decode(TransferForecastRecord.self, from: Data(text.utf8))
        else { return }
        upsert(value)
    }

    private static func save(_ records: [TransferForecastRecord]) {
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredTransferForecast>())) ?? []).forEach(context.delete)
            LififyDatabase.saveSide()
            for (position, record) in records.enumerated() {
                context.insert(StoredTransferForecast(record, position: position))
            }
            LififyDatabase.saveSide()
        }
        cached = records
    }
}

/// One real transfer in a period stands in for every occurrence of its forecast in that period.
@MainActor
enum TransferForecastAssignmentStore {

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
        LinkTable.clear(.transferAssignment)
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
        LinkTable.map(.transferAssignment)
    }

    private static func save(_ map: [String: String]) {
        LinkTable.replace(.transferAssignment, with: map)
    }
}

enum ForecastRefKind: String, Codable {
    case income
    case fixed
    case transfer
    case variable
    case shopping
}

/// Hides one forecast date without deleting the series.
@MainActor
enum ForecastSkipStore {
    static let revisionKey = "lifify.forecastSkipRevision"

    static func skip(_ kind: ForecastRefKind, id: UUID, on day: Date) {
        var values = all()
        values.insert(token(kind, id, day))
        save(values)
    }

    static func isSkipped(_ kind: ForecastRefKind, id: UUID, on day: Date) -> Bool {
        all().contains(token(kind, id, day))
    }

    static func reset() {
        LinkTable.clear(.forecastSkip)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for value in all().sorted() {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    private static func token(_ kind: ForecastRefKind, _ id: UUID, _ day: Date) -> String {
        "\(kind.rawValue)|\(id.uuidString)|\(day.dayKey)"
    }

    private static func all() -> Set<String> {
        Set(LinkTable.map(.forecastSkip).keys)
    }

    private static func save(_ values: Set<String>) {
        LinkTable.replace(.forecastSkip, with: Dictionary(uniqueKeysWithValues: values.map { ($0, "") }))
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

/// A real booking replaces every occurrence of one forecast inside its period.
@MainActor
enum ForecastPeriodLinkStore {
    static let revisionKey = "lifify.forecastLinkRevision"

    static func assign(entryID: UUID, kind: ForecastRefKind, forecastID: UUID) {
        var map = mapping()
        map[entryID.uuidString] = "\(kind.rawValue)|\(forecastID.uuidString)"
        save(map)
    }

    static func link(for entryID: UUID) -> (kind: ForecastRefKind, id: UUID)? {
        guard let raw = mapping()[entryID.uuidString] else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = ForecastRefKind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        return (kind, id)
    }

    static func covers(_ kind: ForecastRefKind, id: UUID, entries: [LedgerEntry], period: ForecastPeriod) -> Bool {
        entries.contains { entry in
            guard period.contains(entry.date), let link = link(for: entry.id) else { return false }
            return link.kind == kind && link.id == id
        }
    }

    static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    static func reset() {
        LinkTable.clear(.forecastPeriod)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    private static func mapping() -> [String: String] {
        LinkTable.map(.forecastPeriod)
    }

    private static func save(_ map: [String: String]) {
        LinkTable.replace(.forecastPeriod, with: map)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

/// Stops a same-day fixed-cost match from attaching again after the user removes it.
@MainActor
enum ForecastMatchRejectionStore {
    static let revisionKey = "lifify.forecastMatchRejectionRevision"

    static func reject(costID: UUID, entryID: UUID) {
        var values = all()
        values.insert(token(costID, entryID))
        save(values)
    }

    static func isRejected(costID: UUID, entryID: UUID) -> Bool {
        all().contains(token(costID, entryID))
    }

    static func reset() {
        LinkTable.clear(.matchRejection)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for value in all().sorted() {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    private static func token(_ costID: UUID, _ entryID: UUID) -> String {
        "fixed|\(costID.uuidString)|\(entryID.uuidString)"
    }

    private static func all() -> Set<String> {
        Set(LinkTable.map(.matchRejection).keys)
    }

    private static func save(_ values: Set<String>) {
        LinkTable.replace(.matchRejection, with: Dictionary(uniqueKeysWithValues: values.map { ($0, "") }))
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

@MainActor
enum RewardPolicyStore {
    static func allowsMultiplePurchases(for rewardID: UUID) -> Bool {
        LinkTable.map(.rewardPolicy)[rewardID.uuidString].map { $0 == "true" } ?? true
    }

    static func setAllowsMultiplePurchases(_ allowed: Bool, for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: allowed ? "true" : "false")
    }

    static func remove(for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: nil)
    }
}

/// Which expense group shows a booking. The booking itself is not changed.
@MainActor
enum ExpenseGroupAssignmentStore {
    static let revisionKey = "lifify.expenseGroupAssignmentRevision"

    static func groupID(for entryID: UUID) -> UUID? {
        mapping()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func entryIDs(in groupID: UUID) -> [UUID] {
        let token = groupID.uuidString
        return mapping().compactMap { entryID, assigned in
            guard assigned == token else { return nil }
            return UUID(uuidString: entryID)
        }
    }

    static func pairs() -> [(entryID: UUID, groupID: UUID)] {
        mapping().compactMap { entryID, groupID in
            guard let entryID = UUID(uuidString: entryID), let groupID = UUID(uuidString: groupID) else { return nil }
            return (entryID, groupID)
        }
    }

    static func replace(groupID: UUID, entryIDs: Set<UUID>) {
        var map = mapping()
        let token = groupID.uuidString
        for key in map.filter({ $0.value == token }).map(\.key) {
            map.removeValue(forKey: key)
        }
        for id in entryIDs {
            map[id.uuidString] = token
        }
        save(map)
    }

    static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    static func removeGroup(_ groupID: UUID) {
        let token = groupID.uuidString
        save(mapping().filter { $0.value != token })
    }

    static func reset() {
        LinkTable.clear(.expenseGroup)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    private static func mapping() -> [String: String] {
        LinkTable.map(.expenseGroup)
    }

    private static func save(_ map: [String: String]) {
        LinkTable.replace(.expenseGroup, with: map)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}
