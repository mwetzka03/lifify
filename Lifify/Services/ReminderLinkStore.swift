import Foundation

struct ReminderRecurrenceMetadata: Codable, Sendable {
    let recurrence: ChallengeRecurrence
    let interval: Int
    let weekdays: Set<Int>
    let endDate: Date?
}

@MainActor
enum ReminderLinkStore {
    static func metadata(for externalIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let externalIdentifier, let raw = LinkTable.map(.reminderRecurrence)[externalIdentifier] else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: Data(raw.utf8))
    }

    static func set(_ metadata: ReminderRecurrenceMetadata, for externalIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        LinkTable.set(.reminderRecurrence, key: externalIdentifier, value: String(decoding: data, as: UTF8.self))
    }

    static func remove(for externalIdentifier: String?) {
        guard let externalIdentifier else { return }
        LinkTable.set(.reminderRecurrence, key: externalIdentifier, value: nil)
    }
}

@MainActor
enum EventRecurrenceStore {
    static func metadata(for eventIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let eventIdentifier, let raw = LinkTable.map(.eventRecurrence)[eventIdentifier] else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: Data(raw.utf8))
    }

    static func set(_ metadata: ReminderRecurrenceMetadata, for eventIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        LinkTable.set(.eventRecurrence, key: eventIdentifier, value: String(decoding: data, as: UTF8.self))
    }

    static func remove(for eventIdentifier: String?) {
        guard let eventIdentifier else { return }
        LinkTable.set(.eventRecurrence, key: eventIdentifier, value: nil)
    }
}

@MainActor
enum ReminderSyncPreference {
    static func isEnabled(for challengeID: UUID) -> Bool {
        LinkTable.map(.reminderSync)[challengeID.uuidString].map { $0 == "true" } ?? true
    }

    static func set(_ enabled: Bool, for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: enabled ? "true" : "false")
    }

    static func remove(for challengeID: UUID) {
        LinkTable.set(.reminderSync, key: challengeID.uuidString, value: nil)
    }
}
