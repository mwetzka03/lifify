import Foundation

/// Keeps workout, challenge, and calendar links closed.
/// Linking a challenge also links its calendar entries, and the other way around.
enum WorkoutLinkRules {
    struct CalendarLink: Hashable {
        var eventID: UUID
        var challengeID: UUID?
    }

    struct Snapshot: Equatable {
        var challenges: Set<UUID>
        var events: Set<UUID>
    }

    static func applyChallenges(
        _ challenges: Set<UUID>,
        previous: Snapshot,
        calendar: [CalendarLink]
    ) -> Snapshot {
        let removed = previous.challenges.subtracting(challenges)
        var events = previous.events
        events.subtract(eventIDs(in: calendar, challenges: removed))
        return close(challenges: challenges, events: events, calendar: calendar)
    }

    static func applyEvents(
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

    static func close(challenges: Set<UUID>, events: Set<UUID>, calendar: [CalendarLink]) -> Snapshot {
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

    private static func eventIDs(in calendar: [CalendarLink], challenges: Set<UUID>) -> Set<UUID> {
        Set(calendar.compactMap { link in
            guard let challengeID = link.challengeID, challenges.contains(challengeID) else { return nil }
            return link.eventID
        })
    }
}
