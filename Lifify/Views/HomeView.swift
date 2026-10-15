import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var transactions: [CoinTransaction]
    @Query private var rewards: [RewardItem]
    @State private var mode = ChallengeCalendarViewMode.day
    @State private var selectedDate = Date.now
    @State private var expandedWeekday: Date?
    @AppStorage("userName") private var userName = ""
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !userName.isEmpty {
                    Text("\(L("Willkommen zurück", "Welcome back")), \(userName)")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                noticeSection
                NavigationLink {
                    DashboardView()
                } label: {
                    BudgetSummaryCard(
                        planned: plannedBudget,
                        spent: spentBudget,
                        nextSalary: nextSalaryDate,
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
                        withAnimation { selectedDate = .now }
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
        .appCanvas()
    }

    private var dayView: some View {
        NavigationLink {
            ChallengeCalendarView(initialDate: selectedDate, initialMode: .day)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppDate.weekdayAndNumeric(selectedDate))
                        .font(.title3.bold())
                    Spacer()
                    if Calendar.current.isDateInToday(selectedDate) {
                        Text(L("Heute", "Today"))
                            .font(.caption.bold())
                            .foregroundStyle(.red)
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
                                Label(event.title, systemImage: event.icon)
                                Spacer()
                                if event.linkedChallengeID != nil {
                                    Image(systemName: "target").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    agendaSection(L("Challenges", "Challenges"), systemImage: "target", isEmpty: dayChallenges.isEmpty) {
                        ForEach(dayChallenges.prefix(5)) { challenge in
                            HStack {
                                Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                                Text(challenge.title)
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
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var weekView: some View {
        VStack(spacing: 7) {
            ForEach(ChallengeService.days(for: .week, around: selectedDate), id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation {
                            if isExpanded(day) {
                                expandedWeekday = nil
                            } else {
                                expandedWeekday = day
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack {
                                Text(AppDate.weekdayShort(day))
                                    .font(.caption)
                                Text(AppDate.day(day))
                                    .font(.title3.bold())
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? .red : .primary)
                            }
                            .frame(width: 44)
                            Divider()
                            Label("\(events(on: day).count)", systemImage: "calendar")
                            Label("\(dueChallenges(on: day).count)", systemImage: "target")
                            Spacer()
                            Image(systemName: isExpanded(day) ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if isExpanded(day) {
                        dayDetails(day)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 13))
            }
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
                                    .foregroundStyle(Calendar.current.isDateInToday(date) ? .white : .primary)
                                    .frame(width: 28, height: 28)
                                    .background(Calendar.current.isDateInToday(date) ? Color.red : .clear, in: Circle())
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
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16))
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
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 18))
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
            }
            popupRows(popup)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func popupRows(_ popup: HomePopup) -> some View {
        switch popup.kind {
        case .morning(let items):
            ForEach(items, id: \.event.id) { item in
                Button {
                    ChallengeService.toggleCompletion(
                        challenge: item.challenge,
                        date: .now,
                        completions: completions,
                        transactions: transactions,
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
                        CoinAmountView(amount: item.challenge.rewardCoins, showsPlus: true)
                            .font(.caption)
                        if item.challenge.recurrence != .none {
                            let streak = ChallengeService.streak(
                                for: item.challenge,
                                endingOn: .now,
                                completions: completions
                            )
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
        }
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
        return popups
    }

    private var rewardReminders: [(event: ChallengeCalendarEvent, reward: RewardItem, days: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
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
        events(on: .now).compactMap { event in
            guard let challengeID = event.linkedChallengeID,
                  let challenge = challenges.first(where: { $0.id == challengeID }),
                  !ChallengeService.isCompleted(challenge, on: .now, completions: completions)
            else {
                return nil
            }
            return (event, challenge)
        }
    }

    private var plannedBudget: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.startOfDay(for: budgetPeriodStart)
        let periodIncome = entries.filter {
            $0.kind == .income && $0.date >= start && $0.date <= budgetPeriodEnd
        }
        let booked = periodIncome.reduce(0) { $0 + abs($1.amountCents) }
        let bookedFromToday = periodIncome.filter { $0.date >= today }.reduce(0) { $0 + abs($1.amountCents) }
        let upcoming = forecasts.filter(\.isActive).reduce(0) { total, forecast in
            total + upcomingAmount(of: forecast, from: today)
        }
        return booked + max(0, upcoming - bookedFromToday)
    }

    private func upcomingAmount(of forecast: IncomeForecast, from today: Date) -> Int {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: budgetPeriodEnd)
        return CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: budgetPeriodEnd
        )
        .filter {
            let day = calendar.startOfDay(for: $0)
            return day >= today && day <= end
        }
        .count * abs(forecast.amountCents)
    }

    private var spentBudget: Int {
        if forecasts.contains(where: \.isActive) {
            return entries
                .filter { $0.kind == .expense && $0.date >= budgetPeriodStart && $0.date <= .now }
                .reduce(0) { $0 + abs($1.amountCents) }
        }
        let variable = variableBudgets.reduce(0) {
            $0 + FinanceService.variableSpent(budgetID: $1.id, monthKey: Date.now.monthKey, entries: entries, splits: splits)
        }
        let pool = pools.filter(\.isActive).reduce(0) {
            let key = CalendarService.periodKey(for: .now, pool: $1)
            return $0 + FinanceService.poolSpent(pool: $1, periodKey: key, splits: splits)
        }
        return variable + pool
    }

    private var primaryForecast: IncomeForecast? {
        guard let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString)
        else {
            return forecasts.first(where: \.isActive)
        }
        return forecasts.first { $0.id == id } ?? forecasts.first(where: \.isActive)
    }

    private var nextSalaryDate: Date? {
        guard let forecast = primaryForecast,
              let limit = Calendar.current.date(byAdding: .year, value: 2, to: .now)
        else {
            return nil
        }
        let today = Calendar.current.startOfDay(for: .now)
        return CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: limit
        )
        .first { Calendar.current.startOfDay(for: $0) > today }
    }

    private var daysUntilSalary: Int? {
        guard let nextSalaryDate else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: nextSalaryDate)
        ).day
    }

    private var dailyAllowance: Int? {
        let remaining = plannedBudget - spentBudget
        guard remaining > 0, let daysUntilSalary else { return nil }
        return remaining / max(daysUntilSalary, 1)
    }

    private var budgetPeriodStart: Date {
        let calendar = Calendar.current
        guard DashboardPeriodMode(rawValue: dashboardPeriod) == .salaryPeriod,
              let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString),
              let forecast = forecasts.first(where: { $0.id == id })
        else {
            return calendar.date(
                from: calendar.dateComponents([.year, .month], from: .now)
            ) ?? calendar.startOfDay(for: .now)
        }
        let now = Date.now
        let occurrences = CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: now
        )
        if let latest = occurrences.last(where: { $0 <= now }) {
            return latest
        }
        let current = calendar.dateComponents([.year, .month], from: now)
        let candidate = CalendarService.dueDate(
            year: current.year ?? calendar.component(.year, from: now),
            month: current.month ?? calendar.component(.month, from: now),
            day: forecast.dayOfMonth,
            rule: forecast.dueRule
        )
        if candidate <= now { return candidate }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = calendar.dateComponents([.year, .month], from: previousMonth)
        return CalendarService.dueDate(
            year: previous.year ?? calendar.component(.year, from: previousMonth),
            month: previous.month ?? calendar.component(.month, from: previousMonth),
            day: forecast.dayOfMonth,
            rule: forecast.dueRule
        )
    }

    private var budgetPeriodEnd: Date {
        let calendar = Calendar.current
        let fallback = calendar.date(byAdding: .month, value: 1, to: budgetPeriodStart)
            .flatMap { calendar.date(byAdding: .second, value: -1, to: $0) }
            ?? budgetPeriodStart
        guard DashboardPeriodMode(rawValue: dashboardPeriod) == .salaryPeriod,
              let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString),
              let forecast = forecasts.first(where: { $0.id == id }),
              let limit = calendar.date(byAdding: .year, value: 2, to: budgetPeriodStart)
        else {
            return fallback
        }
        let nextOccurrence = CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: limit
        )
        .first { $0 > budgetPeriodStart }
        guard let nextOccurrence else { return fallback }
        return calendar.date(byAdding: .second, value: -1, to: nextOccurrence) ?? fallback
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
                    HomeTransactionRow(entry: entry)
                }
                if periodEntries.count > 5 {
                    NavigationLink {
                        PeriodTransactionsView(title: periodTitle, entries: periodEntries)
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
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 18))
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
        challenges.filter { ChallengeService.isDue($0, on: day) }
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

    private var remaining: Int { planned - spent }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.gray.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(remaining < 0 ? .red : .blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
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
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 22))
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
    }

    let id: String
    let kind: Kind
}

private struct HomeTransactionRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(AppDate.numeric(entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: entry.kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents)))
                .foregroundStyle(entry.kind == .expense ? .red : (entry.kind == .income ? .green : .primary))
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct PeriodTransactionsView: View {
    let title: String
    let entries: [LedgerEntry]

    var body: some View {
        List(entries) { entry in
            HomeTransactionRow(entry: entry)
        }
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
