import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData

/// The work behind Siri and Shortcuts, kept apart from the intents so tests can run it.
@MainActor
enum SiriActions {
    /// Lists the challenges that are due and still open today.
    static func openChallenges(context: ModelContext, now: Date = AppClock.now) -> [ChallengeItem] {
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        return challenges
            .filter { ChallengeService.isDue($0, on: now) && !ChallengeService.isCompleted($0, on: now, completions: completions) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Says whether a challenge may be checked off without opening it.
    ///
    /// Sport with a linked training finishes only through that training. Abstinence and the
    /// nutrition challenge follow their own rules.
    static func canCheckOff(_ challenge: ChallengeItem) -> Bool {
        !challenge.isReadOnly
            && challenge.category != .abstinence
            && ChallengeCheckoff.allowsHand(
                category: challenge.category,
                linkedWorkouts: WorkoutLinkStore.planIDs(forChallenge: challenge.id).count,
                followsNutrition: ChallengeCheckoff.followsNutrition(challenge.externalIdentifier)
            )
    }

    /// Checks a challenge off for today. An already finished challenge stays as it is.
    ///
    /// - Parameters:
    ///   - id: The challenge.
    ///   - context: The database context.
    ///   - now: The current time.
    /// - Returns: The sentence Siri says.
    static func checkOff(id: UUID, context: ModelContext, now: Date = AppClock.now) -> String {
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        guard let challenge = challenges.first(where: { $0.id == id }) else {
            return L("Diese Challenge gibt es nicht mehr.", "That challenge no longer exists.")
        }
        guard canCheckOff(challenge) else {
            return L("\(challenge.title) lässt sich so nicht abhaken.", "\(challenge.title) can't be checked off this way.")
        }
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let done = ChallengeService.markCompletedIfNeeded(challenge: challenge, date: now, completions: completions, events: events, context: context)
        return done
            ? L("\(challenge.title) ist abgehakt.", "\(challenge.title) is checked off.")
            : L("\(challenge.title) war heute schon erledigt.", "\(challenge.title) was already done today.")
    }

    /// Enters a confirmed meal for today.
    ///
    /// - Parameters:
    ///   - title: The meal's name.
    ///   - calories: The calories, if known.
    ///   - context: The database context.
    ///   - sessions: The training sessions for the day's target.
    ///   - now: The current time.
    /// - Returns: The sentence Siri says.
    static func logMeal(title: String, calories: Int?, context: ModelContext, sessions: [WorkoutSession], now: Date = .now) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return L("Die Mahlzeit braucht einen Namen.", "The meal needs a name.") }
        let known = MealFavorites.all().first { $0.id == MealFavorites.key(for: name) }
        var meal = known.map { MealFavorites.meal(from: $0, dayKey: NutritionPlan.dayKey(now), now: now) }
            ?? MealRecord(dayKey: NutritionPlan.dayKey(now), title: name, createdAt: now, source: .manual, status: .confirmed)
        if let calories, calories > 0 { meal.nutrients[Nutrient.calories.rawValue] = Double(calories) }
        MealLog.upsert(meal)
        NutritionLedger.settle(context: context, sessions: sessions)
        let amount = NutritionPlan.rounded(.calories, meals: [meal])
        return amount > 0
            ? L("\(name) mit \(amount) kcal ist eingetragen.", "\(name) with \(amount) kcal is logged.")
            : L("\(name) ist eingetragen.", "\(name) is logged.")
    }

    /// Reads the remaining budget and what is left per day.
    static func remainingBudget(context: ModelContext, now: Date = FinanceClock.now) -> String {
        let budget = HomeBudget.current(context: context, now: now)
        let remaining = Money.string(cents: budget.remaining)
        guard budget.remaining >= 0 else {
            return L("Dein Budget ist um \(Money.string(cents: -budget.remaining)) überzogen.", "Your budget is over by \(Money.string(cents: -budget.remaining)).")
        }
        guard let daily = budget.dailyAllowance(now: now) else {
            return L("Du hast noch \(remaining).", "You have \(remaining) left.")
        }
        return L("Du hast noch \(remaining), das sind \(Money.string(cents: daily)) pro Tag.", "You have \(remaining) left, which is \(Money.string(cents: daily)) per day.")
    }
}
