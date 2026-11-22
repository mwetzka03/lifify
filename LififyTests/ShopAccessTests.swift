import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Shop lock")
    @MainActor
    struct ShopAccessTests {
        @Test(arguments: [
            (-1, 0, ShopAccess.locked),
            (-25, 10, ShopAccess.locked),
            (0, 0, ShopAccess.open),
            (0, 1, ShopAccess.notEnoughCoins),
            (9, 10, ShopAccess.notEnoughCoins),
            (10, 10, ShopAccess.open)
        ])
        func accessFollowsBalanceAndPrice(balance: Int, price: Int, expected: ShopAccess) {
            #expect(ShopAccess.check(balance: balance, price: price) == expected)
        }

        @Test func unlockNeedsTheMissingCoins() {
            #expect(ShopAccess.coinsToUnlock(balance: -35) == 35)
            #expect(ShopAccess.coinsToUnlock(balance: 0) == 0)
            #expect(ShopAccess.coinsToUnlock(balance: 12) == 0)
        }

        @Test func negativeBalanceBlocksEvenAFreeReward() async throws {
            try await withTestStore { store in
                let reward = RewardItem(title: "Gratis", price: 0)
                store.context.insert(reward)
                store.context.insert(CoinTransaction(title: "Minus", amount: -1))
                try #expect(!ChallengeService.purchase(reward: reward, transactions: store.all(), context: store.context))
                try #expect(store.all(RewardPurchase.self).isEmpty)
                try #expect(store.wallet() == -1)
            }
        }

        @Test func balanceOfZeroOpensTheShopAgain() async throws {
            try await withTestStore { store in
                let reward = RewardItem(title: "Gratis", price: 0)
                store.context.insert(reward)
                store.context.insert(CoinTransaction(title: "Minus", amount: -5))
                store.context.insert(CoinTransaction(title: "Ausgleich", amount: 5))
                try #expect(ChallengeService.purchase(reward: reward, transactions: store.all(), context: store.context))
            }
        }

        @Test func negativeBalanceBlocksAFreeFreeze() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Täglich", recurrence: .daily, startDate: date(2026, 3, 2), rewardCoins: 0)
                store.context.insert(challenge)
                StreakSettings.setEnabled(true, for: challenge.id)
                store.context.insert(CoinTransaction(title: "Minus", amount: -1))
                try #expect(!ChallengeService.purchaseFreeze(challenge: challenge, transactions: store.all(), context: store.context))
                #expect(StreakSettings.state(for: challenge.id)?.purchased == 0)
            }
        }

        @Test func fastFoodStillBooksWhileLockedAndRefunds() async throws {
            try await withTestStore { store in
                store.context.insert(CoinTransaction(title: "Minus", amount: -10))
                try store.context.save()
                var meal = MealRecord(
                    dayKey: NutritionPlan.dayKey(.now),
                    title: "Burger",
                    source: .manual,
                    status: .draft,
                    kind: .fastFood
                )
                MealLog.upsert(meal)
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == -10 - MealScore.fastFoodPrice)
                try #expect(store.all(RewardPurchase.self).count == 1)

                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == -10 - MealScore.fastFoodPrice)

                meal = try #require(MealLog.all().first)
                meal.kind = .balanced
                MealLog.upsert(meal)
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == -10)
                try #expect(store.all(RewardPurchase.self).isEmpty)
            }
        }
    }
}
