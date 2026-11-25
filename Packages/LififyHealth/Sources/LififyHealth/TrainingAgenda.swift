import Foundation
import LififyChallenges
import LififyCore

/// One planned training in the calendar.
public struct TrainingAgendaItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let planID: UUID
    public let planName: String
    public let date: Date
    /// A session of this plan finished on that day.
    public let isDone: Bool
}

/// Finds the trainings the calendar plans, through the links between events, challenges, and plans.
@MainActor
public enum TrainingAgenda {
    /// The plans linked to an event, directly or through its challenge.
    public static func planIDs(for event: ChallengeCalendarEvent) -> [UUID] {
        var ids = WorkoutLinkStore.planIDs(forEvent: event.id)
        if let challenge = event.linkedChallengeID {
            ids += WorkoutLinkStore.planIDs(forChallenge: challenge).filter { !ids.contains($0) }
        }
        return ids
    }

    /// The trainings of a date range, in time order.
    ///
    /// An event with one linked plan shows that plan. Events that share several plans form a weekly
    /// rotation: each plan is due once per week, so every such event shows one plan, the finished ones
    /// first and the open ones after them, instead of every plan at every event.
    ///
    /// - Parameters:
    ///   - events: The calendar events.
    ///   - plans: The training plans, in the order open plans are suggested.
    ///   - sessions: The finished sessions.
    ///   - start: The first moment of the range.
    ///   - end: The first moment after the range.
    ///   - calendar: The calendar of the days and weeks.
    /// - Returns: The trainings of the range.
    public static func items(
        events: [ChallengeCalendarEvent],
        plans: [WorkoutPlan],
        sessions: [WorkoutSession],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [TrainingAgendaItem] {
        let weeks = weekRange(from: start, to: end, calendar: calendar)
        let linked = events
            .filter { !$0.isReminderSuggestion && $0.startDate >= weeks.lowerBound && $0.startDate < weeks.upperBound }
            .sorted { $0.startDate < $1.startDate }
            .map { event in (event, planIDs(for: event).filter { id in plans.contains { $0.id == id } }) }
            .filter { !$0.1.isEmpty }
        let groups = Dictionary(grouping: linked) { entry in
            RotationKey(week: calendar.dateInterval(of: .weekOfYear, for: entry.0.startDate)?.start ?? entry.0.startDate, plans: Set(entry.1))
        }
        return groups
            .flatMap { key, entries in
                assign(events: entries.map(\.0), key: key, plans: plans, sessions: sessions, calendar: calendar)
            }
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date == $1.date ? $0.planName < $1.planName : $0.date < $1.date }
    }

    /// The events of one week that share the same plans.
    private struct RotationKey: Hashable {
        let week: Date
        let plans: Set<UUID>
    }

    /// Widens a range to whole weeks, so a single day still sees the rest of its week's rotation.
    private static func weekRange(from start: Date, to end: Date, calendar: Calendar) -> Range<Date> {
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let lastMoment = end > start ? end.addingTimeInterval(-1) : start
        let last = calendar.dateInterval(of: .weekOfYear, for: lastMoment)?.end ?? end
        return first..<max(last, end)
    }

    /// Gives each event of one rotation a plan.
    ///
    /// - Parameters:
    ///   - events: The events of the rotation, in time order.
    ///   - key: The week and the shared plans.
    ///   - plans: All plans, for names and the order of open plans.
    ///   - sessions: The finished sessions.
    ///   - calendar: The calendar of the days and weeks.
    /// - Returns: One item per event, while plans are left; finished plans sit on their day when an event is there.
    private static func assign(
        events: [ChallengeCalendarEvent],
        key: RotationKey,
        plans: [WorkoutPlan],
        sessions: [WorkoutSession],
        calendar: Calendar
    ) -> [TrainingAgendaItem] {
        let ordered = plans.filter { key.plans.contains($0.id) }
        guard ordered.count > 1 else {
            return events.compactMap { event in ordered.first.map { item(event: event, plan: $0, sessions: sessions, calendar: calendar) } }
        }
        let week = calendar.dateInterval(of: .weekOfYear, for: key.week)
        let finished = sessions
            .filter { key.plans.contains($0.planID) && week?.contains($0.finishedAt) == true }
            .sorted { $0.finishedAt < $1.finishedAt }
        var slots: [UUID: WorkoutPlan] = [:]
        var used = Set<UUID>()
        for session in finished where !used.contains(session.planID) {
            let free = events.filter { slots[$0.id] == nil }
            let event = free.first { calendar.isDate($0.startDate, inSameDayAs: session.finishedAt) } ?? free.first
            guard let event, let plan = ordered.first(where: { $0.id == session.planID }) else { continue }
            slots[event.id] = plan
            used.insert(plan.id)
        }
        var open = ordered.filter { !used.contains($0.id) }.makeIterator()
        for event in events where slots[event.id] == nil {
            guard let plan = open.next() else { break }
            slots[event.id] = plan
        }
        return events.compactMap { event in
            slots[event.id].map { plan in
                TrainingAgendaItem(id: "\(event.id)-\(plan.id)", planID: plan.id, planName: plan.name, date: event.startDate, isDone: used.contains(plan.id))
            }
        }
    }

    /// One event with its single plan, done when a session of the plan finished that day.
    private static func item(event: ChallengeCalendarEvent, plan: WorkoutPlan, sessions: [WorkoutSession], calendar: Calendar) -> TrainingAgendaItem {
        let done = sessions.contains { $0.planID == plan.id && calendar.isDate($0.finishedAt, inSameDayAs: event.startDate) }
        return TrainingAgendaItem(id: "\(event.id)-\(plan.id)", planID: plan.id, planName: plan.name, date: event.startDate, isDone: done)
    }
}
