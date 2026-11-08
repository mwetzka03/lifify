import Foundation
import SwiftData

/// Writes a finished workout onto that day's linked challenge and calendar occurrence.
@MainActor
enum WorkoutCalendarSync {
    static let noteMarker = "Lifify-Training"

    /// Nearest five minutes. 12:02 stays 12:00, 12:03 becomes 12:05.
    static func clock(_ date: Date) -> Date {
        let step: TimeInterval = 300
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    /// Duration on the same five-minute grid. A finished workout keeps at least five minutes so the event has a span.
    static func duration(seconds: Int) -> Int {
        let step = 300
        let rounded = Int((Double(max(seconds, 0)) / Double(step)).rounded()) * step
        return max(rounded, step)
    }

    static func apply(session: WorkoutSession, context: ModelContext, sessions: [WorkoutSession]) async {
        let end = clock(session.finishedAt)
        let length = duration(seconds: session.durationSeconds)
        let start = end.addingTimeInterval(-TimeInterval(length))
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let linkedIDs = Set(WorkoutLinkStore.challengeIDs(for: session.planID))
        let explicitEventIDs = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        var challengeByID: [UUID: ChallengeItem] = [:]
        for challenge in challenges where linkedIDs.contains(challenge.id) && !challenge.isArchived {
            challengeByID[challenge.id] = challenge
        }

        for event in events where !event.isReminderSuggestion && explicitEventIDs.contains(event.id) && onFinishDay(event, session: session) {
            await updateOccurrence(event, start: start, end: end)
            if let id = event.linkedChallengeID,
               let challenge = challenges.first(where: { $0.id == id && !$0.isArchived }) {
                challengeByID[id] = challenge
            }
        }

        for challenge in challengeByID.values {
            let occurrences = events.filter { event in
                !event.isReminderSuggestion
                    && onFinishDay(event, session: session)
                    && event.linkedChallengeID == challenge.id
            }
            if occurrences.isEmpty {
                if ChallengeService.isDue(challenge, on: session.finishedAt),
                   challenge.externalIdentifier?.hasPrefix("event-challenge:") != true {
                    await createOccurrence(for: challenge, session: session, start: start, end: end, context: context)
                }
            } else {
                for event in occurrences {
                    await updateOccurrence(event, start: start, end: end)
                }
            }
            if ChallengeService.isDue(challenge, on: session.finishedAt) || !occurrences.isEmpty {
                ChallengeService.markCompletedIfNeeded(
                    challenge: challenge,
                    date: session.finishedAt,
                    completions: completions,
                    events: events,
                    context: context
                )
            }
        }
        try? context.save()
        let stored = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        WorkoutLinkStore.reconcile(calendar: stored.filter { !$0.isReminderSuggestion }.map {
            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
        })
        await cleanup(context: context, sessions: sessions)
    }

    /// After a day ends with none of the linked workouts, removes only that occurrence.
    static func cleanup(context: ModelContext, sessions: [WorkoutSession]) async {
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let doomed = events.filter { event in
            guard !event.isReminderSuggestion else { return false }
            let day = calendar.startOfDay(for: event.startDate)
            guard day < today else { return false }
            let challengePlans = Set(
                event.linkedChallengeID.map { WorkoutLinkStore.planIDs(forChallenge: $0) } ?? []
            )
            let eventPlans = Set(WorkoutLinkStore.planIDs(forEvent: event.id))
            let relevant = challengePlans.union(eventPlans)
            let managed = WorkoutLinkStore.isManaged(eventID: event.id) || event.details.contains(noteMarker)
            guard !relevant.isEmpty || managed else { return false }
            let covered = sessions.contains { session in
                guard calendar.isDate(session.finishedAt, inSameDayAs: day) else { return false }
                return relevant.isEmpty || relevant.contains(session.planID)
            }
            return !covered
        }
        guard !doomed.isEmpty else { return }
        for event in doomed {
            if let identifier = event.externalIdentifier, !identifier.hasPrefix("reminder:") {
                await EventKitSyncService.deleteCalendarEvent(
                    externalIdentifier: identifier,
                    occurrenceStart: event.startDate
                )
            }
            WorkoutLinkStore.removeEvent(event.id)
            context.delete(event)
        }
        try? context.save()
    }

    private static func onFinishDay(_ event: ChallengeCalendarEvent, session: WorkoutSession) -> Bool {
        Calendar.current.isDate(event.startDate, inSameDayAs: session.finishedAt)
    }

    /// Moves one occurrence. The series title stays, and later days of a recurrence are left alone.
    private static func updateOccurrence(_ event: ChallengeCalendarEvent, start: Date, end: Date) async {
        let hadExternal = event.externalIdentifier?.isEmpty == false
        let identifier = await EventKitSyncService.saveCalendarEvent(
            externalIdentifier: event.externalIdentifier,
            originalStart: event.startDate,
            title: event.title,
            notes: event.details,
            start: start,
            end: end,
            isAllDay: false,
            occurrenceOnly: true
        )
        guard identifier != nil || !hadExternal else { return }
        event.startDate = start
        event.endDate = end
        event.isAllDay = false
        if let identifier {
            event.externalIdentifier = identifier
        }
    }

    private static func createOccurrence(
        for challenge: ChallengeItem,
        session: WorkoutSession,
        start: Date,
        end: Date,
        context: ModelContext
    ) async {
        let trimmed = challenge.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? session.planName : trimmed
        let notes = "\(noteMarker)\n\(session.planName)"
        let identifier = await EventKitSyncService.saveCalendarEvent(
            externalIdentifier: nil,
            originalStart: nil,
            title: title,
            notes: notes,
            start: start,
            end: end,
            isAllDay: false,
            occurrenceOnly: true
        )
        let event = ChallengeCalendarEvent(
            title: title,
            details: notes,
            startDate: start,
            endDate: end,
            isAllDay: false,
            colorHex: "#2F9E7A",
            icon: "figure.strengthtraining.traditional",
            linkedChallengeID: challenge.id,
            externalIdentifier: identifier,
            isReadOnly: false
        )
        context.insert(event)
        WorkoutLinkStore.link(planID: session.planID, eventID: event.id, managed: true)
    }
}
