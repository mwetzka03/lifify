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
    static func clearCaches() {
        ChallengeTimeStore.clearCache()
        ChallengeCategoryStore.clearCache()
        StreakSettings.clearCache()
        AbstinenceSettings.clearCache()
        HistoricalPriceStore.clearCache()
        HoldingLotStore.clearCache()
        SavingsPlanStore.clearCache()
        HoldingMaintenance.clearCache()
        ClosedPositionStore.clearCache()
        HoldingMarketStore.clearCache()
        PortfolioLinkStore.clearCache()
        LinkTable.clearCache()
        TransferForecastStore.clearCache()
        NoticeTemplateStore.clearCache()
        WorkoutLinkStore.clearCache()
        MealLog.clearCache()
    }
}

/// The folder for data files. Tests swap in a temporary one, so they never touch user files.
enum AppFiles {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replacement: URL?

    static var supportDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        return replacement ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func use(_ directory: URL?) {
        lock.lock()
        replacement = directory
        lock.unlock()
    }
}
