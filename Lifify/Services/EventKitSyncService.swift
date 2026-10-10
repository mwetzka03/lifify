import Combine
@preconcurrency import EventKit
import Foundation
import SwiftData

@MainActor
final class EventKitSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var message: String?
    private let store = EKEventStore()

    func sync(
        context: ModelContext,
        existingEvents: [ChallengeCalendarEvent],
        existingChallenges: [ChallengeItem]
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
                        ChallengeCalendarEvent(
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
                let reminders = await Self.fetchReminders()
                for reminder in reminders {
                    let identifier = reminder.identifier
                    guard !identifier.isEmpty else { continue }
                    let challenge = existingChallenges.first { $0.externalIdentifier == identifier } ??
                        ChallengeItem(
                            title: reminder.title,
                            category: .todo,
                            recurrence: .none,
                            startDate: reminder.dueDate,
                            externalIdentifier: identifier,
                            isReadOnly: true
                        )
                    challenge.title = reminder.title
                    challenge.details = reminder.notes
                    challenge.startDate = reminder.dueDate
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

    nonisolated private static func fetchReminders() async -> [ReminderSnapshot] {
        let storeBox = EventStoreBox()
        await withCheckedContinuation { continuation in
            storeBox.store.fetchReminders(matching: storeBox.store.predicateForReminders(in: nil)) {
                let snapshots = ($0 ?? []).compactMap { reminder -> ReminderSnapshot? in
                    guard !reminder.isCompleted else { return nil }
                    return ReminderSnapshot(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Erinnerung",
                        notes: reminder.notes ?? "",
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }
}

private final class EventStoreBox: @unchecked Sendable {
    let store = EKEventStore()
}

private struct ReminderSnapshot: Sendable {
    let identifier: String
    let title: String
    let notes: String
    let dueDate: Date?
}
