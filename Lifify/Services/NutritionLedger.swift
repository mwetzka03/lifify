import Foundation
import SwiftData

/// Keeps the calorie challenge and the fast-food shop item in step with the meal log.
@MainActor
enum NutritionLedger {
    static let challengeMark = "nutrition:calories"
    private static let rewardKey = "lifify.fastFoodReward"

    static func settle(context: ModelContext, sessions: [WorkoutSession]) {
        let reward = ensureReward(context: context)
        let challenge = ensureChallenge(context: context)
        var meals = MealLog.all()
        var mealsChanged = false
        for index in meals.indices {
            let wantsCharge = meals[index].kind == .fastFood
            if wantsCharge, meals[index].chargeID == nil {
                meals[index].chargeID = charge(reward, context: context)
                mealsChanged = true
            } else if !wantsCharge, let chargeID = meals[index].chargeID {
                refund(chargeID, context: context)
                meals[index].chargeID = nil
                mealsChanged = true
            }
        }
        if mealsChanged {
            for meal in meals { MealLog.upsert(meal) }
        }
        settleDays(meals: MealLog.all(), challenge: challenge, sessions: sessions, context: context)
    }

    static func forget(_ meal: MealRecord, context: ModelContext) {
        if let chargeID = meal.chargeID {
            refund(chargeID, context: context)
        }
    }

    private static func ensureChallenge(context: ModelContext) -> ChallengeItem {
        let stored = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        if let existing = stored.first(where: { $0.externalIdentifier == challengeMark }) {
            if NutritionCopy.previousCalorieTitles.contains(existing.title) {
                existing.title = NutritionCopy.calorieChallenge
                try? context.save()
            }
            return existing
        }
        let challenge = ChallengeItem(
            title: NutritionCopy.calorieChallenge,
            details: L(
                "Ein Tag zählt, wenn die bestätigten Mahlzeiten das Kalorienziel nicht übersteigen. Eine Reihe aus unverarbeiteten und ausgewogenen Mahlzeiten zahlt mehr. Fast Food wird im Shop gekauft.",
                "A day counts when the confirmed meals stay within the calorie target. A run of whole and balanced meals pays more. Fast food is bought in the shop."
            ),
            category: .other,
            recurrence: .daily,
            startDate: Calendar.current.startOfDay(for: .now),
            rewardCoins: MealScore.baseCoins,
            externalIdentifier: challengeMark
        )
        context.insert(challenge)
        try? context.save()
        StreakSettings.setEnabled(true, for: challenge.id)
        IconPreferenceStore.set("fork.knife", for: challenge.id)
        ChallengePinStore.pin(challenge.id)
        return challenge
    }

    private static func ensureReward(context: ModelContext) -> RewardItem {
        let stored = (try? context.fetch(FetchDescriptor<RewardItem>())) ?? []
        if let id = UserDefaults.standard.string(forKey: rewardKey).flatMap(UUID.init(uuidString:)),
           let existing = stored.first(where: { $0.id == id }) {
            existing.isActive = true
            RewardPolicyStore.setAllowsMultiplePurchases(true, for: existing.id)
            return existing
        }
        let reward = RewardItem(
            title: L("Fast Food", "Fast food"),
            details: L(
                "Wird gekauft, wenn eine Mahlzeit als Fast Food erkannt wird.",
                "Bought when a meal is recognized as fast food."
            ),
            price: MealScore.fastFoodPrice,
            icon: "takeoutbag.and.cup.and.straw",
            colorHex: "#C4554A"
        )
        context.insert(reward)
        try? context.save()
        RewardPolicyStore.setAllowsMultiplePurchases(true, for: reward.id)
        UserDefaults.standard.set(reward.id.uuidString, forKey: rewardKey)
        return reward
    }

    private static func charge(_ reward: RewardItem, context: ModelContext) -> UUID {
        let purchase = RewardPurchase(rewardID: reward.id, title: reward.title, price: reward.price)
        context.insert(purchase)
        context.insert(CoinTransaction(title: reward.title, amount: -reward.price, referenceID: purchase.id))
        try? context.save()
        return purchase.id
    }

    private static func refund(_ purchaseID: UUID, context: ModelContext) {
        let purchases = (try? context.fetch(FetchDescriptor<RewardPurchase>())) ?? []
        let coins = (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []
        purchases.filter { $0.id == purchaseID }.forEach(context.delete)
        coins.filter { $0.referenceID == purchaseID }.forEach(context.delete)
        try? context.save()
    }

    private static func settleDays(
        meals: [MealRecord],
        challenge: ChallengeItem,
        sessions: [WorkoutSession],
        context: ModelContext
    ) {
        guard !challenge.isArchived else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []
        let measures = UserBody.current()
        let birth = UserProfile.birth()
        var tracked = completions
        for key in Set(meals.map(\.dayKey)) {
            guard let day = NutritionPlan.date(from: key, calendar: calendar), day <= today else { continue }
            let confirmed = NutritionPlan.onDay(key, meals: meals).filter { $0.status == .confirmed }
            let eaten = NutritionPlan.rounded(.calories, meals: confirmed)
            let trained = NutritionPlan.trained(on: day, sessions: sessions, calendar: calendar)
            let target = NutritionPlan.dayTarget(measures: measures, birth: birth, on: day, trained: trained, calendar: calendar)
            let base = MealScore.coins(eaten: eaten, target: target, kinds: confirmed.map(\.kind))
            let existing = tracked.first {
                $0.challengeID == challenge.id && calendar.isDate($0.date, inSameDayAs: day)
            }
            if base == 0 {
                guard let existing else { continue }
                transactions.filter { $0.referenceID == existing.id }.forEach(context.delete)
                context.delete(existing)
                tracked.removeAll { $0.id == existing.id }
                continue
            }
            let earned = ChallengeService.projectedCoins(
                challenge: challenge,
                on: day,
                completions: tracked,
                events: events,
                baseCoins: base
            )
            if let existing {
                guard existing.earnedCoins != earned else { continue }
                existing.earnedCoins = earned
                transactions.first { $0.referenceID == existing.id }?.amount = earned
            } else if ChallengeService.markCompletedIfNeeded(
                challenge: challenge,
                date: day,
                completions: tracked,
                events: events,
                context: context,
                baseCoins: base
            ) {
                let fresh = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
                tracked = fresh
            }
        }
        try? context.save()
    }
}
