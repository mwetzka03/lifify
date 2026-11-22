import Foundation
import SwiftData

/// One entry of a small relation between finance records, such as refund → original booking.
@Model
final class StoredFinanceLink {
    @Attribute(.unique) var rowID: String
    var kindRaw: String
    var key: String
    var value: String

    init(kind: FinanceLinkKind, key: String, value: String) {
        rowID = "\(kind.rawValue)|\(key)"
        kindRaw = kind.rawValue
        self.key = key
        self.value = value
    }
}

@Model
final class StoredTransferForecast {
    @Attribute(.unique) var forecastID: UUID
    var position: Int
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

    init(_ record: TransferForecastRecord, position: Int) {
        forecastID = record.id
        self.position = position
        name = record.name
        amountCents = record.amountCents
        fromAccountID = record.fromAccountID
        toAccountID = record.toAccountID
        cadenceRaw = record.cadenceRaw
        firstDate = record.firstDate
        endDate = record.endDate
        dueRuleRaw = record.dueRuleRaw
        dayOfMonth = record.dayOfMonth
        active = record.active
    }

    var record: TransferForecastRecord {
        var record = TransferForecastRecord(
            id: forecastID,
            name: name,
            amountCents: amountCents,
            fromAccountID: fromAccountID,
            toAccountID: toAccountID,
            firstDate: firstDate,
            endDate: endDate,
            dayOfMonth: dayOfMonth,
            active: active
        )
        record.cadenceRaw = cadenceRaw
        record.dueRuleRaw = dueRuleRaw
        return record
    }
}

/// A Shortcuts template. The template's own rules decide how its fields are read.
@Model
final class StoredNoticeTemplate {
    var position: Int
    var payload: Data

    init(payload: Data, position: Int) {
        self.payload = payload
        self.position = position
    }
}

enum FinanceLinkKind: String, CaseIterable, Codable {
    case refund
    case transferAssignment
    case forecastSkip
    case forecastPeriod
    case matchRejection
    case expenseGroup
    case incomePrimary
    case incomeSecondary
    case incomeEntry
    case budgetAccounts
    case bankCursor
    case bankCurrent

    /// These already have their own backup record types.
    var hasOwnBackupRecord: Bool {
        switch self {
        case .expenseGroup, .incomePrimary, .incomeSecondary, .incomeEntry: true
        default: false
        }
    }
}

/// Reads and writes the finance relations. Reads come from memory after the first load.
@MainActor
enum FinanceLinkTable {
    static let backupType = "financeLink"
    private static var cached: [FinanceLinkKind: [String: String]] = [:]

    static func clearCache() {
        cached = [:]
    }

    static func map(_ kind: FinanceLinkKind) -> [String: String] {
        if let values = cached[kind] { return values }
        let raw = kind.rawValue
        let rows = LififyDatabase.rows(FetchDescriptor<StoredFinanceLink>(predicate: #Predicate { $0.kindRaw == raw }))
        let values = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        cached[kind] = values
        return values
    }

    static func replace(_ kind: FinanceLinkKind, with values: [String: String]) {
        let current = map(kind)
        guard current != values else { return }
        cached[kind] = values
        guard let context = LififyDatabase.sideContext else { return }
        let raw = kind.rawValue
        let rows = (try? context.fetch(FetchDescriptor<StoredFinanceLink>(predicate: #Predicate { $0.kindRaw == raw }))) ?? []
        var seen = Set<String>()
        for row in rows {
            if let value = values[row.key] {
                row.value = value
                seen.insert(row.key)
            } else {
                context.delete(row)
            }
        }
        for (key, value) in values where !seen.contains(key) {
            context.insert(StoredFinanceLink(kind: kind, key: key, value: value))
        }
        LififyDatabase.saveSide()
    }

    static func set(_ kind: FinanceLinkKind, key: String, value: String?) {
        var values = map(kind)
        values[key] = value
        replace(kind, with: values)
    }

    static func clear(_ kind: FinanceLinkKind) {
        replace(kind, with: [:])
    }

    static func exportRecords() -> [BackupRecord] {
        FinanceLinkKind.allCases.filter { !$0.hasOwnBackupRecord }.flatMap { kind in
            map(kind).map { key, value in
                BackupRecord(type: backupType, id: UUID(), strings: [kind.rawValue, key, value])
            }
        }
    }

    static func restore(_ record: BackupRecord) {
        guard record.strings.count == 3, let kind = FinanceLinkKind(rawValue: record.strings[0]) else { return }
        set(kind, key: record.strings[1], value: record.strings[2])
    }
}
