import Foundation
import LififyChallenges
import LififyCore
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Testing on a simulated day must leave the real wallet and its markers untouched.
    @Suite("Simulated day")
    @MainActor
    struct SimulatedDayTests {
        /// Switches developer mode on and moves to a day in the future.
        private func simulate(_ store: TestStore, daysAhead: Int = 10) {
            store.defaults.set(true, forKey: AppClock.modeKey)
            AppClock.setSimulatedDay(days(daysAhead, after: .now))
        }

        /// Returns to the real day and removes what the simulation changed.
        private func backToRealDay(_ store: TestStore) {
            AppClock.resetSimulatedDay()
            SimulatedDayLedger.rollbackIfOnRealDay(context: store.context)
        }

        @Test func checkOffOnASimulatedDayIsRemoved() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", rewardCoins: 10)
                store.context.insert(challenge)
                simulate(store)
                ChallengeService.toggleCompletion(
                    challenge: challenge, date: AppClock.now, completions: [], transactions: [], context: store.context
                )
                try #expect(store.wallet() == 10)

                backToRealDay(store)

                try #expect(store.wallet() == 0)
                try #expect(store.all(ChallengeCompletion.self).isEmpty)
                #expect(SimulatedDayLedger.effects().isEmpty)
            }
        }

        @Test func realBookingsStay() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", rewardCoins: 10)
                store.context.insert(challenge)
                ChallengeService.toggleCompletion(
                    challenge: challenge, date: .now, completions: [], transactions: [], context: store.context
                )
                #expect(SimulatedDayLedger.effects().isEmpty)
                simulate(store)
                backToRealDay(store)
                try #expect(store.wallet() == 10)
                try #expect(store.all(ChallengeCompletion.self).count == 1)
            }
        }

        @Test func nothingIsRemovedWhileStillSimulating() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", rewardCoins: 10)
                store.context.insert(challenge)
                simulate(store)
                ChallengeService.toggleCompletion(
                    challenge: challenge, date: AppClock.now, completions: [], transactions: [], context: store.context
                )
                AppClock.setSimulatedDay(days(12, after: .now))
                SimulatedDayLedger.rollbackIfOnRealDay(context: store.context)
                try #expect(store.wallet() == 10)
            }
        }

        @Test func abstinenceBonusesCanBeEarnedAgain() async throws {
            try await withTestStore { store in
                let start = days(-2, after: .now)
                let challenge = ChallengeItem(title: "Rauchfrei", category: .abstinence, startDate: start, rewardCoins: 10)
                store.context.insert(challenge)
                simulate(store)
                AbstinenceService.settle(context: store.context)
                #expect(AbstinenceSettings.awarded(for: challenge.id).contains(AbstinenceMilestone.day7.rawValue))
                try #expect(store.wallet() > 0)

                backToRealDay(store)

                #expect(AbstinenceSettings.awarded(for: challenge.id).isEmpty)
                #expect(AbstinenceSettings.notices().isEmpty)
                try #expect(store.wallet() == 0)
                AbstinenceService.settle(context: store.context)
                #expect(AbstinenceSettings.awarded(for: challenge.id).contains(AbstinenceMilestone.hour24.rawValue))
                #expect(!AbstinenceSettings.awarded(for: challenge.id).contains(AbstinenceMilestone.day7.rawValue))
                try #expect(store.wallet() > 0)
            }
        }

        @Test func rewardPurchaseIsReversed() async throws {
            try await withTestStore { store in
                let reward = RewardItem(title: "Kino", price: 5)
                let abstinence = UUID()
                store.context.insert(reward)
                store.context.insert(CoinTransaction(title: "Start", amount: 20))
                AbstinenceSettings.setRewardLink(abstinence, for: reward.id)
                RewardPolicyStore.setAllowsMultiplePurchases(false, for: reward.id)
                try store.context.save()
                simulate(store)
                #expect(ChallengeService.purchase(reward: reward, transactions: try store.all(), context: store.context))
                #expect(!reward.isActive)
                #expect(AbstinenceSettings.exceptions(for: abstinence).count == 1)

                backToRealDay(store)

                #expect(reward.isActive)
                try #expect(store.all(RewardPurchase.self).isEmpty)
                #expect(AbstinenceSettings.exceptions(for: abstinence).isEmpty)
                try #expect(store.wallet() == 20)
            }
        }

        @Test func freezePurchaseIsReversed() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", recurrence: .daily, rewardCoins: 1)
                store.context.insert(challenge)
                store.context.insert(CoinTransaction(title: "Start", amount: 500))
                StreakSettings.setEnabled(true, for: challenge.id)
                try store.context.save()
                simulate(store)
                #expect(ChallengeService.purchaseFreeze(challenge: challenge, transactions: try store.all(), context: store.context))
                #expect(StreakSettings.state(for: challenge.id)?.purchased == 1)

                backToRealDay(store)

                #expect(StreakSettings.state(for: challenge.id)?.purchased == 0)
                try #expect(store.wallet() == 500)
            }
        }

        @Test func resettingTheAppForgetsSimulatedChanges() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Lesen", rewardCoins: 10)
                store.context.insert(challenge)
                simulate(store)
                ChallengeService.toggleCompletion(
                    challenge: challenge, date: AppClock.now, completions: [], transactions: [], context: store.context
                )
                #expect(!SimulatedDayLedger.effects().isEmpty)
                try BackupService.resetApp(from: store.context)
                #expect(SimulatedDayLedger.effects().isEmpty)
            }
        }

        @Test func birthdayBonusCanBePaidAgain() async throws {
            try await withTestStore { store in
                let simulated = days(10, after: .now)
                let birth = Calendar.current.date(byAdding: .year, value: -30, to: simulated)!
                UserProfile.setBirthDate(birth)
                simulate(store)
                BirthdayBonusService.settle(context: store.context)
                try #expect(store.wallet() == BirthdayBonus.coins)
                #expect(UserProfile.awardedYear() != nil)

                backToRealDay(store)

                try #expect(store.wallet() == 0)
                #expect(UserProfile.awardedYear() == nil)
            }
        }
    }
}
