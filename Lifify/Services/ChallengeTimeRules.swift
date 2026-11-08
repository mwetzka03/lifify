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
    static let assignmentLookbackDays = 7

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

    /// An event can be assigned when it is still ahead, or at most a week in the past.
    /// The event already chosen stays available so editing it does not drop the link.
    static func canAssign(start: Date, now: Date, keepingSelection: Bool, calendar: Calendar = .current) -> Bool {
        if keepingSelection { return true }
        guard let earliest = calendar.date(byAdding: .day, value: -assignmentLookbackDays, to: calendar.startOfDay(for: now)) else {
            return false
        }
        return start >= earliest
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

    /// One timed challenge makes the event that long.
    /// Several, with some finished, shrink the event to the finished minutes.
    /// Several, with none finished, keep the planned slot.
    static func displayedMinutes(planned: Int, linked: [Int], completed: [Int]) -> Int {
        let timed = linked.filter { $0 > 0 }
        if timed.count == 1 { return timed[0] }
        let done = completed.filter { $0 > 0 }.reduce(0, +)
        if done > 0 { return done }
        return max(planned, 0)
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
