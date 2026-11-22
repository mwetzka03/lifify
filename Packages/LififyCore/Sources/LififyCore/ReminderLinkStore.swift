import Foundation

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

@MainActor
public enum ReminderLinkStore {
    public static func metadata(for externalIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let externalIdentifier, let raw = LinkTable.map(.reminderRecurrence)[externalIdentifier] else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: Data(raw.utf8))
    }

    public static func set(_ metadata: ReminderRecurrenceMetadata, for externalIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        LinkTable.set(.reminderRecurrence, key: externalIdentifier, value: String(decoding: data, as: UTF8.self))
    }

    public static func remove(for externalIdentifier: String?) {
        guard let externalIdentifier else { return }
        LinkTable.set(.reminderRecurrence, key: externalIdentifier, value: nil)
    }
}

@MainActor
public enum EventRecurrenceStore {
    public static func metadata(for eventIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let eventIdentifier, let raw = LinkTable.map(.eventRecurrence)[eventIdentifier] else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: Data(raw.utf8))
    }

    public static func set(_ metadata: ReminderRecurrenceMetadata, for eventIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        LinkTable.set(.eventRecurrence, key: eventIdentifier, value: String(decoding: data, as: UTF8.self))
    }

    public static func remove(for eventIdentifier: String?) {
        guard let eventIdentifier else { return }
        LinkTable.set(.eventRecurrence, key: eventIdentifier, value: nil)
    }
}

@MainActor
public enum ReminderSyncPreference {
    public static func isEnabled(for challengeID: UUID) -> Bool {
        LinkTable.map(.reminderSync)[challengeID.uuidString].map { $0 == "true" } ?? true
    }

    public static func set(_ enabled: Bool, for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: enabled ? "true" : "false")
    }

    public static func remove(for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: nil)
    }
}
