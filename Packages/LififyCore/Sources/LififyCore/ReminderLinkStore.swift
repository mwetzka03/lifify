import Foundation

/// The repeat rule of a reminder or calendar event.
public struct ReminderRecurrenceMetadata: Codable, Sendable {
    public let recurrence: ChallengeRecurrence
    public let interval: Int
    public let weekdays: Set<Int>
    public let endDate: Date?

    public init(recurrence: ChallengeRecurrence, interval: Int, weekdays: Set<Int>, endDate: Date?) {
        self.recurrence = recurrence
        self.interval = interval
        self.weekdays = weekdays
        self.endDate = endDate
    }
}

/// A link-table section that stores repeat rules by system identifier.
@MainActor
public protocol RecurrenceLinkTable {
    /// The section holding the rules.
    static var linkKind: LinkKind { get }
}

public extension RecurrenceLinkTable {
    /// Returns the stored rule of an identifier.
    static func metadata(for identifier: String?) -> ReminderRecurrenceMetadata? {
        guard let identifier, let raw = LinkTable.map(linkKind)[identifier] else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: Data(raw.utf8))
    }

    /// Stores the rule of an identifier.
    static func set(_ metadata: ReminderRecurrenceMetadata, for identifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        LinkTable.set(linkKind, key: identifier, value: String(decoding: data, as: UTF8.self))
    }

    /// Removes the rule of an identifier.
    static func remove(for identifier: String?) {
        guard let identifier else { return }
        LinkTable.set(linkKind, key: identifier, value: nil)
    }
}

/// The repeat rules of linked reminders.
@MainActor
public enum ReminderLinkStore: RecurrenceLinkTable {
    public static let linkKind = LinkKind.reminderRecurrence
}

/// The repeat rules of calendar events.
@MainActor
public enum EventRecurrenceStore: RecurrenceLinkTable {
    public static let linkKind = LinkKind.eventRecurrence
}

/// Whether a challenge mirrors its completion to its reminder.
@MainActor
public enum ReminderSyncPreference {
    /// Says whether the sync is on. It is on unless a person turned it off.
    public static func isEnabled(for challengeID: UUID) -> Bool {
        LinkTable.map(.reminderSync)[challengeID.uuidString].map { $0 == "true" } ?? true
    }

    /// Turns the sync on or off.
    public static func set(_ enabled: Bool, for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: enabled ? "true" : "false")
    }

    /// Removes the stored choice.
    public static func remove(for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: nil)
    }
}
