import SwiftData
import SwiftUI

struct ChallengesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeItem.createdAt, order: .reverse) private var challenges: [ChallengeItem]
    @Query(sort: \ChallengeGroup.title) private var groups: [ChallengeGroup]
    @Query(sort: \ChallengeCalendarEvent.startDate) private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @State private var completedTab = false
    @State private var filter = ChallengeFilter.all
    @State private var showingNewChallenge = false
    @State private var showingNewGroup = false
    @State private var edited: ChallengeItem?
    @State private var acceptedRecommendation: ChallengeCalendarEvent?
    @State private var showingShop = false
    @State private var showingWallet = false
    @AppStorage(StreakSettings.revisionKey) private var streakRevision = 0
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0

    var body: some View {
        List {
            Section {
                DisclosureGroup {
                    if recommendations.isEmpty {
                        Text(L("Keine importierten Empfehlungen", "No imported recommendations"))
                            .foregroundStyle(.secondary)
                    }
                        ForEach(recommendations) { recommendation in
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(recommendation.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(AppDate.numeric(recommendation.startDate))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button(L("Übernehmen", "Accept")) {
                                    acceptedRecommendation = recommendation
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                } label: {
                    Label(
                        "\(L("Empfehlungen", "Recommendations")) (\(recommendations.count))",
                        systemImage: "lightbulb.fill"
                    )
                }
            }

            Section {
                Picker(L("Status", "Status"), selection: $completedTab) {
                    Text(L("Aktiv", "Active")).tag(false)
                    Text(L("Abgeschlossen", "Completed")).tag(true)
                }
                .pickerStyle(.segmented)
                Picker(L("Filter", "Filter"), selection: $filter) {
                    ForEach(ChallengeFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if filter != .single {
                ForEach(groups) { group in
                    NavigationLink {
                        ChallengeGroupDetailView(group: group)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(group.title).font(.headline)
                                Spacer()
                                CoinAmountView(
                                    amount: groupMembers(group).reduce(0) { $0 + $1.rewardCoins }
                                )
                            }
                            ForEach(groupMembers(group).prefix(3)) { challenge in
                                Label(challenge.title, systemImage: "arrow.turn.down.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if groupMembers(group).count > 3 {
                                Text("+\(groupMembers(group).count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if filter != .groups {
                ForEach(filteredChallenges) { challenge in
                    Button {
                        ChallengeService.toggleCompletion(
                            challenge: challenge,
                            date: AppClock.now,
                            completions: completions,
                            transactions: transactions,
                            events: calendarEvents,
                            context: context
                        )
                    } label: {
                        HStack {
                            Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(challenge.title).foregroundStyle(.primary)
                                challengeMeta(challenge)
                            }
                            Spacer()
                            Image(systemName: ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(challenge.isReadOnly)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteChallenge(challenge)
                        } label: {
                            Label(L("Löschen", "Delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            edited = challenge
                        } label: {
                            Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }

            if visibleChallengesEmpty && !recommendations.isEmpty {
                Text(L("Keine Challenges", "No challenges"))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if visibleChallengesEmpty && recommendations.isEmpty {
                ContentUnavailableView(L("Keine Challenges", "No challenges"), systemImage: "target")
            }
        }
        .toolbar {
            leadingChallengeLinks
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Challenge", "Challenge")) { showingNewChallenge = true }
                    Button(L("Gruppe", "Group")) { showingNewGroup = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewChallenge) { ChallengeForm(challenge: nil) }
        .sheet(isPresented: $showingNewGroup) { ChallengeGroupForm() }
        .sheet(item: $edited) { ChallengeForm(challenge: $0) }
        .sheet(item: $acceptedRecommendation) {
            ChallengeForm(challenge: nil, recommendation: $0)
        }
        .navigationDestination(isPresented: $showingShop) { ShopView() }
        .navigationDestination(isPresented: $showingWallet) { WalletView() }
        .onAppear { commitSimulatedDay() }
        .onChange(of: developerDay) { commitSimulatedDay() }
        .onChange(of: developerMode) { commitSimulatedDay() }
    }

    private func commitSimulatedDay() {
        ChallengeService.commitFreezes(for: challenges, completions: completions, events: calendarEvents, on: AppClock.now)
    }

    @ToolbarContentBuilder
    private var leadingChallengeLinks: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                challengeLinkBubbles
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                challengeLinkBubbles
            }
        }
    }

    private var challengeLinkBubbles: some View {
        HStack(spacing: 8) {
            glassToolbarButton {
                showingShop = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gift.fill")
                    Text(L("Shop", "Shop"))
                }
            }
            glassToolbarButton {
                showingWallet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "c.circle.fill")
                        .foregroundStyle(.orange)
                    Text("\(ChallengeService.walletBalance(transactions: transactions))")
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func glassToolbarButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let content = label()
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if #available(iOS 26.0, *) {
            Button(action: action) { content }
                .buttonStyle(.glass)
        } else {
            Button(action: action) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var visibleChallengesEmpty: Bool {
        switch filter {
        case .groups:
            return groups.isEmpty
        case .single:
            return filteredChallenges.isEmpty
        case .all:
            return groups.isEmpty && filteredChallenges.isEmpty
        }
    }

    private var filteredChallenges: [ChallengeItem] {
        challenges.filter { challenge in
            let done = challenge.isArchived ||
                ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions)
            return done == completedTab && challenge.groupID == nil
        }
    }

    private var recommendations: [ChallengeCalendarEvent] {
        calendarEvents.filter(\.isReminderSuggestion)
    }

    private func groupMembers(_ group: ChallengeGroup) -> [ChallengeItem] {
        challenges.filter { $0.groupID == group.id }
    }

    private func deleteChallenge(_ challenge: ChallengeItem) {
        for completion in completions.filter({ $0.challengeID == challenge.id }) {
            transactions.filter { $0.referenceID == completion.id }.forEach(context.delete)
            context.delete(completion)
        }
        IconPreferenceStore.remove(for: challenge.id)
        ReminderLinkStore.remove(for: challenge.externalIdentifier)
        StreakSettings.remove(for: challenge.id)
        context.delete(challenge)
        try? context.save()
    }

    private func challengeMeta(_ challenge: ChallengeItem) -> some View {
        let _ = streakRevision
        let _ = developerMode
        let _ = developerDay
        let enabled = StreakSettings.isEnabled(for: challenge.id)
        let streak = ChallengeService.status(
            for: challenge,
            endingOn: AppClock.now,
            completions: completions,
            events: calendarEvents
        ).count
        let linked = calendarEvents.filter { !$0.isReminderSuggestion && $0.linkedChallengeID == challenge.id }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(challenge.recurrence.label)
                CoinAmountView(
                    amount: ChallengeService.projectedCoins(
                        challenge: challenge,
                        on: AppClock.now,
                        completions: completions,
                        events: calendarEvents
                    ),
                    showsPlus: true
                )
                if enabled {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.orange)
                }
            }
            if let caption = LinkCaption.calendar(
                titles: linked.map(\.title),
                count: linked.count,
                singleDate: linked.count == 1 ? linked.first?.startDate : nil
            ) {
                Text(caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private enum ChallengeFilter: String, CaseIterable, Identifiable {
    case all
    case groups
    case single
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: L("Alle", "All")
        case .groups: L("Gruppen", "Groups")
        case .single: L("Einzeln", "Single")
        }
    }
}

private struct ChallengeForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeGroup.title) private var groups: [ChallengeGroup]
    private let existing: ChallengeItem?
    private let sourceRecommendation: ChallengeCalendarEvent?
    @State private var title: String
    @State private var details: String
    @State private var category: ChallengeCategory
    @State private var recurrence: ChallengeRecurrence
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var weekdays: Set<Int>
    @State private var rewardCoins: Int
    @State private var streaksEnabled: Bool
    @State private var groupID: UUID?
    @State private var icon: String
    @State private var syncToReminders: Bool
    @State private var isSaving = false
    @State private var savedChallenge: ChallengeItem?
    @State private var saveMessage: String?

    @MainActor
    init(challenge: ChallengeItem?, recommendation: ChallengeCalendarEvent? = nil) {
        let reminderMetadata = ReminderLinkStore.metadata(
            for: challenge?.externalIdentifier ?? recommendation?.externalIdentifier
        )
        existing = challenge
        sourceRecommendation = recommendation
        _title = State(initialValue: challenge?.title ?? recommendation?.title ?? "")
        _details = State(initialValue: challenge?.details ?? recommendation?.details ?? "")
        _category = State(initialValue: challenge?.category ?? (recommendation == nil ? .habit : .todo))
        _recurrence = State(initialValue: challenge?.recurrence ?? reminderMetadata?.recurrence ?? .none)
        _startDate = State(initialValue: challenge?.startDate ?? recommendation?.startDate ?? .now)
        _hasEndDate = State(initialValue: challenge?.endDate != nil || reminderMetadata?.endDate != nil)
        _endDate = State(initialValue: challenge?.endDate ?? reminderMetadata?.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!)
        _weekdays = State(initialValue: challenge?.weekdaySet ?? reminderMetadata?.weekdays ?? [])
        _rewardCoins = State(initialValue: challenge?.rewardCoins ?? 10)
        _streaksEnabled = State(initialValue: challenge.map { StreakSettings.isEnabled(for: $0.id) } ?? false)
        _groupID = State(initialValue: challenge?.groupID)
        _icon = State(initialValue: challenge.map { IconPreferenceStore.icon(for: $0.id, fallback: "target") } ?? (recommendation == nil ? "target" : "lightbulb"))
        _syncToReminders = State(initialValue: challenge.map { ReminderSyncPreference.isEnabled(for: $0.id) } ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing?.isReadOnly == true {
                    Text(L("Diese Challenge stammt aus Erinnerungen.", "This challenge comes from Reminders."))
                        .foregroundStyle(.secondary)
                }
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                SymbolPicker(title: L("Symbol", "Icon"), selection: $icon)
                Picker(L("Kategorie", "Category"), selection: $category) {
                    ForEach(ChallengeCategory.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Wiederholung", "Recurrence"), selection: $recurrence) {
                    ForEach(ChallengeRecurrence.allCases) { Text($0.label).tag($0) }
                }
                if recurrence != .none {
                    AppDateField(title: L("Start", "Start"), selection: $startDate)
                    Toggle(L("Enddatum", "End date"), isOn: $hasEndDate)
                    if hasEndDate {
                        AppDateField(title: L("Ende", "End"), selection: $endDate, minimum: startDate)
                    }
                    if recurrence == .weekly {
                        WeekdayPicker(selection: $weekdays)
                    }
                }
                LabeledContent(L("Belohnung", "Reward")) {
                    TextField("0", value: $rewardCoins, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle(L("Streaks aktivieren", "Enable streaks"), isOn: $streaksEnabled)
                Text(L(
                    "Die Serie zählt jede Erledigung. Die Quote folgt der Frequenz, zum Beispiel dreimal in der Woche oder einmal im Monat, an beliebigen Tagen. Fehlt sie am Ende, fällt die Serie auf 0, außer eine Freeze schützt sie.",
                    "The streak counts every completion. The quota follows the frequency, for example three times a week or once a month, on any days. If it is missed at the end, the streak drops to 0 unless a freeze protects it."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if existing?.isReadOnly != true,
                   existing?.externalIdentifier?.hasPrefix("event-challenge:") != true {
                    Toggle(L("In Apple Erinnerungen sichern", "Save to Apple Reminders"), isOn: $syncToReminders)
                }
                Picker(L("Gruppe", "Group"), selection: $groupID) {
                    Text(L("Keine", "None")).tag(Optional<UUID>.none)
                    ForEach(groups) { Text($0.title).tag(Optional($0.id)) }
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .disabled(existing?.isReadOnly == true)
            .navigationTitle(L("Challenge", "Challenge"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Schließen", "Close")) { dismiss() } }
                if existing?.isReadOnly != true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await save() }
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
    }

    @MainActor
    private func save() async {
        guard !title.isEmpty else { return }
        isSaving = true
        saveMessage = nil
        defer { isSaving = false }

        let challenge = existing ?? savedChallenge ?? ChallengeItem(
            title: title,
            externalIdentifier: sourceRecommendation?.externalIdentifier
        )
        challenge.title = title
        challenge.details = details
        challenge.category = category
        challenge.recurrence = recurrence
        challenge.startDate = startDate
        challenge.endDate = recurrence != .none && hasEndDate ? endDate : nil
        challenge.weekdaySet = recurrence == .weekly ? weekdays : []
        challenge.rewardCoins = max(rewardCoins, 0)
        challenge.streakTarget = 0
        challenge.groupID = groupID
        StreakSettings.setEnabled(streaksEnabled, for: challenge.id)
        if existing == nil, savedChallenge == nil {
            context.insert(challenge)
            savedChallenge = challenge
        }
        if let sourceRecommendation, sourceRecommendation.modelContext != nil {
            context.delete(sourceRecommendation)
        }
        IconPreferenceStore.set(icon, for: challenge.id)
        ReminderSyncPreference.set(syncToReminders, for: challenge.id)
        try? context.save()

        if let externalIdentifier = challenge.externalIdentifier,
           externalIdentifier.hasPrefix("event-challenge:") {
            if challenge.recurrence == .none {
                ReminderLinkStore.remove(for: externalIdentifier)
            } else {
                ReminderLinkStore.set(
                    ReminderRecurrenceMetadata(
                        recurrence: challenge.recurrence,
                        interval: 1,
                        weekdays: challenge.weekdaySet,
                        endDate: challenge.endDate
                    ),
                    for: externalIdentifier
                )
            }
            dismiss()
            return
        }

        guard syncToReminders else {
            dismiss()
            return
        }
        guard let externalIdentifier = await EventKitSyncService.saveReminder(
            externalIdentifier: challenge.externalIdentifier,
            title: challenge.title,
            notes: challenge.details,
            startDate: challenge.startDate ?? .now,
            endDate: challenge.endDate,
            recurrence: challenge.recurrence,
            recurrenceInterval: 1,
            weekdays: challenge.weekdaySet
        ) else {
            saveMessage = L(
                "Die Challenge wurde lokal gespeichert, konnte aber nicht mit Apple Erinnerungen synchronisiert werden.",
                "The challenge was saved locally but could not be synced with Apple Reminders."
            )
            return
        }
        challenge.externalIdentifier = externalIdentifier
        try? context.save()
        dismiss()
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private var labels: [String] { Calendar.current.shortWeekdaySymbols }

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                Button {
                    if selection.contains(day) { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(String(labels[day - 1].prefix(1)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selection.contains(day) ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(selection.contains(day) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ChallengeGroupDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @State private var edited: ChallengeItem?
    let group: ChallengeGroup

    var body: some View {
        List {
            if !group.details.isEmpty { Section { Text(group.details) } }
            ForEach(challenges.filter { $0.groupID == group.id }) { challenge in
                let _ = developerMode
                let _ = developerDay
                Button {
                    ChallengeService.toggleCompletion(
                        challenge: challenge,
                        date: AppClock.now,
                        completions: completions,
                        transactions: transactions,
                        events: calendarEvents,
                        context: context
                    )
                } label: {
                    HStack {
                        Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title)
                            if let caption = groupCalendarCaption(challenge) {
                                Text(caption)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Image(systemName: ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.green)
                    }
                }
                .disabled(challenge.isReadOnly)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteChallenge(challenge)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        edited = challenge
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle(group.title)
        .sheet(item: $edited) { ChallengeForm(challenge: $0) }
    }

    private func groupCalendarCaption(_ challenge: ChallengeItem) -> String? {
        let linked = calendarEvents.filter { !$0.isReminderSuggestion && $0.linkedChallengeID == challenge.id }
        return LinkCaption.calendar(
            titles: linked.map(\.title),
            count: linked.count,
            singleDate: linked.count == 1 ? linked.first?.startDate : nil
        )
    }

    private func deleteChallenge(_ challenge: ChallengeItem) {
        for completion in completions.filter({ $0.challengeID == challenge.id }) {
            transactions.filter { $0.referenceID == completion.id }.forEach(context.delete)
            context.delete(completion)
        }
        IconPreferenceStore.remove(for: challenge.id)
        ReminderLinkStore.remove(for: challenge.externalIdentifier)
        StreakSettings.remove(for: challenge.id)
        context.delete(challenge)
        try? context.save()
    }
}

private struct ChallengeGroupForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
            }
            .navigationTitle(L("Neue Gruppe", "New group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !title.isEmpty else { return }
                        context.insert(ChallengeGroup(title: title, details: details))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
