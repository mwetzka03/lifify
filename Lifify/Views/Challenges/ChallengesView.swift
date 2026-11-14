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
    @State private var createCategory: ChallengeCategory?
    @State private var showingNewGroup = false
    @State private var edited: ChallengeItem?
    @State private var acceptedRecommendation: ChallengeCalendarEvent?
    @State private var showingShop = false
    @State private var showingWallet = false
    @State private var pendingDuration: PendingDuration?
    @State private var expandedGroups: Set<UUID> = []
    @AppStorage(StreakSettings.revisionKey) private var streakRevision = 0
    @AppStorage(ChallengeCategoryStore.revisionKey) private var categoryRevision = 0
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @AppStorage(ChallengePinStore.revisionKey) private var pinRevision = 0
    @AppStorage(ChallengeGroupPinStore.revisionKey) private var groupPinRevision = 0
    @AppStorage(WorkoutLinkStore.revisionKey) private var workoutLinkRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recommendationsCard
                if showsPinnedBoard {
                    pinnedBoard
                }
                filterCard
                if completedTab {
                    completedBoard
                } else {
                    if filter != .groups {
                        ForEach(activeSections) { section in
                            challengeSection(section)
                        }
                    }
                    if filter != .single, !looseGroups.isEmpty {
                        groupBoard
                    }
                }
                if visibleChallengesEmpty && !recommendations.isEmpty {
                    Text(L("Keine Challenges", "No challenges"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .overlay {
            if visibleChallengesEmpty && recommendations.isEmpty && (completedTab || filter == .groups) {
                ContentUnavailableView(L("Keine Challenges", "No challenges"), systemImage: "target")
            }
        }
        .toolbar {
            leadingChallengeLinks
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(ChallengeCreateMenu.abstinence) { createCategory = .abstinence }
                    Button(ChallengeCreateMenu.sport) { createCategory = .sport }
                    Button(ChallengeCreateMenu.other) { createCategory = .other }
                    Button(ChallengeCreateMenu.group) { showingNewGroup = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $createCategory) { category in
            ChallengeForm(challenge: nil, presetCategory: category)
        }
        .sheet(isPresented: $showingNewGroup) { ChallengeGroupForm() }
        .sheet(item: $edited) { ChallengeForm(challenge: $0) }
        .sheet(item: $pendingDuration) { pending in
            ActualDurationSheet(suggested: pending.suggested) { minutes in
                ChallengeFinish.commit(
                    challenge: pending.challenge,
                    date: pending.date,
                    actualMinutes: minutes,
                    completions: completions,
                    transactions: transactions,
                    events: calendarEvents,
                    context: context
                )
                pendingDuration = nil
            } onCancel: {
                pendingDuration = nil
            }
        }
        .sheet(item: $acceptedRecommendation) {
            ChallengeForm(challenge: nil, recommendation: $0)
        }
        .navigationDestination(isPresented: $showingShop) { ShopView() }
        .navigationDestination(isPresented: $showingWallet) { WalletView() }
        .appGlassCanvas()
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
            .padding(.vertical, CardBoard.toolbarVerticalPadding)
            .frame(minHeight: CardBoard.toolbarMinHeight)
            .fixedSize(horizontal: true, vertical: false)
        if #available(iOS 26.0, *) {
            Button(action: action) { content }
                .buttonStyle(.glass)
        } else {
            Button(action: action) {
                content
                    .padding(.horizontal, 14)
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
            guard !challenge.isArchived else { return false }
            guard EventChallengeLink.showsIndividual(inGroup: !challenge.groupIDs.isEmpty, singleFilter: filter == .single) else {
                return false
            }
            return ChallengeActivity.staysOnActiveList(
                recurrence: challenge.recurrence,
                hasCompletion: completions.contains { $0.challengeID == challenge.id }
            )
        }
    }

    private var historySource: [ChallengeHistoryCompletion] {
        let _ = developerMode
        let _ = developerDay
        let shown = Set(ChallengePinLayout.below(ids: challenges.map(\.id), pinned: ChallengePinStore.ids()))
        let allowed = challenges.filter { challenge in
            guard shown.contains(challenge.id) else { return false }
            switch filter {
            case .all: return true
            case .groups: return !challenge.groupIDs.isEmpty
            case .single: return true
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

    private var recommendationsCard: some View {
        DisclosureGroup {
            if recommendations.isEmpty {
                Text(RecommendationCopy.empty)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(recommendations) { recommendation in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.title)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(AppDate.numeric(recommendation.startDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button(L("Übernehmen", "Accept")) {
                            acceptedRecommendation = recommendation
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 12)
                    if recommendation.id != recommendations.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label(
                "\(RecommendationCopy.heading) (\(recommendations.count))",
                systemImage: "lightbulb.fill"
            )
        }
        .padding(14)
        .appGlassCard(radius: 18)
    }

    private var pinnedChallenges: [ChallengeItem] {
        let _ = pinRevision
        let _ = workoutLinkRevision
        let active = challenges.filter { !$0.isArchived }
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        return ChallengePinStore.ids().compactMap { byID[$0] }
    }

    private var pinnedGroups: [ChallengeGroup] {
        let _ = groupPinRevision
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return ChallengeGroupPinStore.ids().compactMap { byID[$0] }
    }

    private var looseGroups: [ChallengeGroup] {
        let _ = groupPinRevision
        let pinned = Set(ChallengeGroupPinStore.ids())
        return groups.filter { ChallengeGroupBoard.showsInOwnSection(pinned: pinned.contains($0.id)) }
    }

    private var showsPinnedBoard: Bool {
        !pinnedChallenges.isEmpty || (filter != .single && !pinnedGroups.isEmpty)
    }

    private var pinnedBoard: some View {
        let cards = pinnedChallenges
        let pairCount = cards.count - cards.count % 2
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Angepinnt", "Pinned"))
                .appText(.section)
            if !cards.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(stride(from: 0, to: pairCount, by: 2)), id: \.self) { start in
                        EqualHeightPair {
                            challengeCard(cards[start])
                            challengeCard(cards[start + 1])
                        }
                    }
                    if cards.count % 2 == 1, let last = cards.last {
                        challengeCard(last)
                    }
                }
            }
            if filter != .single, !pinnedGroups.isEmpty {
                VStack(spacing: 10) {
                    ForEach(pinnedGroups) { group in
                        groupCard(group)
                    }
                }
            }
        }
    }

    private var groupBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Gruppen", "Groups"))
                .appText(.section)
            VStack(spacing: 10) {
                ForEach(looseGroups) { group in
                    groupCard(group)
                }
            }
        }
    }

    private var filterCard: some View {
        VStack(spacing: 10) {
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
        .padding(14)
        .appGlassCard(radius: 18)
    }

    @ViewBuilder
    private var completedBoard: some View {
        if !abstinenceHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Abstinenz", "Abstinence"))
                    .appText(.section)
                ForEach(abstinenceHistory) { span in
                    abstinenceHistoryRow(span)
                }
            }
        }
        ForEach(historyDays) { day in
            VStack(alignment: .leading, spacing: 8) {
                Text(AppDate.weekdayAndNumeric(day.day))
                    .appText(.section)
                LazyVGrid(columns: CardBoard.challengeColumns(), spacing: 10) {
                    ForEach(day.entries) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func groupCard(_ group: ChallengeGroup) -> some View {
        let _ = groupPinRevision
        let listed = listedGroupMembers(group)
        let open = expandedGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if open {
                    expandedGroups.remove(group.id)
                } else {
                    expandedGroups.insert(group.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.title)
                            .font(.headline)
                        if ChallengeGroupPinStore.contains(group.id) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        CoinAmountView(
                            amount: activeGroupMembers(group).reduce(0) { $0 + $1.rewardCoins }
                        )
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if !open {
                        ForEach(listed.prefix(3)) { challenge in
                            let done = isFinished(challenge)
                            Label(challenge.title, systemImage: done ? "checkmark" : "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .opacity(done ? 0.65 : 1)
                        }
                        if listed.count > 3 {
                            Text("+\(listed.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu { groupPinButton(group) }
            if open {
                ForEach(listed) { challenge in
                    groupMemberCard(challenge)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 18)
    }

    @ViewBuilder
    private func groupMemberCard(_ challenge: ChallengeItem) -> some View {
        if isFinished(challenge), challenge.recurrence == .none {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    AppSymbolImage(name: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        .frame(width: 28, height: 28)
                    Text(challenge.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                challengeMeta(challenge)
                Text(L("Erledigt", "Done"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .equalPairCard(radius: 18)
            .opacity(0.7)
            .contextMenu {
                Button {
                    edited = challenge
                } label: {
                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteChallenge(challenge)
                } label: {
                    Label(L("Löschen", "Delete"), systemImage: "trash")
                }
            }
        } else {
            challengeCard(challenge)
        }
    }

    private func groupPinButton(_ group: ChallengeGroup) -> some View {
        let pinned = ChallengeGroupPinStore.contains(group.id)
        return Button {
            ChallengeGroupPinStore.toggle(group.id)
        } label: {
            Label(
                pinned ? L("Lösen", "Unpin") : L("Anpinnen", "Pin"),
                systemImage: pinned ? "pin.slash" : "pin"
            )
        }
    }

    private func challengeSection(_ section: ChallengeSections.Section) -> some View {
        let pinned = Set(ChallengePinStore.ids())
        let cards = section.challengeIDs.compactMap { id in
            filteredChallenges.first { $0.id == id && !pinned.contains($0.id) }
        }
        return Group {
            if ChallengeBoard.showsCategory(unpinned: cards.count) {
                sectionStack(section, cards: cards)
            }
        }
    }

    private func sectionStack(_ section: ChallengeSections.Section, cards: [ChallengeItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if section.showsTitle, !cards.isEmpty {
                Text(sectionTitle(section))
                    .appText(.section)
            }
            let pairCount = cards.count - cards.count % 2
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: pairCount, by: 2)), id: \.self) { start in
                    EqualHeightPair {
                        challengeCard(cards[start])
                        challengeCard(cards[start + 1])
                    }
                }
                if cards.count % 2 == 1, CardBoard.singleCardUsesFullWidth, let last = cards.last {
                    challengeCard(last)
                }
                if section.id == "abstinence" {
                    createChallengeButton(.abstinence)
                }
                if section.id == "sport" {
                    createChallengeButton(.sport)
                }
            }
        }
    }

    private func createChallengeButton(_ category: ChallengeCategory) -> some View {
        Button {
            createCategory = category
        } label: {
            Label(
                category == .abstinence ? ChallengeCreateCopy.abstinence : ChallengeCreateCopy.sport,
                systemImage: "plus"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appGlassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func challengeCard(_ challenge: ChallengeItem) -> some View {
        if challenge.category == .abstinence {
            abstinenceLink(challenge)
        } else {
            regularChallengeRow(challenge)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appGlassCard(radius: 18)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let challenge {
                Button {
                    edited = challenge
                } label: {
                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteChallenge(challenge)
                } label: {
                    Label(L("Löschen", "Delete"), systemImage: "trash")
                }
            }
        }
    }

    private func historyRow(_ entry: ChallengeHistoryEntry) -> some View {
        let challenge = challenges.first { $0.id == entry.challengeID }
        return Button {
            guard let challenge, !challenge.isReadOnly else { return }
            finish(challenge, on: entry.date)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Text(entry.title)
                    .lineLimit(2)
                Text(L("Erledigt am \(AppDate.numeric(entry.date))", "Done on \(AppDate.numeric(entry.date))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .appGlassCard(radius: 18)
        }
        .buttonStyle(.plain)
        .disabled(challenge?.isReadOnly == true)
        .contextMenu {
            if let challenge {
                Button {
                    edited = challenge
                } label: {
                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteChallenge(challenge)
                } label: {
                    Label(L("Löschen", "Delete"), systemImage: "trash")
                }
            }
        }
    }

    private var recommendations: [ChallengeCalendarEvent] {
        calendarEvents.filter(\.isReminderSuggestion)
    }

    private func isFinished(_ challenge: ChallengeItem) -> Bool {
        !ChallengeActivity.staysOnActiveList(
            recurrence: challenge.recurrence,
            hasCompletion: completions.contains { $0.challengeID == challenge.id }
        )
    }

    private func listedGroupMembers(_ group: ChallengeGroup) -> [ChallengeItem] {
        challenges
            .filter { $0.belongs(to: group.id) && ChallengeGroupBoard.keepsFinishedMember(archived: $0.isArchived) }
            .sorted { lhs, rhs in
                let leftDone = isFinished(lhs)
                let rightDone = isFinished(rhs)
                if leftDone != rightDone { return !leftDone }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func activeGroupMembers(_ group: ChallengeGroup) -> [ChallengeItem] {
        listedGroupMembers(group).filter { !isFinished($0) }
    }

    private func abstinenceLink(_ challenge: ChallengeItem) -> some View {
        NavigationLink {
            AbstinenceDetailView(challengeID: challenge.id)
        } label: {
            AbstinenceSummary(challenge: challenge)
                .padding(12)
                .equalPairCard(radius: 18)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                edited = challenge
            } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteChallenge(challenge)
            } label: {
                Label(L("Löschen", "Delete"), systemImage: "trash")
            }
            pinButton(challenge)
        }
        .overlay(alignment: .topTrailing) {
            if ChallengePinStore.contains(challenge.id) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    private func finish(_ challenge: ChallengeItem, on date: Date) {
        if let minutes = ChallengeFinish.suggestedMinutes(
            challenge: challenge,
            on: date,
            completions: completions,
            events: calendarEvents
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
            events: calendarEvents,
            context: context
        )
    }

    private func pinButton(_ challenge: ChallengeItem) -> some View {
        let pinned = ChallengePinStore.contains(challenge.id)
        let full = ChallengePinStore.ids().count >= ChallengePinStore.limit
        return Button {
            ChallengePinStore.toggle(challenge.id)
        } label: {
            Label(
                pinned ? L("Lösen", "Unpin") : L("Anpinnen", "Pin"),
                systemImage: pinned ? "pin.slash" : "pin"
            )
        }
        .disabled(!pinned && full)
    }

    private func regularChallengeRow(_ challenge: ChallengeItem) -> some View {
        let _ = pinRevision
        let _ = workoutLinkRevision
        let doneToday = ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions)
        let gray = ChallengeActivity.dimsActiveRow(recurrence: challenge.recurrence, completedToday: doneToday)
        let workouts = WorkoutLinkStore.planIDs(forChallenge: challenge.id).count
        let followsNutrition = ChallengeCheckoff.followsNutrition(challenge.externalIdentifier)
        let handLocked = !ChallengeCheckoff.allowsHand(
            category: challenge.category,
            linkedWorkouts: workouts,
            followsNutrition: followsNutrition
        )
        let pinned = ChallengePinStore.contains(challenge.id)
        return Button {
            guard !handLocked else { return }
            finish(challenge, on: AppClock.now)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    AppSymbolImage(name: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        .frame(width: 28, height: 28)
                    Text(challenge.title)
                        .foregroundStyle(gray ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if ChallengeBoard.showsCheckCircle(allowsHand: !handLocked) {
                        Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(gray ? Color.secondary : Color.green)
                    }
                }
                challengeMeta(challenge)
                if let caption = ChallengeCheckoff.lockCaption(followsNutrition: followsNutrition, linkedWorkouts: workouts) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if gray {
                    Text(L("Heute erledigt", "Done today"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .equalPairCard(radius: 18)
            .opacity(gray ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(challenge.isReadOnly)
        .contextMenu {
            Button {
                edited = challenge
            } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteChallenge(challenge)
            } label: {
                Label(L("Löschen", "Delete"), systemImage: "trash")
            }
            pinButton(challenge)
        }
    }

    private func deleteChallenge(_ challenge: ChallengeItem) {
        for completion in completions.filter({ $0.challengeID == challenge.id }) {
            transactions.filter { $0.referenceID == completion.id }.forEach(context.delete)
            context.delete(completion)
        }
        IconPreferenceStore.remove(for: challenge.id)
        ChallengePinStore.unpin(challenge.id)
        for event in calendarEvents where event.linkedChallengeID == challenge.id {
            event.linkedChallengeID = nil
        }
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
        let minutes = ChallengeTimeStore.minutes(for: challenge.id)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.recurrence.label)
                if let minutes {
                    Text(ChallengeCardCopy.duration(minutes: minutes))
                        .foregroundStyle(.green)
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
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
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
    @Query(sort: \ChallengeItem.createdAt) private var formChallenges: [ChallengeItem]
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
    @State private var separatedEventGroup = false
    @State private var icon: String
    @State private var syncToReminders: Bool
    @State private var offersEvents: Bool
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
        let presetIcon = if presetCategory == .abstinence {
            "lungs.fill"
        } else if presetCategory == .sport {
            "figure.run"
        } else {
            "target"
        }
        _icon = State(initialValue: challenge.map { IconPreferenceStore.icon(for: $0.id, fallback: presetIcon) } ?? (recommendation == nil ? presetIcon : "lightbulb"))
        _syncToReminders = State(initialValue: challenge.map { ReminderSyncPreference.isEnabled(for: $0.id) } ?? true)
        _offersEvents = State(initialValue: challenge.map { EventOffer.isEnabled(for: $0.id) } ?? true)
        _showsMoreSettings = State(initialValue: !EditorCopy.moreStartsClosed)
    }

    @State private var showsMoreSettings: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                if existing?.isReadOnly == true {
                    Text(L("Diese Challenge stammt aus Erinnerungen.", "This challenge comes from Reminders."))
                        .foregroundStyle(.secondary)
                }
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                SymbolPicker(title: L("Symbol", "Icon"), selection: $icon)
                let _ = categoryRevision
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
                }
                }
                .appGlassRow()
                Section {
                    MoreSettingsToggle(isExpanded: $showsMoreSettings)
                    if showsMoreSettings {
                    Picker(L("Kategorie", "Category"), selection: $categoryKey) {
                        ForEach(ChallengeCategory.offered) { Text($0.label).tag($0.rawValue) }
                        ForEach(ChallengeCategoryStore.all()) { custom in
                            Text(custom.name).tag(ChallengeCategoryStore.raw(custom.id))
                        }
                    }
                    Button(L("Kategorie anlegen", "Add category")) { showingNewCategory = true }
                    if categoryKey != ChallengeCategory.abstinence.rawValue && categoryKey != ChallengeCategory.sport.rawValue {
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
                            "Leer lassen, wenn die Challenge keine Dauer hat. In einem Termin zählen nur Challenges mit Dauer zur Zeit.",
                            "Leave this empty when the challenge has no duration. In an event, only challenges with a duration count toward the time."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if categoryKey != ChallengeCategory.abstinence.rawValue {
                        Toggle(L("Streaks aktivieren", "Enable streaks"), isOn: $streaksEnabled)
                        Text(L(
                            "Die Serie zählt jede Erledigung. Die Quote folgt der Frequenz, zum Beispiel dreimal in der Woche oder einmal im Monat, an beliebigen Tagen.",
                            "The streak counts every completion. The quota follows the frequency, for example three times a week or once a month, on any days."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if existing?.isReadOnly != true,
                           !ChallengeTimeRules.isAdopted(existing?.externalIdentifier) {
                            Toggle(L("In Apple Erinnerungen sichern", "Save to Apple Reminders"), isOn: $syncToReminders)
                        }
                    }
                    Picker(L("Gruppe", "Group"), selection: $groupID) {
                        Text(L("Keine", "None")).tag(Optional<UUID>.none)
                        ForEach(groups) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Text(L(
                        "Diese Gruppe bleibt zusätzlich zur Gruppe, die ein Termin anlegt.",
                        "This group stays in addition to the group an event creates."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if ChallengeTimeRules.allowsTime(ChallengeCategory(rawValue: categoryKey) ?? .other) {
                        Toggle(L("Für Termine vorschlagen", "Suggest for events"), isOn: $offersEvents)
                        Text(L(
                            "Eingeschaltet heißt, die Challenge erscheint beim Zuweisen zu einem Termin. Die älteste steht oben.",
                            "On means the challenge appears when you assign work to an event. The oldest one is listed first."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    }
                }
                .appGlassRow()
                if let saveMessage {
                    Section {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .appGlassRow()
                }
            }
            .disabled(existing?.isReadOnly == true)
            .appGlassList()
            .navigationTitle(existing == nil ? L("Neue Challenge", "New challenge") : L("Challenge", "Challenge"))
            .onAppear(perform: separateEventGroup)
            .onChange(of: formEvents.count) { _, _ in separateEventGroup() }
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
        let slot = ChallengeTimeStore.plannedMinutes(for: event.id)
            ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
        let linked = ChallengeTimeStore.memberIDs(for: event.id).compactMap { ChallengeTimeStore.minutes(for: $0) }
        let when = ChallengeTimeRules.scheduleCaption(
            allDay: event.isAllDay,
            dateText: AppDate.numeric(event.startDate),
            timeText: AppDate.time(event.startDate),
            slotMinutes: slot,
            linkedMinutes: linked
        )
        return "\(event.title) · \(when)"
    }

    private var linkableEvents: [ChallengeCalendarEvent] {
        formEvents.filter { event in
            guard !event.isReminderSuggestion else { return false }
            let selected = event.id == linkedEventID
            if !selected, event.isAllDay { return false }
            let linked = event.linkedChallengeID.flatMap { id in formChallenges.first { $0.id == id } }
            var minutes = ChallengeTimeStore.memberIDs(for: event.id).compactMap { ChallengeTimeStore.minutes(for: $0) }
            if let linked,
               let extra = ChallengeTimeStore.minutes(for: linked.id),
               !ChallengeTimeRules.isExclusiveLink(category: linked.category, identifier: linked.externalIdentifier),
               event.linkedChallengeID.map({ !ChallengeTimeStore.memberIDs(for: event.id).contains($0) }) == true {
                minutes.append(extra)
            }
            let slot = ChallengeTimeStore.plannedMinutes(for: event.id)
                ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
            var otherIDs = ChallengeTimeStore.memberIDs(for: event.id).filter { $0 != existing?.id }
            if let linkedID = event.linkedChallengeID, linkedID != existing?.id, !otherIDs.contains(linkedID) {
                otherIDs.append(linkedID)
            }
            let others = otherIDs.compactMap { id in formChallenges.first { $0.id == id }?.recurrence }
            if !selected, !EventRewrite.canShare(adding: recurrence, others: others) { return false }
            return ChallengeTimeRules.canOffer(
                exclusive: ChallengeTimeRules.isExclusiveLink(
                    category: linked?.category,
                    identifier: linked?.externalIdentifier
                ),
                slotMinutes: slot,
                linkedMinutes: minutes,
                keepingSelection: selected
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func separateEventGroup() {
        guard !separatedEventGroup, let existing else { return }
        guard let eventID = linkedEventID else {
            separatedEventGroup = true
            return
        }
        guard let event = formEvents.first(where: { $0.id == eventID }) else { return }
        separatedEventGroup = true
        groupID = existing.groupIDs.first { $0 != event.linkedChallengeGroupID }
    }

    private func assignEvent(_ challenge: ChallengeItem) {
        if let eventID = linkedEventID, let event = formEvents.first(where: { $0.id == eventID }) {
            let existingMembers = ChallengeTimeStore.memberIDs(for: eventID).filter { $0 != challenge.id }
            var otherIDs = existingMembers
            if let linked = event.linkedChallengeID, linked != challenge.id, !otherIDs.contains(linked) {
                otherIDs.append(linked)
            }
            let others = otherIDs.compactMap { id in formChallenges.first { $0.id == id }?.recurrence }
            var eventGroup: UUID?
            if EventRewrite.canShare(adding: challenge.recurrence, others: others) {
                eventGroup = event.linkedChallengeGroupID
                var members = existingMembers
                members.append(challenge.id)
                ChallengeTimeStore.setMembers(members, for: eventID)
                if EventRewrite.acceptsSharedEvent(challenge.recurrence) {
                    let ids = EventChallengeLink.members(already: members, linked: event.linkedChallengeID, adding: challenge.id)
                    let shareable = ids.filter { id in
                        id == challenge.id || formChallenges.first { $0.id == id }?.recurrence == .none
                    }
                    if let joined = EventGroupSync.join(event: event, challengeIDs: shareable, context: context) {
                        event.linkedChallengeGroupID = joined
                        eventGroup = joined
                    }
                }
                EventGroupSync.place(challenge, on: event)
                if let placed = challenge.startDate { startDate = placed }
                weekdays = challenge.weekdaySet
                if let end = challenge.endDate {
                    endDate = end
                    hasEndDate = true
                } else if recurrence != .none {
                    hasEndDate = false
                }
            }
            challenge.groupIDs = ChallengeGroups.membership(chosen: groupID, eventGroup: eventGroup)
        } else if let current = ChallengeTimeStore.eventID(containing: challenge.id) {
            var members = ChallengeTimeStore.memberIDs(for: current)
            members.removeAll { $0 == challenge.id }
            ChallengeTimeStore.setMembers(members, for: current)
            challenge.groupIDs = ChallengeGroups.membership(chosen: groupID, eventGroup: nil)
        } else {
            challenge.groupIDs = ChallengeGroups.membership(chosen: groupID, eventGroup: nil)
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
            assignEvent(challenge)
        } else {
            ChallengeTimeStore.removeChallenge(challenge.id)
            challenge.groupIDs = ChallengeGroups.membership(chosen: groupID, eventGroup: nil)
        }
        if abstinence { syncToReminders = false }
        IconPreferenceStore.set(icon, for: challenge.id)
        ReminderSyncPreference.set(syncToReminders, for: challenge.id)
        EventOffer.set(offersEvents, for: challenge.id)
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
           ChallengeTimeRules.isAdopted(externalIdentifier) {
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
        let linkedEvent = linkedEventID.flatMap { id in formEvents.first { $0.id == id } }
        guard let externalIdentifier = await EventKitSyncService.saveReminder(
            externalIdentifier: challenge.externalIdentifier,
            title: challenge.title,
            notes: challenge.details,
            startDate: challenge.startDate ?? .now,
            endDate: challenge.endDate,
            recurrence: challenge.recurrence,
            recurrenceInterval: 1,
            weekdays: challenge.weekdaySet,
            includesTime: EventChallengeLink.reminderIncludesTime(allDay: linkedEvent?.isAllDay ?? true)
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
                        .background(selection.contains(day) ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(selection.contains(day) ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
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
                Section {
                    TextField(L("Titel", "Title"), text: $title)
                    TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                }
                .appGlassRow()
            }
            .appGlassList()
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
