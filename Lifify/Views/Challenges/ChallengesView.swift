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

    var body: some View {
        List {
            Section {
                DisclosureGroup {
                    if recommendations.isEmpty {
                        Text(L("Keine importierten Empfehlungen", "No imported recommendations"))
                            .foregroundStyle(.secondary)
                    }
                        ForEach(recommendations) { recommendation in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recommendation.title)
                                    .font(.headline)
                                if !recommendation.details.isEmpty {
                                    Text(recommendation.details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    if let externalIdentifier = recommendation.externalIdentifier,
                                       !externalIdentifier.isEmpty {
                                        Text(recommendation.startDate, format: .dateTime.day().month().year())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L("Übernehmen", "Accept")) {
                                        acceptedRecommendation = recommendation
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 4)
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
                            Text(group.title).font(.headline)
                            Text("\(groupMembers(group).count) \(L("Challenges", "challenges"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if filter != .groups {
                ForEach(filteredChallenges) { challenge in
                    Button {
                        ChallengeService.toggleCompletion(
                            challenge: challenge,
                            date: .now,
                            completions: completions,
                            transactions: transactions,
                            context: context
                        )
                    } label: {
                        HStack {
                            Image(systemName: ChallengeService.isCompleted(challenge, on: .now, completions: completions) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.green)
                            Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(challenge.title).foregroundStyle(.primary)
                                Text(challengeMeta(challenge))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(challenge.isReadOnly)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            edited = challenge
                        } label: {
                            Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            deleteChallenge(challenge)
                        } label: {
                            Label(L("Löschen", "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty && challenges.isEmpty {
                ContentUnavailableView(L("Keine Challenges", "No challenges"), systemImage: "target")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ShopView()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                        Text("\(ChallengeService.walletBalance(transactions: transactions))")
                            .foregroundStyle(.primary)
                        Image(systemName: "gift.fill")
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                }
            }
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
    }

    private var filteredChallenges: [ChallengeItem] {
        challenges.filter { challenge in
            let done = challenge.isArchived ||
                ChallengeService.isCompleted(challenge, on: .now, completions: completions)
            return done == completedTab && (filter != .single || challenge.groupID == nil)
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
        context.delete(challenge)
        try? context.save()
    }

    private func challengeMeta(_ challenge: ChallengeItem) -> String {
        let streak = ChallengeService.streak(for: challenge, endingOn: .now, completions: completions)
        let target = challenge.streakTarget > 0 ? "/\(challenge.streakTarget)" : ""
        return "\(challenge.recurrence.label) · +\(challenge.rewardCoins) · 🔥 \(streak)\(target)"
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
    @State private var streakTarget: Int
    @State private var groupID: UUID?
    @State private var icon: String

    @MainActor
    init(challenge: ChallengeItem?, recommendation: ChallengeCalendarEvent? = nil) {
        existing = challenge
        sourceRecommendation = recommendation
        _title = State(initialValue: challenge?.title ?? recommendation?.title ?? "")
        _details = State(initialValue: challenge?.details ?? recommendation?.details ?? "")
        _category = State(initialValue: challenge?.category ?? (recommendation == nil ? .habit : .todo))
        _recurrence = State(initialValue: challenge?.recurrence ?? (recommendation == nil ? .daily : .none))
        _startDate = State(initialValue: challenge?.startDate ?? recommendation?.startDate ?? .now)
        _hasEndDate = State(initialValue: challenge?.endDate != nil)
        _endDate = State(initialValue: challenge?.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!)
        _weekdays = State(initialValue: challenge?.weekdaySet ?? [])
        _rewardCoins = State(initialValue: challenge?.rewardCoins ?? 10)
        _streakTarget = State(initialValue: challenge?.streakTarget ?? 0)
        _groupID = State(initialValue: challenge?.groupID)
        _icon = State(initialValue: challenge.map { IconPreferenceStore.icon(for: $0.id, fallback: "target") } ?? (recommendation == nil ? "target" : "lightbulb"))
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
                DatePicker(L("Start", "Start"), selection: $startDate, displayedComponents: .date)
                Toggle(L("Enddatum", "End date"), isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker(L("Ende", "End"), selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                if recurrence == .weekly {
                    WeekdayPicker(selection: $weekdays)
                }
                Stepper("\(L("Coins", "Coins")): \(rewardCoins)", value: $rewardCoins, in: 0...10_000)
                Stepper("\(L("Streak-Ziel", "Streak target")): \(streakTarget)", value: $streakTarget, in: 0...365)
                Picker(L("Gruppe", "Group"), selection: $groupID) {
                    Text(L("Keine", "None")).tag(Optional<UUID>.none)
                    ForEach(groups) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            .disabled(existing?.isReadOnly == true)
            .navigationTitle(L("Challenge", "Challenge"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Schließen", "Close")) { dismiss() } }
                if existing?.isReadOnly != true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Speichern", "Save")) {
                            guard !title.isEmpty else { return }
                            let challenge = existing ?? ChallengeItem(
                                title: title,
                                externalIdentifier: sourceRecommendation?.externalIdentifier
                            )
                            challenge.title = title
                            challenge.details = details
                            challenge.category = category
                            challenge.recurrence = recurrence
                            challenge.startDate = startDate
                            challenge.endDate = hasEndDate ? endDate : nil
                            challenge.weekdaySet = weekdays
                            challenge.rewardCoins = rewardCoins
                            challenge.streakTarget = streakTarget
                            challenge.groupID = groupID
                            if existing == nil { context.insert(challenge) }
                            if let sourceRecommendation { context.delete(sourceRecommendation) }
                            IconPreferenceStore.set(icon, for: challenge.id)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
        }
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
    @State private var edited: ChallengeItem?
    let group: ChallengeGroup

    var body: some View {
        List {
            if !group.details.isEmpty { Section { Text(group.details) } }
            ForEach(challenges.filter { $0.groupID == group.id }) { challenge in
                Button {
                    ChallengeService.toggleCompletion(challenge: challenge, date: .now, completions: completions, transactions: transactions, context: context)
                } label: {
                    Label(
                        challenge.title,
                        systemImage: ChallengeService.isCompleted(challenge, on: .now, completions: completions) ? "checkmark.circle.fill" : "circle"
                    )
                }
                .disabled(challenge.isReadOnly)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        edited = challenge
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                    Button(role: .destructive) {
                        deleteChallenge(challenge)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(group.title)
        .sheet(item: $edited) { ChallengeForm(challenge: $0) }
    }

    private func deleteChallenge(_ challenge: ChallengeItem) {
        for completion in completions.filter({ $0.challengeID == challenge.id }) {
            transactions.filter { $0.referenceID == completion.id }.forEach(context.delete)
            context.delete(completion)
        }
        IconPreferenceStore.remove(for: challenge.id)
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
