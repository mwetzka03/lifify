import Foundation
import LififyChallenges
import LififyCore
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Favorites and recent meals can be entered again and survive a Health backup.
    @Suite("Meal favorites")
    @MainActor
    struct MealFavoritesTests {
        /// Builds a confirmed meal.
        private func meal(_ title: String, day: Int = 2, kind: MealKind = .balanced, status: MealStatus = .confirmed) -> MealRecord {
            MealRecord(
                dayKey: NutritionPlan.dayKey(date(2026, 3, day)), title: title, createdAt: date(2026, 3, day),
                source: .photo, status: status, photoName: "foto.jpg", nutrients: [Nutrient.calories.rawValue: 640.4], kind: kind
            )
        }

        @Test func aFavoriteTogglesByNameIgnoringCase() async throws {
            try await withTestStore { _ in
                MealFavorites.toggle(meal("Müsli"))
                #expect(MealFavorites.contains(meal(" müsli ")))
                #expect(MealFavorites.all().map(\.calories) == [640])
                MealFavorites.toggle(meal("MUESLI"))
                #expect(MealFavorites.all().count == 2)
                MealFavorites.toggle(meal("müsli"))
                #expect(MealFavorites.all().map(\.title) == ["MUESLI"])
            }
        }

        @Test func recentMealsAreUniqueConfirmedAndNotFavorites() async throws {
            try await withTestStore { _ in
                MealFavorites.toggle(meal("Reis"))
                let meals = [meal("Reis", day: 5), meal("Nudeln", day: 1), meal("nudeln", day: 4), meal("Entwurf", day: 6, status: .draft), meal("Suppe", day: 3)]
                #expect(MealFavorites.recent(in: meals).map(\.title) == ["nudeln", "Suppe"])
                #expect(MealFavorites.recent(in: meals, limit: 1).count == 1)
            }
        }

        @Test func aNewEntryCopiesValuesButNotPhotoOrCharge() async throws {
            try await withTestStore { _ in
                var source = meal("Burger", kind: .fastFood)
                source.chargeID = UUID()
                let copy = MealFavorites.meal(from: MealTemplate(meal: source), dayKey: "2026-03-09")
                #expect(copy.id != source.id)
                #expect(copy.dayKey == "2026-03-09")
                #expect(copy.status == .confirmed)
                #expect(copy.kind == .fastFood)
                #expect(copy.nutrients == source.nutrients)
                #expect(copy.photoName == nil)
                #expect(copy.chargeID == nil)
            }
        }

        @Test func aRepeatedFastFoodMealIsChargedAgain() async throws {
            try await withTestStore { store in
                let template = MealTemplate(meal: meal("Burger", kind: .fastFood))
                MealLog.upsert(MealFavorites.meal(from: template, dayKey: NutritionPlan.dayKey(.now)))
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == -MealScore.fastFoodPrice)
            }
        }

        @Test func favoritesSurviveAHealthBackup() async throws {
            try await withTestStore { store in
                MealFavorites.toggle(meal("Reis"))
                let data = try BackupService.exportData(
                    accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .training,
                    workoutSnapshot: WorkoutStore(fileURL: WorkoutStore.defaultFileURL()).exportSnapshotData()
                )
                try BackupService.deleteHealthData(from: store.context)
                #expect(MealFavorites.all().isEmpty)
                try BackupService.restore(data: data, into: store.context)
                #expect(MealFavorites.all().map(\.title) == ["Reis"])
            }
        }
    }
}
