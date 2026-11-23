import Foundation
import LififyCore

/// Whether the challenge list shows estimates, hides them, or shows both.
public enum ChallengeTimeFilter: String, CaseIterable, Identifiable {
    case withTime
    case withoutTime
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .withTime: L("Mit Zeit", "With time")
        case .withoutTime: L("Ohne Zeit", "Without time")
        case .all: L("Alle", "All")
        }
    }
}

/// How optional challenge estimates fill a calendar slot.
/// Sport and abstinence stay out of this. They keep their own rules.
public enum ChallengeTimeRules {
    public static let suggestionAge: TimeInterval = 7 * 86_400
    /// A challenge created from an event carries this prefix. That link is exclusive.
    public static let adoptedMark = "event-challenge:"

    /// Sport and abstinence have no minutes.
    public static func allowsTime(_ category: ChallengeCategory) -> Bool {
        category != .sport && category != .abstinence
    }

    /// Says whether a duration fits the filter.
    public static func matches(_ filter: ChallengeTimeFilter, minutes: Int?) -> Bool {
        let hasTime = (minutes ?? 0) > 0
        switch filter {
        case .all: return true
        case .withTime: return hasTime
        case .withoutTime: return !hasTime
        }
    }

    /// Says whether a challenge came from a calendar event.
    public static func isAdopted(_ identifier: String?) -> Bool {
        identifier?.hasPrefix(adoptedMark) == true
    }

    /// Sport, abstinence, and a challenge created from the event take that event alone.
    public static func isExclusiveLink(category: ChallengeCategory?, identifier: String?) -> Bool {
        if isAdopted(identifier) { return true }
        return category == .sport || category == .abstinence
    }

    /// Timed challenges use the slot. With none attached, the event still has room.
    public static func hasOpenTime(slotMinutes: Int, linkedMinutes: [Int]) -> Bool {
        let used = linkedMinutes.filter { $0 > 0 }
        guard !used.isEmpty else { return true }
        return remaining(slotMinutes: slotMinutes, linkedMinutes: used) > 0
    }

    /// A full event, or one already taken by sport, abstinence, or its own challenge, stays out.
    /// The event already chosen stays, so it can be cleared.
    public static func canOffer(
        exclusive: Bool,
        slotMinutes: Int,
        linkedMinutes: [Int],
        keepingSelection: Bool
    ) -> Bool {
        if keepingSelection { return true }
        if exclusive { return false }
        return hasOpenTime(slotMinutes: slotMinutes, linkedMinutes: linkedMinutes)
    }

    /// None sits on today. The index is how many events are on earlier days.
    public static func pickerAnchor(eventStarts: [Date], today: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        return eventStarts.filter { calendar.startOfDay(for: $0) < start }.count
    }

    /// Returns the whole minutes between two dates.
    public static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    /// How many of these estimates fit from the front into the slot.
    public static func fitCount(minutes: [Int], slotMinutes: Int) -> Int {
        guard slotMinutes > 0 else { return 0 }
        var used = 0
        var count = 0
        for item in minutes where item > 0 {
            if used + item > slotMinutes { break }
            used += item
            count += 1
        }
        return count
    }

    /// Returns the minutes left in a slot.
    public static func remaining(slotMinutes: Int, linkedMinutes: [Int]) -> Int {
        max(0, slotMinutes - linkedMinutes.filter { $0 > 0 }.reduce(0, +))
    }

    /// A challenge without an estimate does not use the slot.
    public static func canAdd(minutes: Int?, remaining: Int) -> Bool {
        guard let minutes, minutes > 0 else { return true }
        return minutes <= remaining
    }

    /// Checking off a timed challenge that sits on an event asks for the real minutes.
    public static func asksForActualDuration(hasEstimate: Bool, linkedToEvent: Bool, completing: Bool) -> Bool {
        completing && hasEstimate && linkedToEvent
    }

    /// Splits minutes into hours and minutes.
    public static func durationParts(_ minutes: Int) -> (hours: Int, minutes: Int) {
        let safe = max(minutes, 0)
        return (safe / 60, safe % 60)
    }

