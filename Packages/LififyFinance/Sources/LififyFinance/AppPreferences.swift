import Foundation
import LififyCore
import SwiftData

/// Whether finance periods follow calendar months or the salary.
public enum DashboardPeriodMode: String, CaseIterable, Identifiable {
    case calendarMonth
    case salaryPeriod

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .calendarMonth: L("Kalendermonat", "Calendar month")
        case .salaryPeriod: L("Seit letztem Gehalt", "Since last salary")
        }
    }
}

/// Links incoming IBANs and single bookings to income forecasts.
@MainActor
public enum IncomeAssignmentStore {
    private static let ibanKey = "iban"
    private static let forecastKey = "forecastID"

    public static var primaryForecastID: UUID? {
        LinkTable.map(.incomePrimary)[forecastKey].flatMap(UUID.init(uuidString:))
    }

    /// Stores the primary income's IBAN and forecast.
    public static func setPrimary(iban: String, forecastID: UUID) {
        let normalized = normalize(iban)
        var values = [forecastKey: forecastID.uuidString]
        if !normalized.isEmpty { values[ibanKey] = normalized }
        LinkTable.replace(.incomePrimary, with: values)
    }

    /// Replaces the secondary income mappings.
    public static func setSecondary(_ values: [(iban: String, forecastID: UUID)]) {
        let pairs = values.compactMap { value -> (String, String)? in
            let iban = normalize(value.iban)
            return iban.isEmpty ? nil : (iban, value.forecastID.uuidString)
        }
        LinkTable.replace(.incomeSecondary, with: Dictionary(pairs, uniquingKeysWith: { _, newest in newest }))
    }

    /// Returns the secondary mappings by IBAN.
    public static func secondaryMappings() -> [String: String] {
        LinkTable.map(.incomeSecondary)
    }

    /// Adds one secondary income mapping.
    public static func addSecondary(iban: String, forecastID: UUID) {
        guard !iban.isEmpty else { return }
        LinkTable.set(.incomeSecondary, key: iban, value: forecastID.uuidString)
    }

    /// Returns the forecasts assigned to single bookings.
    public static func entryAssignments() -> [String: String] {
        LinkTable.map(.incomeEntry)
    }

    public static var primaryIBAN: String? {
        LinkTable.map(.incomePrimary)[ibanKey]
    }

    /// Finds the forecast of an IBAN.
    public static func forecastID(for iban: String) -> UUID? {
        let normalized = normalize(iban)
        guard !normalized.isEmpty else { return nil }
        if primaryIBAN == normalized, let primaryForecastID {
            return primaryForecastID
        }
        return secondaryMappings()[normalized].flatMap(UUID.init(uuidString:))
    }

    /// Assigns one booking to a forecast.
    public static func assign(entryID: UUID, to forecastID: UUID) {
        LinkTable.set(.incomeEntry, key: entryID.uuidString, value: forecastID.uuidString)
    }

    /// Removes a booking's assignment.
    public static func clear(entryID: UUID) {
        LinkTable.set(.incomeEntry, key: entryID.uuidString, value: nil)
    }

