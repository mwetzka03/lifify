import Foundation

struct ReminderRecurrenceMetadata: Codable, Sendable {
    let recurrence: ChallengeRecurrence
    let interval: Int
    let weekdays: Set<Int>
    let endDate: Date?
}

enum ReminderLinkStore {
    private static func key(for externalIdentifier: String) -> String {
        "reminder.recurrence.\(externalIdentifier)"
    }

    static func metadata(for externalIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let externalIdentifier,
              let data = AppDefaults.store.data(forKey: key(for: externalIdentifier))
        else {
            return nil
        }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: data)
    }

    static func set(_ metadata: ReminderRecurrenceMetadata, for externalIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        AppDefaults.store.set(data, forKey: key(for: externalIdentifier))
    }

    static func remove(for externalIdentifier: String?) {
        guard let externalIdentifier else { return }
        AppDefaults.store.removeObject(forKey: key(for: externalIdentifier))
    }
}

enum EventRecurrenceStore {
    static func metadata(for eventIdentifier: String?) -> ReminderRecurrenceMetadata? {
        guard let eventIdentifier,
              let data = AppDefaults.store.data(forKey: key(for: eventIdentifier))
        else {
            return nil
        }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: data)
    }

    static func set(_ metadata: ReminderRecurrenceMetadata, for eventIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        AppDefaults.store.set(data, forKey: key(for: eventIdentifier))
    }

    static func remove(for eventIdentifier: String?) {
        guard let eventIdentifier else { return }
        AppDefaults.store.removeObject(forKey: key(for: eventIdentifier))
    }

    private static func key(for eventIdentifier: String) -> String {
        "event.recurrence.\(eventIdentifier)"
    }
}

enum ReminderSyncPreference {
    static func isEnabled(for challengeID: UUID) -> Bool {
        let key = key(for: challengeID)
        guard AppDefaults.store.object(forKey: key) != nil else { return true }
        return AppDefaults.store.bool(forKey: key)
    }

    static func set(_ enabled: Bool, for challengeID: UUID) {
        AppDefaults.store.set(enabled, forKey: key(for: challengeID))
    }

    static func remove(for challengeID: UUID) {
        AppDefaults.store.removeObject(forKey: key(for: challengeID))
    }

    private static func key(for challengeID: UUID) -> String {
        "challenge.syncReminders.\(challengeID.uuidString)"
    }
}
