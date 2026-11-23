import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation

/// UserDefaults values the backup carries as they are, sorted by backup area.
///
/// Left out on purpose:
/// - caches: `lifify.historicalPrices`
/// - UI refresh counters: every `…Revision` key
/// - device and setup state: developer day, onboarding, store generation
/// - Trade Republic extract and everything in the Keychain, such as the Gemini key
/// `market.*`, `icon.*`, and the other stores with their own record types are exported separately.
@MainActor
enum BackupDefaults {
    static let recordType = "defaultsSnapshot"
    /// A file with this record was written by 0.5.5 and carries the complete finance relations.

    static let financeKeys: Set<String> = [
        TradeAccountPreference.storageKey,
        TradeFeePreference.storageKey
    ]
    static let financePrefixes: [String] = []

    static let challengeKeys: Set<String> = []
    static let challengePrefixes: [String] = []

    /// Device-wide choices. Only a backup of the entire app carries them.
    static let appKeys: Set<String> = [
        "lifify.saveMealPhotos",
        "lifify.briefingEnabled",
        "lifify.briefingHour",
        "lifify.briefingMinute",
        "restChimeSoundID",
        ProgressiveOverload.stepKey,
        PeriodReviewNotifier.enabledKey,
        "portfolioSort",
        "portfolioPerformanceBasis",
        "portfolioPerformanceUnit"
    ]

    private static let revisionKeys = [
        ChallengePinStore.revisionKey,
        ChallengeGroupPinStore.revisionKey
    ]

    /// Says whether a preference belongs to a backup scope.
    static func belongs(_ key: String, to scope: BackupScope) -> Bool {
        let finance = financeKeys.contains(key) || financePrefixes.contains { key.hasPrefix($0) }
        let challenges = challengeKeys.contains(key) || challengePrefixes.contains { key.hasPrefix($0) }
        switch scope {
        case .all: return finance || challenges || appKeys.contains(key)
        case .finance: return finance
        case .challenges: return challenges
        case .training: return false
        }
    }

    /// Always written for a scope with values, even when empty, so a restore can clear old ones.
    static func record(scope: BackupScope, defaults: UserDefaults = AppDefaults.store) -> BackupRecord? {
        guard scope != .training else { return nil }
        let values = defaults.dictionaryRepresentation().filter { belongs($0.key, to: scope) }
        var strings: [String] = []
        for key in values.keys.sorted() {
            guard let value = values[key],
                  let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
            else { continue }
            strings += [key, data.base64EncodedString()]
        }
        return BackupRecord(type: recordType, id: UUID(), strings: strings)
    }

    /// An older backup has no snapshot and leaves the current values alone.
    static func restore(from records: [BackupRecord], scope: BackupScope, defaults: UserDefaults = AppDefaults.store) {
        guard let record = records.first(where: { $0.type == recordType }) else { return }
        var values: [String: Any] = [:]
        for index in stride(from: 0, to: record.strings.count - 1, by: 2) {
            let key = record.strings[index]
            guard belongs(key, to: scope),
                  let data = Data(base64Encoded: record.strings[index + 1]),
                  let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            else { continue }
            values[key] = value
        }
        for key in defaults.dictionaryRepresentation().keys where belongs(key, to: scope) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        for key in revisionKeys {
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        }
    }
}
