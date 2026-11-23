import Foundation
import LififyCore
import LififyChallenges

/// Connects the Health package to the challenge rules.
@MainActor
public enum HealthHooks {
    /// Installs the callbacks the challenge package uses.
    public static func install() {
        ChallengeHooks.confirmedMeals = { day in
            let key = NutritionPlan.dayKey(day)
            return NutritionPlan.onDay(key, meals: MealLog.all()).filter { $0.status == .confirmed }.count
        }
    }
}