    /// Formats a duration.
    public static func durationText(_ minutes: Int) -> String {
        let parts = durationParts(minutes)
        if parts.hours > 0, parts.minutes > 0 {
            return L("\(parts.hours) Std \(parts.minutes) Min", "\(parts.hours) h \(parts.minutes) min")
        }
        if parts.hours > 0 {
            return L("\(parts.hours) Std", "\(parts.hours) h")
        }
        return L("\(parts.minutes) Min", "\(parts.minutes) min")
    }

    /// Date and start stay. A free event shows its length. A filled event shows only the time still left.
    public static func scheduleCaption(
        allDay: Bool,
        dateText: String,
        timeText: String,
        slotMinutes: Int,
        linkedMinutes: [Int]
    ) -> String {
        if allDay { return L("Ganztägig", "All day") }
        let used = linkedMinutes.filter { $0 > 0 }
        if used.isEmpty {
            return "\(dateText) · \(timeText) · \(durationText(slotMinutes))"
        }
        let left = remaining(slotMinutes: slotMinutes, linkedMinutes: used)
        return "\(dateText) · \(timeText) · \(durationText(left))"
    }

    /// Oldest first. A finished challenge is left out. One already on the event stays if it is not marked finished.
    public static func offeredSuggestions(
        candidates: [(id: UUID, minutes: Int?, createdAt: Date, offered: Bool, finished: Bool)],
        already: Set<UUID>
    ) -> [UUID] {
        candidates
            .filter { $0.offered && !$0.finished && !already.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)
    }

    /// Suggests challenges that fit a slot.
    public static func suggestions(
        candidates: [(id: UUID, minutes: Int?, createdAt: Date)],
        now: Date,
        remaining: Int,
        already: Set<UUID>,
        minimumAge: TimeInterval = suggestionAge
    ) -> [UUID] {
        candidates.compactMap { item in
            guard !already.contains(item.id) else { return nil }
            guard now.timeIntervalSince(item.createdAt) >= minimumAge else { return nil }
            guard canAdd(minutes: item.minutes, remaining: remaining) else { return nil }
            return item.id
        }
    }
}

/// Linking a challenge to an event puts it on that event's day and into the shared group.
public enum EventChallengeLink {
    /// The result of placing challenges on a slot.
    public struct Placement: Equatable {
        public var start: Date
        public var weekdays: Set<Int>
        public var end: Date?

        public init(start: Date, weekdays: Set<Int>, end: Date? = nil) {
            self.start = start
            self.weekdays = weekdays
            self.end = end
        }
    }

    /// The event start replaces the challenge day. A weekly challenge moves onto that weekday.
    /// An end that would fall before the new day is cleared.
    public static func placement(
        eventStart: Date,
        recurrence: ChallengeRecurrence,
        weekdays: Set<Int>,
        end: Date?,
        calendar: Calendar = .current
    ) -> Placement {
        var days = weekdays
        if recurrence == .weekly {
            days = [calendar.component(.weekday, from: eventStart)]
        }
        var keptEnd = end
        if let end, calendar.startOfDay(for: end) < calendar.startOfDay(for: eventStart) {
            keptEnd = nil
        }
        return Placement(start: eventStart, weekdays: days, end: keptEnd)
    }

    /// Everyone already on the event, plus the challenge linked afterwards.
    public static func members(already: [UUID], linked: UUID?, adding: UUID?) -> [UUID] {
        var ids = already
        if let linked, !ids.contains(linked) { ids.append(linked) }
        if let adding, !ids.contains(adding) { ids.append(adding) }
        return ids
    }

    /// Two or more challenges on an event form a group.
    public static func makesGroup(count: Int) -> Bool { count >= 2 }

    /// A timed event writes the clock into the reminder. An all-day event keeps the date only.
    public static func reminderIncludesTime(allDay: Bool) -> Bool { !allDay }

