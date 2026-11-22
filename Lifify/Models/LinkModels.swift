import Foundation
import SwiftData

/// One entry of a small relation between records, such as refund → original booking.
@Model
final class StoredLink {
    @Attribute(.unique) var rowID: String
    var kindRaw: String
    var key: String
    var value: String

    init(kind: LinkKind, key: String, value: String) {
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

enum LinkKind: String, CaseIterable, Codable {
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
    case challengeDuration
    case challengeActual
    case challengeMembers
    case challengePlanned
    case abstinenceDifficulty
    case abstinenceAwarded
    case abstinenceRelapses
    case abstinenceNotices
    case abstinenceExceptions
    case abstinenceRewardLink
    case rewardPolicy
    case reminderSync
    case reminderRecurrence
    case eventRecurrence
    case icon
    case customCategories
    case pinnedChallenges
    case pinnedGroups
    case eventOffer
    case fastFoodReward

    static let financeRecords: [LinkKind] = [
        .refund, .transferAssignment, .forecastSkip, .forecastPeriod, .matchRejection,
        .budgetAccounts, .bankCursor, .bankCurrent
    ]
    static let challengeRecords: [LinkKind] = [.pinnedChallenges, .pinnedGroups, .eventOffer, .fastFoodReward]
}

/// Reads and writes the finance relations. Reads come from memory after the first load.
@MainActor
enum LinkTable {
    static let backupType = "financeLink"
    static let challengeBackupType = "challengeLink"
    private static var cached: [LinkKind: [String: String]] = [:]

    static func clearCache() {
        cached = [:]
    }

    static func map(_ kind: LinkKind) -> [String: String] {
        if let values = cached[kind] { return values }
        let raw = kind.rawValue
        let rows = LififyDatabase.rows(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.kindRaw == raw }))
        let values = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        cached[kind] = values
        return values
    }

    static func replace(_ kind: LinkKind, with values: [String: String]) {
        let current = map(kind)
        guard current != values else { return }
        cached[kind] = values
        guard let context = LififyDatabase.sideContext else { return }
        let raw = kind.rawValue
        let rows = (try? context.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.kindRaw == raw }))) ?? []
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
            context.insert(StoredLink(kind: kind, key: key, value: value))
        }
        LififyDatabase.saveSide()
    }

    static func set(_ kind: LinkKind, key: String, value: String?) {
        var values = map(kind)
        values[key] = value
        replace(kind, with: values)
    }

    static func clear(_ kind: LinkKind) {
        replace(kind, with: [:])
    }

    static func exportRecords() -> [BackupRecord] {
        records(LinkKind.financeRecords, type: backupType) + records(LinkKind.challengeRecords, type: challengeBackupType)
    }

    private static func records(_ kinds: [LinkKind], type: String) -> [BackupRecord] {
        kinds.flatMap { kind in
            map(kind).map { key, value in
                BackupRecord(type: type, id: UUID(), strings: [kind.rawValue, key, value])
            }
        }
    }

    static func decoded<T: Decodable>(_ kind: LinkKind, as type: T.Type) -> [String: T] {
        map(kind).compactMapValues { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    static func encoded<T: Encodable>(_ values: [String: T]) -> [String: String] {
        values.compactMapValues { value in
            (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    static func replaceEncoded<T: Encodable>(_ kind: LinkKind, with values: [String: T]) {
        replace(kind, with: encoded(values))
    }

    static func restore(_ record: BackupRecord) {
        guard record.strings.count == 3, let kind = LinkKind(rawValue: record.strings[0]) else { return }
        set(kind, key: record.strings[1], value: record.strings[2])
    }
}
