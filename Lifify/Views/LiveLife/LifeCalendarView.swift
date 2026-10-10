import SwiftData
import SwiftUI

struct LifeCalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LifeCalendarEvent.startDate) private var events: [LifeCalendarEvent]
    @Query(sort: \LifeChallenge.createdAt) private var challenges: [LifeChallenge]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @State private var selectedDate: Date
    @State private var mode: LifeCalendarViewMode
    @State private var showingNewEvent = false
    @State private var editedEvent: LifeCalendarEvent?

    init(initialDate: Date = .now, initialMode: LifeCalendarViewMode = .week) {
        _selectedDate = State(initialValue: initialDate)
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker(L("Ansicht", "View"), selection: $mode) {
                ForEach(LifeCalendarViewMode.allCases) { Text($0.label).tag($0) }
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
                                LiveLifeService.toggleCompletion(
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
        .navigationTitle(L("Kalender", "Calendar"))
        .toolbar {
            Button { showingNewEvent = true } label: {
                Label(L("Termin hinzufügen", "Add event"), systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewEvent) {
            LifeEventForm(event: nil, initialDate: selectedDate)
        }
        .sheet(item: $editedEvent) {
            LifeEventForm(event: $0, initialDate: $0.startDate)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width < -60 { move(1) }
                if value.translation.width > 60 { move(-1) }
            }
        )
    }

    private var days: [Date] {
        LiveLifeService.days(for: mode, around: selectedDate)
    }

    private func eventsForDay(_ day: Date) -> [LifeCalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.startDate < end && $0.endDate >= start }
    }

    private func challengesForDay(_ day: Date) -> [LifeChallenge] {
        challenges.filter { LiveLifeService.isDue($0, on: day) }
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
    let events: [LifeCalendarEvent]
    let challenges: [LifeChallenge]
    let completions: [ChallengeCompletion]
    let onEvent: (LifeCalendarEvent) -> Void
    let onChallenge: (LifeChallenge) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(day, format: .dateTime.weekday(.wide).day().month())
                    .font(.headline)
                Spacer()
                if Calendar.current.isDateInToday(day) {
                    Text(L("Heute", "Today")).font(.caption).foregroundStyle(.blue)
                }
            }
            if events.isEmpty && challenges.isEmpty {
                Text(L("Keine Einträge", "No entries")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                Button { onEvent(event) } label: {
                    HStack {
                        Image(systemName: event.icon)
                        VStack(alignment: .leading) {
                            Text(event.title)
                            if !event.isAllDay {
                                Text(event.startDate, format: .dateTime.hour().minute())
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
            ForEach(challenges) { challenge in
                let completed = LiveLifeService.isCompleted(challenge, on: day, completions: completions)
                Button { onChallenge(challenge) } label: {
                    HStack {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(completed ? .green : .secondary)
                        Text(challenge.title)
                        Spacer()
                        Text("+\(challenge.rewardCoins)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .disabled(challenge.isReadOnly)
            }
        }
        .padding()
        .background(Calendar.current.isDateInToday(day) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LifeEventForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LifeChallenge.title) private var challenges: [LifeChallenge]
    @Query(sort: \LifeChallengeGroup.title) private var groups: [LifeChallengeGroup]
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    private let existing: LifeCalendarEvent?
    @State private var title: String
    @State private var details: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var linkedChallengeID: UUID?
    @State private var linkedGroupID: UUID?
    @State private var linkedRewardID: UUID?

    init(event: LifeCalendarEvent?, initialDate: Date) {
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
                if existing?.isReadOnly == true {
                    Text(L("Dieser Termin stammt aus dem Systemkalender.", "This event comes from the system calendar."))
                        .foregroundStyle(.secondary)
                }
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                Toggle(L("Ganztägig", "All day"), isOn: $allDay)
                DatePicker(L("Beginn", "Start"), selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker(L("Ende", "End"), selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                optionalPicker(L("Challenge", "Challenge"), selection: $linkedChallengeID, values: challenges.map { ($0.id, $0.title) })
                optionalPicker(L("Gruppe", "Group"), selection: $linkedGroupID, values: groups.map { ($0.id, $0.title) })
                optionalPicker(L("Belohnung", "Reward"), selection: $linkedRewardID, values: rewards.map { ($0.id, $0.title) })
                if let existing, !existing.isReadOnly {
                    Button(L("Termin löschen", "Delete event"), role: .destructive) {
                        context.delete(existing)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .disabled(existing?.isReadOnly == true)
            .navigationTitle(L("Termin", "Event"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Schließen", "Close")) { dismiss() } }
                if existing?.isReadOnly != true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Speichern", "Save")) {
                            guard !title.isEmpty else { return }
                            let event = existing ?? LifeCalendarEvent(title: title, startDate: start, endDate: end)
                            event.title = title
                            event.details = details
                            event.startDate = start
                            event.endDate = end
                            event.isAllDay = allDay
                            event.linkedChallengeID = linkedChallengeID
                            event.linkedChallengeGroupID = linkedGroupID
                            event.linkedRewardID = linkedRewardID
                            if existing == nil { context.insert(event) }
                            try? context.save()
                            dismiss()
                        }
                    }
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
}
