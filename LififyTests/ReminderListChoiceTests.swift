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
