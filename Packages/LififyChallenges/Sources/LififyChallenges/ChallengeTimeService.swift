import Foundation
import LififyCore
import SwiftData

/// Replaces a calendar event once every one-time challenge on it is checked off.
@MainActor
public enum ChallengeTimeService {
    /// One local event that moved, with the system occurrence it replaces.
    private struct MovedEvent {
        let event: ChallengeCalendarEvent
        let oldIdentifier: String?
        let oldStart: Date
    }

    /// Moves finished events to their actual duration and rewrites them in the system calendar.
    ///
    /// - Parameters:
    ///   - context: The database context.
    ///   - completions: The completions to use, or `nil` to read them from the store.
    /// - Returns: The running calendar rewrite, or `nil` when no event moved.
    @discardableResult
    public static func resize(context: ModelContext, completions: [ChallengeCompletion]? = nil) -> Task<Void, Never>? {
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let tracked = completions ?? ((try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? [])
        let moved = events
            .filter { !$0.isAllDay && !$0.isReminderSuggestion }
            .compactMap { move($0, challenges: challenges, completions: tracked) }
        guard !moved.isEmpty else { return nil }
        try? context.save()
        return Task { @MainActor in
            for change in moved {
                await rewrite(change, context: context)
            }
        }
    }

    /// Moves one event when all its one-time members are done and its window really changed.
    ///
    /// - Parameters:
    ///   - event: The event to check.
    ///   - challenges: All challenges.
    ///   - completions: All known completions.
    /// - Returns: The change to mirror to the system calendar, or `nil` when nothing moved.
    private static func move(
        _ event: ChallengeCalendarEvent,
        challenges: [ChallengeItem],
        completions: [ChallengeCompletion]
    ) -> MovedEvent? {
        let oneTime = ChallengeTimeStore.memberIDs(for: event.id).filter { id in
            challenges.first { $0.id == id }.map { EventRewrite.acceptsSharedEvent($0.recurrence) } ?? false
        }
        let done = Set(completions.map(\.challengeID).filter(oneTime.contains))
        guard EventRewrite.ready(memberIDs: oneTime, completedIDs: done) else { return nil }
        let stamps = oneTime.compactMap { id in
            completions.filter { $0.challengeID == id }.map(\.date).max()
        }
        let durations = oneTime.map { ChallengeTimeStore.actualMinutes(for: $0) ?? 0 }
        guard let window = EventRewrite.window(checkedOffAt: stamps, durations: durations) else { return nil }
        let sameStart = abs(window.start.timeIntervalSince(event.startDate)) <= 30
        let sameEnd = abs(window.end.timeIntervalSince(event.endDate)) <= 30
        guard !sameStart || !sameEnd else { return nil }
        let change = MovedEvent(event: event, oldIdentifier: event.externalIdentifier, oldStart: event.startDate)
        event.startDate = window.start
        event.endDate = window.end
        event.externalIdentifier = nil
        return change
    }

    /// Deletes the old system occurrence and creates the new one.
    private static func rewrite(_ change: MovedEvent, context: ModelContext) async {
        if let oldIdentifier = change.oldIdentifier {
            await EventKitSyncService.deleteCalendarEvent(
                externalIdentifier: oldIdentifier,
                occurrenceStart: change.oldStart
            )
        }
        if let identifier = await EventKitSyncService.saveCalendarEvent(
            externalIdentifier: nil,
            originalStart: nil,
            title: change.event.title,
            notes: change.event.details,
            start: change.event.startDate,
            end: change.event.endDate,
            isAllDay: false
        ) {
            change.event.externalIdentifier = identifier
            try? context.save()
        }
    }
}
