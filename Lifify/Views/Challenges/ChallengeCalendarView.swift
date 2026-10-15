import SwiftData
import SwiftUI

struct ChallengeCalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeCalendarEvent.startDate) private var events: [ChallengeCalendarEvent]
    @Query(sort: \ChallengeItem.createdAt) private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @State private var selectedDate: Date
    @State private var mode: ChallengeCalendarViewMode
    @State private var showingNewEvent = false
    @State private var editedEvent: ChallengeCalendarEvent?

    init(initialDate: Date = .now, initialMode: ChallengeCalendarViewMode = .week) {
        _selectedDate = State(initialValue: initialDate)
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker(L("Ansicht", "View"), selection: $mode) {
                ForEach(ChallengeCalendarViewMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button(L("Heute", "Today")) { selectedDate = .now }
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(days, id: \.self) { day in
                        DayAgendaCard(
                            day: day,
                            events: eventsForDay(day),
                            challenges: challengesForDay(day),
                            completions: completions,
                            onEvent: { editedEvent = $0 },
                            onChallenge: {
                                ChallengeService.toggleCompletion(
                                    challenge: $0,
                                    date: day,
                                    completions: completions,
                                    transactions: transactions,
                                    context: context
                                )
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .appCanvas()
        .navigationTitle(L("Kalender", "Calendar"))
        .toolbar {
            Button { showingNewEvent = true } label: {
                Label(L("Termin hinzufügen", "Add event"), systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewEvent) {
            ChallengeEventForm(event: nil, initialDate: selectedDate)
        }
        .sheet(item: $editedEvent) {
            ChallengeEventForm(event: $0, initialDate: $0.startDate)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width < -60 { move(1) }
                if value.translation.width > 60 { move(-1) }
            }
        )
    }

    private var days: [Date] {
        ChallengeService.days(for: mode, around: selectedDate)
    }

    private func eventsForDay(_ day: Date) -> [ChallengeCalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events.filter {
            !$0.isReminderSuggestion && $0.startDate < end && $0.endDate >= start
        }
    }

    private func challengesForDay(_ day: Date) -> [ChallengeItem] {
        challenges.filter { ChallengeService.isDue($0, on: day) }
    }

    private func move(_ value: Int) {
        let component: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        if let date = Calendar.current.date(byAdding: component, value: value, to: selectedDate) {
            withAnimation { selectedDate = date }
        }
    }
}

private struct DayAgendaCard: View {
    let day: Date
    let events: [ChallengeCalendarEvent]
    let challenges: [ChallengeItem]
    let completions: [ChallengeCompletion]
    let onEvent: (ChallengeCalendarEvent) -> Void
    let onChallenge: (ChallengeItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppDate.weekdayAndNumeric(day))
                    .font(.headline)
                Spacer()
                if Calendar.current.isDateInToday(day) {
                    Text(L("Heute", "Today")).font(.caption).foregroundStyle(.blue)
                }
            }
            if events.isEmpty && challenges.isEmpty {
                Text(L("Keine Einträge", "No entries")).font(.caption).foregroundStyle(.secondary)
            }
            if !events.isEmpty || !challenges.isEmpty {
                Text(L("Termine", "Events"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            if events.isEmpty && !challenges.isEmpty {
                Text(L("Keine Termine", "No events")).font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(events) { event in
                Button { onEvent(event) } label: {
                    HStack {
                        Image(systemName: event.icon)
                        VStack(alignment: .leading) {
                            Text(event.title)
                            if !event.isAllDay {
                                Text(AppDate.time(event.startDate))
                                    .font(.caption)
                            }
                            if event.linkedChallengeID != nil || event.linkedChallengeGroupID != nil {
                                Label(L("Mit Challenge verknüpft", "Linked to challenge"), systemImage: "target")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if event.linkedRewardID != nil {
                                Label(L("Mit Belohnung verknüpft", "Linked to reward"), systemImage: "gift")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.plain)
            }
            if !events.isEmpty || !challenges.isEmpty {
                Text(L("Challenges", "Challenges"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            if challenges.isEmpty && !events.isEmpty {
                Text(L("Keine Challenges", "No challenges")).font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(challenges) { challenge in
                let completed = ChallengeService.isCompleted(challenge, on: day, completions: completions)
                Button { onChallenge(challenge) } label: {
                    HStack {
                        Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        Text(challenge.title)
                        Spacer()
                        CoinAmountView(amount: challenge.rewardCoins, showsPlus: true)
                            .font(.caption)
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(completed ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(challenge.isReadOnly)
            }
        }
        .padding()
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ChallengeEventForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeItem.title) private var challenges: [ChallengeItem]
    @Query(sort: \ChallengeGroup.title) private var groups: [ChallengeGroup]
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    private let existing: ChallengeCalendarEvent?
    @State private var savedEvent: ChallengeCalendarEvent?
    @State private var title: String
    @State private var details: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var linkedChallengeID: UUID?
    @State private var linkedGroupID: UUID?
    @State private var linkedRewardID: UUID?
    @State private var adoptedChallengeID: UUID?
    @State private var isSaving = false
    @State private var statusMessage: String?

    @MainActor
    init(event: ChallengeCalendarEvent?, initialDate: Date) {
        existing = event
        _title = State(initialValue: event?.title ?? "")
        _details = State(initialValue: event?.details ?? "")
        _start = State(initialValue: event?.startDate ?? initialDate)
        _end = State(initialValue: event?.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: initialDate)!)
        _allDay = State(initialValue: event?.isAllDay ?? false)
        _linkedChallengeID = State(initialValue: event?.linkedChallengeID)
        _linkedGroupID = State(initialValue: event?.linkedChallengeGroupID)
        _linkedRewardID = State(initialValue: event?.linkedRewardID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(L(
                    "Änderungen und neue Termine werden in den Systemkalender geschrieben.",
                    "Changes and new events are written to the system calendar."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                Toggle(L("Ganztägig", "All day"), isOn: $allDay)
                AppDateField(title: L("Beginn", "Start"), selection: $start, includesTime: !allDay)
                AppDateField(title: L("Ende", "End"), selection: $end, minimum: start, includesTime: !allDay)
                optionalPicker(L("Challenge", "Challenge"), selection: $linkedChallengeID, values: challenges.map { ($0.id, $0.title) })
                optionalPicker(L("Gruppe", "Group"), selection: $linkedGroupID, values: groups.map { ($0.id, $0.title) })
                optionalPicker(L("Belohnung", "Reward"), selection: $linkedRewardID, values: rewards.map { ($0.id, $0.title) })
                Button(L("Als Challenge übernehmen", "Adopt as challenge")) {
                    Task { await adoptAsChallenge() }
                }
                .disabled(title.isEmpty || isSaving)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if existing != nil || savedEvent != nil {
                    Button(L("Termin löschen", "Delete event"), role: .destructive) {
                        Task { await deleteEvent() }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle(L("Termin", "Event"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Schließen", "Close")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndClose() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(L("Speichern", "Save"))
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func optionalPicker(_ title: String, selection: Binding<UUID?>, values: [(UUID, String)]) -> some View {
        Picker(title, selection: selection) {
            Text(L("Keine", "None")).tag(Optional<UUID>.none)
            ForEach(values, id: \.0) { Text($0.1).tag(Optional($0.0)) }
        }
    }

    @MainActor
    private func saveAndClose() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard await writeEvent() != nil else { return }
        if statusMessage == nil { dismiss() }
    }

    @MainActor
    private func writeEvent() async -> ChallengeCalendarEvent? {
        guard !title.isEmpty else { return nil }
        let current = existing ?? savedEvent
        let identifier = await EventKitSyncService.saveCalendarEvent(
            externalIdentifier: current?.externalIdentifier,
            originalStart: current?.startDate,
            title: title,
            notes: details,
            start: start,
            end: end > start ? end : start.addingTimeInterval(allDay ? 86_400 : 3_600),
            isAllDay: allDay
        )
        let event = current ?? ChallengeCalendarEvent(title: title, startDate: start, endDate: end)
        event.title = title
        event.details = details
        event.startDate = start
        event.endDate = end > start ? end : start.addingTimeInterval(allDay ? 86_400 : 3_600)
        event.isAllDay = allDay
        event.linkedChallengeID = linkedChallengeID
        event.linkedChallengeGroupID = linkedGroupID
        event.linkedRewardID = linkedRewardID
        if let identifier {
            event.externalIdentifier = identifier
            statusMessage = nil
        } else {
            statusMessage = L(
                "Lokal gespeichert. Der Systemkalender konnte nicht aktualisiert werden.",
                "Saved locally. The system calendar could not be updated."
            )
        }
        if event.modelContext == nil { context.insert(event) }
        savedEvent = event
        try? context.save()
        return event
    }

    @MainActor
    private func adoptAsChallenge() async {
        guard !title.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let event = await writeEvent() else { return }
        let metadata: ReminderRecurrenceMetadata?
        if let identifier = event.externalIdentifier {
            metadata = await EventKitSyncService.loadRecurrence(
                externalIdentifier: identifier,
                occurrenceStart: event.startDate
            )
        } else {
            metadata = nil
        }
        let challengeKey = event.externalIdentifier.map { "event-challenge:\($0)" }
        let challenge = adoptedChallengeID.flatMap { id in challenges.first { $0.id == id } }
            ?? challenges.first { challengeKey != nil && $0.externalIdentifier == challengeKey }
            ?? ChallengeItem(
                title: title,
                details: details,
                category: .habit,
                recurrence: metadata?.recurrence ?? .none,
                startDate: start,
                endDate: metadata?.endDate,
                weeklyDays: metadata?.weekdays ?? [],
                externalIdentifier: challengeKey
            )
        challenge.title = title
        challenge.details = details
        challenge.recurrence = metadata?.recurrence ?? .none
        challenge.startDate = start
        challenge.endDate = metadata?.endDate
        challenge.weekdaySet = metadata?.weekdays ?? []
        challenge.isReadOnly = false
        adoptedChallengeID = challenge.id
        if challenge.modelContext == nil { context.insert(challenge) }
        if let challengeKey {
            challenge.externalIdentifier = challengeKey
            if let metadata {
                ReminderLinkStore.set(metadata, for: challengeKey)
            } else {
                ReminderLinkStore.remove(for: challengeKey)
            }
        }
        ReminderSyncPreference.set(false, for: challenge.id)
        IconPreferenceStore.set("target", for: challenge.id)
        linkedChallengeID = challenge.id
        event.linkedChallengeID = challenge.id
        if let identifier = event.externalIdentifier,
           let siblings = try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>()) {
            for sibling in siblings where sibling.externalIdentifier == identifier {
                sibling.linkedChallengeID = challenge.id
            }
        }
        try? context.save()
        if event.externalIdentifier == nil {
            statusMessage = L(
                "Challenge lokal angelegt. Der Systemkalender konnte nicht aktualisiert werden.",
                "Challenge saved locally. The system calendar could not be updated."
            )
        } else if metadata == nil {
            statusMessage = L("Challenge angelegt.", "Challenge created.")
        } else {
            statusMessage = L("Wiederkehrende Challenge angelegt.", "Recurring challenge created.")
        }
    }

    @MainActor
    private func deleteEvent() async {
        guard !isSaving, let event = existing ?? savedEvent else { return }
        isSaving = true
        if let identifier = event.externalIdentifier, !identifier.hasPrefix("reminder:") {
            await EventKitSyncService.deleteCalendarEvent(
                externalIdentifier: identifier,
                occurrenceStart: event.startDate
            )
        }
        context.delete(event)
        try? context.save()
        dismiss()
    }
}
