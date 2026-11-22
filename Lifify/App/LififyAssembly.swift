import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData

/// Connects the packages. It runs once before any store is used.
@MainActor
enum LififyAssembly {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        AppDefaults.registerCaches {
            HistoricalPriceStore.clearCache()
            HoldingLotStore.clearCache()
            SavingsPlanStore.clearCache()
            HoldingMaintenance.clearCache()
            ClosedPositionStore.clearCache()
            HoldingMarketStore.clearCache()
            PortfolioLinkStore.clearCache()
            TransferForecastStore.clearCache()
            NoticeTemplateStore.clearCache()
            ChallengeTimeStore.clearCache()
            ChallengeCategoryStore.clearCache()
            StreakSettings.clearCache()
            AbstinenceSettings.clearCache()
            WorkoutLinkStore.clearCache()
            MealLog.clearCache()
        }
        HealthHooks.install()
        ChallengeHooks.abstinenceChanged = { context in
            await DailyBriefingService.scheduleAbstinence(context: context)
        }
    }
}
