import Foundation
import LififyCore

/// One list of the Reminders app.
public struct ReminderListOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String

    /// Creates a list option.
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Decides in which Reminders list Lifify creates new challenges.
///
/// The person's choice wins. Without one, a list named To-Do (or To Do, Todo) is used, and only
/// without such a list the system's default list. Existing reminders keep their list.
public enum ReminderListChoice {
    public nonisolated static let storageKey = "lifify.reminderListID"

    /// The stored choice, or `nil` for automatic.
    public static var storedID: String? {
        let value = AppDefaults.store.string(forKey: storageKey) ?? ""
        return value.isEmpty ? nil : value
    }

    /// The list for new reminders.
    ///
    /// - Parameters:
    ///   - lists: The lists that exist now.
    ///   - stored: The person's choice, if any.
    /// - Returns: The list's identifier, or `nil` for the system default.
    public static func pick(from lists: [ReminderListOption], stored: String? = storedID) -> String? {
        if let stored, lists.contains(where: { $0.id == stored }) { return stored }
        return lists.first { isToDo($0.title) }?.id
    }

    /// Says whether a list title means a to-do list.
    public static func isToDo(_ title: String) -> Bool {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter }
        return folded == "todo" || folded == "todos"
    }
}
