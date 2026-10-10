import SwiftData
import SwiftUI

struct HomeView: View {
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @State private var mode = ChallengeCalendarViewMode.day
    @State private var selectedDate = Date.now

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink {
                    DashboardView()
                } label: {
                    BudgetSummaryCard(planned: plannedBudget, spent: spentBudget)
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
                .frame(minHeight: 310, alignment: .top)

                HStack(spacing: 12) {
                    NavigationLink {
                        TransactionsView()
                    } label: {
                        HomeShortcut(title: L("Buchung", "Transaction"), icon: "plus.circle.fill", color: .blue)
                    }
                    NavigationLink {
                        ChallengesView()
                    } label: {
                        HomeShortcut(title: L("Challenge", "Challenge"), icon: "checkmark.circle.fill", color: .green)
                    }
                    NavigationLink {
                        ShopView()
                    } label: {
                        HomeShortcut(title: L("Shop", "Shop"), icon: "gift.fill", color: .orange)
                    }
                }
            }
            .padding()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width < -60 { move(by: 1) }
                if value.translation.width > 60 { move(by: -1) }
            }
        )
    }

    private var dayView: some View {
        NavigationLink {
            ChallengeCalendarView(initialDate: selectedDate, initialMode: .day)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedDate, format: .dateTime.weekday(.wide).day().month().year())
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
                }
                ForEach(dayEvents.prefix(5)) { event in
                    HStack {
                        Text(event.isAllDay ? L("Ganztägig", "All day") : event.startDate.formatted(.dateTime.hour().minute()))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Label(event.title, systemImage: event.icon)
                        Spacer()
                    }
                }
                ForEach(dayChallenges.prefix(5)) { challenge in
                    HStack {
                        Image(systemName: ChallengeService.isCompleted(challenge, on: selectedDate, completions: completions) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ChallengeService.isCompleted(challenge, on: selectedDate, completions: completions) ? .green : .secondary)
                        Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "target"))
                        Text(challenge.title)
                        Spacer()
                        Text("+\(challenge.rewardCoins) 🪙")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding()
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var weekView: some View {
        VStack(spacing: 7) {
            ForEach(ChallengeService.days(for: .week, around: selectedDate), id: \.self) { day in
                NavigationLink {
                    ChallengeCalendarView(initialDate: day, initialMode: .day)
                } label: {
                    HStack(spacing: 12) {
                        VStack {
                            Text(day, format: .dateTime.weekday(.abbreviated))
                                .font(.caption)
                            Text(day, format: .dateTime.day())
                                .font(.title3.bold())
                                .foregroundStyle(Calendar.current.isDateInToday(day) ? .red : .primary)
                        }
                        .frame(width: 44)
                        Divider()
                        Label("\(events(on: day).count)", systemImage: "calendar")
                        Label("\(dueChallenges(on: day).count)", systemImage: "target")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Calendar.current.isDateInToday(day) ? Color.red.opacity(0.09) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthView: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(Calendar.current.veryShortWeekdaySymbols.shiftedForMonday, id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        NavigationLink {
                            ChallengeCalendarView(initialDate: date, initialMode: .day)
                        } label: {
                            VStack(spacing: 3) {
                                Text(date, format: .dateTime.day())
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
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var plannedBudget: Int {
        variableBudgets.reduce(0) { $0 + $1.monthlyAmountCents } +
        pools.filter(\.isActive).reduce(0) { $0 + $1.amountCents }
    }

    private var spentBudget: Int {
        let variable = variableBudgets.reduce(0) {
            $0 + FinanceService.variableSpent(budgetID: $1.id, monthKey: Date.now.monthKey, entries: entries, splits: splits)
        }
        let pool = pools.filter(\.isActive).reduce(0) {
            let key = CalendarService.periodKey(for: .now, pool: $1)
            return $0 + FinanceService.poolSpent(pool: $1, periodKey: key, splits: splits)
        }
        return variable + pool
    }

    private var periodTitle: String {
        switch mode {
        case .day:
            return selectedDate.formatted(.dateTime.day().month(.wide).year())
        case .week:
            let days = ChallengeService.days(for: .week, around: selectedDate)
            return "\(days.first?.formatted(.dateTime.day().month()) ?? "") – \(days.last?.formatted(.dateTime.day().month().year()) ?? "")"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
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

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.gray.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(Double(spent) / Double(max(planned, 1)), 1))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(Money.string(cents: max(planned - spent, 0))).font(.caption.bold())
                    Text(L("offen", "left")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Budget", "Budget")).font(.headline)
                LabeledContent(L("Verbraucht", "Spent"), value: Money.string(cents: spent))
                LabeledContent(L("Offen", "Remaining"), value: Money.string(cents: planned - spent))
                LabeledContent(L("Gesamt", "Total"), value: Money.string(cents: planned))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct HomeShortcut: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension Array where Element == String {
    var shiftedForMonday: [String] {
        guard count == 7 else { return self }
        return Array(self[1...]) + [self[0]]
    }
}
