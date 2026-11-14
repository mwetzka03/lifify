import Foundation

/// Whether the challenge list shows estimates, hides them, or shows both.
enum ChallengeTimeFilter: String, CaseIterable, Identifiable {
    case withTime
    case withoutTime
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withTime: L("Mit Zeit", "With time")
        case .withoutTime: L("Ohne Zeit", "Without time")
        case .all: L("Alle", "All")
        }
    }
}

/// How optional challenge estimates fill a calendar slot.
/// Sport and abstinence stay out of this. They keep their own rules.
enum ChallengeTimeRules {
    static let suggestionAge: TimeInterval = 7 * 86_400
    /// A challenge created from an event carries this prefix. That link is exclusive.
    static let adoptedMark = "event-challenge:"

    static func allowsTime(_ category: ChallengeCategory) -> Bool {
        category != .sport && category != .abstinence
    }

    static func matches(_ filter: ChallengeTimeFilter, minutes: Int?) -> Bool {
        let hasTime = (minutes ?? 0) > 0
        switch filter {
        case .all: return true
        case .withTime: return hasTime
        case .withoutTime: return !hasTime
        }
    }

    static func isAdopted(_ identifier: String?) -> Bool {
        identifier?.hasPrefix(adoptedMark) == true
    }

    /// Sport, abstinence, and a challenge created from the event take that event alone.
    static func isExclusiveLink(category: ChallengeCategory?, identifier: String?) -> Bool {
        if isAdopted(identifier) { return true }
        return category == .sport || category == .abstinence
    }

    /// Timed challenges use the slot. With none attached, the event still has room.
    static func hasOpenTime(slotMinutes: Int, linkedMinutes: [Int]) -> Bool {
        let used = linkedMinutes.filter { $0 > 0 }
        guard !used.isEmpty else { return true }
        return remaining(slotMinutes: slotMinutes, linkedMinutes: used) > 0
    }

    /// A full event, or one already taken by sport, abstinence, or its own challenge, stays out.
    /// The event already chosen stays, so it can be cleared.
    static func canOffer(
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
    static func pickerAnchor(eventStarts: [Date], today: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        return eventStarts.filter { calendar.startOfDay(for: $0) < start }.count
    }

    static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    /// How many of these estimates fit from the front into the slot.
    static func fitCount(minutes: [Int], slotMinutes: Int) -> Int {
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

    static func remaining(slotMinutes: Int, linkedMinutes: [Int]) -> Int {
        max(0, slotMinutes - linkedMinutes.filter { $0 > 0 }.reduce(0, +))
    }

    /// A challenge without an estimate does not use the slot.
    static func canAdd(minutes: Int?, remaining: Int) -> Bool {
        guard let minutes, minutes > 0 else { return true }
        return minutes <= remaining
    }

    /// The event keeps its planned length until a challenge is checked off.
    /// `linked` holds the estimates that are still open.
    /// `completed` holds the actual minutes entered for the finished ones.
    /// With no actual minutes, the planned slot stays, even for a single challenge.
    static func displayedMinutes(planned: Int, linked: [Int], completed: [Int]) -> Int {
        let actuals = completed.filter { $0 > 0 }
        guard !actuals.isEmpty else { return max(planned, 0) }
        let open = linked.filter { $0 > 0 }.reduce(0, +)
        return max(actuals.reduce(0, +) + open, 1)
    }

    /// Checking off a timed challenge that sits on an event asks for the real minutes.
    static func asksForActualDuration(hasEstimate: Bool, linkedToEvent: Bool, completing: Bool) -> Bool {
        completing && hasEstimate && linkedToEvent
    }

    static func durationParts(_ minutes: Int) -> (hours: Int, minutes: Int) {
        let safe = max(minutes, 0)
        return (safe / 60, safe % 60)
    }

    static func durationText(_ minutes: Int) -> String {
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
    static func scheduleCaption(
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
    static func offeredSuggestions(
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

    static func suggestions(
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

/// Several challenges on one event share a group named after that event and its day.
enum EventGroupName {
    static func title(event: String, day: String) -> String {
        "\(event) – \(day)"
    }
}

/// The challenge switch that offers it when an event is looking for work. Missing means on.
enum EventOffer {
    static func enabled(stored: Bool?) -> Bool { stored ?? true }

    static func isEnabled(for id: UUID, defaults: UserDefaults = .standard) -> Bool {
        let key = storageKey(id)
        guard defaults.object(forKey: key) != nil else { return enabled(stored: nil) }
        return enabled(stored: defaults.bool(forKey: key))
    }

    static func set(_ value: Bool, for id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: storageKey(id))
    }

    private static func storageKey(_ id: UUID) -> String {
        "lifify.eventOffer.\(id.uuidString)"
    }
}
