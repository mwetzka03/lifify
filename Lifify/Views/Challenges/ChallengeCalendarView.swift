import SwiftData
import SwiftUI

struct ChallengeCalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeCalendarEvent.startDate) private var events: [ChallengeCalendarEvent]
    @Query(sort: \ChallengeItem.createdAt) private var challenges: [ChallengeItem]
    @Query(sort: \ChallengeGroup.title) private var groups: [ChallengeGroup]
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @State private var selectedDate: Date
    @State private var mode: ChallengeCalendarViewMode
    @State private var showingNewEvent = false
    @State private var editedEvent: ChallengeCalendarEvent?
    @State private var pendingDuration: PendingDuration?

    init(initialDate: Date = AppClock.now, initialMode: ChallengeCalendarViewMode = .week) {
        _selectedDate = State(initialValue: initialDate)
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        let _ = developerMode
        let _ = developerDay
        let _ = mode
        let today = Calendar.current.startOfDay(for: AppClock.now)
        let agenda = AgendaScroll.days(around: today)
        return VStack(spacing: 10) {
            HStack {
                Text(L("Heute steht oben. Weiter oben liegt die Vergangenheit, darunter die Zukunft.", "Today sits at the top. The past is further up, and the future is below."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Heute", "Today")) {
                    selectedDate = today
                }
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(agenda, id: \.timeIntervalSinceReferenceDate) { day in
                            DayAgendaCard(
                                day: day,
                                events: eventsForDay(day),
                                scheduleEvents: events,
                                challenges: challengesForDay(day),
                                allChallenges: challenges,
                                groups: groups,
                                rewards: rewards,
                                completions: completions,
                                onEvent: { editedEvent = $0 },
                                onChallenge: { finish($0, on: day) }
                            )
                            .id(day.timeIntervalSinceReferenceDate)
                            .opacity(day < today ? 0.72 : 1)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    let identifier = today.timeIntervalSinceReferenceDate
                    Task { @MainActor in
                        proxy.scrollTo(identifier, anchor: .top)
                    }
                }
                .onChange(of: selectedDate) {
                    let start = Calendar.current.startOfDay(for: selectedDate)
                    proxy.scrollTo(start.timeIntervalSinceReferenceDate, anchor: .top)
                }
            }
        }
        .appGlassCanvas()
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
        .sheet(item: $pendingDuration) { pending in
            ActualDurationSheet(suggested: pending.suggested) { minutes in
                ChallengeFinish.commit(
                    challenge: pending.challenge,
                    date: pending.date,
                    actualMinutes: minutes,
                    completions: completions,
                    transactions: transactions,
                    events: events,
                    context: context
                )
                pendingDuration = nil
            } onCancel: {
                pendingDuration = nil
            }
        }
        .onChange(of: developerDay) {
            if developerMode { selectedDate = AppClock.now }
        }
        .onChange(of: developerMode) {
            selectedDate = AppClock.now
        }
    }

    private func finish(_ challenge: ChallengeItem, on date: Date) {
        if let minutes = ChallengeFinish.suggestedMinutes(
            challenge: challenge,
            on: date,
            completions: completions,
            events: events
        ) {
            pendingDuration = PendingDuration(challenge: challenge, date: date, suggested: minutes)
            return
        }
        ChallengeFinish.commit(
            challenge: challenge,
            date: date,
            actualMinutes: nil,
            completions: completions,
            transactions: transactions,
            events: events,
            context: context
        )
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
}

private struct DayAgendaCard: View {
    let day: Date
    let events: [ChallengeCalendarEvent]
    let scheduleEvents: [ChallengeCalendarEvent]
    let challenges: [ChallengeItem]
    let allChallenges: [ChallengeItem]
    let groups: [ChallengeGroup]
    let rewards: [RewardItem]
    let completions: [ChallengeCompletion]
    let onEvent: (ChallengeCalendarEvent) -> Void
    let onChallenge: (ChallengeItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppDate.weekdayAndNumeric(day))
                    .font(.headline)
                Spacer()
                if AppClock.isToday(day) {
                    Text(L("Heute", "Today")).font(.caption).appAccentForeground()
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
                        AppSymbolImage(name: event.icon)
                        VStack(alignment: .leading) {
                            Text(event.title)
                            if !event.isAllDay {
                                Text(AppDate.time(event.startDate))
                                    .font(.caption)
                            }
                            if let caption = eventLinkCaption(event) {
                                Label(caption.text, systemImage: caption.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(caption.color)
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
                        AppSymbolImage(name: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title)
                            if let caption = challengeCalendarCaption(challenge) {
                                Text(caption)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        CoinAmountView(
                            amount: ChallengeService.projectedCoins(
                                challenge: challenge,
                                on: day,
                                completions: completions,
                                events: scheduleEvents
                            ),
                            showsPlus: true
                        )
                        .font(.caption)
                        if StreakSettings.isEnabled(for: challenge.id) {
                            let streak = ChallengeService.status(
                                for: challenge,
                                endingOn: day,
                                completions: completions,
                                events: scheduleEvents
                            ).count
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                Text("\(streak)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                        let followsNutrition = ChallengeCheckoff.followsNutrition(challenge.externalIdentifier)
                        let allowsHand = ChallengeCheckoff.allowsHand(
                            category: challenge.category,
                            linkedWorkouts: WorkoutLinkStore.planIDs(forChallenge: challenge.id).count,
                            followsNutrition: followsNutrition
                        )
                        if ChallengeBoard.showsCheckCircle(allowsHand: allowsHand) {
                            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(completed ? .green : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(challenge.isReadOnly)
            }
        }
        .padding()
        .appGlassCard(radius: 16)
    }

    private func eventLinkCaption(_ event: ChallengeCalendarEvent) -> EventLinkCaption? {
        let memberTitles = ChallengeTimeStore.memberIDs(for: event.id).compactMap { id in
            allChallenges.first(where: { $0.id == id })?.title
        }
        let sportTitle = event.linkedChallengeID.flatMap { id in
            allChallenges.first(where: { $0.id == id })?.title
        }
        if let text = LinkCaption.challenges(memberTitles, fallback: sportTitle) {
            return EventLinkCaption(text: text, symbol: "target", color: .green)
        }
        if let id = event.linkedChallengeGroupID, let title = groups.first(where: { $0.id == id })?.title {
            return EventLinkCaption(text: LinkCaption.group(title), symbol: "target", color: .green)
        }
        if let id = event.linkedRewardID, let title = rewards.first(where: { $0.id == id })?.title {
            return EventLinkCaption(text: LinkCaption.reward(title), symbol: "gift", color: .orange)
        }
        return nil
    }

    private func challengeCalendarCaption(_ challenge: ChallengeItem) -> String? {
        let linked = ChallengeTimeStore.linkedEvents(for: challenge.id, in: scheduleEvents)
        return LinkCaption.calendar(
            titles: linked.map(\.title),
            count: linked.count,
            singleDate: linked.count == 1 ? linked.first?.startDate : nil
        )
    }
}

private struct EventLinkCaption {
    var text: String
    var symbol: String
    var color: Color
}

private struct ChallengeEventForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeItem.title) private var challenges: [ChallengeItem]
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    private let existing: ChallengeCalendarEvent?
    @State private var savedEvent: ChallengeCalendarEvent?
    @State private var title: String
    @State private var details: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var linkedChallengeID: UUID?
    @State private var memberIDs: [UUID]
    @State private var linkedGroupID: UUID?
    @State private var linkedRewardID: UUID?
    @State private var adoptedChallengeID: UUID?
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var showsMoreSettings: Bool

    @MainActor
    init(event: ChallengeCalendarEvent?, initialDate: Date) {
        existing = event
        _title = State(initialValue: event?.title ?? "")
        _details = State(initialValue: event?.details ?? "")
        let initialStart = event?.startDate ?? initialDate
        let plannedMinutes = event.flatMap { ChallengeTimeStore.plannedMinutes(for: $0.id) }
        let initialEnd: Date
        if let event, let plannedMinutes, plannedMinutes > 0, !event.isAllDay {
            initialEnd = event.startDate.addingTimeInterval(TimeInterval(plannedMinutes * 60))
        } else {
            initialEnd = event?.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: initialDate)!
        }
        _start = State(initialValue: initialStart)
        _end = State(initialValue: initialEnd)
        _allDay = State(initialValue: event?.isAllDay ?? false)
        let storedMembers = event.map { ChallengeTimeStore.memberIDs(for: $0.id) } ?? []
        _linkedChallengeID = State(initialValue: event?.linkedChallengeID)
        _memberIDs = State(initialValue: storedMembers)
        _linkedGroupID = State(initialValue: event?.linkedChallengeGroupID)
        _linkedRewardID = State(initialValue: event?.linkedRewardID)
        _showsMoreSettings = State(initialValue: !EditorCopy.moreStartsClosed)
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
                Section {
                    MoreSettingsToggle(isExpanded: $showsMoreSettings)
                    if showsMoreSettings {
                    Text(L("Vorhandene Challenges", "Existing challenges"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    optionalPicker(
                        L("Sport-Challenge", "Sport challenge"),
                        selection: $linkedChallengeID,
                        values: challenges.filter { $0.category == .sport && !$0.isArchived }.map { ($0.id, $0.title) }
                    )
                    EventChallengeTimeSection(
                        memberIDs: $memberIDs,
                        slotMinutes: max(ChallengeTimeRules.minutes(from: start, to: end), 1),
                        challenges: challenges
                    )
                    Text(L("Neue Challenge", "New challenge"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    Button(L("Als neue Challenge anlegen", "Create as a new challenge")) {
                        Task { await adoptAsChallenge() }
                    }
                    .disabled(title.isEmpty || isSaving)
                    Text(L(
                        "Das legt eine Challenge aus diesem Termin an. Eine Wiederholung verknüpft die Serie.",
                        "This creates a challenge from this event. A repeat links the series."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    optionalPicker(L("Belohnung", "Reward"), selection: $linkedRewardID, values: rewards.map { ($0.id, $0.title) })
                    }
                }
                .appGlassRow()
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
            .appGlassList()
            .navigationTitle(existing == nil ? L("Neuer Termin", "New event") : L("Termin", "Event"))
            .onAppear {
                guard let linked = linkedChallengeID,
                      let challenge = challenges.first(where: { $0.id == linked }),
                      ChallengeTimeRules.allowsTime(challenge.category),
                      !memberIDs.contains(linked)
                else { return }
                memberIDs.append(linked)
                linkedChallengeID = nil
            }
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
        let previousStart = event.startDate
        let previousEnd = event.endDate
        event.title = title
        event.details = details
        event.startDate = start
        event.endDate = end > start ? end : start.addingTimeInterval(allDay ? 86_400 : 3_600)
        event.isAllDay = allDay
        let previousCategory = challenges.first { $0.id == event.linkedChallengeID }?.category
        if linkedChallengeID != nil || previousCategory != .abstinence {
            event.linkedChallengeID = linkedChallengeID
        }
        if event.modelContext == nil { context.insert(event) }
        let slot = ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
        let storedPlan = ChallengeTimeStore.plannedMinutes(for: event.id)
        let plannedEnd = storedPlan.map { previousStart.addingTimeInterval(TimeInterval($0 * 60)) } ?? previousEnd
        let timesChanged = abs(plannedEnd.timeIntervalSince(event.endDate)) > 60
            || abs(previousStart.timeIntervalSince(event.startDate)) > 60
        if storedPlan == nil || timesChanged {
            ChallengeTimeStore.setPlannedMinutes(max(slot, 1), for: event.id)
        }
        let timedMembers = memberIDs.filter { id in
            guard let category = challenges.first(where: { $0.id == id })?.category else { return false }
            return ChallengeTimeRules.allowsTime(category)
        }
        ChallengeTimeStore.setMembers(allDay ? [] : timedMembers, for: event.id)
        let assigned = assignedChallengeIDs(timed: timedMembers)
        if assigned.count >= 2 {
            event.linkedChallengeGroupID = syncEventGroup(event: event, challengeIDs: assigned)
        } else {
            event.linkedChallengeGroupID = linkedGroupID
        }
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
        ChallengeTimeService.resize(context: context)
        syncWorkoutLinks()
        return event
    }

    private func assignedChallengeIDs(timed: [UUID]) -> [UUID] {
        var ids = timed
        if let linkedChallengeID, !ids.contains(linkedChallengeID) {
            ids.append(linkedChallengeID)
        }
        return ids
    }

    private func syncEventGroup(event: ChallengeCalendarEvent, challengeIDs: [UUID]) -> UUID {
        let name = EventGroupName.title(event: event.title, day: AppDate.numeric(event.startDate))
        let stored = (try? context.fetch(FetchDescriptor<ChallengeGroup>())) ?? []
        let group = stored.first { $0.id == event.linkedChallengeGroupID }
            ?? stored.first { $0.title == name }
            ?? ChallengeGroup(title: name, startDate: event.startDate)
        group.title = name
        group.startDate = event.startDate
        if group.modelContext == nil { context.insert(group) }
        let people = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        for challenge in people where challengeIDs.contains(challenge.id) {
            challenge.groupID = group.id
        }
        return group.id
    }

    private func syncWorkoutLinks() {
        let stored = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        WorkoutLinkStore.reconcile(calendar: stored.filter { !$0.isReminderSuggestion }.map {
            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
        })
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
                category: .other,
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
        syncWorkoutLinks()
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
        ChallengeTimeStore.removeEvent(event.id)
        context.delete(event)
        try? context.save()
        dismiss()
    }
}
