import Foundation
import LififyCore
import LififyChallenges

@MainActor
public enum HealthHooks {
    public static func install() {
        ChallengeHooks.confirmedMeals = { day in
            let key = NutritionPlan.dayKey(day)
            return NutritionPlan.onDay(key, meals: MealLog.all()).filter { $0.status == .confirmed }.count
        }
    }
}
