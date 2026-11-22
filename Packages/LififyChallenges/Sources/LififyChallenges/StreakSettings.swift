import Foundation
import LififyCore
import SwiftData

/// Streak switches, per-challenge freezes, and the global coin multiplier.
/// Stored beside the data model so an existing store stays readable.
@MainActor
public enum StreakSettings {
    public static let revisionKey = "lifify.streakRevision"
    public static let freezeFactorKey = "lifify.streakFreezeFactor"
    public nonisolated static let thresholds = [5, 10, 15, 20, 25, 50, 100, 200, 250, 500, 1000]
    public static let defaultMultipliers: [Int: Double] = [
        5: 1.1,
        10: 1.2,
        15: 1.3,
        20: 1.4,
        25: 1.5,
        50: 1.75,
        100: 2,
        200: 2.25,
        250: 2.5,
        500: 2.75,
        1000: 3
    ]

    public struct State: Codable, Equatable {
        public var enabled: Bool
        public var enabledAt: Date
        public var purchased: Int
        public var usedPeriodKeys: [String]

        public init(enabled: Bool, enabledAt: Date, purchased: Int, usedPeriodKeys: [String]) {
            self.enabled = enabled
            self.enabledAt = enabledAt
            self.purchased = purchased
            self.usedPeriodKeys = usedPeriodKeys
        }
    }

    private static let multiplierKey = "lifify.streakMultipliers"
    private static var cachedStates: [String: State]?
    private static var cachedMultipliers: [Int: Double]?

    public static func clearCache() {
        cachedStates = nil
        cachedMultipliers = nil
    }

    public static func isEnabled(for challengeID: UUID) -> Bool {
        states()[challengeID.uuidString]?.enabled == true
    }

    public static func setEnabled(_ enabled: Bool, for challengeID: UUID) {
        var map = states()
        var state = map[challengeID.uuidString] ?? State(enabled: false, enabledAt: .now, purchased: 0, usedPeriodKeys: [])
        if enabled, !state.enabled {
            state.enabledAt = .now
        }
        state.enabled = enabled
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    public static func balance(for challengeID: UUID) -> Int {
        guard let state = states()[challengeID.uuidString], state.enabled else { return 0 }
        return max(0, StreakFreeze.startingCount + state.purchased - state.usedPeriodKeys.count)
    }

    public static var freezeFactor: Int {
        guard let stored = AppDefaults.store.object(forKey: freezeFactorKey) as? Int else { return 10 }
        return max(stored, 1)
    }

    public static func setFreezeFactor(_ value: Int) {
        AppDefaults.store.set(max(value, 1), forKey: freezeFactorKey)
        bump()
    }

    public static func resetFreezeFactor() {
        AppDefaults.store.removeObject(forKey: freezeFactorKey)
        bump()
    }

    public static func price(rewardCoins: Int, factor: Int) -> Int {
        max(rewardCoins, 0) * max(factor, 1)
    }

    /// Whole numbers from 1 up. A comma or a dot is not a factor.
    public static func wholeFactor(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed), value >= 1 else { return nil }
        return value
    }

    public static func price(for challenge: ChallengeItem) -> Int {
        price(rewardCoins: challenge.rewardCoins, factor: freezeFactor)
    }

    public static func addPurchasedFreeze(for challengeID: UUID) {
        var map = states()
        var state = map[challengeID.uuidString] ?? State(enabled: true, enabledAt: .now, purchased: 0, usedPeriodKeys: [])
        state.purchased += 1
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    public static func setUsedPeriodKeys(_ keys: [String], for challengeID: UUID) {
        var map = states()
        guard var state = map[challengeID.uuidString] else { return }
        let unique = Array(Set(keys)).sorted()
        guard unique != state.usedPeriodKeys.sorted() else { return }
        state.usedPeriodKeys = unique
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    public static func state(for challengeID: UUID) -> State? {
        states()[challengeID.uuidString]
    }

    public static func multiplier(forStreak streak: Int) -> Double {
        factor(forStreak: streak, configured: effectiveMultipliers())
    }

    public static func merging(_ stored: [Int: Double]) -> [Int: Double] {
        var map = defaultMultipliers
        for (key, value) in stored where thresholds.contains(key) {
            map[key] = value
        }
        return map
    }

    public static func effectiveMultipliers() -> [Int: Double] {
        merging(multipliers())
    }

    public static func factor(forStreak streak: Int, configured: [Int: Double]) -> Double {
        guard let threshold = thresholds.last(where: { $0 <= streak && configured[$0] != nil }) else { return 1 }
        let value = configured[threshold] ?? 1
        return value >= 0 ? value : 1
    }

    public static func storedMultiplier(for threshold: Int) -> Double {
        let value = effectiveMultipliers()[threshold] ?? 1
        return value >= 0 ? value : 1
    }

    public static func setMultiplier(_ value: Double, for threshold: Int) {
        guard thresholds.contains(threshold) else { return }
        var map = multipliers()
        map[threshold] = max(value, 0)
        saveMultipliers(map)
    }

    public static func editString(for threshold: Int) -> String {
        let value = storedMultiplier(for: threshold)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "1"
    }

    public static func parseMultiplier(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            return max(number.doubleValue, 0)
        }
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized).map { max($0, 0) }
    }

