import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Siri follows the same check-off, meal, and budget rules as the app.
    @Suite("Siri actions")
    @MainActor
    struct SiriActionsTests {
        private let now = date(2026, 3, 18)

        @Test func checksOffOnceAndPaysCoins() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", recurrence: .daily, startDate: date(2026, 3, 1), rewardCoins: 10)
                store.context.insert(challenge)
                try store.context.save()
                #expect(SiriActions.openChallenges(context: store.context, now: now).map(\.id) == [challenge.id])
                _ = SiriActions.checkOff(id: challenge.id, context: store.context, now: now)
                try #expect(store.wallet() == 10)
                #expect(SiriActions.openChallenges(context: store.context, now: now).isEmpty)
                _ = SiriActions.checkOff(id: challenge.id, context: store.context, now: now)
                try #expect(store.wallet() == 10)
                try #expect(store.all(ChallengeCompletion.self).count == 1)
            }
        }

        @Test func sportWithALinkedTrainingIsRefused() async throws {
            try await withTestStore { store in
                let sport = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: date(2026, 3, 1))
                store.context.insert(sport)
                WorkoutLinkStore.link(planID: UUID(), challengeID: sport.id)
                try store.context.save()
                #expect(!SiriActions.canCheckOff(sport))
                _ = SiriActions.checkOff(id: sport.id, context: store.context, now: now)
                try #expect(store.all(ChallengeCompletion.self).isEmpty)
            }
        }

        @Test func abstinenceIsRefused() async throws {
            try await withTestStore { store in
                let abstinence = ChallengeItem(title: "Rauchfrei", category: .abstinence, startDate: date(2026, 3, 1))
                store.context.insert(abstinence)
                #expect(!SiriActions.canCheckOff(abstinence))
            }
        }

        @Test func logsAMealAndUsesAFavoritesValues() async throws {
            try await withTestStore { store in
                MealFavorites.toggle(MealRecord(dayKey: "2026-03-01", title: "Müsli", source: .manual, status: .confirmed, nutrients: [Nutrient.calories.rawValue: 420]))
                let answer = SiriActions.logMeal(title: "müsli", calories: nil, context: store.context, sessions: [], now: now)
                #expect(answer.contains("420"))
                #expect(MealLog.all().first?.status == .confirmed)
                #expect(MealLog.all().first?.dayKey == NutritionPlan.dayKey(now))
                _ = SiriActions.logMeal(title: "Apfel", calories: 80, context: store.context, sessions: [], now: now)
                #expect(MealLog.all().count == 2)
                #expect(SiriActions.logMeal(title: "  ", calories: 80, context: store.context, sessions: [], now: now).isEmpty == false)
                #expect(MealLog.all().count == 2)
            }
        }

        @Test func saysTheRemainingBudget() async throws {
            try await withTestStore { store in
                store.context.insert(Account(name: "Giro", isMain: true))
                store.context.insert(IncomeForecast(name: "Lohn", amountCents: 10_000, firstPaymentDate: date(2026, 3, 1), dayOfMonth: 1))
                store.context.insert(LedgerEntry(date: date(2026, 3, 1), title: "Lohn", amountCents: 10_000, kind: .income))
                store.context.insert(LedgerEntry(date: date(2026, 3, 2), title: "Kauf", amountCents: 12_000, kind: .expense))
                try store.context.save()
                let answer = SiriActions.remainingBudget(context: store.context, now: now)
                #expect(answer == L("Dein Budget ist um \(Money.string(cents: 2_000)) überzogen.", "Your budget is over by \(Money.string(cents: 2_000))."))
            }
        }
    }
}