    /// Lists the IBANs of a forecast.
    public static func ibans(for forecastID: UUID) -> [String] {
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

    /// Returns the forecast assigned to a booking.
    public static func forecastID(forEntryID entryID: UUID) -> UUID? {
        entryAssignments()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    /// Removes all income assignments.
    public static func reset() {
        [.incomePrimary, .incomeSecondary, .incomeEntry].forEach(LinkTable.clear)
    }

    /// Hashes the stored assignments, so views notice a change.
    public static func fingerprint() -> Int {
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

    /// Normalizes an IBAN for comparison.
    private static func normalize(_ iban: String) -> String {
        iban.replacingOccurrences(of: " ", with: "").uppercased()
    }
}

/// Links a refund booking to the expense it pays back. The map is refund id → original id.
@MainActor
public enum RefundLinkStore {

    /// Links a refund to its original booking.
    public static func link(refundID: UUID, to originalID: UUID) {
        guard refundID != originalID else { return }
        var map = mapping()
        map[refundID.uuidString] = originalID.uuidString
        save(map)
    }

    /// Returns the original booking of a refund.
    public static func originalID(for refundID: UUID) -> UUID? {
        mapping()[refundID.uuidString].flatMap(UUID.init(uuidString:))
    }

    private static var reverse: (revision: Int, ids: [String: [UUID]])?

    /// Lists the refunds of a booking, using a lookup that is rebuilt only after a change.
    public static func refundIDs(for originalID: UUID) -> [UUID] {
        let revision = LinkTable.revision
        if reverse?.revision != revision {
            var ids: [String: [UUID]] = [:]
            for (refund, original) in mapping() {
                if let id = UUID(uuidString: refund) { ids[original, default: []].append(id) }
            }
            reverse = (revision, ids)
        }
        return reverse?.ids[originalID.uuidString] ?? []
    }

    /// Says whether the booking is a refund.
    public static func isRefund(_ entryID: UUID) -> Bool {
        mapping()[entryID.uuidString] != nil
    }

    /// Says whether the booking has a refund.
    public static func isRefunded(_ originalID: UUID) -> Bool {
        !refundIDs(for: originalID).isEmpty
    }

    /// Removes a refund link.
    public static func unlink(refundID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: refundID.uuidString) != nil else { return }
        save(map)
    }

    /// Removes all links that touch a booking.
    public static func removeAll(touching id: UUID) {
        let token = id.uuidString
        let map = mapping().filter { $0.key != token && $0.value != token }
        save(map)
    }

    /// What still counts as an expense. A partial refund leaves the remainder.
    public static func countedExpenseCents(of entry: LedgerEntry, entries: [LedgerEntry]) -> Int {
        max(0, abs(entry.amountCents) - refundedCents(for: entry.id, entries: entries))
    }

    /// Signed remainder shown under the original expense. Nil when nothing is linked or the refunds are not in `entries`.
    public static func realExpenseCents(of entry: LedgerEntry, entries: [LedgerEntry]) -> Int? {
        let ids = Set(refundIDs(for: entry.id))
        guard !ids.isEmpty else { return nil }
        let linked = entries.filter { ids.contains($0.id) }
        guard !linked.isEmpty else { return nil }
        let refunded = linked.reduce(0) { $0 + abs($1.amountCents) }
        return -max(0, abs(entry.amountCents) - refunded)
    }

    /// Removes all refund links.
    public static func reset() {
        LinkTable.clear(.refund)
    }

    /// Hashes the refund links, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    /// Sums the refunds of a booking.
    private static func refundedCents(for originalID: UUID, entries: [LedgerEntry]) -> Int {
        let ids = Set(refundIDs(for: originalID))
        guard !ids.isEmpty else { return 0 }
        return entries.reduce(0) { total, entry in
            ids.contains(entry.id) ? total + abs(entry.amountCents) : total
        }
    }

    /// Reads the refund links.
    private static func mapping() -> [String: String] {
        LinkTable.map(.refund)
    }

    /// Writes the refund links.
    private static func save(_ map: [String: String]) {
        LinkTable.replace(.refund, with: map)
    }
}

/// A planned transfer between two accounts.
public struct TransferForecastRecord: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var amountCents: Int
    public var fromAccountID: UUID?
    public var toAccountID: UUID?
    public var cadenceRaw: String
    public var firstDate: Date
    public var endDate: Date?
    public var dueRuleRaw: String
    public var dayOfMonth: Int
    public var active: Bool

    public var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    public var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    public init(
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

/// Stores the planned transfers.
@MainActor
public enum TransferForecastStore {
    public static let backupType = "transferForecast"
    private static var cached: [TransferForecastRecord]?

    /// Drops the in-memory copy.
    public static func clearCache() {
        cached = nil
    }

    /// Returns all planned transfers.
    public static func all() -> [TransferForecastRecord] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredTransferForecast>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.map(\.record)
        cached = decoded
        return decoded
    }

    /// Adds a transfer or replaces the one with the same ID.
    public static func upsert(_ record: TransferForecastRecord) {
        var records = all()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        save(records)
    }

    /// Deletes a planned transfer.
    public static func remove(id: UUID) {
        save(all().filter { $0.id != id })
        TransferForecastAssignmentStore.removeForecast(id)
    }

    /// Deletes all planned transfers.
    public static func reset() {
        LififyDatabase.deleteAll(StoredTransferForecast.self)
        cached = []
        TransferForecastAssignmentStore.reset()
    }

    /// Exports the transfers for a backup.
    public static func exportRecords() -> [BackupRecord] {
        all().compactMap { record in
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            return BackupRecord(type: backupType, id: record.id, strings: [String(decoding: data, as: UTF8.self)])
        }
    }

    /// Restores one transfer from a backup.
    public static func restore(_ record: BackupRecord) {
        guard let text = record.strings.first,
              let value = try? JSONDecoder().decode(TransferForecastRecord.self, from: Data(text.utf8))
        else { return }
        upsert(value)
    }

    /// Writes the transfers to the database.
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
public enum TransferForecastAssignmentStore {

    /// Assigns a booking to a planned transfer.
    public static func assign(entryID: UUID, forecastID: UUID) {
        var map = mapping()
        map[entryID.uuidString] = forecastID.uuidString
        save(map)
    }

    /// Returns the planned transfer of a booking.
    public static func forecastID(for entryID: UUID) -> UUID? {
        mapping()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    /// Removes a booking's assignment.
    public static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    /// Removes all assignments to a planned transfer.
    public static func removeForecast(_ forecastID: UUID) {
        let token = forecastID.uuidString
        save(mapping().filter { $0.value != token })
    }

    /// Removes all transfer assignments.
    public static func reset() {
        LinkTable.clear(.transferAssignment)
    }

    /// Hashes the assignments, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    /// Reads the assignments.
    private static func mapping() -> [String: String] {
        LinkTable.map(.transferAssignment)
    }

    /// Writes the assignments.
    private static func save(_ map: [String: String]) {
        LinkTable.replace(.transferAssignment, with: map)
    }
}

/// The kinds of forecast a booking or skip can refer to.
public enum ForecastRefKind: String, Codable {
    case income
    case fixed
    case transfer
    case variable
    case shopping
}

/// Hides one forecast date without deleting the series.
@MainActor
public enum ForecastSkipStore {
    public static let revisionKey = "lifify.forecastSkipRevision"

    /// Skips a forecast on one day.
    public static func skip(_ kind: ForecastRefKind, id: UUID, on day: Date) {
        var values = all()
        values.insert(token(kind, id, day))
        save(values)
    }

    /// Says whether a forecast is skipped on that day.
    public static func isSkipped(_ kind: ForecastRefKind, id: UUID, on day: Date) -> Bool {
        LinkTable.map(.forecastSkip)[token(kind, id, day)] != nil
    }

    /// Removes all skips.
    public static func reset() {
        LinkTable.clear(.forecastSkip)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Hashes the skips, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for value in all().sorted() {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    /// Builds the storage key of a skip.
    private static func token(_ kind: ForecastRefKind, _ id: UUID, _ day: Date) -> String {
        "\(kind.rawValue)|\(id.uuidString)|\(day.dayKey)"
    }

    /// Reads all skips.
    private static func all() -> Set<String> {
        Set(LinkTable.map(.forecastSkip).keys)
    }

    /// Writes all skips.
    private static func save(_ values: Set<String>) {
        LinkTable.replace(.forecastSkip, with: Dictionary(uniqueKeysWithValues: values.map { ($0, "") }))
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Reads the change counter.
    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

/// A real booking replaces every occurrence of one forecast inside its period.
@MainActor
public enum ForecastPeriodLinkStore {
    public static let revisionKey = "lifify.forecastLinkRevision"

    /// Links a booking to a forecast for its period.
    public static func assign(entryID: UUID, kind: ForecastRefKind, forecastID: UUID) {
        var map = mapping()
        map[entryID.uuidString] = "\(kind.rawValue)|\(forecastID.uuidString)"
        save(map)
    }

    /// Returns the forecast linked to a booking.
    public static func link(for entryID: UUID) -> (kind: ForecastRefKind, id: UUID)? {
        guard let raw = mapping()[entryID.uuidString] else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = ForecastRefKind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        return (kind, id)
    }

    /// Says whether a linked booking covers the forecast in the period.
    public static func covers(_ kind: ForecastRefKind, id: UUID, entries: [LedgerEntry], period: ForecastPeriod) -> Bool {
        let wanted = "\(kind.rawValue)|\(id.uuidString)"
        let linked = Set(mapping().compactMap { $0.value == wanted ? UUID(uuidString: $0.key) : nil })
        guard !linked.isEmpty else { return false }
        return entries.contains { linked.contains($0.id) && period.contains($0.date) }
    }

    /// Removes a booking's link.
    public static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    /// Removes all period links.
    public static func reset() {
        LinkTable.clear(.forecastPeriod)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Hashes the links, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for pair in mapping().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
        return hasher.finalize()
    }

    /// Reads the links.
    private static func mapping() -> [String: String] {
        LinkTable.map(.forecastPeriod)
    }

    /// Writes the links.
    private static func save(_ map: [String: String]) {
        LinkTable.replace(.forecastPeriod, with: map)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Reads the change counter.
    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

/// Stops a same-day fixed-cost match from attaching again after the user removes it.
@MainActor
public enum ForecastMatchRejectionStore {
    public static let revisionKey = "lifify.forecastMatchRejectionRevision"

    /// Remembers that a booking is not a match for a fixed cost.
    public static func reject(costID: UUID, entryID: UUID) {
        var values = all()
        values.insert(token(costID, entryID))
        save(values)
    }

    /// Says whether the match was rejected.
    public static func isRejected(costID: UUID, entryID: UUID) -> Bool {
        let rejected = LinkTable.map(.matchRejection)
        guard !rejected.isEmpty else { return false }
        return rejected[token(costID, entryID)] != nil
    }

    /// Removes all rejections.
    public static func reset() {
        LinkTable.clear(.matchRejection)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Hashes the rejections, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(revision())
        for value in all().sorted() {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    /// Builds the storage key of a rejection.
    private static func token(_ costID: UUID, _ entryID: UUID) -> String {
        "fixed|\(costID.uuidString)|\(entryID.uuidString)"
    }

    /// Reads all rejections.
    private static func all() -> Set<String> {
        Set(LinkTable.map(.matchRejection).keys)
    }

    /// Writes all rejections.
    private static func save(_ values: Set<String>) {
        LinkTable.replace(.matchRejection, with: Dictionary(uniqueKeysWithValues: values.map { ($0, "") }))
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Reads the change counter.
    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}

/// Which expense group shows a booking. The booking itself is not changed.
@MainActor
public enum ExpenseGroupAssignmentStore {
    public static let revisionKey = "lifify.expenseGroupAssignmentRevision"

    /// Returns the expense group of a booking.
    public static func groupID(for entryID: UUID) -> UUID? {
        mapping()[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    /// Lists the bookings of an expense group.
    public static func entryIDs(in groupID: UUID) -> [UUID] {
        let token = groupID.uuidString
        return mapping().compactMap { entryID, assigned in
            guard assigned == token else { return nil }
            return UUID(uuidString: entryID)
        }
    }

    /// Lists all booking and group pairs.
    public static func pairs() -> [(entryID: UUID, groupID: UUID)] {
        mapping().compactMap { entryID, groupID in
            guard let entryID = UUID(uuidString: entryID), let groupID = UUID(uuidString: groupID) else { return nil }
            return (entryID, groupID)
        }
    }

    /// Replaces the bookings of a group.
    public static func replace(groupID: UUID, entryIDs: Set<UUID>) {
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

    /// Removes a booking from its group.
    public static func clear(entryID: UUID) {
        var map = mapping()
        guard map.removeValue(forKey: entryID.uuidString) != nil else { return }
        save(map)
    }

    /// Removes all assignments to a group.
    public static func removeGroup(_ groupID: UUID) {
        let token = groupID.uuidString
        save(mapping().filter { $0.value != token })
    }

    /// Removes all group assignments.
    public static func reset() {
        LinkTable.clear(.expenseGroup)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Reads the assignments.
    private static func mapping() -> [String: String] {
        LinkTable.map(.expenseGroup)
    }

    /// Writes the assignments.
    private static func save(_ map: [String: String]) {
        LinkTable.replace(.expenseGroup, with: map)
        AppDefaults.store.set(revision() + 1, forKey: revisionKey)
    }

    /// Reads the change counter.
    private static func revision() -> Int {
        AppDefaults.store.integer(forKey: revisionKey)
    }
}
