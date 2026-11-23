import Foundation
import LififyCore

/// One relapse with how long the run lasted.
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

/// A bought reward recorded on an abstinence challenge.
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

/// An in-app notice about a reached bonus.
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

    /// Drops the in-memory copies.
    public static func clearCache() {
        cachedDifficulty = nil
        cachedAwarded = nil
        cachedMultipliers = nil
        cachedRelapses = nil
        cachedNotices = nil
        cachedExceptions = nil
        cachedRewardLinks = nil
    }

    /// Returns a challenge's difficulty.
    public static func difficulty(for challengeID: UUID) -> AbstinenceDifficulty {
        let raw = difficulties()[challengeID.uuidString] ?? ""
        return AbstinenceDifficulty(rawValue: raw) ?? .medium
    }

    /// Stores a challenge's difficulty.
    public static func setDifficulty(_ difficulty: AbstinenceDifficulty, for challengeID: UUID) {
        var map = difficulties()
        map[challengeID.uuidString] = difficulty.rawValue
        saveDifficulties(map)
    }

    /// Returns the bonuses already paid in this run.
    public static func awarded(for challengeID: UUID) -> Set<String> {
        Set(awardedMap()[challengeID.uuidString] ?? [])
    }

    /// Stores the bonuses paid in this run.
    public static func setAwarded(_ milestones: Set<String>, for challengeID: UUID) {
        var map = awardedMap()
        let sorted = milestones.sorted()
        guard sorted != (map[challengeID.uuidString] ?? []).sorted() else { return }
        map[challengeID.uuidString] = sorted
        saveAwarded(map)
    }

    /// Forgets the bonuses paid, so a new run can earn them.
    public static func clearAwarded(for challengeID: UUID) {
        var map = awardedMap()
        guard map.removeValue(forKey: challengeID.uuidString) != nil else { return }
        saveAwarded(map)
    }

    /// Returns the bonus multiplier of a milestone.
    public static func multiplier(for difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> Double {
        let value = effective(difficulty)[milestone.rawValue] ?? 0
        return value >= 0 ? value : 0
    }

    /// Returns all multipliers of a difficulty.
    public static func effective(_ difficulty: AbstinenceDifficulty) -> [String: Double] {
        let stored = multipliers()[difficulty.rawValue] ?? [:]
        return AbstinenceRules.merging(stored, defaults: AbstinenceRules.defaultMultipliers[difficulty] ?? [:])
    }

    /// Stores one multiplier.
    public static func setMultiplier(_ value: Double, difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) {
        var map = multipliers()
        var row = map[difficulty.rawValue] ?? [:]
        row[milestone.rawValue] = max(value, 0)
        map[difficulty.rawValue] = row
        saveMultipliers(map)
    }

    /// Formats a multiplier for editing.
    public static func editString(difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> String {
        format(multiplier(for: difficulty, milestone: milestone))
    }

    /// Lists a challenge's relapses, newest first.
    public static func relapses(for challengeID: UUID) -> [AbstinenceRelapse] {
        (relapseMap()[challengeID.uuidString] ?? []).sorted { $0.date > $1.date }
    }

    /// Records a relapse.
    public static func recordRelapse(_ relapse: AbstinenceRelapse, for challengeID: UUID) {
        var map = relapseMap()
        var list = map[challengeID.uuidString] ?? []
        list.append(relapse)
        map[challengeID.uuidString] = list
        saveRelapses(map)
    }

    /// Lists the notices, newest first.
    public static func notices() -> [AbstinenceNotice] {
        storedNotices().sorted { $0.date > $1.date }
    }

    /// Adds a notice once.
    public static func postNotice(_ notice: AbstinenceNotice) {
        var list = storedNotices()
        guard !list.contains(where: { $0.id == notice.id }) else { return }
        list.append(notice)
        saveNotices(list)
    }

    /// Lists a challenge's reward exceptions, newest first.
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

    /// Returns the challenge linked to a reward.
    public static func rewardLink(for rewardID: UUID) -> UUID? {
        rewardLinks()[rewardID.uuidString].flatMap(UUID.init(uuidString:))
    }

    /// Links a reward to a challenge, or removes the link.
    public static func setRewardLink(_ challengeID: UUID?, for rewardID: UUID) {
        var map = rewardLinks()
        if let challengeID {
            map[rewardID.uuidString] = challengeID.uuidString
        } else {
            map.removeValue(forKey: rewardID.uuidString)
        }
        saveRewardLinks(map)
    }

    /// Removes a notice.
    public static func dismissNotice(_ id: String) {
        var list = storedNotices()
        let count = list.count
        list.removeAll { $0.id == id }
        guard list.count != count else { return }
        saveNotices(list)
    }

    /// Removes everything stored for a challenge.
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

    /// Restores the default multipliers.
    public static func resetMultipliers() {
        saveMultipliers([:])
    }

    /// Clears all abstinence data.
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

    /// Exports the abstinence data for a backup.
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

    /// Restores a difficulty.
    public static func restoreDifficulty(_ record: BackupRecord) {
        guard let raw = record.strings.first, AbstinenceDifficulty(rawValue: raw) != nil else { return }
        var map = difficulties()
        map[record.id.uuidString] = raw
        saveDifficulties(map)
    }

    /// Restores paid bonuses.
    public static func restoreAwarded(_ record: BackupRecord) {
        var map = awardedMap()
        map[record.id.uuidString] = record.strings.sorted()
        saveAwarded(map)
    }

    /// Restores a multiplier.
    public static func restoreMultiplier(_ record: BackupRecord) {
        guard record.strings.count >= 2,
              let difficulty = AbstinenceDifficulty(rawValue: record.strings[0]),
              let milestone = AbstinenceMilestone(rawValue: record.strings[1]),
              let value = record.doubles.first
        else { return }
        setMultiplier(value, difficulty: difficulty, milestone: milestone)
    }

    /// Restores a relapse.
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

    /// Restores a reward exception.
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

    /// Restores a reward link.
    public static func restoreRewardLink(_ record: BackupRecord) {
        guard let challengeID = record.uuids.first ?? nil else { return }
        setRewardLink(challengeID, for: record.id)
    }

    /// Restores a notice.
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

    /// Formats a multiplier.
    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Reads the difficulties.
    private static func difficulties() -> [String: String] {
        if let cachedDifficulty { return cachedDifficulty }
        let decoded = LinkTable.map(.abstinenceDifficulty)
        cachedDifficulty = decoded
        return decoded
    }

    /// Reads the paid bonuses.
    private static func awardedMap() -> [String: [String]] {
        if let cachedAwarded { return cachedAwarded }
        let decoded = LinkTable.decoded(.abstinenceAwarded, as: [String].self)
        cachedAwarded = decoded
        return decoded
    }

    /// Reads the multipliers.
    private static func multipliers() -> [String: [String: Double]] {
        if let cachedMultipliers { return cachedMultipliers }
        let decoded = dictionary(multiplierKey, as: [String: [String: Double]].self) ?? [:]
        cachedMultipliers = decoded
        return decoded
    }

    /// Decodes a stored dictionary.
    private static func dictionary<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = AppDefaults.store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Writes the difficulties.
    private static func saveDifficulties(_ map: [String: String]) {
        LinkTable.replace(.abstinenceDifficulty, with: map)
        bump()
        cachedDifficulty = map
    }

    /// Writes the paid bonuses.
    private static func saveAwarded(_ map: [String: [String]]) {
        LinkTable.replaceEncoded(.abstinenceAwarded, with: map)
        bump()
        cachedAwarded = map
    }

    /// Writes the multipliers.
    private static func saveMultipliers(_ map: [String: [String: Double]]) {
        save(map, key: multiplierKey)
        cachedMultipliers = map
    }

    /// Reads the relapses.
    private static func relapseMap() -> [String: [AbstinenceRelapse]] {
        if let cachedRelapses { return cachedRelapses }
        let decoded = LinkTable.decoded(.abstinenceRelapses, as: [AbstinenceRelapse].self)
        cachedRelapses = decoded
        return decoded
    }

    /// Reads the notices.
    private static func storedNotices() -> [AbstinenceNotice] {
        if let cachedNotices { return cachedNotices }
        let decoded = LinkTable.decoded(.abstinenceNotices, as: [AbstinenceNotice].self)["all"] ?? []
        cachedNotices = decoded
        return decoded
    }

    /// Writes the relapses.
    private static func saveRelapses(_ map: [String: [AbstinenceRelapse]]) {
        LinkTable.replaceEncoded(.abstinenceRelapses, with: map)
        bump()
        cachedRelapses = map
    }

    /// Writes the notices.
    private static func saveNotices(_ list: [AbstinenceNotice]) {
        LinkTable.replaceEncoded(.abstinenceNotices, with: list.isEmpty ? [:] : ["all": list])
        bump()
        cachedNotices = list
    }

    /// Reads the reward exceptions.
    private static func exceptionMap() -> [String: [AbstinenceException]] {
        if let cachedExceptions { return cachedExceptions }
        let decoded = LinkTable.decoded(.abstinenceExceptions, as: [AbstinenceException].self)
        cachedExceptions = decoded
        return decoded
    }

    /// Reads the reward links.
    private static func rewardLinks() -> [String: String] {
        if let cachedRewardLinks { return cachedRewardLinks }
        let decoded = LinkTable.map(.abstinenceRewardLink)
        cachedRewardLinks = decoded
        return decoded
    }

    /// Writes the reward exceptions.
    private static func saveExceptions(_ map: [String: [AbstinenceException]]) {
        LinkTable.replaceEncoded(.abstinenceExceptions, with: map)
        bump()
        cachedExceptions = map
    }

    /// Writes the reward links.
    private static func saveRewardLinks(_ map: [String: String]) {
        LinkTable.replace(.abstinenceRewardLink, with: map)
        bump()
        cachedRewardLinks = map
    }

    /// Encodes and stores a value.
    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        AppDefaults.store.set(data, forKey: key)
        bump()
    }

    /// Signals that the settings changed.
    private static func bump() {
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
