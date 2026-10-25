import Foundation

/// Streak switches, per-challenge freezes, and the global coin multiplier.
/// Stored beside the data model so an existing store stays readable.
@MainActor
enum StreakSettings {
    static let revisionKey = "lifify.streakRevision"
    static let thresholds = [5, 10, 15, 20, 25, 50, 100, 200, 250, 500, 1000]

    struct State: Codable, Equatable {
        var enabled: Bool
        var enabledAt: Date
        var purchased: Int
        var usedPeriodKeys: [String]
    }

    private static let stateKey = "lifify.streakStates"
    private static let multiplierKey = "lifify.streakMultipliers"
    private static var cachedStates: [String: State]?
    private static var cachedMultipliers: [Int: Double]?

    static func isEnabled(for challengeID: UUID) -> Bool {
        states()[challengeID.uuidString]?.enabled == true
    }

    static func setEnabled(_ enabled: Bool, for challengeID: UUID) {
        var map = states()
        var state = map[challengeID.uuidString] ?? State(enabled: false, enabledAt: .now, purchased: 0, usedPeriodKeys: [])
        if enabled, !state.enabled {
            state.enabledAt = .now
        }
        state.enabled = enabled
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    static func balance(for challengeID: UUID) -> Int {
        guard let state = states()[challengeID.uuidString], state.enabled else { return 0 }
        return max(0, 2 + state.purchased - state.usedPeriodKeys.count)
    }

    static func price(for challenge: ChallengeItem) -> Int {
        max(challenge.rewardCoins, 0) * 10
    }

    static func addPurchasedFreeze(for challengeID: UUID) {
        var map = states()
        var state = map[challengeID.uuidString] ?? State(enabled: true, enabledAt: .now, purchased: 0, usedPeriodKeys: [])
        state.purchased += 1
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    static func setUsedPeriodKeys(_ keys: [String], for challengeID: UUID) {
        var map = states()
        guard var state = map[challengeID.uuidString] else { return }
        let unique = Array(Set(keys)).sorted()
        guard unique != state.usedPeriodKeys.sorted() else { return }
        state.usedPeriodKeys = unique
        map[challengeID.uuidString] = state
        saveStates(map)
    }

    static func state(for challengeID: UUID) -> State? {
        states()[challengeID.uuidString]
    }

    static func multiplier(forStreak streak: Int) -> Double {
        let configured = multipliers()
        guard let threshold = thresholds.last(where: { $0 <= streak && configured[$0] != nil }) else { return 1 }
        let value = configured[threshold] ?? 1
        return value >= 0 ? value : 1
    }

    static func storedMultiplier(for threshold: Int) -> Double {
        let value = multipliers()[threshold] ?? 1
        return value >= 0 ? value : 1
    }

    static func setMultiplier(_ value: Double, for threshold: Int) {
        guard thresholds.contains(threshold) else { return }
        var map = multipliers()
        map[threshold] = max(value, 0)
        saveMultipliers(map)
    }

    static func editString(for threshold: Int) -> String {
        let value = storedMultiplier(for: threshold)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "1"
    }

    static func parseMultiplier(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            return max(number.doubleValue, 0)
        }
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized).map { max($0, 0) }
    }

    static func remove(for challengeID: UUID) {
        var map = states()
        guard map.removeValue(forKey: challengeID.uuidString) != nil else { return }
        saveStates(map)
    }

    static func removeAllChallenges() {
        saveStates([:])
    }

    static func resetMultipliers() {
        saveMultipliers([:])
    }

    static func reset() {
        cachedStates = [:]
        cachedMultipliers = [:]
        UserDefaults.standard.removeObject(forKey: stateKey)
        UserDefaults.standard.removeObject(forKey: multiplierKey)
        bump()
    }

    static func exportStateRecords() -> [BackupRecord] {
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

    static func exportMultiplierRecords() -> [BackupRecord] {
        multipliers().map { threshold, value in
            BackupRecord(
                type: "streakMultiplier",
                id: UUID(),
                integers: [threshold],
                doubles: [value]
            )
        }
    }

    static func restoreState(_ record: BackupRecord) {
        var map = states()
        map[record.id.uuidString] = State(
            enabled: record.booleans.first ?? false,
            enabledAt: record.dates.compactMap { $0 }.first ?? .now,
            purchased: record.integers.first ?? 0,
            usedPeriodKeys: record.strings
        )
        saveStates(map)
    }

    static func restoreMultiplier(_ record: BackupRecord) {
        guard let threshold = record.integers.first, let value = record.doubles.first else { return }
        setMultiplier(value, for: threshold)
    }

    private static func states() -> [String: State] {
        if let cachedStates { return cachedStates }
        let decoded: [String: State]
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let value = try? JSONDecoder().decode([String: State].self, from: data) {
            decoded = value
        } else {
            decoded = [:]
        }
        cachedStates = decoded
        return decoded
    }

    private static func multipliers() -> [Int: Double] {
        if let cachedMultipliers { return cachedMultipliers }
        let decoded: [Int: Double]
        if let data = UserDefaults.standard.data(forKey: multiplierKey),
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
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
        cachedStates = map
        bump()
    }

    private static func saveMultipliers(_ map: [Int: Double]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: multiplierKey)
        cachedMultipliers = map
        bump()
    }

    private static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
