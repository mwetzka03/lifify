import Foundation

/// Apple Calendar expands a recurrence about one year ahead. Lifify follows that window.
enum CalendarSyncWindow {
    static let pastDays = 30
    static let futureDays = 365

    static func start(around date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -pastDays, to: date) ?? date
    }

    static func end(around date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: futureDays, to: date) ?? date
    }

    static func contains(_ date: Date, around now: Date, calendar: Calendar = .current) -> Bool {
        date >= start(around: now, calendar: calendar) && date < end(around: now, calendar: calendar)
    }

    /// An imported Apple event that disappeared is removed only inside the sync window.
    /// Older events and reminders stay. A matched event stays too.
    static func removesImportedEvent(
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
enum AgendaScroll {
    static let pastDays = 30
    static let futureDays = 45

    static func days(around today: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: today)
        let first = calendar.date(byAdding: .day, value: -pastDays, to: start) ?? start
        return (0..<(pastDays + 1 + futureDays)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first)
        }
    }

    static func todayIndex(in days: [Date], today: Date, calendar: Calendar = .current) -> Int? {
        days.firstIndex { calendar.isDate($0, inSameDayAs: today) }
    }
}

/// A new occurrence of a series keeps the challenge already linked to that series.
enum CalendarSeriesLink {
    struct Event {
        var externalIdentifier: String?
        var challengeID: UUID?
        var groupID: UUID?
        var rewardID: UUID?
    }

    struct Links: Equatable {
        var challengeID: UUID?
        var groupID: UUID?
        var rewardID: UUID?
    }

    static func links(externalIdentifier: String, events: [Event]) -> Links {
        let siblings = events.filter { $0.externalIdentifier == externalIdentifier }
        return Links(
            challengeID: siblings.compactMap(\.challengeID).first,
            groupID: siblings.compactMap(\.groupID).first,
            rewardID: siblings.compactMap(\.rewardID).first
        )
    }
}
