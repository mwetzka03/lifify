import Foundation
import LififyCore

public struct AbstinenceRelapse: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var lasted: TimeInterval

    public init(id: UUID, date: Date, lasted: TimeInterval) {
        self.id = id
        self.date = date
        self.lasted = lasted
    }
}

public struct AbstinenceException: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var rewardID: UUID
    public var rewardTitle: String

    public init(id: UUID, date: Date, rewardID: UUID, rewardTitle: String) {
        self.id = id
        self.date = date
        self.rewardID = rewardID
        self.rewardTitle = rewardTitle
    }
}

public struct AbstinenceNotice: Codable, Equatable, Identifiable {
    public var id: String
    public var challengeID: UUID
    public var title: String
    public var milestone: String
    public var coins: Int
    public var date: Date

    public init(id: String, challengeID: UUID, title: String, milestone: String, coins: Int, date: Date) {
        self.id = id
        self.challengeID = challengeID
        self.title = title
        self.milestone = milestone
        self.coins = coins
        self.date = date
    }
}

/// Difficulty, bonus multipliers, and which bonuses this run already paid.
/// Stored beside the data model so an existing store stays readable.
@MainActor
public enum AbstinenceSettings {
    public static let revisionKey = "lifify.abstinenceRevision"

    private static let multiplierKey = "lifify.abstinenceMultipliers"
    private static var cachedDifficulty: [String: String]?
    private static var cachedAwarded: [String: [String]]?
    private static var cachedMultipliers: [String: [String: Double]]?
    private static var cachedRelapses: [String: [AbstinenceRelapse]]?
    private static var cachedNotices: [AbstinenceNotice]?
    private static var cachedExceptions: [String: [AbstinenceException]]?
    private static var cachedRewardLinks: [String: String]?

    public static func clearCache() {
        cachedDifficulty = nil
        cachedAwarded = nil
        cachedMultipliers = nil
        cachedRelapses = nil
        cachedNotices = nil
        cachedExceptions = nil
        cachedRewardLinks = nil
    }

    public static func difficulty(for challengeID: UUID) -> AbstinenceDifficulty {
        let raw = difficulties()[challengeID.uuidString] ?? ""
        return AbstinenceDifficulty(rawValue: raw) ?? .medium
    }

    public static func setDifficulty(_ difficulty: AbstinenceDifficulty, for challengeID: UUID) {
        var map = difficulties()
        map[challengeID.uuidString] = difficulty.rawValue
        saveDifficulties(map)
    }

    public static func awarded(for challengeID: UUID) -> Set<String> {
        Set(awardedMap()[challengeID.uuidString] ?? [])
    }

    public static func setAwarded(_ milestones: Set<String>, for challengeID: UUID) {
        var map = awardedMap()
        let sorted = milestones.sorted()
        guard sorted != (map[challengeID.uuidString] ?? []).sorted() else { return }
        map[challengeID.uuidString] = sorted
        saveAwarded(map)
    }

    public static func clearAwarded(for challengeID: UUID) {
        var map = awardedMap()
        guard map.removeValue(forKey: challengeID.uuidString) != nil else { return }
        saveAwarded(map)
    }

