import Foundation
import SwiftData

/// Replaces a calendar event once every one-time challenge on it is checked off.
@MainActor
enum ChallengeTimeService {
    static func resize(context: ModelContext, completions: [ChallengeCompletion]? = nil) {
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let tracked = completions ?? ((try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? [])
        var changed: [(event: ChallengeCalendarEvent, oldIdentifier: String?, oldStart: Date)] = []
        for event in events where !event.isAllDay && !event.isReminderSuggestion {
            let members = ChallengeTimeStore.memberIDs(for: event.id)
            let oneTime = members.filter { id in
                challenges.first { $0.id == id }.map { EventRewrite.acceptsSharedEvent($0.recurrence) } ?? false
            }
            let done = Set(tracked.compactMap { completion -> UUID? in
                oneTime.contains(completion.challengeID) ? completion.challengeID : nil
            })
            guard EventRewrite.ready(memberIDs: oneTime, completedIDs: done) else { continue }
            let stamps = oneTime.compactMap { id in
                tracked.filter { $0.challengeID == id }.map(\.date).max()
            }
            let durations = oneTime.map { id in
                ChallengeTimeStore.actualMinutes(for: id) ?? 0
            }
            guard let window = EventRewrite.window(checkedOffAt: stamps, durations: durations) else { continue }
            let sameStart = abs(window.start.timeIntervalSince(event.startDate)) <= 30
            let sameEnd = abs(window.end.timeIntervalSince(event.endDate)) <= 30
            guard !sameStart || !sameEnd else { continue }
            let oldIdentifier = event.externalIdentifier
            let oldStart = event.startDate
            event.startDate = window.start
            event.endDate = window.end
            event.externalIdentifier = nil
            changed.append((event, oldIdentifier, oldStart))
        }
        guard !changed.isEmpty else { return }
        try? context.save()
        for change in changed {
            let title = change.event.title
            let notes = change.event.details
            let start = change.event.startDate
            let end = change.event.endDate
            let event = change.event
            let oldIdentifier = change.oldIdentifier
            let oldStart = change.oldStart
            Task { @MainActor in
                if let oldIdentifier {
                    await EventKitSyncService.deleteCalendarEvent(
                        externalIdentifier: oldIdentifier,
                        occurrenceStart: oldStart
                    )
                }
                if let identifier = await EventKitSyncService.saveCalendarEvent(
                    externalIdentifier: nil,
                    originalStart: nil,
                    title: title,
                    notes: notes,
                    start: start,
                    end: end,
                    isAllDay: false
                ) {
                    event.externalIdentifier = identifier
                    try? context.save()
                }
            }
        }
    }
}
