import Foundation
import SwiftData

/// Applies the slot length after challenges are linked or checked off.
@MainActor
enum ChallengeTimeService {
    static func resize(context: ModelContext, completions: [ChallengeCompletion]? = nil) {
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let tracked = completions ?? ((try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? [])
        var changed: [ChallengeCalendarEvent] = []
        for event in events where !event.isAllDay && !event.isReminderSuggestion {
            let ids = ChallengeTimeStore.memberIDs(for: event.id)
            guard !ids.isEmpty else { continue }
            let linked = ids.compactMap { id -> Int? in
                guard let challenge = challenges.first(where: { $0.id == id }),
                      ChallengeTimeRules.allowsTime(challenge.category)
                else { return nil }
                return ChallengeTimeStore.minutes(for: id)
            }
            let completed = ids.compactMap { id -> Int? in
                guard let challenge = challenges.first(where: { $0.id == id }),
                      ChallengeTimeRules.allowsTime(challenge.category),
                      let minutes = ChallengeTimeStore.minutes(for: id),
                      ChallengeService.isCompleted(challenge, on: event.startDate, completions: tracked)
                else { return nil }
                return minutes
            }
            let planned = ChallengeTimeStore.plannedMinutes(for: event.id)
                ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
            let shown = ChallengeTimeRules.displayedMinutes(planned: planned, linked: linked, completed: completed)
            guard shown > 0 else { continue }
            let newEnd = event.startDate.addingTimeInterval(TimeInterval(shown * 60))
            guard abs(newEnd.timeIntervalSince(event.endDate)) > 30 else { continue }
            event.endDate = newEnd
            changed.append(event)
        }
        guard !changed.isEmpty else { return }
        try? context.save()
        for event in changed {
            let title = event.title
            let notes = event.details
            let start = event.startDate
            let end = event.endDate
            let identifier = event.externalIdentifier
            Task {
                _ = await EventKitSyncService.saveCalendarEvent(
                    externalIdentifier: identifier,
                    originalStart: start,
                    title: title,
                    notes: notes,
                    start: start,
                    end: end,
                    isAllDay: false
                )
            }
        }
    }
}
