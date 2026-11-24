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
    /// - Parameters:
    ///   - events: The calendar events.
    ///   - plans: The training plans.
    ///   - sessions: The finished sessions.
    ///   - start: The first moment of the range.
    ///   - end: The first moment after the range.
    ///   - calendar: The calendar of the days.
    /// - Returns: One item per event and linked plan.
    public static func items(
        events: [ChallengeCalendarEvent],
        plans: [WorkoutPlan],
        sessions: [WorkoutSession],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [TrainingAgendaItem] {
        events
            .filter { !$0.isReminderSuggestion && $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .flatMap { event in
                planIDs(for: event).compactMap { id -> TrainingAgendaItem? in
                    guard let plan = plans.first(where: { $0.id == id }) else { return nil }
                    let done = sessions.contains { $0.planID == id && calendar.isDate($0.finishedAt, inSameDayAs: event.startDate) }
                    return TrainingAgendaItem(id: "\(event.id)-\(id)", planID: id, planName: plan.name, date: event.startDate, isDone: done)
                }
            }
    }
}
