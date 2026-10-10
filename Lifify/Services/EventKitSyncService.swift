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
                    let previousRecurrence = ReminderLinkStore.metadata(for: suggestionIdentifier)
                    if let recurrence = reminder.recurrence {
                        ReminderLinkStore.set(recurrence, for: suggestionIdentifier)
                    } else if previousRecurrence?.recurrence != .irregular {
                        ReminderLinkStore.remove(for: suggestionIdentifier)
                    }
                    if let legacyChallenge = existingChallenges.first(where: {
                        $0.externalIdentifier == identifier && $0.isReadOnly
                    }) {
                        context.delete(legacyChallenge)
                    }
                    if let linkedChallenge = existingChallenges.first(where: {
                        $0.externalIdentifier == suggestionIdentifier
                    }) {
                        if let recurrence = reminder.recurrence {
                            linkedChallenge.recurrence = recurrence.recurrence
                            linkedChallenge.weekdaySet = recurrence.weekdays
                            linkedChallenge.endDate = recurrence.endDate
                        } else if previousRecurrence?.recurrence != .irregular {
                            linkedChallenge.recurrence = .none
                            linkedChallenge.weekdaySet = []
                            linkedChallenge.endDate = nil
                        }
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

    static func saveReminder(
        externalIdentifier: String?,
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date?,
        recurrence: ChallengeRecurrence,
        recurrenceInterval: Int,
        weekdays: Set<Int>
    ) async -> String? {
        do {
            let eventStore = EKEventStore()
            guard try await eventStore.requestFullAccessToReminders() else { return nil }

            let prefix = "reminder:"
            let existingIdentifier = externalIdentifier.flatMap {
                $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil
            }
            let reminder = existingIdentifier.flatMap {
                eventStore.calendarItem(withIdentifier: $0) as? EKReminder
            } ?? EKReminder(eventStore: eventStore)

            if reminder.calendar == nil {
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
            }
            guard reminder.calendar != nil else { return nil }

            reminder.title = title
            reminder.notes = notes
            var dueComponents = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: startDate
            )
            dueComponents.calendar = Calendar.current
            reminder.dueDateComponents = dueComponents

            let recurrenceEnd = endDate.map { EKRecurrenceEnd(end: $0) }
            let interval = max(recurrenceInterval, 1)
            switch recurrence {
            case .daily:
                reminder.recurrenceRules = [
                    EKRecurrenceRule(recurrenceWith: .daily, interval: interval, end: recurrenceEnd)
                ]
            case .weekly:
                let recurrenceDays = weekdays
                    .filter { (1...7).contains($0) }
                    .compactMap { EKWeekday(rawValue: $0) }
                    .map { EKRecurrenceDayOfWeek($0) }
                reminder.recurrenceRules = [
                    EKRecurrenceRule(
                        recurrenceWith: .weekly,
                        interval: interval,
                        daysOfTheWeek: recurrenceDays.isEmpty ? nil : recurrenceDays,
                        daysOfTheMonth: nil,
                        monthsOfTheYear: nil,
                        weeksOfTheYear: nil,
                        daysOfTheYear: nil,
                        setPositions: nil,
                        end: recurrenceEnd
                    )
                ]
            case .monthly:
                reminder.recurrenceRules = [
                    EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, end: recurrenceEnd)
                ]
            case .yearly:
                reminder.recurrenceRules = [
                    EKRecurrenceRule(recurrenceWith: .yearly, interval: interval, end: recurrenceEnd)
                ]
            case .none, .irregular:
                reminder.recurrenceRules = []
            }

            try eventStore.save(reminder, commit: true)
            let linkedIdentifier = "\(prefix)\(reminder.calendarItemIdentifier)"
            if recurrence == .none {
                ReminderLinkStore.remove(for: linkedIdentifier)
            } else {
                ReminderLinkStore.set(
                    ReminderRecurrenceMetadata(
                        recurrence: recurrence,
                        interval: interval,
                        weekdays: weekdays,
                        endDate: endDate
                    ),
                    for: linkedIdentifier
                )
            }
            return linkedIdentifier
        } catch {
            return nil
        }
    }

    nonisolated private static func fetchReminders() async -> [ReminderSnapshot] {
        let storeBox = EventStoreBox()
        return await withCheckedContinuation { continuation in
            storeBox.store.fetchReminders(matching: storeBox.store.predicateForReminders(in: nil)) {
                let snapshots = ($0 ?? []).compactMap { reminder -> ReminderSnapshot? in
                    guard !reminder.isCompleted else { return nil }
                    let calendar = Calendar(identifier: .gregorian)
                    let dueDate = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
                    let recurrence: ReminderRecurrenceMetadata? =
                        reminder.recurrenceRules?.first.flatMap { rule -> ReminderRecurrenceMetadata? in
                        let recurrence: ChallengeRecurrence
                        switch rule.frequency {
                        case .daily: recurrence = .daily
                        case .weekly: recurrence = .weekly
                        case .monthly: recurrence = .monthly
                        case .yearly: recurrence = .yearly
                        @unknown default: return nil
                        }
                        var weekdays = Set(
                            (rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue }
                        )
                        if recurrence == .weekly, weekdays.isEmpty, let dueDate {
                            weekdays.insert(calendar.component(.weekday, from: dueDate))
                        }
                        return ReminderRecurrenceMetadata(
                            recurrence: recurrence,
                            interval: max(rule.interval, 1),
                            weekdays: weekdays,
                            endDate: rule.recurrenceEnd?.endDate
                        )
                    }
                    return ReminderSnapshot(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Erinnerung",
                        notes: reminder.notes ?? "",
                        dueDate: dueDate,
                        recurrence: recurrence
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
    let recurrence: ReminderRecurrenceMetadata?
}
