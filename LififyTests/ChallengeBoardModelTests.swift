import Foundation
import LififyChallenges
import LififyCore
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// A card fed only its own completions must show the same streak and coins.
    @Suite("Challenge board model")
    @MainActor
    struct ChallengeBoardModelTests {
        @Test func ownCompletionsGiveTheSameStreakAndCoins() async throws {
            try await withTestStore { store in
                // Streaks count from the moment they are enabled, so the days lie ahead of today.
                let now = days(4, after: .now)
                let challenge = ChallengeItem(title: "A", recurrence: .daily, startDate: days(-4, after: now), rewardCoins: 10)
                let other = ChallengeItem(title: "B", recurrence: .daily, startDate: days(-4, after: now))
                store.context.insert(challenge)
                store.context.insert(other)
                StreakSettings.setEnabled(true, for: challenge.id)
                var all: [ChallengeCompletion] = []
                for offset in 1...4 {
                    all.append(ChallengeCompletion(challengeID: challenge.id, date: days(-offset, after: now), earnedCoins: 10))
                    all.append(ChallengeCompletion(challengeID: other.id, date: days(-offset - 1, after: now), earnedCoins: 10))
                }
                all.forEach(store.context.insert)
                let own = ChallengeCompletionIndex(all).completions(for: challenge.id)
                #expect(own.count == 4)
                let full = ChallengeService.status(for: challenge, endingOn: now, completions: all, events: [])
                let narrowed = ChallengeService.status(for: challenge, endingOn: now, completions: own, events: [])
                #expect(full == narrowed)
                #expect(full.count == 4)
                #expect(
                    ChallengeService.projectedCoins(challenge: challenge, on: now, completions: all, events: [])
                        == ChallengeService.projectedCoins(challenge: challenge, on: now, completions: own, events: [])
                )
            }
        }

        @Test func indexFollowsSavedAndUnsavedChanges() async throws {
            try await withTestStore { store in
                let id = UUID()
                let model = ChallengeBoardModel()
                let first = ChallengeCompletion(challengeID: id, date: date(2026, 3, 1), earnedCoins: 1)
                #expect(!model.index(completions: [], hasUnsavedChanges: false).hasCompletion(id))
                #expect(model.index(completions: [first], hasUnsavedChanges: false).hasCompletion(id))
                #expect(!model.index(completions: [], hasUnsavedChanges: true).hasCompletion(id))
                let moved = ChallengeCompletion(challengeID: UUID(), date: date(2026, 3, 1), earnedCoins: 1)
                _ = model.index(completions: [first], hasUnsavedChanges: false)
                ModelChangeCounter.bump()
                #expect(!model.index(completions: [moved], hasUnsavedChanges: false).hasCompletion(id))
            }
        }
    }
}