    public static func multiplier(for difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> Double {
        let value = effective(difficulty)[milestone.rawValue] ?? 0
        return value >= 0 ? value : 0
    }

    public static func effective(_ difficulty: AbstinenceDifficulty) -> [String: Double] {
        let stored = multipliers()[difficulty.rawValue] ?? [:]
        return AbstinenceRules.merging(stored, defaults: AbstinenceRules.defaultMultipliers[difficulty] ?? [:])
    }

    public static func setMultiplier(_ value: Double, difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) {
        var map = multipliers()
        var row = map[difficulty.rawValue] ?? [:]
        row[milestone.rawValue] = max(value, 0)
        map[difficulty.rawValue] = row
        saveMultipliers(map)
    }

    public static func editString(difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> String {
        format(multiplier(for: difficulty, milestone: milestone))
    }

    public static func relapses(for challengeID: UUID) -> [AbstinenceRelapse] {
        (relapseMap()[challengeID.uuidString] ?? []).sorted { $0.date > $1.date }
    }

    public static func recordRelapse(_ relapse: AbstinenceRelapse, for challengeID: UUID) {
        var map = relapseMap()
        var list = map[challengeID.uuidString] ?? []
        list.append(relapse)
        map[challengeID.uuidString] = list
        saveRelapses(map)
    }

    public static func notices() -> [AbstinenceNotice] {
        storedNotices().sorted { $0.date > $1.date }
    }

    public static func postNotice(_ notice: AbstinenceNotice) {
        var list = storedNotices()
        guard !list.contains(where: { $0.id == notice.id }) else { return }
        list.append(notice)
        saveNotices(list)
    }

    public static func exceptions(for challengeID: UUID) -> [AbstinenceException] {
        (exceptionMap()[challengeID.uuidString] ?? []).sorted { $0.date > $1.date }
    }

    /// Records a bought reward on the abstinence. The timer and the awarded bonuses stay as they are.
    public static func recordException(_ exception: AbstinenceException, for challengeID: UUID) {
        var map = exceptionMap()
        var list = map[challengeID.uuidString] ?? []
        list.append(exception)
        map[challengeID.uuidString] = list
        saveExceptions(map)
    }

    /// Removes one recorded reward exception.
    public static func removeException(_ id: UUID, for challengeID: UUID) {
        var map = exceptionMap()
        guard var list = map[challengeID.uuidString] else { return }
        list.removeAll { $0.id == id }
        map[challengeID.uuidString] = list.isEmpty ? nil : list
        saveExceptions(map)
    }

    public static func rewardLink(for rewardID: UUID) -> UUID? {
        rewardLinks()[rewardID.uuidString].flatMap(UUID.init(uuidString:))
    }

    public static func setRewardLink(_ challengeID: UUID?, for rewardID: UUID) {
        var map = rewardLinks()
        if let challengeID {
            map[rewardID.uuidString] = challengeID.uuidString
        } else {
            map.removeValue(forKey: rewardID.uuidString)
        }
        saveRewardLinks(map)
    }

    public static func dismissNotice(_ id: String) {
        var list = storedNotices()
        let count = list.count
        list.removeAll { $0.id == id }
        guard list.count != count else { return }
        saveNotices(list)
    }

    public static func remove(for challengeID: UUID) {
        var storedDifficulties = difficulties()
        var storedAwarded = awardedMap()
        var storedRelapses = relapseMap()
        let removedDifficulty = storedDifficulties.removeValue(forKey: challengeID.uuidString) != nil
        let removedAwarded = storedAwarded.removeValue(forKey: challengeID.uuidString) != nil
        let removedRelapses = storedRelapses.removeValue(forKey: challengeID.uuidString) != nil
        if removedDifficulty { saveDifficulties(storedDifficulties) }
        if removedAwarded { saveAwarded(storedAwarded) }
        if removedRelapses { saveRelapses(storedRelapses) }
        let notices = storedNotices().filter { $0.challengeID != challengeID }
        if notices.count != storedNotices().count { saveNotices(notices) }
        var exceptions = exceptionMap()
        if exceptions.removeValue(forKey: challengeID.uuidString) != nil { saveExceptions(exceptions) }
        var links = rewardLinks()
        let remaining = links.filter { $0.value != challengeID.uuidString }
        if remaining.count != links.count {
            links = remaining
            saveRewardLinks(links)
        }
    }

    public static func resetMultipliers() {
        saveMultipliers([:])
    }

    public static func reset() {
        cachedDifficulty = [:]
        cachedAwarded = [:]
        cachedMultipliers = [:]
        cachedRelapses = [:]
        cachedNotices = []
        cachedExceptions = [:]
        cachedRewardLinks = [:]
        AppDefaults.store.removeObject(forKey: multiplierKey)
        [.abstinenceDifficulty, .abstinenceAwarded, .abstinenceRelapses, .abstinenceNotices, .abstinenceExceptions, .abstinenceRewardLink]
            .forEach(LinkTable.clear)
        bump()
    }

    public static func exportRecords() -> [BackupRecord] {
        var records: [BackupRecord] = []
        records += difficulties().compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return BackupRecord(type: "abstinenceDifficulty", id: id, strings: [value])
        }
        records += awardedMap().compactMap { key, values in
            guard let id = UUID(uuidString: key) else { return nil }
            return BackupRecord(type: "abstinenceAwarded", id: id, strings: values.sorted())
        }
        records += AbstinenceDifficulty.allCases.flatMap { difficulty in
            effective(difficulty).map { milestone, value in
                BackupRecord(
                    type: "abstinenceMultiplier",
                    id: UUID(),
                    strings: [difficulty.rawValue, milestone],
                    doubles: [value]
                )
            }
        }
        records += relapseMap().flatMap { key, items in
            items.compactMap { item -> BackupRecord? in
                guard let challengeID = UUID(uuidString: key) else { return nil }
                return BackupRecord(
                    type: "abstinenceRelapse",
                    id: item.id,
                    doubles: [item.lasted],
                    dates: [item.date],
                    uuids: [challengeID]
                )
            }
        }
        records += exceptionMap().flatMap { key, items in
            items.compactMap { item -> BackupRecord? in
                guard let challengeID = UUID(uuidString: key) else { return nil }
                return BackupRecord(
                    type: "abstinenceException",
                    id: item.id,
                    strings: [item.rewardTitle],
                    dates: [item.date],
                    uuids: [challengeID, item.rewardID]
                )
            }
        }
        records += rewardLinks().compactMap { key, value in
            guard let rewardID = UUID(uuidString: key), let challengeID = UUID(uuidString: value) else { return nil }
            return BackupRecord(type: "abstinenceRewardLink", id: rewardID, uuids: [challengeID])
        }
        records += storedNotices().map { notice in
            BackupRecord(
                type: "abstinenceNotice",
                id: UUID(),
                strings: [notice.id, notice.title, notice.milestone],
                integers: [notice.coins],
                dates: [notice.date],
                uuids: [notice.challengeID]
            )
        }
        return records
    }

    public static func restoreDifficulty(_ record: BackupRecord) {
        guard let raw = record.strings.first, AbstinenceDifficulty(rawValue: raw) != nil else { return }
        var map = difficulties()
        map[record.id.uuidString] = raw
        saveDifficulties(map)
    }

    public static func restoreAwarded(_ record: BackupRecord) {
        var map = awardedMap()
        map[record.id.uuidString] = record.strings.sorted()
        saveAwarded(map)
    }

    public static func restoreMultiplier(_ record: BackupRecord) {
        guard record.strings.count >= 2,
              let difficulty = AbstinenceDifficulty(rawValue: record.strings[0]),
              let milestone = AbstinenceMilestone(rawValue: record.strings[1]),
              let value = record.doubles.first
        else { return }
        setMultiplier(value, difficulty: difficulty, milestone: milestone)
    }

    public static func restoreRelapse(_ record: BackupRecord) {
        guard let challengeID = record.uuids.first ?? nil,
              let date = record.dates.first ?? nil
        else { return }
        let relapse = AbstinenceRelapse(id: record.id, date: date, lasted: record.doubles.first ?? 0)
        var map = relapseMap()
        var list = map[challengeID.uuidString] ?? []
        guard !list.contains(where: { $0.id == relapse.id }) else { return }
        list.append(relapse)
        map[challengeID.uuidString] = list
        saveRelapses(map)
    }

    public static func restoreException(_ record: BackupRecord) {
        guard let challengeID = record.uuids.first ?? nil,
              let rewardID = record.uuids.dropFirst().first ?? nil,
              let date = record.dates.first ?? nil
        else { return }
        let exception = AbstinenceException(
            id: record.id,
            date: date,
            rewardID: rewardID,
            rewardTitle: record.strings.first ?? ""
        )
        var map = exceptionMap()
        var list = map[challengeID.uuidString] ?? []
        guard !list.contains(where: { $0.id == exception.id }) else { return }
        list.append(exception)
        map[challengeID.uuidString] = list
        saveExceptions(map)
    }

    public static func restoreRewardLink(_ record: BackupRecord) {
        guard let challengeID = record.uuids.first ?? nil else { return }
        setRewardLink(challengeID, for: record.id)
    }

    public static func restoreNotice(_ record: BackupRecord) {
        guard record.strings.count >= 3,
              let challengeID = record.uuids.first ?? nil,
              let date = record.dates.first ?? nil
        else { return }
        postNotice(AbstinenceNotice(
            id: record.strings[0],
            challengeID: challengeID,
            title: record.strings[1],
            milestone: record.strings[2],
            coins: record.integers.first ?? 0,
            date: date
        ))
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private static func difficulties() -> [String: String] {
        if let cachedDifficulty { return cachedDifficulty }
        let decoded = LinkTable.map(.abstinenceDifficulty)
        cachedDifficulty = decoded
        return decoded
    }

    private static func awardedMap() -> [String: [String]] {
        if let cachedAwarded { return cachedAwarded }
        let decoded = LinkTable.decoded(.abstinenceAwarded, as: [String].self)
        cachedAwarded = decoded
        return decoded
    }

    private static func multipliers() -> [String: [String: Double]] {
        if let cachedMultipliers { return cachedMultipliers }
        let decoded = dictionary(multiplierKey, as: [String: [String: Double]].self) ?? [:]
        cachedMultipliers = decoded
        return decoded
    }

    private static func dictionary<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = AppDefaults.store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func saveDifficulties(_ map: [String: String]) {
        LinkTable.replace(.abstinenceDifficulty, with: map)
        bump()
        cachedDifficulty = map
    }

    private static func saveAwarded(_ map: [String: [String]]) {
        LinkTable.replaceEncoded(.abstinenceAwarded, with: map)
        bump()
        cachedAwarded = map
    }

    private static func saveMultipliers(_ map: [String: [String: Double]]) {
        save(map, key: multiplierKey)
        cachedMultipliers = map
    }

    private static func relapseMap() -> [String: [AbstinenceRelapse]] {
        if let cachedRelapses { return cachedRelapses }
        let decoded = LinkTable.decoded(.abstinenceRelapses, as: [AbstinenceRelapse].self)
        cachedRelapses = decoded
        return decoded
    }

    private static func storedNotices() -> [AbstinenceNotice] {
        if let cachedNotices { return cachedNotices }
        let decoded = LinkTable.decoded(.abstinenceNotices, as: [AbstinenceNotice].self)["all"] ?? []
        cachedNotices = decoded
        return decoded
    }

    private static func saveRelapses(_ map: [String: [AbstinenceRelapse]]) {
        LinkTable.replaceEncoded(.abstinenceRelapses, with: map)
        bump()
        cachedRelapses = map
    }

    private static func saveNotices(_ list: [AbstinenceNotice]) {
        LinkTable.replaceEncoded(.abstinenceNotices, with: list.isEmpty ? [:] : ["all": list])
        bump()
        cachedNotices = list
    }

    private static func exceptionMap() -> [String: [AbstinenceException]] {
        if let cachedExceptions { return cachedExceptions }
        let decoded = LinkTable.decoded(.abstinenceExceptions, as: [AbstinenceException].self)
        cachedExceptions = decoded
        return decoded
    }

    private static func rewardLinks() -> [String: String] {
        if let cachedRewardLinks { return cachedRewardLinks }
        let decoded = LinkTable.map(.abstinenceRewardLink)
        cachedRewardLinks = decoded
        return decoded
    }

    private static func saveExceptions(_ map: [String: [AbstinenceException]]) {
        LinkTable.replaceEncoded(.abstinenceExceptions, with: map)
        bump()
        cachedExceptions = map
    }

    private static func saveRewardLinks(_ map: [String: String]) {
        LinkTable.replace(.abstinenceRewardLink, with: map)
        bump()
        cachedRewardLinks = map
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        AppDefaults.store.set(data, forKey: key)
        bump()
    }

    private static func bump() {
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
