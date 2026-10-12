import SwiftData
import SwiftUI

struct DashboardView: View {
    let isMainTab: Bool
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var holdings: [PortfolioHolding]
    @Query private var fixedCosts: [FixedCost]
    @Query private var forecasts: [IncomeForecast]
    @Query private var variableBudgets: [VariableBudget]
    @Query private var splits: [TransactionSplit]
    @Query(sort: \ShoppingItem.createdAt, order: .reverse) private var shopping: [ShoppingItem]
    @State private var selectedPeriodID: String?

    init(isMainTab: Bool = false) {
        self.isMainTab = isMainTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let period = selectedPeriod {
                    periodBar(period)
                    let snapshot = forecast(for: period)
                    netWorthCard(snapshot, period: period)
                    LazyVGrid(columns: columns, spacing: 12) {
                        flowTile(L("Einnahmen", "Income"), amount: snapshot.income, footnote: incomeFootnote(snapshot, period: period))
                        flowTile(L("Ausgaben", "Expenses"), amount: -snapshot.expenses, footnote: expenseFootnote(snapshot, period: period))
                    }
                    flowTile(
                        L("Differenz", "Difference"),
                        amount: snapshot.difference,
                        footnote: L("Einnahmen minus Ausgaben", "Income minus expenses")
                    )
                    LazyVGrid(columns: columns, spacing: 12) {
                        balanceTile(L("Startsaldo", "Opening balance"), amount: snapshot.startBalance)
                        balanceTile(
                            L("Endsaldo", "Closing balance"),
                            amount: snapshot.endBalance,
                            delta: snapshot.balanceChange
                        )
                        flowTile(L("Verbleibende Fixkosten", "Remaining fixed costs"), amount: -snapshot.remainingFixed)
                        flowTile(L("Verbleibende variable Kosten", "Remaining variable costs"), amount: -snapshot.remainingVariable)
                    }
                    biasCard(snapshot)
                    eventsSection(snapshot)
                } else {
                    ContentUnavailableView(
                        L("Noch kein Zeitraum", "No period yet"),
                        systemImage: "calendar",
                        description: Text(L(
                            "Lege ein Konto und eine Haupteinnahme an.",
                            "Create an account and a primary income."
                        ))
                    )
                }
                accountsSection
                if isMainTab { sections }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("Finanzen", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func periodBar(_ period: ForecastPeriod) -> some View {
        HStack(spacing: 8) {
            Button { shiftPeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .disabled(periodIndex == 0)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(AppDate.range(from: period.start, to: period.end))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Button(L("Heute", "Today")) { jumpToToday() }
                    .font(.caption.weight(.semibold))
                    .disabled(period.contains(.now))
            }
            Spacer(minLength: 0)
            Button { shiftPeriod(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(periodIndex == periods.count - 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func netWorthCard(_ forecast: PeriodForecast, period: ForecastPeriod) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Gesamtvermögen", "Net worth"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.string(cents: forecast.netWorth))
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(netWorthCaption(period))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func biasCard(_ forecast: PeriodForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Bias (angewendet / geplant)", "Bias (applied / planned)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Angewendet", "Applied"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: forecast.biasApplied))
                        .font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Geplant", "Planned"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Money.signed(cents: forecast.biasPlanned))
                        .font(.headline)
                        .foregroundStyle(forecast.biasPlanned > 0 ? .orange : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func eventsSection(_ forecast: PeriodForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ereignisse", "Events"))
                .font(.headline)
            if forecast.events.isEmpty {
                Text(L("In diesem Zeitraum liegen keine Ereignisse.", "There are no events in this period."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let rows = runningTotals(forecast.events)
                ForEach(rows, id: \.line.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.line.title)
                                .lineLimit(1)
                            Text(AppDate.numeric(row.line.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.signed(cents: row.line.amountCents))
                                .foregroundStyle(flowColor(row.line.amountCents))
                            Text(Money.signed(cents: row.subtotal))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Konten", "Accounts"))
                .font(.headline)
            if accounts.filter({ $0.kind != .savingsGroup }).isEmpty {
                Text(L("Noch keine Konten.", "No accounts yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts.filter { $0.kind != .savingsGroup }) { account in
                HStack {
                    Label(account.name, systemImage: icon(for: account.kind))
                    Spacer()
                    Text(Money.string(cents: FinanceService.balance(for: account, entries: entries, holdings: holdings)))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLink(L("Buchungen", "Transactions"), systemImage: "list.bullet.rectangle") { TransactionsView() }
            sectionLink(L("Fixkosten", "Fixed costs"), systemImage: "repeat") { FixedCostsView() }
            sectionLink(L("Variable Kosten", "Variable costs"), systemImage: "gauge.with.dots.needle.67percent") { VariableBudgetsView() }
            sectionLink(L("Budgetpools", "Budget pools"), systemImage: "tray.full") { BudgetPoolsView() }
            sectionLink(L("Einnahmeprognosen", "Income forecasts"), systemImage: "calendar.badge.plus") { IncomeForecastsView() }
            sectionLink(L("Einkaufszettel", "Shopping list"), systemImage: "cart") { ShoppingListView() }
            sectionLink(L("Schulden", "Debts"), systemImage: "person.2") { DebtsView() }
            sectionLink(L("Ausgabengruppen", "Expense groups"), systemImage: "square.stack.3d.up") { ExpenseGroupsView() }
            sectionLink(L("Depot", "Portfolio"), systemImage: "chart.line.uptrend.xyaxis") { PortfolioView() }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionLink<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func flowTile(_ title: String, amount: Int, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(Money.signed(cents: amount))
                .font(.headline)
                .foregroundStyle(flowColor(amount))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func balanceTile(_ title: String, amount: Int, delta: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Money.string(cents: amount))
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let delta {
                Text(Money.signed(cents: delta))
                    .font(.caption2)
                    .foregroundStyle(flowColor(delta))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var periods: [ForecastPeriod] {
        let earliest = entries.map(\.date).min() ?? .now
        let latest = Calendar.current.date(byAdding: .month, value: 18, to: .now) ?? .now
        return FinanceService.forecastPeriods(primary: primaryForecast, earliest: earliest, latest: latest)
    }

    private var selectedPeriod: ForecastPeriod? {
        if let selectedPeriodID, let match = periods.first(where: { $0.id == selectedPeriodID }) {
            return match
        }
        return periods.first { $0.contains(.now) } ?? periods.last
    }

    private var periodIndex: Int? {
        guard let selectedPeriod else { return nil }
        return periods.firstIndex(of: selectedPeriod)
    }

    private var primaryForecast: IncomeForecast? {
        guard let id = UserDefaults.standard.string(forKey: "primaryIncomeForecastID").flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return forecasts.first { $0.id == id }
    }

    private func forecast(for period: ForecastPeriod) -> PeriodForecast {
        FinanceService.periodForecast(
            period: period,
            periods: periods,
            accounts: accounts,
            entries: entries,
            holdings: holdings,
            fixedCosts: fixedCosts,
            variableBudgets: variableBudgets,
            splits: splits,
            forecasts: forecasts,
            shopping: shopping
        )
    }

    private func shiftPeriod(_ delta: Int) {
        guard let index = periodIndex else { return }
        let next = index + delta
        guard periods.indices.contains(next) else { return }
        withAnimation { selectedPeriodID = periods[next].id }
    }

    private func jumpToToday() {
        withAnimation { selectedPeriodID = periods.first { $0.contains(.now) }?.id }
    }

    private func incomeFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now) else { return nil }
        return "\(L("Offen", "Open")) \(Money.signed(cents: forecast.openIncome))"
    }

    private func expenseFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now), forecast.bookedExpenses > 0 else { return nil }
        return "\(L("Bereits", "Already")) \(Money.string(cents: forecast.bookedExpenses))"
    }

    private func netWorthCaption(_ period: ForecastPeriod) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        if period.contains(today) { return L("Heute", "Today") }
        if period.end < today { return L("Zum Periodenende", "At period end") }
        return L("Prognose zum Periodenende", "Forecast at period end")
    }

    private func runningTotals(_ lines: [ForecastLine]) -> [(line: ForecastLine, subtotal: Int)] {
        var sum = 0
        return lines.map { line in
            sum += line.amountCents
            return (line, sum)
        }
    }

    private func flowColor(_ cents: Int) -> Color {
        if cents > 0 { return .green }
        if cents < 0 { return .red }
        return .primary
    }

    private func icon(for kind: AccountKind) -> String {
        switch kind {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .savingsGroup: "folder"
        case .portfolio: "chart.line.uptrend.xyaxis"
        }
    }
}
