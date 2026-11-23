import Foundation
import LififyCore

/// Active list and the day-by-day completion history.
public enum ChallengeActivity {
    /// A one-time challenge leaves the active list once it has been done.
    /// A recurring challenge stays, and is only grayed for the day it was done.
    public static func staysOnActiveList(recurrence: ChallengeRecurrence, hasCompletion: Bool) -> Bool {
        if recurrence == .none && hasCompletion { return false }
        return true
    }

    /// Says whether a repeating challenge done today appears dimmed.
    public static func dimsActiveRow(recurrence: ChallengeRecurrence, completedToday: Bool) -> Bool {
        recurrence != .none && completedToday
    }
}

/// One finished challenge in the history.
public struct ChallengeHistoryEntry: Identifiable, Equatable {
    public var challengeID: UUID
    public var title: String
    public var date: Date
    public var id: String { "\(challengeID.uuidString)-\(date.timeIntervalSinceReferenceDate)" }

    public init(challengeID: UUID, title: String, date: Date) {
        self.challengeID = challengeID
        self.title = title
        self.date = date
    }
}

/// One day of the history.
public struct ChallengeHistoryDay: Identifiable, Equatable {
    public var day: Date
    public var entries: [ChallengeHistoryEntry]
    public var id: Date { day }

    public init(day: Date, entries: [ChallengeHistoryEntry]) {
        self.day = day
        self.entries = entries
    }
}

/// A completion, reduced for the history.
public struct ChallengeHistoryCompletion {
    public var challengeID: UUID
    public var title: String
    public var date: Date

    public init(challengeID: UUID, title: String, date: Date) {
        self.challengeID = challengeID
        self.title = title
        self.date = date
    }
}

/// Groups completions for the history.
public enum ChallengeHistory {
    /// Groups completions by day, newest first.
    public static func grouped(completions: [ChallengeHistoryCompletion], calendar: Calendar = .current) -> [ChallengeHistoryDay] {
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

    /// One row for the whole abstinence, instead of one completion on every day.
    public static func abstinenceSpans(
        _ completions: [ChallengeHistoryCompletion],
        calendar: Calendar = .current
    ) -> [AbstinenceHistorySpan] {
        let grouped = Dictionary(grouping: completions, by: \.challengeID)
        return grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.first?.title ?? ""
            let right = grouped[rhs]?.first?.title ?? ""
            if left == right { return lhs.uuidString < rhs.uuidString }
            return left.localizedStandardCompare(right) == .orderedAscending
        }.compactMap { id in
            guard let items = grouped[id], let title = items.first?.title else { return nil }
            let days = Set(items.map { calendar.startOfDay(for: $0.date) })
            guard let first = days.min(), let last = days.max() else { return nil }
            return AbstinenceHistorySpan(
                challengeID: id,
                title: title,
                first: first,
                last: last,
                dayCount: days.count
            )
        }
    }
}

/// One continuous abstinence run.
public struct AbstinenceHistorySpan: Equatable, Identifiable {
    public var challengeID: UUID
    public var title: String
    public var first: Date
    public var last: Date
    public var dayCount: Int
    public var id: UUID { challengeID }

    public init(challengeID: UUID, title: String, first: Date, last: Date, dayCount: Int) {
        self.challengeID = challengeID
        self.title = title
        self.first = first
        self.last = last
        self.dayCount = dayCount
    }
}
