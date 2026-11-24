import Foundation
import LififyChallenges
import LififyCore
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// The step goal becomes a challenge that checks itself off from Apple Health.
    @Suite("Step challenge")
    @MainActor
    struct StepChallengeTests {
        /// Turns Apple Health on and sets a goal.
        private func prepare(_ store: TestStore, goal: Int = 8_000) {
            store.defaults.set(true, forKey: AppleHealthSync.enabledKey)
            store.defaults.set(goal, forKey: StepChallenge.goalKey)
        }

        @Test func aGoalWithAppleHealthMakesOneLockedChallenge() async throws {
            try await withTestStore { store in
                #expect(StepChallenge.sync(context: store.context) == nil)
                prepare(store)
                let challenge = try #require(StepChallenge.sync(context: store.context))
                #expect(StepChallenge.sync(context: store.context)?.id == challenge.id)
                #expect(challenge.rewardCoins == StepChallenge.rewardCoins)
                #expect(StreakSettings.isEnabled(for: challenge.id))
                #expect(!SiriActions.canCheckOff(challenge))
                #expect(ChallengeCheckoff.isAutomatic(challenge.externalIdentifier))
                store.defaults.set(10_000, forKey: StepChallenge.goalKey)
                #expect(StepChallenge.sync(context: store.context)?.title == StepChallenge.title(for: 10_000))
                store.defaults.set(0, forKey: StepChallenge.goalKey)
                #expect(StepChallenge.sync(context: store.context) == nil)
                #expect(challenge.isArchived)
            }
        }

        @Test func reachedDaysAreBookedOnce() async throws {
            try await withTestStore { store in
                prepare(store)
                let now = AppClock.now
                let today = Calendar.current.startOfDay(for: now)
                let yesterday = days(-1, after: today)
                let days = [
                    HealthDayValue(date: today, value: 9_000),
                    HealthDayValue(date: yesterday, value: 12_000)
                ]
                #expect(StepChallenge.settle(days: days, context: store.context, now: now) == 1)
                try #expect(store.wallet() == StepChallenge.rewardCoins)
                #expect(StepChallenge.settle(days: days, context: store.context, now: now) == 0)
                let short = [HealthDayValue(date: today, value: 3_000)]
                try await withTestStore { other in
                    prepare(other)
                    #expect(StepChallenge.settle(days: short, context: other.context, now: now) == 0)
                }
            }
        }

        @Test func theEveningNoteSaysTheStepsLeft() async throws {
            try await withTestStore { store in
                prepare(store)
                let at = date(2026, 3, 18, 18)
                let open = try #require(StepChallenge.note(steps: 5_000, readAt: at))
                #expect(open.body.contains(3_000.formatted()))
                let done = try #require(StepChallenge.note(steps: 9_000, readAt: at))
                #expect(done.title == L("Schrittziel erreicht", "Step goal reached"))
                #expect(StepChallenge.note(steps: nil, readAt: nil)?.body.contains(8_000.formatted()) == true)
                store.defaults.set(0, forKey: StepChallenge.goalKey)
                #expect(StepChallenge.note(steps: 5_000, readAt: at) == nil)
            }
        }
    }
}
