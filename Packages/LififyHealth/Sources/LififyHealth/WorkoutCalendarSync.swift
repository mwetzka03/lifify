import Foundation
import LififyChallenges
import LififyCore
import SwiftData

/// Writes a finished workout onto that day's linked challenge and calendar occurrence.
@MainActor
public enum WorkoutCalendarSync {
    public static let noteMarker = "Lifify-Training"

    /// Nearest five minutes. 12:02 stays 12:00, 12:03 becomes 12:05.
    public static func clock(_ date: Date) -> Date {
        let step: TimeInterval = 300
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    /// Duration on the same five-minute grid. A finished workout keeps at least five minutes so the event has a span.
    public static func duration(seconds: Int) -> Int {
        let step = 300
        let rounded = Int((Double(max(seconds, 0)) / Double(step)).rounded()) * step
        return max(rounded, step)
    }

    /// Moves the linked events to the real training time and checks the challenges off.
    ///
    /// - Parameters:
    ///   - session: The finished session.
    ///   - context: The database context.
    ///   - sessions: All sessions, used for the cleanup afterward.
    public static func apply(session: WorkoutSession, context: ModelContext, sessions: [WorkoutSession]) async {
        let end = clock(session.finishedAt)
        let length = duration(seconds: session.durationSeconds)
        let start = end.addingTimeInterval(-TimeInterval(length))
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let linkedIDs = Set(WorkoutLinkStore.challengeIDs(for: session.planID))
        let explicitEventIDs = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        var challengeByID: [UUID: ChallengeItem] = [:]
        var placed = false
        for challenge in challenges where linkedIDs.contains(challenge.id) && !challenge.isArchived {
            challengeByID[challenge.id] = challenge
        }

        for event in events where !event.isReminderSuggestion && explicitEventIDs.contains(event.id) && onFinishDay(event, session: session) {
            await updateOccurrence(event, start: start, end: end)
            placed = true
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
                   !ChallengeTimeRules.isAdopted(challenge.externalIdentifier) {
                    await createStandalone(session: session, start: start, end: end, events: events, completions: completions, challenge: challenge, context: context)
                    placed = true
                }
            } else {
                for event in occurrences {
                    await updateOccurrence(event, start: start, end: end)
                }
                placed = true
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
        if !placed {
            // A training on a day without its slot still lands in the calendar, at its real time.
            await createStandalone(session: session, start: start, end: end, events: events, completions: completions, context: context)
        }
        try? context.save()
        let stored = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        WorkoutLinkStore.reconcile(calendar: stored.filter { !$0.isReminderSuggestion }.map {
            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
        })
        await cleanup(context: context, sessions: sessions)
    }

    /// After a day ends with none of the linked workouts, removes only that occurrence.
    public static func cleanup(context: ModelContext, sessions: [WorkoutSession]) async {
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

    /// Says whether the event lies on the session's day.
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

    /// Creates an event for a due challenge without one.
    /// Creates an event for a training that had no slot that day: a copy of the plan's linked
    /// recurring event (calendar, place, color, symbol, challenge) at the real time, titled
    /// "Series: Plan" such as "GYM: Unterkörper", or a plain event when nothing is linked.
    ///
    /// - Parameters:
    ///   - session: The finished training.
    ///   - start: The rounded start.
    ///   - end: The rounded end.
    ///   - events: All calendar events, to find the linked series.
    ///   - completions: The check-offs, so a linked challenge is checked once.
    ///   - challenge: The linked challenge when no series event exists.
    ///   - context: The database context.
    private static func createStandalone(
        session: WorkoutSession,
        start: Date,
        end: Date,
        events: [ChallengeCalendarEvent],
        completions: [ChallengeCompletion],
        challenge: ChallengeItem? = nil,
        context: ModelContext
    ) async {
        let series = seriesEvent(for: session, in: events)
        let title = standaloneTitle(series: series?.title ?? challenge?.title, plan: session.planName)
        let notes = "\(noteMarker)\n\(session.planName)"
        let identifier = await EventKitSyncService.saveCalendarEvent(
            externalIdentifier: nil,
            originalStart: nil,
            title: title,
            notes: notes,
            start: start,
            end: end,
            isAllDay: false,
            occurrenceOnly: true,
            calendarOfEvent: series?.externalIdentifier ?? trainingCalendarSample(session: session, events: events)
        )
        let event = ChallengeCalendarEvent(
            title: title,
            details: notes,
            startDate: start,
            endDate: end,
            isAllDay: false,
            colorHex: series?.colorHex ?? "#2F9E7A",
            icon: series?.icon ?? "figure.strengthtraining.traditional",
            linkedChallengeID: series?.linkedChallengeID ?? challenge?.id,
            externalIdentifier: identifier,
            isReadOnly: false
        )
        context.insert(event)
        WorkoutLinkStore.link(planID: session.planID, eventID: event.id, managed: true)
        checkLinkedChallenge(of: event, session: session, events: events + [event], completions: completions, context: context)
    }

    /// A system event of an earlier training, preferring this plan, whose calendar new trainings join.
    static func trainingCalendarSample(session: WorkoutSession, events: [ChallengeCalendarEvent]) -> String? {
        let own = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        let linked = events.filter { $0.externalIdentifier != nil && !$0.isReminderSuggestion && !TrainingAgenda.planIDs(for: $0).isEmpty }
        return (linked.first { own.contains($0.id) } ?? linked.first)?.externalIdentifier
    }

    /// The plan's calendar series: an event linked to the plan directly or through its challenge,
    /// past or coming, the one nearest to the training. Copies made by Lifify do not count.
    static func seriesEvent(for session: WorkoutSession, in events: [ChallengeCalendarEvent]) -> ChallengeCalendarEvent? {
        let own = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        let challenges = Set(WorkoutLinkStore.challengeIDs(for: session.planID))
        return events
            .filter { event in
                !event.isReminderSuggestion && !event.details.contains(noteMarker)
                    && (own.contains(event.id) || event.linkedChallengeID.map(challenges.contains) == true)
            }
            .min { abs($0.startDate.timeIntervalSince(session.finishedAt)) < abs($1.startDate.timeIntervalSince(session.finishedAt)) }
    }

    /// "Series: Plan", or the plan alone when there is no series or both are the same.
    public static func standaloneTitle(series: String?, plan: String) -> String {
        let name = series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name.caseInsensitiveCompare(plan) != .orderedSame else { return plan }
        return "\(name): \(plan)"
    }

    /// Checks off the challenge the copied event belongs to, as on its normal day.
    private static func checkLinkedChallenge(
        of event: ChallengeCalendarEvent,
        session: WorkoutSession,
        events: [ChallengeCalendarEvent],
        completions: [ChallengeCompletion],
        context: ModelContext
    ) {
        guard let id = event.linkedChallengeID,
              let challenge = ((try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []).first(where: { $0.id == id && !$0.isArchived })
        else { return }
        ChallengeService.markCompletedIfNeeded(challenge: challenge, date: session.finishedAt, completions: completions, events: events, context: context)
    }

    /// Gives recent trainings that ended without any event their event, once after an update.
    ///
    /// - Parameters:
    ///   - sessions: The finished trainings.
    ///   - days: How many days back to look.
    ///   - context: The database context.
    public static func backfillMissingEvents(sessions: [WorkoutSession], days: Int = 7, context: ModelContext) async {
        let calendar = Calendar.current
        guard let since = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) else { return }
        for session in sessions where session.finishedAt >= since {
            let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
            guard !hasEvent(for: session, in: events) else { continue }
            let end = clock(session.finishedAt)
            let start = end.addingTimeInterval(-TimeInterval(duration(seconds: session.durationSeconds)))
            let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
            await createStandalone(session: session, start: start, end: end, events: events, completions: completions, context: context)
        }
        try? context.save()
    }

    /// Whether the training's day already has an event of its plan or its challenge.
    static func hasEvent(for session: WorkoutSession, in events: [ChallengeCalendarEvent]) -> Bool {
        let own = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        let challenges = Set(WorkoutLinkStore.challengeIDs(for: session.planID))
        return events.contains { event in
            !event.isReminderSuggestion && onFinishDay(event, session: session)
                && (own.contains(event.id) || event.linkedChallengeID.map(challenges.contains) == true)
        }
    }

    /// Replaces plain training events made before the series copy existed with a copy of the series.
    ///
    /// Only events Lifify made for a training (its note mark), named just after the plan and without a
    /// challenge, are replaced, and only when the plan has a series to copy now.
    ///
    /// - Parameters:
    ///   - sessions: The finished trainings.
    ///   - days: How many days back to look.
    ///   - context: The database context.
    /// - Returns: How many events were replaced.
    @discardableResult
    public static func replacePlainCopies(sessions: [WorkoutSession], days: Int = 7, context: ModelContext) async -> Int {
        let calendar = Calendar.current
        guard let since = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) else { return 0 }
        var replaced = 0
        for session in sessions where session.finishedAt >= since {
            let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
            guard seriesEvent(for: session, in: events) != nil else { continue }
            let own = Set(WorkoutLinkStore.eventIDs(for: session.planID))
            let plain = events.filter { event in
                own.contains(event.id) && onFinishDay(event, session: session) && event.details.contains(noteMarker)
                    && event.linkedChallengeID == nil && event.title == session.planName
            }
            guard !plain.isEmpty else { continue }
            for event in plain {
                if let identifier = event.externalIdentifier {
                    await EventKitSyncService.deleteCalendarEvent(externalIdentifier: identifier, occurrenceStart: event.startDate)
                }
                context.delete(event)
            }
            try? context.save()
            let remaining = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
            let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
            let end = clock(session.finishedAt)
            let start = end.addingTimeInterval(-TimeInterval(duration(seconds: session.durationSeconds)))
            await createStandalone(session: session, start: start, end: end, events: remaining, completions: completions, context: context)
            replaced += 1
        }
        try? context.save()
        return replaced
    }
}
