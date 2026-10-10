import Combine
import EventKit
import Foundation
import SwiftData

@MainActor
final class EventKitSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var message: String?
    private let store = EKEventStore()

    func sync(
        context: ModelContext,
        existingEvents: [LifeCalendarEvent],
        existingChallenges: [LifeChallenge]
    ) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let eventsAllowed = try await store.requestFullAccessToEvents()
            let remindersAllowed = try await store.requestFullAccessToReminders()
            var importedEvents = 0
            var importedReminders = 0

            if eventsAllowed {
                let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
                let end = Calendar.current.date(byAdding: .day, value: 365, to: .now)!
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                for event in store.events(matching: predicate) {
                    guard let identifier = event.eventIdentifier else { continue }
                    let model = existingEvents.first { $0.externalIdentifier == identifier } ??
                        LifeCalendarEvent(
                            title: event.title ?? L("Kalenderereignis", "Calendar event"),
                            startDate: event.startDate,
                            endDate: event.endDate,
                            externalIdentifier: identifier,
                            isReadOnly: true
                        )
                    model.title = event.title ?? model.title
                    model.details = event.notes ?? ""
                    model.startDate = event.startDate
                    model.endDate = event.endDate
                    model.isAllDay = event.isAllDay
                    if model.modelContext == nil { context.insert(model) }
                    importedEvents += 1
                }
            }

            if remindersAllowed {
                let reminders = await fetchReminders()
                for reminder in reminders where !reminder.isCompleted {
                    guard let identifier = reminder.calendarItemIdentifier else { continue }
                    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    let challenge = existingChallenges.first { $0.externalIdentifier == identifier } ??
                        LifeChallenge(
                            title: reminder.title,
                            category: .todo,
                            recurrence: .none,
                            startDate: dueDate,
                            externalIdentifier: identifier,
                            isReadOnly: true
                        )
                    challenge.title = reminder.title
                    challenge.details = reminder.notes ?? ""
                    challenge.startDate = dueDate
                    if challenge.modelContext == nil { context.insert(challenge) }
                    importedReminders += 1
                }
            }
            try context.save()
            message = String(
                format: L("%d Termine und %d Erinnerungen synchronisiert.", "%d events and %d reminders synced."),
                importedEvents,
                importedReminders
            )
        } catch {
            message = error.localizedDescription
        }
    }

    private func fetchReminders() async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) {
                continuation.resume(returning: $0 ?? [])
            }
        }
    }
}
