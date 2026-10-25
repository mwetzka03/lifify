import Foundation

/// Active list and the day-by-day completion history.
enum ChallengeActivity {
    /// A one-time challenge leaves the active list once it has been done.
    /// A recurring challenge stays, and is only grayed for the day it was done.
    static func staysOnActiveList(recurrence: ChallengeRecurrence, hasCompletion: Bool) -> Bool {
        if recurrence == .none && hasCompletion { return false }
        return true
    }

    static func dimsActiveRow(recurrence: ChallengeRecurrence, completedToday: Bool) -> Bool {
        recurrence != .none && completedToday
    }
}

struct ChallengeHistoryEntry: Identifiable, Equatable {
    var challengeID: UUID
    var title: String
    var date: Date
    var id: String { "\(challengeID.uuidString)-\(date.timeIntervalSinceReferenceDate)" }
}

struct ChallengeHistoryDay: Identifiable, Equatable {
    var day: Date
    var entries: [ChallengeHistoryEntry]
    var id: Date { day }
}

struct ChallengeHistoryCompletion {
    var challengeID: UUID
    var title: String
    var date: Date
}

enum ChallengeHistory {
    static func grouped(completions: [ChallengeHistoryCompletion], calendar: Calendar = .current) -> [ChallengeHistoryDay] {
        let buckets = Dictionary(grouping: completions) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { day in
            var seen = Set<UUID>()
            let entries = (buckets[day] ?? [])
                .sorted { lhs, rhs in
                    if lhs.title == rhs.title { return lhs.challengeID.uuidString < rhs.challengeID.uuidString }
                    return lhs.title < rhs.title
                }
                .compactMap { completion -> ChallengeHistoryEntry? in
                    guard seen.insert(completion.challengeID).inserted else { return nil }
                    return ChallengeHistoryEntry(challengeID: completion.challengeID, title: completion.title, date: day)
                }
            return ChallengeHistoryDay(day: day, entries: entries)
        }
    }
}