    public static func remove(for challengeID: UUID) {
        var map = states()
        guard map.removeValue(forKey: challengeID.uuidString) != nil else { return }
        saveStates(map)
    }

    public static func removeAllChallenges() {
        saveStates([:])
    }

    public static func resetMultipliers() {
        saveMultipliers([:])
    }

    public static func reset() {
        cachedStates = [:]
        cachedMultipliers = [:]
        LififyDatabase.deleteAll(StoredStreakState.self)
        AppDefaults.store.removeObject(forKey: multiplierKey)
        AppDefaults.store.removeObject(forKey: freezeFactorKey)
        bump()
    }

    public static func exportStateRecords() -> [BackupRecord] {
        states().compactMap { key, state in
            guard let id = UUID(uuidString: key) else { return nil }
            return BackupRecord(
                type: "streakState",
                id: id,
                strings: state.usedPeriodKeys,
                integers: [state.purchased],
                booleans: [state.enabled],
                dates: [state.enabledAt]
            )
        }
    }

    public static func exportFreezeFactorRecord() -> BackupRecord {
        BackupRecord(type: "streakFreezeFactor", id: UUID(), integers: [freezeFactor])
    }

    public static func restoreFreezeFactor(_ record: BackupRecord) {
        setFreezeFactor(record.integers.first ?? 10)
    }

    public static func exportMultiplierRecords() -> [BackupRecord] {
        effectiveMultipliers().map { threshold, value in
            BackupRecord(
                type: "streakMultiplier",
                id: UUID(),
                integers: [threshold],
                doubles: [value]
            )
        }
    }

    public static func restoreState(_ record: BackupRecord) {
        var map = states()
        map[record.id.uuidString] = State(
            enabled: record.booleans.first ?? false,
            enabledAt: record.dates.compactMap { $0 }.first ?? .now,
            purchased: record.integers.first ?? 0,
            usedPeriodKeys: record.strings
        )
        saveStates(map)
    }

    public static func restoreMultiplier(_ record: BackupRecord) {
        guard let threshold = record.integers.first, let value = record.doubles.first else { return }
        setMultiplier(value, for: threshold)
    }

    private static func states() -> [String: State] {
        if let cachedStates { return cachedStates }
        var decoded: [String: State] = [:]
        for row in LififyDatabase.rows(FetchDescriptor<StoredStreakState>()) {
            decoded[row.challengeID.uuidString] = row.state
        }
        cachedStates = decoded
        return decoded
    }

    private static func multipliers() -> [Int: Double] {
        if let cachedMultipliers { return cachedMultipliers }
        let decoded: [Int: Double]
        if let data = AppDefaults.store.data(forKey: multiplierKey),
           let raw = try? JSONDecoder().decode([String: Double].self, from: data) {
            decoded = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
        } else {
            decoded = [:]
        }
        cachedMultipliers = decoded
        return decoded
    }

    private static func saveStates(_ map: [String: State]) {
        if let context = LififyDatabase.sideContext {
            let rows = (try? context.fetch(FetchDescriptor<StoredStreakState>())) ?? []
            var existing = Dictionary(rows.map { ($0.challengeID, $0) }, uniquingKeysWith: { first, _ in first })
            for (key, state) in map {
                guard let id = UUID(uuidString: key) else { continue }
                if let row = existing.removeValue(forKey: id) {
                    if row.state != state {
                        row.enabled = state.enabled
                        row.enabledAt = state.enabledAt
                        row.purchased = state.purchased
                        row.usedPeriodKeysData = (try? JSONEncoder().encode(state.usedPeriodKeys)) ?? Data("[]".utf8)
                    }
                } else {
                    context.insert(StoredStreakState(challengeID: id, state: state))
                }
            }
            existing.values.forEach(context.delete)
            LififyDatabase.saveSide()
        }
        cachedStates = map
        bump()
    }

    private static func saveMultipliers(_ map: [Int: Double]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        AppDefaults.store.set(data, forKey: multiplierKey)
        cachedMultipliers = map
        bump()
    }

    private static func bump() {
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
