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
                let activeSuggestionIDs = Set(reminders.map { "reminder:\($0.identifier)" })
                existingEvents
                    .filter { $0.isReminderSuggestion && !activeSuggestionIDs.contains($0.externalIdentifier ?? "") }
                    .forEach(context.delete)
                for reminder in reminders {
                    let identifier = reminder.identifier
                    guard !identifier.isEmpty else { continue }
                    let suggestionIdentifier = "reminder:\(identifier)"
                    if let legacyChallenge = existingChallenges.first(where: {
                        $0.externalIdentifier == identifier && $0.isReadOnly
                    }) {
                        context.delete(legacyChallenge)
                    }
                    guard !existingChallenges.contains(where: { $0.externalIdentifier == suggestionIdentifier }) else {
                        continue
                    }
                    let dueDate = reminder.dueDate ?? .now
                    let suggestion = existingEvents.first { $0.externalIdentifier == suggestionIdentifier } ??
                        ChallengeCalendarEvent(
                            title: reminder.title,
                            startDate: dueDate,
                            endDate: Calendar.current.date(byAdding: .hour, value: 1, to: dueDate) ?? dueDate,
                            icon: "lightbulb",
                            externalIdentifier: suggestionIdentifier,
                            isReadOnly: true
                        )
                    suggestion.title = reminder.title
                    suggestion.details = reminder.notes
                    suggestion.startDate = dueDate
                    suggestion.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: dueDate) ?? dueDate
                    if suggestion.modelContext == nil { context.insert(suggestion) }
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

    static func setReminderCompletion(
        externalIdentifier: String,
        isCompleted: Bool
    ) async {
        let prefix = "reminder:"
        guard externalIdentifier.hasPrefix(prefix) else { return }
        let identifier = String(externalIdentifier.dropFirst(prefix.count))
        guard !identifier.isEmpty else { return }

        do {
            let eventStore = EKEventStore()
            guard try await eventStore.requestFullAccessToReminders(),
                  let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
            else {
                return
            }
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? .now : nil
            try eventStore.save(reminder, commit: true)
        } catch {
            // Local completion remains authoritative when EventKit cannot be updated.
        }
    }

    nonisolated private static func fetchReminders() async -> [ReminderSnapshot] {
        let storeBox = EventStoreBox()
        return await withCheckedContinuation { continuation in
            storeBox.store.fetchReminders(matching: storeBox.store.predicateForReminders(in: nil)) {
                let snapshots = ($0 ?? []).compactMap { reminder -> ReminderSnapshot? in
                    guard !reminder.isCompleted else { return nil }
                    let calendar = Calendar(identifier: .gregorian)
                    return ReminderSnapshot(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Erinnerung",
                        notes: reminder.notes ?? "",
                        dueDate: reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
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
