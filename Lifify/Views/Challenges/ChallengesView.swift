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
    @AppStorage(ChallengeCategoryStore.revisionKey) private var categoryRevision = 0
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

            if completedTab {
                if !abstinenceHistory.isEmpty {
                    Section(L("Abstinenz", "Abstinence")) {
                        ForEach(abstinenceHistory) { span in
                            abstinenceHistoryRow(span)
                        }
                    }
                }
                ForEach(historyDays) { day in
                    Section(AppDate.weekdayAndNumeric(day.day)) {
                        ForEach(day.entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }

            if !completedTab && filter != .single {
                ForEach(groups) { group in
                    NavigationLink {
                        ChallengeGroupDetailView(group: group)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(group.title).font(.headline)
                                Spacer()
                                CoinAmountView(
                                    amount: activeGroupMembers(group).reduce(0) { $0 + $1.rewardCoins }
                                )
                            }
                            ForEach(activeGroupMembers(group).prefix(3)) { challenge in
                                Label(challenge.title, systemImage: "arrow.turn.down.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if activeGroupMembers(group).count > 3 {
                                Text("+\(activeGroupMembers(group).count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !completedTab && filter != .groups {
                ForEach(activeSections) { section in
                    if section.showsTitle {
                        Section {
                            sectionChallenges(section)
                        } header: {
                            Text(sectionTitle(section))
                        }
                    } else {
                        Section {
                            sectionChallenges(section)
                        }
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
        AbstinenceService.settle(context: context)
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
        if completedTab { return historyDays.isEmpty && abstinenceHistory.isEmpty }
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
            guard challenge.groupID == nil, !challenge.isArchived else { return false }
            return ChallengeActivity.staysOnActiveList(
                recurrence: challenge.recurrence,
                hasCompletion: completions.contains { $0.challengeID == challenge.id }
            )
        }
    }

    private var historySource: [ChallengeHistoryCompletion] {
        let _ = developerMode
        let _ = developerDay
        let allowed = challenges.filter { challenge in
            switch filter {
            case .all: return true
            case .groups: return challenge.groupID != nil
            case .single: return challenge.groupID == nil
            }
        }
        let titles = Dictionary(uniqueKeysWithValues: allowed.map { ($0.id, $0.title) })
        return completions.compactMap { completion -> ChallengeHistoryCompletion? in
            guard let title = titles[completion.challengeID] else { return nil }
            return ChallengeHistoryCompletion(challengeID: completion.challengeID, title: title, date: completion.date)
        }
    }

    private var abstinenceIDs: Set<UUID> {
        Set(challenges.filter { $0.category == .abstinence }.map(\.id))
    }

    private var abstinenceHistory: [AbstinenceHistorySpan] {
        ChallengeHistory.abstinenceSpans(historySource.filter { abstinenceIDs.contains($0.challengeID) })
    }

    private var historyDays: [ChallengeHistoryDay] {
        ChallengeHistory.grouped(completions: historySource.filter { !abstinenceIDs.contains($0.challengeID) })
    }

    private var activeSections: [ChallengeSections.Section] {
        let _ = categoryRevision
        return ChallengeSections.make(
            challenges: filteredChallenges.map { ChallengeSections.Challenge(id: $0.id, categoryRaw: $0.categoryRaw) },
            customs: ChallengeCategoryStore.all().map {
                ChallengeSections.Custom(id: $0.id, name: $0.name, separate: $0.separate)
            }
        )
    }

    private func sectionTitle(_ section: ChallengeSections.Section) -> String {
        switch section.id {
        case "abstinence": return L("Abstinenz", "Abstinence")
        case "sport": return L("Sport", "Sport")
        case "rest": return L("Weitere", "More")
        default:
            return ChallengeCategoryStore.all().first { $0.id.uuidString == section.id }?.name
                ?? L("Weitere", "More")
        }
    }

    @ViewBuilder
    private func sectionChallenges(_ section: ChallengeSections.Section) -> some View {
        ForEach(section.challengeIDs, id: \.self) { id in
            if let challenge = filteredChallenges.first(where: { $0.id == id }) {
                if challenge.category == .abstinence {
                    abstinenceLink(challenge)
                } else {
                    regularChallengeRow(challenge)
                }
            }
        }
    }

    private func abstinenceHistoryRow(_ span: AbstinenceHistorySpan) -> some View {
        let challenge = challenges.first { $0.id == span.challengeID }
        let range = span.dayCount <= 1
            ? AppDate.numeric(span.first)
            : "\(AppDate.numeric(span.first)) – \(AppDate.numeric(span.last))"
        let days = span.dayCount == 1 ? L("1 Tag", "1 day") : "\(span.dayCount) \(L("Tage", "days"))"
        return NavigationLink {
            AbstinenceDetailView(challengeID: span.challengeID)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(span.title)
                Text("\(days) · \(range)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let challenge {
                Button(role: .destructive) {
                    deleteChallenge(challenge)
                } label: {
                    Label(L("Löschen", "Delete"), systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let challenge {
                Button {
                    edited = challenge
                } label: {
                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    private func historyRow(_ entry: ChallengeHistoryEntry) -> some View {
        let challenge = challenges.first { $0.id == entry.challengeID }
        return Button {
            guard let challenge, !challenge.isReadOnly else { return }
            ChallengeService.toggleCompletion(
                challenge: challenge,
                date: entry.date,
                completions: completions,
                transactions: transactions,
                events: calendarEvents,
                context: context
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                    Text(L("Erledigt am \(AppDate.numeric(entry.date))", "Done on \(AppDate.numeric(entry.date))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(challenge?.isReadOnly == true)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let challenge {
                Button(role: .destructive) {
                    deleteChallenge(challenge)
                } label: {
                    Label(L("Löschen", "Delete"), systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let challenge {
                Button {
                    edited = challenge
                } label: {
                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    private var recommendations: [ChallengeCalendarEvent] {
        calendarEvents.filter(\.isReminderSuggestion)
    }

    private func groupMembers(_ group: ChallengeGroup) -> [ChallengeItem] {
        challenges.filter { $0.groupID == group.id }
    }

    private func activeGroupMembers(_ group: ChallengeGroup) -> [ChallengeItem] {
        groupMembers(group).filter { challenge in
            !challenge.isArchived && ChallengeActivity.staysOnActiveList(
                recurrence: challenge.recurrence,
                hasCompletion: completions.contains { $0.challengeID == challenge.id }
            )
        }
    }

    private func abstinenceLink(_ challenge: ChallengeItem) -> some View {
        NavigationLink {
            AbstinenceDetailView(challengeID: challenge.id)
        } label: {
            AbstinenceSummary(challenge: challenge)
        }
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

    private func regularChallengeRow(_ challenge: ChallengeItem) -> some View {
        let doneToday = ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions)
        let gray = ChallengeActivity.dimsActiveRow(recurrence: challenge.recurrence, completedToday: doneToday)
        return Button {
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
                    Text(challenge.title).foregroundStyle(gray ? .secondary : .primary)
                    challengeMeta(challenge)
                    if gray {
                        Text(L("Heute erledigt", "Done today"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(gray ? Color.secondary : Color.green)
            }
            .opacity(gray ? 0.55 : 1)
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

    private func deleteChallenge(_ challenge: ChallengeItem) {
        for completion in completions.filter({ $0.challengeID == challenge.id }) {
            transactions.filter { $0.referenceID == completion.id }.forEach(context.delete)
            context.delete(completion)
        }
        IconPreferenceStore.remove(for: challenge.id)
        ReminderLinkStore.remove(for: challenge.externalIdentifier)
        StreakSettings.remove(for: challenge.id)
        AbstinenceSettings.remove(for: challenge.id)
        ChallengeTimeStore.removeChallenge(challenge.id)
        let challengeID = challenge.id.uuidString
        context.delete(challenge)
        try? context.save()
        Task { await LififyNotifications.cancel(idPrefix: challengeID) }
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
        let linked = ChallengeTimeStore.linkedEvents(for: challenge.id, in: calendarEvents)
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

struct ChallengeForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ChallengeGroup.title) private var groups: [ChallengeGroup]
    @Query(sort: \ChallengeCalendarEvent.startDate) private var formEvents: [ChallengeCalendarEvent]
    private let existing: ChallengeItem?
    private let sourceRecommendation: ChallengeCalendarEvent?
    @State private var title: String
    @State private var details: String
    @AppStorage(ChallengeCategoryStore.revisionKey) private var categoryRevision = 0
    @State private var categoryKey: String
    @State private var showingNewCategory = false
    @State private var recurrence: ChallengeRecurrence
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var weekdays: Set<Int>
    @State private var rewardCoins: Int
    @State private var streaksEnabled: Bool
    @State private var difficulty: AbstinenceDifficulty
    @State private var durationText: String
    @State private var linkedEventID: UUID?
    @State private var groupID: UUID?
    @State private var icon: String
    @State private var syncToReminders: Bool
    @State private var isSaving = false
    @State private var savedChallenge: ChallengeItem?
    @State private var saveMessage: String?

    @MainActor
    init(challenge: ChallengeItem?, recommendation: ChallengeCalendarEvent? = nil, presetCategory: ChallengeCategory? = nil) {
        let reminderMetadata = ReminderLinkStore.metadata(
            for: challenge?.externalIdentifier ?? recommendation?.externalIdentifier
        )
        existing = challenge
        sourceRecommendation = recommendation
        _title = State(initialValue: challenge?.title ?? recommendation?.title ?? "")
        _details = State(initialValue: challenge?.details ?? recommendation?.details ?? "")
        _categoryKey = State(initialValue: ChallengeCategoryStore.selectionKey(
            for: challenge?.categoryRaw ?? presetCategory?.rawValue ?? ChallengeCategory.other.rawValue
        ))
        _recurrence = State(initialValue: challenge?.recurrence ?? reminderMetadata?.recurrence ?? .none)
        _startDate = State(initialValue: challenge?.startDate ?? recommendation?.startDate ?? .now)
        _hasEndDate = State(initialValue: challenge?.endDate != nil || reminderMetadata?.endDate != nil)
        _endDate = State(initialValue: challenge?.endDate ?? reminderMetadata?.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!)
        _weekdays = State(initialValue: challenge?.weekdaySet ?? reminderMetadata?.weekdays ?? [])
        _rewardCoins = State(initialValue: challenge?.rewardCoins ?? 10)
        _streaksEnabled = State(initialValue: challenge.map { StreakSettings.isEnabled(for: $0.id) } ?? false)
        _difficulty = State(initialValue: challenge.map { AbstinenceSettings.difficulty(for: $0.id) } ?? .medium)
        _durationText = State(initialValue: challenge.flatMap { ChallengeTimeStore.minutes(for: $0.id).map(String.init) } ?? "")
        _linkedEventID = State(initialValue: challenge.flatMap { ChallengeTimeStore.eventID(containing: $0.id) })
        _groupID = State(initialValue: challenge?.groupID)
        let presetIcon = presetCategory == .abstinence ? "lungs.fill" : "target"
        _icon = State(initialValue: challenge.map { IconPreferenceStore.icon(for: $0.id, fallback: presetIcon) } ?? (recommendation == nil ? presetIcon : "lightbulb"))
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
                let _ = categoryRevision
                Picker(L("Kategorie", "Category"), selection: $categoryKey) {
                    ForEach(ChallengeCategory.offered) { Text($0.label).tag($0.rawValue) }
                    ForEach(ChallengeCategoryStore.all()) { custom in
                        Text(custom.name).tag(ChallengeCategoryStore.raw(custom.id))
                    }
                }
                Button(L("Kategorie anlegen", "Add category")) { showingNewCategory = true }
                if categoryKey == ChallengeCategory.abstinence.rawValue {
                    AppDateField(title: L("Abstinent seit", "Abstinent since"), selection: $startDate, includesTime: true)
                    Picker(L("Schwierigkeit", "Difficulty"), selection: $difficulty) {
                        ForEach(AbstinenceDifficulty.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent(L("Coins pro Tag", "Coins per day")) {
                        TextField("0", value: $rewardCoins, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(L(
                        "Der Timer läuft ab diesem Zeitpunkt. Jeder Tag zahlt diese Coins. Boni an den Zeitstufen sind ein Faktor mal diese Coins und hängen an leicht, mittel oder schwer. Die Faktoren stehen unter Einstellungen, Herausforderung.",
                        "The timer runs from this moment. Each day pays these coins. Bonuses at the time steps are a factor times these coins and depend on easy, medium, or hard. The factors are in Settings, Challenges."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
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
                    if categoryKey != ChallengeCategory.sport.rawValue {
                        LabeledContent(L("Dauer in Minuten", "Duration in minutes")) {
                            TextField(L("Optional", "Optional"), text: $durationText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        NavigationLink {
                            ChallengeEventPicker(selection: $linkedEventID, events: linkableEvents)
                        } label: {
                            LabeledContent(L("Termin", "Event"), value: linkedEventTitle)
                        }
                        Text(L(
                            "Leer lassen, wenn die Challenge keine Dauer hat. In einem Termin zählen nur Challenges mit Dauer zur Zeit. Sport und Abstinenz haben eigene Regeln.",
                            "Leave this empty when the challenge has no duration. In an event, only challenges with a duration count toward the time. Sport and abstinence have their own rules."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showingNewCategory) {
                CustomCategoryEditor(existing: nil) { created in
                    categoryKey = ChallengeCategoryStore.raw(created.id)
                }
            }
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

    private var linkedEventTitle: String {
        guard let linkedEventID, let event = formEvents.first(where: { $0.id == linkedEventID }) else {
            return L("Keiner", "None")
        }
        return "\(event.title) · \(AppDate.numeric(event.startDate))"
    }

    private var linkableEvents: [ChallengeCalendarEvent] {
        let minutes = Int(durationText.trimmingCharacters(in: .whitespaces))
        return formEvents.filter { event in
            guard !event.isReminderSuggestion else { return false }
            let selected = event.id == linkedEventID
            if !selected {
                guard !event.isAllDay else { return false }
                guard ChallengeTimeRules.canAssign(start: event.startDate, now: AppClock.now, keepingSelection: false) else {
                    return false
                }
            }
            if selected { return true }
            let planned = ChallengeTimeStore.plannedMinutes(for: event.id)
                ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
            let others = ChallengeTimeStore.memberIDs(for: event.id).filter { $0 != existing?.id }
            let used = others.compactMap { ChallengeTimeStore.minutes(for: $0) }
            let left = ChallengeTimeRules.remaining(slotMinutes: planned, linkedMinutes: used)
            return ChallengeTimeRules.canAdd(minutes: minutes, remaining: left)
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func assignEvent(_ challengeID: UUID, minutes: Int?) {
        if let eventID = linkedEventID {
            var members = ChallengeTimeStore.memberIDs(for: eventID).filter { $0 != challengeID }
            let event = formEvents.first { $0.id == eventID }
            let planned = ChallengeTimeStore.plannedMinutes(for: eventID)
                ?? event.map { ChallengeTimeRules.minutes(from: $0.startDate, to: $0.endDate) }
                ?? 0
            let used = members.compactMap { ChallengeTimeStore.minutes(for: $0) }
            let left = ChallengeTimeRules.remaining(slotMinutes: max(planned, 1), linkedMinutes: used)
            guard ChallengeTimeRules.canAdd(minutes: minutes, remaining: left) else {
                saveMessage = L(
                    "Die Dauer passt nicht mehr in den Termin.",
                    "The duration no longer fits in the event."
                )
                return
            }
            members.append(challengeID)
            ChallengeTimeStore.setMembers(members, for: eventID)
        } else if let current = ChallengeTimeStore.eventID(containing: challengeID) {
            var members = ChallengeTimeStore.memberIDs(for: current)
            members.removeAll { $0 == challengeID }
            ChallengeTimeStore.setMembers(members, for: current)
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
        let abstinence = categoryKey == ChallengeCategory.abstinence.rawValue
        challenge.categoryRaw = categoryKey
        challenge.recurrence = abstinence ? .daily : recurrence
        challenge.startDate = startDate
        challenge.endDate = abstinence ? nil : (recurrence != .none && hasEndDate ? endDate : nil)
        challenge.weekdaySet = !abstinence && recurrence == .weekly ? weekdays : []
        challenge.rewardCoins = max(rewardCoins, 0)
        challenge.streakTarget = 0
        challenge.groupID = groupID
        if abstinence {
            StreakSettings.setEnabled(false, for: challenge.id)
            AbstinenceSettings.setDifficulty(difficulty, for: challenge.id)
        } else {
            StreakSettings.setEnabled(streaksEnabled, for: challenge.id)
            AbstinenceSettings.remove(for: challenge.id)
            let challengeID = challenge.id.uuidString
            Task { await LififyNotifications.cancel(idPrefix: challengeID) }
        }
        if existing == nil, savedChallenge == nil {
            context.insert(challenge)
            savedChallenge = challenge
        }
        if let sourceRecommendation, sourceRecommendation.modelContext != nil {
            context.delete(sourceRecommendation)
        }
        if !abstinence && categoryKey != ChallengeCategory.sport.rawValue {
            let minutes = Int(durationText.trimmingCharacters(in: .whitespaces))
            ChallengeTimeStore.setMinutes(minutes, for: challenge.id)
            assignEvent(challenge.id, minutes: minutes)
        } else {
            ChallengeTimeStore.removeChallenge(challenge.id)
        }
        if abstinence { syncToReminders = false }
        IconPreferenceStore.set(icon, for: challenge.id)
        ReminderSyncPreference.set(syncToReminders, for: challenge.id)
        try? context.save()
        if abstinence {
            AbstinenceService.settle(context: context)
            let challengeID = challenge.id
            let start = challenge.startDate ?? challenge.createdAt
            Task {
                await LififyNotifications.cancel(
                    idPrefix: challengeID.uuidString,
                    keeping: AbstinenceService.notificationIDs(challengeID: challengeID, start: start)
                )
                await DailyBriefingService.scheduleAbstinence(context: context)
            }
        }
        if !abstinence && categoryKey != ChallengeCategory.sport.rawValue { ChallengeTimeService.resize(context: context) }
        if saveMessage != nil { return }

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
            ForEach(challenges.filter { challenge in
                guard challenge.groupID == group.id, !challenge.isArchived else { return false }
                return ChallengeActivity.staysOnActiveList(
                    recurrence: challenge.recurrence,
                    hasCompletion: completions.contains { $0.challengeID == challenge.id }
                )
            }) { challenge in
                let _ = developerMode
                let _ = developerDay
                if challenge.category == .abstinence {
                    groupAbstinenceRow(challenge)
                } else {
                    groupRegularRow(challenge)
                }
            }
        }
        .navigationTitle(group.title)
        .sheet(item: $edited) { ChallengeForm(challenge: $0) }
    }

    private func groupAbstinenceRow(_ challenge: ChallengeItem) -> some View {
        NavigationLink {
            AbstinenceDetailView(challengeID: challenge.id)
        } label: {
            AbstinenceSummary(challenge: challenge)
        }
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

    private func groupRegularRow(_ challenge: ChallengeItem) -> some View {
        let doneToday = ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions)
        let gray = ChallengeActivity.dimsActiveRow(recurrence: challenge.recurrence, completedToday: doneToday)
        return Button {
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
                        .foregroundStyle(gray ? Color.secondary : Color.primary)
                    if let caption = groupCalendarCaption(challenge) {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(Color.green)
                    }
                    if gray {
                        Text(L("Heute erledigt", "Done today"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(gray ? Color.secondary : Color.green)
            }
            .opacity(gray ? 0.55 : 1)
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

    private func groupCalendarCaption(_ challenge: ChallengeItem) -> String? {
        let linked = ChallengeTimeStore.linkedEvents(for: challenge.id, in: calendarEvents)
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
        AbstinenceSettings.remove(for: challenge.id)
        ChallengeTimeStore.removeChallenge(challenge.id)
        let challengeID = challenge.id.uuidString
        context.delete(challenge)
        try? context.save()
        Task { await LififyNotifications.cancel(idPrefix: challengeID) }
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
