import SwiftData
import SwiftUI

struct HomeView: View {
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var lifeEvents: [LifeCalendarEvent]
    @Query private var challenges: [LifeChallenge]
    @Query private var completions: [ChallengeCompletion]
    @State private var mode = LifeCalendarViewMode.day
    @State private var selectedDate = Date.now

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                NavigationLink {
                    DashboardView()
                } label: {
                    BudgetSummaryCard(
                        planned: plannedBudget,
                        spent: spentBudget
                    )
                }
                .buttonStyle(.plain)

                Picker(L("Zeitraum", "Period"), selection: $mode) {
                    ForEach(LifeCalendarViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(periodTitle(selectedDate))
                        .font(.headline)
                    Spacer()
                    Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                }

                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(periodDates.enumerated()), id: \.offset) { index, date in
                        NavigationLink {
                            LifeCalendarView(initialDate: date, initialMode: mode)
                        } label: {
                            HomePeriodColumn(
                                title: columnTitle(index: index, date: date),
                                date: date,
                                eventCount: eventCount(for: date),
                                challengeCount: challengeCount(for: date)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 260)

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
        .navigationTitle(L("Home", "Home"))
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width < -60 { move(by: 1) }
                if value.translation.width > 60 { move(by: -1) }
            }
        )
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

    private var periodDates: [Date] {
        [-1, 0, 1].compactMap { offsetDate(selectedDate, by: $0) }
    }

    private func offsetDate(_ date: Date, by value: Int) -> Date? {
        switch mode {
        case .day: Calendar.current.date(byAdding: .day, value: value, to: date)
        case .week: Calendar.current.date(byAdding: .weekOfYear, value: value, to: date)
        case .month: Calendar.current.date(byAdding: .month, value: value, to: date)
        }
    }

    private func move(by value: Int) {
        if let date = offsetDate(selectedDate, by: value) {
            withAnimation { selectedDate = date }
        }
    }

    private func periodTitle(_ date: Date) -> String {
        switch mode {
        case .day:
            return date.formatted(date: .complete, time: .omitted)
        case .week:
            let days = LiveLifeService.days(for: .week, around: date)
            return "\(days.first?.formatted(.dateTime.day().month()) ?? "") – \(days.last?.formatted(.dateTime.day().month().year()) ?? "")"
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func columnTitle(index: Int, date: Date) -> String {
        if mode == .day {
            return [L("Gestern", "Yesterday"), L("Heute", "Today"), L("Morgen", "Tomorrow")][index]
        }
        return periodTitle(date)
    }

    private func dates(in periodDate: Date) -> [Date] {
        LiveLifeService.days(for: mode, around: periodDate)
    }

    private func eventCount(for periodDate: Date) -> Int {
        let days = dates(in: periodDate)
        return lifeEvents.filter { event in days.contains { Calendar.current.isDate($0, inSameDayAs: event.startDate) } }.count
    }

    private func challengeCount(for periodDate: Date) -> Int {
        let days = dates(in: periodDate)
        return days.reduce(0) { partial, day in
            partial + challenges.filter {
                LiveLifeService.isDue($0, on: day) &&
                !LiveLifeService.isCompleted($0, on: day, completions: completions)
            }.count
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

private struct HomePeriodColumn: View {
    let title: String
    let date: Date
    let eventCount: Int
    let challengeCount: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.caption.bold()).lineLimit(2)
            Text(date, format: .dateTime.day().month())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Label("\(eventCount)", systemImage: "calendar")
            Label("\(challengeCount)", systemImage: "target")
            Spacer()
            Image(systemName: "chevron.right.circle")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Calendar.current.isDateInToday(date) ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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