    /// Einzeln shows every challenge, including the ones that sit in a group.
    public static func showsIndividual(inGroup: Bool, singleFilter: Bool) -> Bool {
        singleFilter || !inGroup
    }
}

/// Several challenges share one event only when each of them happens once.
/// The calendar event is replaced after every one of them is checked off.
public enum EventRewrite {
    /// The moved time of a finished event.
    public struct Window: Equatable {
        public var start: Date
        public var end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// Only one-time challenges can share an event.
    public static func acceptsSharedEvent(_ recurrence: ChallengeRecurrence) -> Bool {
        recurrence == .none
    }

    /// A repeating challenge can take an empty event. It cannot join other challenges.
    public static func canShare(adding: ChallengeRecurrence, others: [ChallengeRecurrence]) -> Bool {
        if !acceptsSharedEvent(adding) { return others.isEmpty }
        return others.allSatisfy(acceptsSharedEvent)
    }

    /// Says whether all members are done.
    public static func ready(memberIDs: [UUID], completedIDs: Set<UUID>) -> Bool {
        let ids = ChallengeGroups.unique(memberIDs)
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { completedIDs.contains($0) }
    }

    /// The end is the last check-off. The start is that moment minus the summed durations.
    public static func window(checkedOffAt: [Date], durations: [Int]) -> Window? {
        let minutes = durations.filter { $0 > 0 }.reduce(0, +)
        guard minutes > 0, let end = checkedOffAt.max() else { return nil }
        return Window(start: end.addingTimeInterval(TimeInterval(-minutes * 60)), end: end)
    }
}

/// A normal group takes every challenge. A group tied to an event takes one-time challenges until the slot is full.
public enum GroupJoin {
    /// Says whether a challenge can join an event.
    public static func canJoin(linkedToEvent: Bool, oneTime: Bool, minutes: Int?, remaining: Int) -> Bool {
        guard linkedToEvent else { return true }
        guard oneTime else { return false }
        return ChallengeTimeRules.canAdd(minutes: minutes, remaining: remaining)
    }
}

/// The calendar line sits on an event's group, not on each member. Its color follows the style.
public enum GroupCalendarLine {
    /// Says whether the event line belongs on the group instead.
    public static func belongsOnGroup(eventGroupID: UUID?, membership: [UUID]) -> Bool {
        guard let eventGroupID else { return false }
        return membership.contains(eventGroupID)
    }
}

/// Deleting a group can keep its challenges. A calendar group always drops the link.
public enum GroupRemoval {
    /// Removes a group from a list.
    public static func remaining(_ groups: [UUID], removing: UUID) -> [UUID] {
        groups.filter { $0 != removing }
    }

    /// An event-made group clears its calendar link.
    public static func clearsCalendarLink(generatedFromEvent: Bool) -> Bool {
        generatedFromEvent
    }
}

/// A challenge starts with two freezes. A nutrition day with no meals is not a miss.
public enum StreakFreeze {
    public static let startingCount = 2

    /// Says whether a day counts for the streak.
    public static func countsDay(followsNutrition: Bool, confirmedMeals: Int) -> Bool {
        if followsNutrition { return confirmedMeals > 0 }
        return true
    }
}

/// Names event groups.
public enum EventGroupName {
    /// Builds the name of an event group.
    public static func title(event: String, day: String) -> String {
        "\(event) – \(day)"
    }
}

/// The challenge switch that offers it when an event is looking for work. Missing means on.
@MainActor
public enum EventOffer {
    /// The offer is on unless it was turned off.
    public nonisolated static func enabled(stored: Bool?) -> Bool { stored ?? true }

    /// Says whether the offer is on for an event.
    public static func isEnabled(for id: UUID) -> Bool {
        enabled(stored: LinkTable.map(.eventOffer)[id.uuidString].map { $0 == "true" })
    }

    /// Stores the choice for an event.
    public static func set(_ value: Bool, for id: UUID) {
        LinkTable.set(.eventOffer, key: id.uuidString, value: value ? "true" : "false")
    }
}
