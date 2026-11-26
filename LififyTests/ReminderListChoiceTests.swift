import Foundation
import LififyChallenges
import LififyCore
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// New challenges go into the chosen list, else into To-Do, else the default list.
    @Suite("Reminder list choice")
    @MainActor
    struct ReminderListChoiceTests {
        private let lists = [
            ReminderListOption(id: "shop", title: "Einkaufsliste"),
            ReminderListOption(id: "todo", title: "To-Do"),
            ReminderListOption(id: "dj", title: "DJing")
        ]

        @Test func toDoIsTheAutomaticList() {
            #expect(ReminderListChoice.pick(from: lists, stored: nil) == "todo")
            #expect(ReminderListChoice.isToDo("To Do"))
            #expect(ReminderListChoice.isToDo("todo"))
            #expect(!ReminderListChoice.isToDo("Einkaufsliste"))
        }

        @Test func aChosenListWinsWhileItExists() {
            #expect(ReminderListChoice.pick(from: lists, stored: "dj") == "dj")
            #expect(ReminderListChoice.pick(from: lists, stored: "gone") == "todo")
        }

        @Test func withoutToDoTheSystemDefaultIsUsed() {
            #expect(ReminderListChoice.pick(from: [ReminderListOption(id: "shop", title: "Einkaufsliste")], stored: nil) == nil)
        }

        @Test func theChoiceIsReadFromSettings() async throws {
            try await withTestStore { store in
                #expect(ReminderListChoice.storedID == nil)
                store.defaults.set("dj", forKey: ReminderListChoice.storageKey)
                #expect(ReminderListChoice.pick(from: lists) == "dj")
            }
        }
    }
}

extension LififyRuleTests {
    /// Pins of deleted challenges must not block the four pin slots.
    @Suite("Challenge pins")
    @MainActor
    struct ChallengePinPruneTests {
        @Test func pinsOfGoneChallengesAreDropped() async throws {
            try await withTestStore { _ in
                let ghosts = (0..<4).map { _ in UUID() }
                ghosts.forEach(ChallengePinStore.pin)
                let real = UUID()
                ChallengePinStore.pin(real)
                #expect(!ChallengePinStore.contains(real))
                ChallengePinStore.prune(keeping: [real, ghosts[0]])
                #expect(ChallengePinStore.ids() == [ghosts[0]])
                ChallengePinStore.pin(real)
                #expect(ChallengePinStore.contains(real))
            }
        }
    }
}

extension LififyRuleTests {
    /// A dismissed challenge suggestion does not come back.
    @Suite("Recommendation rejection")
    @MainActor
    struct RecommendationRejectionTests {
        @Test func aDismissedReminderStaysAway() async throws {
            try await withTestStore { _ in
                let event = ChallengeCalendarEvent(title: "Coach", startDate: .now, endDate: .now, externalIdentifier: "reminder:abc")
                #expect(!RecommendationRejection.isRejected(event))
                RecommendationRejection.reject(event)
                #expect(RecommendationRejection.isRejected(event))
                let again = ChallengeCalendarEvent(title: "Coach", startDate: .now, endDate: .now, externalIdentifier: "reminder:abc")
                #expect(RecommendationRejection.isRejected(again))
            }
        }
    }

    /// Steps and nutrition challenges are switched off in the settings, not deleted by hand.
    @Suite("Automatic challenge deletion")
    struct AutomaticChallengeDeletionTests {
        @Test func onlyManualChallengesCanBeDeleted() {
            #expect(!ChallengeCheckoff.canDelete("health:steps"))
            #expect(!ChallengeCheckoff.canDelete("nutrition:calories"))
            #expect(ChallengeCheckoff.canDelete(nil))
            #expect(ChallengeCheckoff.canDelete("reminder:abc"))
        }
    }
}
