import Foundation
import SwiftData

/// Writes a finished workout into the calendar and removes a planned sport slot once its day ended without a workout.
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
        let sportIDs = Set(challenges.filter { $0.category == .sport && !$0.isArchived }.map(\.id))
        let planChallenges = Set(WorkoutLinkStore.challengeIDs(for: session.planID)).intersection(sportIDs)
        let planEvents = Set(WorkoutLinkStore.eventIDs(for: session.planID))
        let calendar = Calendar.current
        let title = session.planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("Training", "Workout")
            : session.planName
        let notes = "\(noteMarker)\n\(title)"

        func onFinishDay(_ event: ChallengeCalendarEvent) -> Bool {
            calendar.isDate(event.startDate, inSameDayAs: session.finishedAt)
                || calendar.isDate(event.endDate, inSameDayAs: session.finishedAt)
        }

        func isSport(_ event: ChallengeCalendarEvent) -> Bool {
            if event.details.contains(noteMarker) || WorkoutLinkStore.isManaged(eventID: event.id) { return true }
            if let id = event.linkedChallengeID, sportIDs.contains(id) { return true }
            return WorkoutLinkStore.planIDs(for: event.id).contains { plan in
                !Set(WorkoutLinkStore.challengeIDs(for: plan)).isDisjoint(with: sportIDs)
            }
        }

        let linkedSport = events.filter { event in
            !event.isReminderSuggestion && onFinishDay(event) && planEvents.contains(event.id) && isSport(event)
        }
        let challengeSport = events.filter { event in
            guard !event.isReminderSuggestion, onFinishDay(event), let id = event.linkedChallengeID else { return false }
            return planChallenges.contains(id)
        }
        let chosen = linkedSport.first ?? challengeSport.first
        let challengeID = chosen?.linkedChallengeID.flatMap { sportIDs.contains($0) ? $0 : nil }
            ?? planChallenges.sorted { $0.uuidString < $1.uuidString }.first

        if let chosen {
            let identifier = await EventKitSyncService.saveCalendarEvent(
                externalIdentifier: chosen.externalIdentifier,
                originalStart: chosen.startDate,
                title: title,
                notes: notes,
                start: start,
                end: end,
                isAllDay: false
            )
            chosen.title = title
            chosen.details = notes
            chosen.startDate = start
            chosen.endDate = end
            chosen.isAllDay = false
            chosen.icon = "figure.strengthtraining.traditional"
            if chosen.linkedChallengeID == nil {
                chosen.linkedChallengeID = challengeID
            }
            if let identifier {
                chosen.externalIdentifier = identifier
            }
            WorkoutLinkStore.link(planID: session.planID, eventID: chosen.id, managed: true)
        } else {
            let identifier = await EventKitSyncService.saveCalendarEvent(
                externalIdentifier: nil,
                originalStart: nil,
                title: title,
                notes: notes,
                start: start,
                end: end,
                isAllDay: false
            )
            let event = ChallengeCalendarEvent(
                title: title,
                details: notes,
                startDate: start,
                endDate: end,
                isAllDay: false,
                colorHex: "#2F9E7A",
                icon: "figure.strengthtraining.traditional",
                linkedChallengeID: challengeID,
                externalIdentifier: identifier,
                isReadOnly: false
            )
            context.insert(event)
            WorkoutLinkStore.link(planID: session.planID, eventID: event.id, managed: true)
        }
        try? context.save()
        await cleanup(context: context, sessions: sessions)
    }

    /// After a day ends with no workout, removes the sport slot Lifify created or the one explicitly linked to a workout.
    /// Other calendar events stay, including ones that are not tied to sport.
    static func cleanup(context: ModelContext, sessions: [WorkoutSession]) async {
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let sportIDs = Set(challenges.filter { $0.category == .sport }.map(\.id))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let doomed = events.filter { event in
            guard !event.isReminderSuggestion else { return false }
            let day = calendar.startOfDay(for: event.startDate)
            guard day < today else { return false }
            guard !sessions.contains(where: { calendar.isDate($0.finishedAt, inSameDayAs: day) }) else { return false }
            if WorkoutLinkStore.isManaged(eventID: event.id) || event.details.contains(noteMarker) { return true }
            let linked = !WorkoutLinkStore.planIDs(for: event.id).isEmpty
            let sport = event.linkedChallengeID.map { sportIDs.contains($0) } ?? false
            return linked && sport
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
}
