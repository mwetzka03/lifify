import Foundation

struct WorkoutChallengeLink: Codable, Hashable {
    var planID: UUID
    var challengeID: UUID
}

struct WorkoutEventLink: Codable, Hashable {
    var planID: UUID
    var eventID: UUID
    var managed: Bool
}

/// Many-to-many links between workout plans, sport challenges, and calendar events.
/// Stored beside the data model so an existing store stays readable.
enum WorkoutLinkStore {
    private static let challengeKey = "lifify.workoutChallengeLinks"
    private static let eventKey = "lifify.workoutEventLinks"
    static let revisionKey = "lifify.workoutLinkRevision"

    static func challengeIDs(for planID: UUID) -> [UUID] {
        challengeLinks().filter { $0.planID == planID }.map(\.challengeID)
    }

    static func planIDs(forChallenge challengeID: UUID) -> [UUID] {
        challengeLinks().filter { $0.challengeID == challengeID }.map(\.planID)
    }

    static func eventIDs(for planID: UUID) -> [UUID] {
        eventLinks().filter { $0.planID == planID }.map(\.eventID)
    }

    static func planIDs(forEvent eventID: UUID) -> [UUID] {
        eventLinks().filter { $0.eventID == eventID }.map(\.planID)
    }

    static func isManaged(eventID: UUID) -> Bool {
        eventLinks().contains { $0.eventID == eventID && $0.managed }
    }

    static func challengePairs() -> [WorkoutChallengeLink] {
        challengeLinks()
    }

    static func eventPairs() -> [WorkoutEventLink] {
        eventLinks()
    }

    static func setChallenges(_ ids: Set<UUID>, for planID: UUID) {
        var rows = challengeLinks().filter { $0.planID != planID }
        rows.append(contentsOf: ids.map { WorkoutChallengeLink(planID: planID, challengeID: $0) })
        saveChallenges(rows)
    }

    static func setEvents(_ ids: Set<UUID>, for planID: UUID) {
        let existing = eventLinks()
        let managedIDs = Set(existing.filter(\.managed).map(\.eventID))
        var rows = existing.filter { $0.planID != planID }
        rows.append(contentsOf: ids.map {
            WorkoutEventLink(planID: planID, eventID: $0, managed: managedIDs.contains($0))
        })
        saveEvents(rows)
    }

    static func link(planID: UUID, eventID: UUID, managed: Bool) {
        let existing = eventLinks()
        let alreadyManaged = existing.contains { $0.eventID == eventID && $0.managed }
        var rows = existing.filter { !($0.planID == planID && $0.eventID == eventID) }
        rows.append(WorkoutEventLink(planID: planID, eventID: eventID, managed: managed || alreadyManaged))
        if managed || alreadyManaged {
            for index in rows.indices where rows[index].eventID == eventID {
                rows[index].managed = true
            }
        }
        saveEvents(rows)
    }

    static func link(planID: UUID, challengeID: UUID) {
        var rows = challengeLinks()
        let link = WorkoutChallengeLink(planID: planID, challengeID: challengeID)
        guard !rows.contains(link) else { return }
        rows.append(link)
        saveChallenges(rows)
    }

    static func removeEvent(_ eventID: UUID) {
        saveEvents(eventLinks().filter { $0.eventID != eventID })
    }

    static func removePlan(_ planID: UUID) {
        saveChallenges(challengeLinks().filter { $0.planID != planID })
        saveEvents(eventLinks().filter { $0.planID != planID })
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: challengeKey)
        UserDefaults.standard.removeObject(forKey: eventKey)
        bump()
    }

    private static func challengeLinks() -> [WorkoutChallengeLink] {
        decode(challengeKey)
    }

    private static func eventLinks() -> [WorkoutEventLink] {
        decode(eventKey)
    }

    private static func saveChallenges(_ rows: [WorkoutChallengeLink]) {
        encode(rows, key: challengeKey)
    }

    private static func saveEvents(_ rows: [WorkoutEventLink]) {
        encode(rows, key: eventKey)
    }

    private static func decode<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([T].self, from: data)
        else { return [] }
        return rows
    }

    private static func encode<T: Encodable>(_ rows: [T], key: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
        bump()
    }

    private static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
