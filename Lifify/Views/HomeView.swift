import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var entries: [LedgerEntry]
    @Query private var accounts: [Account]
    @Query private var holdings: [PortfolioHolding]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @Query private var rewards: [RewardItem]
    @State private var mode = ChallengeCalendarViewMode.day
    @State private var selectedDate = AppClock.now
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @State private var expandedWeekday: Date?
    @AppStorage("userName") private var userName = ""
    @AppStorage(UserProfile.birthKey) private var birthRaw = ""
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @AppStorage(StreakSettings.revisionKey) private var streakRevision = 0
    @AppStorage(AbstinenceSettings.revisionKey) private var abstinenceRevision = 0
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let _ = developerMode
                let _ = developerDay
                let _ = birthRaw
                if !userName.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.wave.fill")
                            .foregroundStyle(AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color())
                        Text("\(L("Willkommen zurück", "Welcome back")), \(userName)")
                            .appText(.screenTitle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .appGlassCard(radius: 20)
                }
                if let birth = UserProfile.birth(), BirthdayBonus.isBirthday(birth, on: AppClock.now) {
                    Label(
                        L(
                            "Alles Gute zum Geburtstag. 500 Coins liegen in der Wallet.",
                            "Happy birthday. 500 coins are in the wallet."
                        ),
                        systemImage: "gift.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .appGlassCard(radius: 16)
                }
                if developerMode {
                    Text("\(L("Simulierter Tag", "Simulated day")): \(AppDate.numeric(AppClock.now))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                noticeSection
                NavigationLink {
                    BudgetBreakdownView()
                } label: {
                    BudgetSummaryCard(
                        planned: budget.planned,
                        spent: budget.spent,
                        nextSalary: budget.nextSalary,
                        daysUntilSalary: daysUntilSalary,
                        dailyAllowance: dailyAllowance
                    )
                }
                .buttonStyle(.plain)

                Picker(L("Zeitraum", "Period"), selection: $mode) {
                    ForEach(ChallengeCalendarViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Button {
                        withAnimation { selectedDate = AppClock.now }
                    } label: {
                        Text(periodTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                }

                Group {
                    switch mode {
                    case .day:
                        dayView
                    case .week:
                        weekView
                    case .month:
                        monthView
                    }
                }

                periodBookings
            }
            .padding()
        }
        .appGlassCanvas()
        .onAppear {
            ChallengeService.commitFreezes(for: challenges, completions: completions, events: calendarEvents, on: AppClock.now)
            AbstinenceService.settle(context: context)
        }
        .onChange(of: developerDay) {
            guard developerMode else { return }
            selectedDate = AppClock.now
            ChallengeService.commitFreezes(for: challenges, completions: completions, events: calendarEvents, on: AppClock.now)
            AbstinenceService.settle(context: context)
        }
        .onChange(of: developerMode) {
            selectedDate = AppClock.now
            ChallengeService.commitFreezes(for: challenges, completions: completions, events: calendarEvents, on: AppClock.now)
            AbstinenceService.settle(context: context)
        }
    }

    private var dayView: some View {
        NavigationLink {
            ChallengeCalendarView(initialDate: selectedDate, initialMode: .day)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppDate.weekdayAndNumeric(selectedDate))
                        .appText(.value)
                    Spacer()
                    if AppClock.isToday(selectedDate) {
                        Text(L("Heute", "Today"))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red, in: Capsule())
                    }
                }
                Divider()
                let dayEvents = events(on: selectedDate)
                let dayChallenges = dueChallenges(on: selectedDate)
                if dayEvents.isEmpty && dayChallenges.isEmpty {
                    ContentUnavailableView(
                        L("Keine Einträge", "No entries"),
                        systemImage: "calendar",
                        description: Text(L("Tippe, um den Kalender zu öffnen.", "Tap to open the calendar."))
                    )
                } else {
                    agendaSection(L("Termine", "Events"), systemImage: "calendar", isEmpty: dayEvents.isEmpty) {
                        ForEach(dayEvents.prefix(5)) { event in
                            HStack {
                                Text(event.isAllDay ? L("Ganztägig", "All day") : AppDate.time(event.startDate))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 58, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Label(event.title, systemImage: event.icon)
                                    if let text = eventChallengeCaption(event) {
                                        Text(text)
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    agendaSection(L("Challenges", "Challenges"), systemImage: "target", isEmpty: dayChallenges.isEmpty) {
                        ForEach(dayChallenges.prefix(5)) { challenge in
                            HStack {
                                AppSymbolImage(name: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(challenge.title)
                                    if let caption = homeCalendarCaption(challenge) {
                                        Text(caption)
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                CoinAmountView(amount: challenge.rewardCoins, showsPlus: true)
                                    .font(.caption)
                                Image(systemName: ChallengeService.isCompleted(challenge, on: selectedDate, completions: completions) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ChallengeService.isCompleted(challenge, on: selectedDate, completions: completions) ? .green : .secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding()
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .appGlassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    private var weekView: some View {
        VStack(spacing: 7) {
            ForEach(ChallengeService.days(for: .week, around: selectedDate), id: \.timeIntervalSinceReferenceDate) { day in
                WeekDayCard(
                    day: day,
                    expanded: isExpanded(day),
                    eventCount: events(on: day).count,
                    challengeCount: dueChallenges(on: day).count,
                    onToggle: { toggleWeekday(day) }
                ) {
                    dayDetails(day)
                }
            }
        }
    }

    private func toggleWeekday(_ day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        if let expandedWeekday, Calendar.current.isDate(expandedWeekday, inSameDayAs: start) {
            self.expandedWeekday = nil
        } else {
            expandedWeekday = start
        }
    }

    private func isExpanded(_ day: Date) -> Bool {
        guard let expandedWeekday else { return false }
        return Calendar.current.isDate(expandedWeekday, inSameDayAs: day)
    }

    private func dayDetails(_ day: Date) -> some View {
        let dayEvents = events(on: day)
        let dayChallenges = dueChallenges(on: day)
        return VStack(alignment: .leading, spacing: 8) {
            if dayEvents.isEmpty && dayChallenges.isEmpty {
                Text(L("Keine Einträge", "No entries"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !dayEvents.isEmpty {
                Text(L("Termine", "Events"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(dayEvents) { event in
                    HStack {
                        Text(event.isAllDay ? L("Ganztägig", "All day") : AppDate.time(event.startDate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text(event.title)
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }
            if !dayChallenges.isEmpty {
                Text(L("Challenges", "Challenges"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(dayChallenges) { challenge in
                    HStack {
                        Text(challenge.title)
                        Spacer()
                        CoinAmountView(amount: challenge.rewardCoins, showsPlus: true)
                            .font(.caption)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var monthView: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(Array(AppDate.veryShortWeekdaysMondayFirst.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        NavigationLink {
                            ChallengeCalendarView(initialDate: date, initialMode: .day)
                        } label: {
                            VStack(spacing: 3) {
                                Text(AppDate.day(date))
                                    .font(.subheadline)
                                    .foregroundStyle(AppClock.isToday(date) ? .white : .primary)
                                    .frame(width: 28, height: 28)
                                    .background(AppClock.isToday(date) ? Color.red : .clear, in: Circle())
                                HStack(spacing: 2) {
                                    if !events(on: date).isEmpty {
                                        Circle().fill(.blue).frame(width: 4, height: 4)
                                    }
                                    if !dueChallenges(on: date).isEmpty {
                                        Circle().fill(.green).frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
            HStack(spacing: 14) {
                Label(L("Termine", "Events"), systemImage: "circle.fill").foregroundStyle(.blue)
                Label(L("Challenges", "Challenges"), systemImage: "circle.fill").foregroundStyle(.green)
                Spacer()
            }
            .font(.caption)
        }
        .padding(10)
        .appGlassCard(radius: 16)
    }

    @ViewBuilder
    private var noticeSection: some View {
        if homePopups.count >= 3 {
            combinedNoticeCard
        } else {
            ForEach(homePopups) { popup in
                popupCard(popup)
            }
        }
    }

    private var combinedNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Hinweise", "Notices"), systemImage: "bell.fill")
                .font(.headline)
            ForEach(homePopups) { popup in
                popupRows(popup)
            }
        }
        .padding()
        .appGlassCard(radius: 18)
    }

    private func popupCard(_ popup: HomePopup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch popup.kind {
            case .morning:
                Label(L("Heute abhaken?", "Check off today?"), systemImage: "sunrise.fill")
                    .font(.headline)
            case .reward:
                Label(L("Belohnung", "Reward"), systemImage: "gift.fill")
                    .font(.headline)
            case .freeze:
                Label(L("Streak-Freeze", "Streak freeze"), systemImage: "snowflake")
                    .font(.headline)
            case .abstinence:
                Label(L("Geschafft!", "You did it!"), systemImage: "lungs.fill")
                    .font(.headline)
            }
            popupRows(popup)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 18)
    }

    @ViewBuilder
    private func popupRows(_ popup: HomePopup) -> some View {
        switch popup.kind {
        case .morning(let items):
            ForEach(items, id: \.challenge.id) { item in
                Button {
                    ChallengeService.toggleCompletion(
                        challenge: item.challenge,
                        date: AppClock.now,
                        completions: completions,
                        transactions: transactions,
                        events: calendarEvents,
                        context: context
                    )
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.event.title).foregroundStyle(.primary)
                            Text(item.challenge.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        CoinAmountView(
                            amount: ChallengeService.projectedCoins(
                                challenge: item.challenge,
                                on: AppClock.now,
                                completions: completions,
                                events: calendarEvents
                            ),
                            showsPlus: true
                        )
                        .font(.caption)
                        if StreakSettings.isEnabled(for: item.challenge.id) {
                            let streak = ChallengeService.status(
                                for: item.challenge,
                                endingOn: AppClock.now,
                                completions: completions,
                                events: calendarEvents
                            ).count
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                Text("\(streak)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                        Image(systemName: "circle")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(.plain)
            }
        case .reward(let event, let reward, let days):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? reward.title : event.title)
                    Text(rewardDaysText(days))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CoinAmountView(amount: reward.price)
                    .font(.caption)
            }
        case .freeze(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.challenge.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.challenge.title)
                        Text(freezeWarning(done: item.done, required: item.required, recurrence: item.challenge.recurrence))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    ShopView()
                } label: {
                    Text(L("Im Shop kaufen", "Buy in the shop"))
                        .font(.subheadline.weight(.semibold))
                }
            }
        case .abstinence(let notices):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notices) { notice in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notice.title)
                                .foregroundStyle(.primary)
                            Text(abstinenceNoticeLine(notice))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if notice.coins > 0 {
                            CoinAmountView(amount: notice.coins, showsPlus: true)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func abstinenceNoticeLine(_ notice: AbstinenceNotice) -> String {
        guard let milestone = AbstinenceMilestone(rawValue: notice.milestone) else { return notice.milestone }
        return "\(milestone.label). \(AbstinenceCheer.line(for: milestone))"
    }

    private func freezeWarning(done: Int, required: Int, recurrence: ChallengeRecurrence) -> String {
        let when: String
        switch recurrence {
        case .daily: when = L("heute", "today")
        case .weekly: when = L("diese Woche", "this week")
        case .monthly: when = L("diesen Monat", "this month")
        case .yearly: when = L("dieses Jahr", "this year")
        case .none, .irregular: when = L("in diesem Zeitraum", "this period")
        }
        return "\(done)/\(required) \(when). \(L("Keine Streak-Freeze mehr. Kauf eine im Shop, sonst fällt die Serie am Ende auf 0.", "No streak freeze left. Buy one in the shop, or the streak drops to 0 at the end."))"
    }

    private func homeCalendarCaption(_ challenge: ChallengeItem) -> String? {
        let linked = ChallengeTimeStore.linkedEvents(for: challenge.id, in: calendarEvents)
        return LinkCaption.calendar(
            titles: linked.map(\.title),
            count: linked.count,
            singleDate: linked.count == 1 ? linked.first?.startDate : nil
        )
    }

    private func rewardDaysText(_ days: Int) -> String {
        if days == 0 { return L("Heute", "Today") }
        if days == 1 { return L("in 1 Tag", "in 1 day") }
        return "\(L("in", "in")) \(days) \(L("Tagen", "days"))"
    }

    private var homePopups: [HomePopup] {
        var popups: [HomePopup] = []
        if !morningChecks.isEmpty {
            popups.append(HomePopup(id: "morning", kind: .morning(morningChecks)))
        }
        for reminder in rewardReminders {
            popups.append(
                HomePopup(
                    id: "reward-\(reminder.event.id.uuidString)",
                    kind: .reward(reminder.event, reminder.reward, reminder.days)
                )
            )
        }
        if !freezeWarnings.isEmpty {
            popups.append(HomePopup(id: "freeze", kind: .freeze(freezeWarnings)))
        }
        let _ = abstinenceRevision
        let _ = developerDay
        let abstinenceNotices = AbstinenceRules.currentNotices(AbstinenceSettings.notices(), on: AppClock.now)
        if !abstinenceNotices.isEmpty {
            popups.append(HomePopup(id: "abstinence", kind: .abstinence(abstinenceNotices)))
        }
        return popups
    }

    private var freezeWarnings: [(challenge: ChallengeItem, done: Int, required: Int)] {
        let _ = streakRevision
        return challenges.compactMap { challenge in
            guard !challenge.isArchived else { return nil }
            let status = ChallengeService.status(
                for: challenge,
                endingOn: AppClock.now,
                completions: completions,
                events: calendarEvents
            )
            guard status.needsFreezeWarning else { return nil }
            return (challenge, status.done, status.required)
        }
    }

    private var rewardReminders: [(event: ChallengeCalendarEvent, reward: RewardItem, days: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: AppClock.now)
        return calendarEvents.compactMap { event in
            guard !event.isReminderSuggestion,
                  let rewardID = event.linkedRewardID,
                  let reward = rewards.first(where: { $0.id == rewardID })
            else {
                return nil
            }
            let start = calendar.startOfDay(for: event.startDate)
            guard let days = calendar.dateComponents([.day], from: today, to: start).day, days >= 0 else {
                return nil
            }
            let lead = reward.price >= 50 ? 10 : 5
            guard days <= lead else { return nil }
            return (event, reward, days)
        }
        .sorted { $0.days < $1.days }
    }

    private var morningChecks: [(event: ChallengeCalendarEvent, challenge: ChallengeItem)] {
        var seen: Set<UUID> = []
        return events(on: AppClock.now).flatMap { event -> [(event: ChallengeCalendarEvent, challenge: ChallengeItem)] in
            ChallengeTimeStore.challengeIDs(on: event.id, legacy: event.linkedChallengeID).compactMap { challengeID in
                guard seen.insert(challengeID).inserted,
                      let challenge = challenges.first(where: { $0.id == challengeID }),
                      !ChallengeService.isCompleted(challenge, on: AppClock.now, completions: completions)
                else { return nil }
                return (event, challenge)
            }
        }
    }

    private func eventChallengeCaption(_ event: ChallengeCalendarEvent) -> String? {
        let memberTitles = ChallengeTimeStore.memberIDs(for: event.id).compactMap { id in
            challenges.first(where: { $0.id == id })?.title
        }
        let sportTitle = event.linkedChallengeID.flatMap { id in
            challenges.first(where: { $0.id == id })?.title
        }
        return LinkCaption.challenges(memberTitles, fallback: sportTitle)
    }

    private var budget: HomeBudgetSnapshot {
        HomeBudget.make(
            entries: entries,
            accounts: accounts,
            forecasts: forecasts,
            variableBudgets: variableBudgets,
            pools: pools,
            splits: splits,
            dashboardPeriod: dashboardPeriod
        )
    }

    private var daysUntilSalary: Int? {
        guard let nextSalary = budget.nextSalary else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: nextSalary)
        ).day
    }

    private var dailyAllowance: Int? {
        let remaining = budget.remaining
        guard remaining > 0, let daysUntilSalary else { return nil }
        return remaining / max(daysUntilSalary, 1)
    }

    private var periodBookings: some View {
        let visible = Array(periodEntries.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Buchungen", "Transactions"))
                .font(.headline)
            if periodEntries.isEmpty {
                Text(L("Keine Buchungen in diesem Zeitraum", "No transactions in this period"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { entry in
                    HomeTransactionRow(entry: entry, accounts: accounts, holdings: holdings, ledgerEntries: entries)
                }
                if periodEntries.count > 5 {
                    NavigationLink {
                        PeriodTransactionsView(title: periodTitle, entries: periodEntries, accounts: accounts, holdings: holdings, ledgerEntries: entries)
                    } label: {
                        HStack {
                            Text(L("Alle anzeigen", "Show all"))
                            Spacer()
                            Text("\(periodEntries.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 18)
    }

    private var periodEntries: [LedgerEntry] {
        entries
            .filter { $0.date >= periodRange.start && $0.date < periodRange.end }
            .sorted { $0.date > $1.date }
    }

    private var periodRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        switch mode {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let days = ChallengeService.days(for: .week, around: selectedDate)
            let start = calendar.startOfDay(for: days.first ?? selectedDate)
            let last = calendar.startOfDay(for: days.last ?? selectedDate)
            return (start, calendar.date(byAdding: .day, value: 1, to: last)!)
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))
                ?? calendar.startOfDay(for: selectedDate)
            return (start, calendar.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    private var periodTitle: String {
        switch mode {
        case .day:
            return AppDate.weekdayAndNumeric(selectedDate)
        case .week:
            let days = ChallengeService.days(for: .week, around: selectedDate)
            return AppDate.range(from: days.first ?? selectedDate, to: days.last ?? selectedDate)
        case .month:
            return AppDate.monthYear(selectedDate)
        }
    }

    private var monthGrid: [Date?] {
        let calendar = Calendar.current
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let weekday = calendar.component(.weekday, from: first)
        let leading = weekday == 1 ? 6 : weekday - 2
        let days = calendar.range(of: .day, in: .month, for: first) ?? 1..<2
        return Array(repeating: nil, count: leading) + days.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: first)
        }
    }

    private func agendaSection<Content: View>(
        _ title: String,
        systemImage: String,
        isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if isEmpty {
                Text(L("Keine Einträge", "No entries"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func events(on day: Date) -> [ChallengeCalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return calendarEvents.filter {
            !$0.isReminderSuggestion && $0.startDate < end && $0.endDate >= start
        }
    }

    private func dueChallenges(on day: Date) -> [ChallengeItem] {
        challenges.filter { $0.category != .abstinence && ChallengeService.isDue($0, on: day) }
    }

    private func move(by value: Int) {
        let component: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        if let date = Calendar.current.date(byAdding: component, value: value, to: selectedDate) {
            withAnimation { selectedDate = date }
        }
    }
}

private struct BudgetSummaryCard: View {
    let planned: Int
    let spent: Int
    let nextSalary: Date?
    let daysUntilSalary: Int?
    let dailyAllowance: Int?
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    private var remaining: Int { planned - spent }
    private var accent: Color { AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color() }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(accent.opacity(0.22), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(remaining < 0 ? Color.red : accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(Money.string(cents: remaining))
                        .font(.caption.bold())
                        .foregroundStyle(remaining < 0 ? .red : .primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(remaining < 0 ? L("überzogen", "over") : L("offen", "left"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Budget", "Budget")).font(.headline)
                LabeledContent(L("Gesamt", "Total"), value: Money.string(cents: planned))
                LabeledContent(L("Verbraucht", "Spent"), value: Money.string(cents: spent))
                LabeledContent(L("Offen", "Remaining"), value: Money.string(cents: remaining))
                if let nextSalary, let daysUntilSalary {
                    Text(salaryText(date: nextSalary, days: daysUntilSalary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dailyAllowance {
                    Text("\(L("Pro Tag", "Per day")): \(Money.string(cents: dailyAllowance))")
                        .font(.caption.bold())
                }
            }
        }
        .padding()
        .appGlassCard(radius: 22)
    }

    private var progress: Double {
        guard planned > 0 else { return spent > 0 ? 1 : 0 }
        return min(Double(spent) / Double(planned), 1)
    }

    private func salaryText(date: Date, days: Int) -> String {
        let day = Calendar.current.component(.day, from: date)
        let month = Calendar.current.component(.month, from: date)
        let shortDate = String(format: "%02d.%02d.", day, month)
        let phrase = days == 1
            ? L("Nächstes Gehalt in 1 Tag", "Next salary in 1 day")
            : "\(L("Nächstes Gehalt in", "Next salary in")) \(days) \(L("Tagen", "days"))"
        return "\(phrase) (\(shortDate))"
    }
}

private struct HomePopup: Identifiable {
    enum Kind {
        case morning([(event: ChallengeCalendarEvent, challenge: ChallengeItem)])
        case reward(ChallengeCalendarEvent, RewardItem, Int)
        case freeze([(challenge: ChallengeItem, done: Int, required: Int)])
        case abstinence([AbstinenceNotice])
    }

    let id: String
    let kind: Kind
}

private struct HomeTransactionRow: View {
    let entry: LedgerEntry
    var accounts: [Account] = []
    var holdings: [PortfolioHolding] = []
    var ledgerEntries: [LedgerEntry] = []

    var body: some View {
        let category = BookingClassification.category(of: entry, accounts: accounts, viewedAccountID: nil)
        let signed = BookingClassification.signedAmount(of: entry, category: category, viewedAccountID: nil)
        let difference = category == .portfolioSale
            ? HoldingMaintenance.saleEconomics(for: entry, holdings: holdings)?.differenceCents
            : (category == .expense ? RefundLinkStore.realExpenseCents(of: entry, entries: ledgerEntries) : nil)
        let paint = BookingClassification.paint(
            category: category,
            signed: signed,
            scope: .combined,
            differenceCents: difference
        )
        HStack(spacing: 10) {
            Image(systemName: category.systemImage)
                .frame(width: 22)
                .foregroundStyle(paint.iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(category.label) · \(AppDate.numeric(entry.date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BookingAmountStack(
                amount: signed,
                amountColor: paint.amountColor,
                difference: paint.differenceCents,
                amountFont: .subheadline,
                differenceFont: .caption2
            )
        }
        .font(.subheadline)
    }
}

private struct PeriodTransactionsView: View {
    let title: String
    let entries: [LedgerEntry]
    var accounts: [Account] = []
    var holdings: [PortfolioHolding] = []
    var ledgerEntries: [LedgerEntry] = []

    var body: some View {
        List(entries) { entry in
            HomeTransactionRow(entry: entry, accounts: accounts, holdings: holdings, ledgerEntries: ledgerEntries)
        }
        .appGlassList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Array where Element == String {
    var shiftedForMonday: [String] {
        guard count == 7 else { return self }
        return Array(self[1...]) + [self[0]]
    }
}

private struct WeekDayCard<Details: View>: View {
    let day: Date
    let expanded: Bool
    let eventCount: Int
    let challengeCount: Int
    let onToggle: () -> Void
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 0) {
            Button {
                Task { @MainActor in
                    onToggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack {
                        Text(AppDate.weekdayShort(day))
                            .font(.caption)
                        Text(AppDate.day(day))
                            .appText(.value)
                            .foregroundStyle(AppClock.isToday(day) ? .red : .primary)
                    }
                    .frame(width: 44)
                    Divider()
                    Label("\(eventCount)", systemImage: "calendar")
                    Label("\(challengeCount)", systemImage: "target")
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(WeekToggleButtonStyle())
            Group {
                if expanded {
                    details()
                }
            }
            .animation(.easeInOut(duration: 0.22), value: expanded)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(radius: 13)
    }
}

private struct WeekToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
