import Foundation
import SwiftData

/// One entry of a small relation between records, such as refund → original booking.
@Model
public final class StoredLink {
    @Attribute(.unique) public var rowID: String
    public var kindRaw: String
    public var key: String
    public var value: String

    public init(kind: LinkKind, key: String, value: String) {
        rowID = "\(kind.rawValue)|\(key)"
        kindRaw = kind.rawValue
        self.key = key
        self.value = value
    }
}

public enum LinkKind: String, CaseIterable, Codable, Sendable {
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

    public static let financeRecords: [LinkKind] = [
        .refund, .transferAssignment, .forecastSkip, .forecastPeriod, .matchRejection,
        .budgetAccounts, .bankCursor, .bankCurrent
    ]
    public static let challengeRecords: [LinkKind] = [.pinnedChallenges, .pinnedGroups, .eventOffer, .fastFoodReward]
}

/// Reads and writes the finance relations. Reads come from memory after the first load.
@MainActor
public enum LinkTable {
    public static let backupType = "financeLink"
    public static let challengeBackupType = "challengeLink"
    private static var cached: [LinkKind: [String: String]] = [:]
    /// Changes with every write, so derived lookups know when to rebuild.
    public private(set) static var revision = 0

    public static func clearCache() {
        cached = [:]
        revision &+= 1
    }

    public static func map(_ kind: LinkKind) -> [String: String] {
        if let values = cached[kind] { return values }
        let raw = kind.rawValue
        let rows = LififyDatabase.rows(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.kindRaw == raw }))
        let values = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        cached[kind] = values
        return values
    }

    public static func replace(_ kind: LinkKind, with values: [String: String]) {
        let current = map(kind)
        guard current != values else { return }
        cached[kind] = values
        revision &+= 1
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

    public static func set(_ kind: LinkKind, key: String, value: String?) {
        var values = map(kind)
        values[key] = value
        replace(kind, with: values)
    }

    public static func clear(_ kind: LinkKind) {
        replace(kind, with: [:])
    }

    public static func exportRecords() -> [BackupRecord] {
        records(LinkKind.financeRecords, type: backupType) + records(LinkKind.challengeRecords, type: challengeBackupType)
    }

    private static func records(_ kinds: [LinkKind], type: String) -> [BackupRecord] {
        kinds.flatMap { kind in
            map(kind).map { key, value in
                BackupRecord(type: type, id: UUID(), strings: [kind.rawValue, key, value])
            }
        }
    }

    public static func decoded<T: Decodable>(_ kind: LinkKind, as type: T.Type) -> [String: T] {
        map(kind).compactMapValues { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    public static func encoded<T: Encodable>(_ values: [String: T]) -> [String: String] {
        values.compactMapValues { value in
            (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    public static func replaceEncoded<T: Encodable>(_ kind: LinkKind, with values: [String: T]) {
        replace(kind, with: encoded(values))
    }

    public static func restore(_ record: BackupRecord) {
        guard record.strings.count == 3, let kind = LinkKind(rawValue: record.strings[0]) else { return }
        set(kind, key: record.strings[1], value: record.strings[2])
    }
}
