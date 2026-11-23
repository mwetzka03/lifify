import Foundation
import LififyCore

/// Keeps workout, challenge, and calendar links closed.
/// Linking a challenge also links its calendar entries, and the other way around.
public enum WorkoutLinkRules {
    /// An event with its direct challenge.
    public struct CalendarLink: Hashable {
        public var eventID: UUID
        public var challengeID: UUID?

        public init(eventID: UUID, challengeID: UUID? = nil) {
            self.eventID = eventID
            self.challengeID = challengeID
        }
    }

    /// The links of one plan.
    public struct Snapshot: Equatable {
        public var challenges: Set<UUID>
        public var events: Set<UUID>

        public init(challenges: Set<UUID>, events: Set<UUID>) {
            self.challenges = challenges
            self.events = events
        }
    }

    /// Applies a new challenge selection.
    public static func applyChallenges(
        _ challenges: Set<UUID>,
        previous: Snapshot,
        calendar: [CalendarLink]
    ) -> Snapshot {
        let removed = previous.challenges.subtracting(challenges)
        var events = previous.events
        events.subtract(eventIDs(in: calendar, challenges: removed))
        return close(challenges: challenges, events: events, calendar: calendar)
    }

    /// Applies a new event selection.
    public static func applyEvents(
        _ events: Set<UUID>,
        previous: Snapshot,
        calendar: [CalendarLink]
    ) -> Snapshot {
        let removed = previous.events.subtracting(events)
        let removedChallenges = Set(calendar.compactMap { link in
            removed.contains(link.eventID) ? link.challengeID : nil
        })
        var challenges = previous.challenges.subtracting(removedChallenges)
        var kept = events.subtracting(eventIDs(in: calendar, challenges: removedChallenges))
        for link in calendar where removed.contains(link.eventID) && link.challengeID == nil {
            kept.remove(link.eventID)
        }
        return close(challenges: challenges, events: kept, calendar: calendar)
    }

    /// Adds the links that follow from the calendar.
    public static func close(challenges: Set<UUID>, events: Set<UUID>, calendar: [CalendarLink]) -> Snapshot {
        var challenges = challenges
        var events = events
        var changed = true
        while changed {
            changed = false
            for link in calendar where events.contains(link.eventID) {
                if let challengeID = link.challengeID, challenges.insert(challengeID).inserted {
                    changed = true
                }
            }
            for link in calendar {
                guard let challengeID = link.challengeID, challenges.contains(challengeID) else { continue }
                if events.insert(link.eventID).inserted {
                    changed = true
                }
            }
        }
        return Snapshot(challenges: challenges, events: events)
    }

    /// Lists the events of the challenges.
    private static func eventIDs(in calendar: [CalendarLink], challenges: Set<UUID>) -> Set<UUID> {
        Set(calendar.compactMap { link in
            guard let challengeID = link.challengeID, challenges.contains(challengeID) else { return nil }
            return link.eventID
        })
    }
}
