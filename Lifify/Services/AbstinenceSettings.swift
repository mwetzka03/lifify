import Foundation

/// Difficulty, bonus multipliers, and which bonuses this run already paid.
/// Stored beside the data model so an existing store stays readable.
@MainActor
enum AbstinenceSettings {
    static let revisionKey = "lifify.abstinenceRevision"

    private static let difficultyKey = "lifify.abstinenceDifficulty"
    private static let awardedKey = "lifify.abstinenceAwarded"
    private static let multiplierKey = "lifify.abstinenceMultipliers"
    private static var cachedDifficulty: [String: String]?
    private static var cachedAwarded: [String: [String]]?
    private static var cachedMultipliers: [String: [String: Double]]?

    static func difficulty(for challengeID: UUID) -> AbstinenceDifficulty {
        let raw = difficulties()[challengeID.uuidString] ?? ""
        return AbstinenceDifficulty(rawValue: raw) ?? .medium
    }

    static func setDifficulty(_ difficulty: AbstinenceDifficulty, for challengeID: UUID) {
        var map = difficulties()
        map[challengeID.uuidString] = difficulty.rawValue
        saveDifficulties(map)
    }

    static func awarded(for challengeID: UUID) -> Set<String> {
        Set(awardedMap()[challengeID.uuidString] ?? [])
    }

    static func setAwarded(_ milestones: Set<String>, for challengeID: UUID) {
        var map = awardedMap()
        let sorted = milestones.sorted()
        guard sorted != (map[challengeID.uuidString] ?? []).sorted() else { return }
        map[challengeID.uuidString] = sorted
        saveAwarded(map)
    }

    static func clearAwarded(for challengeID: UUID) {
        var map = awardedMap()
        guard map.removeValue(forKey: challengeID.uuidString) != nil else { return }
        saveAwarded(map)
    }

    static func multiplier(for difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> Double {
        let value = effective(difficulty)[milestone.rawValue] ?? 0
        return value >= 0 ? value : 0
    }

    static func effective(_ difficulty: AbstinenceDifficulty) -> [String: Double] {
        let stored = multipliers()[difficulty.rawValue] ?? [:]
        return AbstinenceRules.merging(stored, defaults: AbstinenceRules.defaultMultipliers[difficulty] ?? [:])
    }

    static func setMultiplier(_ value: Double, difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) {
        var map = multipliers()
        var row = map[difficulty.rawValue] ?? [:]
        row[milestone.rawValue] = max(value, 0)
        map[difficulty.rawValue] = row
        saveMultipliers(map)
    }

    static func editString(difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) -> String {
        format(multiplier(for: difficulty, milestone: milestone))
    }

    static func remove(for challengeID: UUID) {
        var storedDifficulties = difficulties()
        var storedAwarded = awardedMap()
        let removedDifficulty = storedDifficulties.removeValue(forKey: challengeID.uuidString) != nil
        let removedAwarded = storedAwarded.removeValue(forKey: challengeID.uuidString) != nil
        if removedDifficulty { saveDifficulties(storedDifficulties) }
        if removedAwarded { saveAwarded(storedAwarded) }
    }

    static func resetMultipliers() {
        saveMultipliers([:])
    }

    static func reset() {
        cachedDifficulty = [:]
        cachedAwarded = [:]
        cachedMultipliers = [:]
        UserDefaults.standard.removeObject(forKey: difficultyKey)
        UserDefaults.standard.removeObject(forKey: awardedKey)
        UserDefaults.standard.removeObject(forKey: multiplierKey)
        bump()
    }

    static func exportRecords() -> [BackupRecord] {
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
        return records
    }

    static func restoreDifficulty(_ record: BackupRecord) {
        guard let raw = record.strings.first, AbstinenceDifficulty(rawValue: raw) != nil else { return }
        var map = difficulties()
        map[record.id.uuidString] = raw
        saveDifficulties(map)
    }

    static func restoreAwarded(_ record: BackupRecord) {
        var map = awardedMap()
        map[record.id.uuidString] = record.strings.sorted()
        saveAwarded(map)
    }

    static func restoreMultiplier(_ record: BackupRecord) {
        guard record.strings.count >= 2,
              let difficulty = AbstinenceDifficulty(rawValue: record.strings[0]),
              let milestone = AbstinenceMilestone(rawValue: record.strings[1]),
              let value = record.doubles.first
        else { return }
        setMultiplier(value, difficulty: difficulty, milestone: milestone)
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private static func difficulties() -> [String: String] {
        if let cachedDifficulty { return cachedDifficulty }
        let decoded = dictionary(difficultyKey, as: [String: String].self) ?? [:]
        cachedDifficulty = decoded
        return decoded
    }

    private static func awardedMap() -> [String: [String]] {
        if let cachedAwarded { return cachedAwarded }
        let decoded = dictionary(awardedKey, as: [String: [String]].self) ?? [:]
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
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func saveDifficulties(_ map: [String: String]) {
        save(map, key: difficultyKey)
        cachedDifficulty = map
    }

    private static func saveAwarded(_ map: [String: [String]]) {
        save(map, key: awardedKey)
        cachedAwarded = map
    }

    private static func saveMultipliers(_ map: [String: [String: Double]]) {
        save(map, key: multiplierKey)
        cachedMultipliers = map
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        bump()
    }

    private static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
