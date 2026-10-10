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
              let data = UserDefaults.standard.data(forKey: key(for: externalIdentifier))
        else {
            return nil
        }
        return try? JSONDecoder().decode(ReminderRecurrenceMetadata.self, from: data)
    }

    static func set(_ metadata: ReminderRecurrenceMetadata, for externalIdentifier: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        UserDefaults.standard.set(data, forKey: key(for: externalIdentifier))
    }

    static func remove(for externalIdentifier: String?) {
        guard let externalIdentifier else { return }
        UserDefaults.standard.removeObject(forKey: key(for: externalIdentifier))
    }
}
