import Foundation

/// The one place services get their UserDefaults from.
/// The app always uses `.standard`. Tests swap in an isolated suite, so they never touch user data.
enum AppDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replacement: UserDefaults?

    static var store: UserDefaults {
        lock.lock()
        defer { lock.unlock() }
        return replacement ?? .standard
    }

    /// Switches the store and drops every in-memory copy of the previous store's values.
    /// Pass `nil` to return to `.standard`.
    @MainActor
    static func use(_ store: UserDefaults?) {
        lock.lock()
        replacement = store
        lock.unlock()
        clearCaches()
    }

    @MainActor
    private static func clearCaches() {
        ChallengeTimeStore.clearCache()
        ChallengeCategoryStore.clearCache()
        StreakSettings.clearCache()
        AbstinenceSettings.clearCache()
        HistoricalPriceStore.clearCache()
        HoldingLotStore.clearCache()
        SavingsPlanStore.clearCache()
        HoldingMaintenance.clearCache()
        ClosedPositionStore.clearCache()
    }
}
