import Foundation
import LififyCore

/// Apple Calendar expands a recurrence about one year ahead. Lifify follows that window.
public enum CalendarSyncWindow {
    public static let pastDays = 30
    public static let futureDays = 365

    /// The first day of the sync window.
    public static func start(around date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -pastDays, to: date) ?? date
    }

    /// The last day of the sync window.
    public static func end(around date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: futureDays, to: date) ?? date
    }

    /// Says whether a date lies in the window.
    public static func contains(_ date: Date, around now: Date, calendar: Calendar = .current) -> Bool {
        date >= start(around: now, calendar: calendar) && date < end(around: now, calendar: calendar)
    }

    /// An imported Apple event that disappeared is removed only inside the sync window.
    /// Older events and reminders stay. A matched event stays too.
    public static func removesImportedEvent(
        start: Date,
        externalIdentifier: String?,
        matched: Bool,
        around now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let externalIdentifier, !externalIdentifier.hasPrefix("reminder:") else { return false }
        guard !matched else { return false }
        return contains(start, around: now, calendar: calendar)
    }
}

/// The challenge calendar opens on today. Earlier days sit above it, later days below it.
public enum AgendaScroll {
    public static let pastDays = 30
    public static let futureDays = 45

    /// Lists the days shown around today.
    public static func days(around today: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: today)
        let first = calendar.date(byAdding: .day, value: -pastDays, to: start) ?? start
        return (0..<(pastDays + 1 + futureDays)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first)
        }
    }

    /// Finds today in the list.
    public static func todayIndex(in days: [Date], today: Date, calendar: Calendar = .current) -> Int? {
        days.firstIndex { calendar.isDate($0, inSameDayAs: today) }
    }
}

/// A new occurrence of a series keeps the challenge already linked to that series.
public enum CalendarSeriesLink {
    /// An event's links, reduced for series matching.
    public struct Event {
        public var externalIdentifier: String?
        public var challengeID: UUID?
        public var groupID: UUID?
        public var rewardID: UUID?

        public init(externalIdentifier: String? = nil, challengeID: UUID? = nil, groupID: UUID? = nil, rewardID: UUID? = nil) {
            self.externalIdentifier = externalIdentifier
            self.challengeID = challengeID
            self.groupID = groupID
            self.rewardID = rewardID
        }
    }

    /// The links a new occurrence inherits.
    public struct Links: Equatable {
        public var challengeID: UUID?
        public var groupID: UUID?
        public var rewardID: UUID?

        public init(challengeID: UUID? = nil, groupID: UUID? = nil, rewardID: UUID? = nil) {
            self.challengeID = challengeID
            self.groupID = groupID
            self.rewardID = rewardID
        }
    }

    /// Returns the links shared by a series.
    public static func links(externalIdentifier: String, events: [Event]) -> Links {
        let siblings = events.filter { $0.externalIdentifier == externalIdentifier }
        return Links(
            challengeID: siblings.compactMap(\.challengeID).first,
            groupID: siblings.compactMap(\.groupID).first,
            rewardID: siblings.compactMap(\.rewardID).first
        )
    }
}
