import Foundation
import LififyCore
import SwiftData

public struct WorkoutChallengeLink: Codable, Hashable {
    public var planID: UUID
    public var challengeID: UUID

    public init(planID: UUID, challengeID: UUID) {
        self.planID = planID
        self.challengeID = challengeID
    }
}

public struct WorkoutEventLink: Codable, Hashable {
    public var planID: UUID
    public var eventID: UUID
    public var managed: Bool

    public init(planID: UUID, eventID: UUID, managed: Bool) {
        self.planID = planID
        self.eventID = eventID
        self.managed = managed
    }
}

/// Many-to-many links between workout plans, sport challenges, and calendar events.
/// Stored beside the data model so an existing store stays readable.
@MainActor
public enum WorkoutLinkStore {
    private static var cachedChallenges: [WorkoutChallengeLink]?
    private static var cachedEvents: [WorkoutEventLink]?
    public static let revisionKey = "lifify.workoutLinkRevision"

    public static func clearCache() {
        cachedChallenges = nil
        cachedEvents = nil
    }

    public static func challengeIDs(for planID: UUID) -> [UUID] {
        challengeLinks().filter { $0.planID == planID }.map(\.challengeID)
    }

    public static func planIDs(forChallenge challengeID: UUID) -> [UUID] {
        challengeLinks().filter { $0.challengeID == challengeID }.map(\.planID)
    }

    public static func eventIDs(for planID: UUID) -> [UUID] {
        eventLinks().filter { $0.planID == planID }.map(\.eventID)
    }

    public static func planIDs(forEvent eventID: UUID) -> [UUID] {
        eventLinks().filter { $0.eventID == eventID }.map(\.planID)
    }

    public static func isManaged(eventID: UUID) -> Bool {
        eventLinks().contains { $0.eventID == eventID && $0.managed }
    }

    public static func challengePairs() -> [WorkoutChallengeLink] {
        challengeLinks()
    }

    public static func eventPairs() -> [WorkoutEventLink] {
        eventLinks()
    }

    public static func setChallenges(_ ids: Set<UUID>, for planID: UUID) {
        var rows = challengeLinks().filter { $0.planID != planID }
        rows.append(contentsOf: ids.map { WorkoutChallengeLink(planID: planID, challengeID: $0) })
        saveChallenges(rows)
    }

    public static func setEvents(_ ids: Set<UUID>, for planID: UUID) {
        let existing = eventLinks()
        let managedIDs = Set(existing.filter(\.managed).map(\.eventID))
        var rows = existing.filter { $0.planID != planID }
        rows.append(contentsOf: ids.map {
            WorkoutEventLink(planID: planID, eventID: $0, managed: managedIDs.contains($0))
        })
        saveEvents(rows)
    }

    public static func link(planID: UUID, eventID: UUID, managed: Bool) {
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

    public static func link(planID: UUID, challengeID: UUID) {
        var rows = challengeLinks()
        let link = WorkoutChallengeLink(planID: planID, challengeID: challengeID)
        guard !rows.contains(link) else { return }
        rows.append(link)
        saveChallenges(rows)
    }

    public static func removeEvent(_ eventID: UUID) {
        saveEvents(eventLinks().filter { $0.eventID != eventID })
    }

    public static func removePlan(_ planID: UUID) {
        saveChallenges(challengeLinks().filter { $0.planID != planID })
        saveEvents(eventLinks().filter { $0.planID != planID })
    }

    public static func replace(challenges: Set<UUID>, events: Set<UUID>, for planID: UUID) {
        var challengeRows = challengeLinks().filter { $0.planID != planID }
        challengeRows.append(contentsOf: challenges.map { WorkoutChallengeLink(planID: planID, challengeID: $0) })
        let existingEvents = eventLinks()
        let managedIDs = Set(existingEvents.filter(\.managed).map(\.eventID))
        var eventRows = existingEvents.filter { $0.planID != planID }
        eventRows.append(contentsOf: events.map {
            WorkoutEventLink(planID: planID, eventID: $0, managed: managedIDs.contains($0))
        })
        write(challenges: challengeRows, events: eventRows)
        bump()
    }

    public static func reconcile(calendar: [WorkoutLinkRules.CalendarLink]) {
        let planIDs = Set(challengeLinks().map(\.planID) + eventLinks().map(\.planID))
        for planID in planIDs {
            let snapshot = WorkoutLinkRules.Snapshot(
                challenges: Set(challengeIDs(for: planID)),
                events: Set(eventIDs(for: planID))
            )
            let closed = WorkoutLinkRules.close(
                challenges: snapshot.challenges,
                events: snapshot.events,
                calendar: calendar
            )
            if closed != snapshot {
                replace(challenges: closed.challenges, events: closed.events, for: planID)
            }
        }
    }

    public static func reset() {
        LififyDatabase.deleteAll(StoredWorkoutLink.self)
        cachedChallenges = []
        cachedEvents = []
        bump()
    }

    private static func challengeLinks() -> [WorkoutChallengeLink] {
        loadIfNeeded()
        return cachedChallenges ?? []
    }

    private static func eventLinks() -> [WorkoutEventLink] {
        loadIfNeeded()
        return cachedEvents ?? []
    }

    private static func loadIfNeeded() {
        guard cachedChallenges == nil || cachedEvents == nil else { return }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredWorkoutLink>(sortBy: [SortDescriptor(\.position)]))
        cachedChallenges = rows.filter { !$0.isEvent }.map { WorkoutChallengeLink(planID: $0.planID, challengeID: $0.targetID) }
        cachedEvents = rows.filter(\.isEvent).map { WorkoutEventLink(planID: $0.planID, eventID: $0.targetID, managed: $0.managed) }
    }

    private static func saveChallenges(_ rows: [WorkoutChallengeLink]) {
        write(challenges: rows, events: eventLinks())
        bump()
    }

    private static func saveEvents(_ rows: [WorkoutEventLink]) {
        write(challenges: challengeLinks(), events: rows)
        bump()
    }

    private static func write(challenges: [WorkoutChallengeLink], events: [WorkoutEventLink]) {
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredWorkoutLink>())) ?? []).forEach(context.delete)
            for (position, link) in challenges.enumerated() {
                context.insert(StoredWorkoutLink(planID: link.planID, targetID: link.challengeID, isEvent: false, managed: false, position: position))
            }
            for (offset, link) in events.enumerated() {
                context.insert(StoredWorkoutLink(planID: link.planID, targetID: link.eventID, isEvent: true, managed: link.managed, position: challenges.count + offset))
            }
            LififyDatabase.saveSide()
        }
        cachedChallenges = challenges
        cachedEvents = events
    }

    private static func bump() {
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
