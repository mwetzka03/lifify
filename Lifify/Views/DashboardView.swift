import SwiftData
import SwiftUI

struct DashboardView: View {
    let isMainTab: Bool
    var path: Binding<NavigationPath>?
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var holdings: [PortfolioHolding]
    @Query private var fixedCosts: [FixedCost]
    @Query private var forecasts: [IncomeForecast]
    @Query private var variableBudgets: [VariableBudget]
    @Query private var splits: [TransactionSplit]
    @Query(sort: \ShoppingItem.createdAt, order: .reverse) private var shopping: [ShoppingItem]
    @EnvironmentObject private var filters: FinanceFilterStore

    init(isMainTab: Bool = false, path: Binding<NavigationPath>? = nil) {
        self.isMainTab = isMainTab
        self.path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let period = selectedPeriod {
                    FinanceFilterControls(periods: periods, accounts: filterAccounts)
                    let snapshot = presented(forecast(for: period))
                    netWorthCard(snapshot, period: period)
                    if selectedFilterAccount?.kind == .portfolio {
                        PortfolioElementsView(accountID: selectedFilterAccount?.id)
                    } else {
                        let liquid = selectedFilterAccount == nil ? liquidForecast(for: period) : nil
                        HStack(alignment: .top, spacing: 8) {
                            linked(.income) {
                                flowTile(L("Einnahmen", "Income"), amount: snapshot.income, footnote: incomeFootnote(snapshot, period: period))
                            }
                            linked(.expenses) {
                                flowTile(L("Ausgaben", "Expenses"), amount: -snapshot.bookedExpenses, footnote: expenseFootnote(snapshot, period: period))
                            }
                            flowTile(L("Differenz", "Difference"), amount: snapshot.realDifference)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            balanceTile(
                                L("Startsaldo", "Opening balance"),
                                amount: snapshot.startBalance,
                                liquid: liquid?.startBalance
                            )
                            balanceTile(
                                L("Endsaldo (Prognose)", "Closing balance (forecast)"),
                                amount: snapshot.endBalance,
                                delta: snapshot.balanceChange,
                                liquid: liquid?.endBalance
                            )
                        }
                        HStack(alignment: .top, spacing: 8) {
                            linked(.fixedCosts) {
                                flowTile(
                                    L("Fixkosten", "Fixed costs"),
                                    amount: -snapshot.bookedFixed,
                                    footnote: openFootnote(snapshot.remainingFixed, period: period)
                                )
                            }
                            linked(.variableCosts) {
                                flowTile(
                                    L("Variable Kosten", "Variable costs"),
                                    amount: -snapshot.bookedVariable,
                                    footnote: openFootnote(snapshot.remainingVariable, period: period)
                                )
                            }
                        }
                        linked(.shopping) { biasCard(snapshot) }
                    }
                    if isMainTab { FinanceMoreSection(path: path) }
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
                    if isMainTab { FinanceMoreSection(path: path) }
                }
            }
            .padding(12)
        }
        .appCanvas()
        .toolbar(isMainTab ? .hidden : .automatic, for: .navigationBar)
        .navigationTitle(isMainTab ? "" : L("Finanzen", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(FinanceDestinationRegistration(isEnabled: path == nil))
    }

    private func linked<Label: View>(_ route: FinanceRoute, @ViewBuilder label: () -> Label) -> some View {
        Group {
            if let path {
                Button {
                    path.wrappedValue.append(route)
                } label: {
                    label()
                }
            } else {
                NavigationLink(value: route, label: label)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func netWorthCard(_ forecast: PeriodForecast, period: ForecastPeriod) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Gesamtvermögen", "Net worth"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(Money.string(cents: forecast.netWorth))
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(netWorthCaption(period))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .financeCard()
    }

    private func biasCard(_ forecast: PeriodForecast) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Einkaufszettel", "Shopping list"))
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Angewendet", "Applied"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: forecast.biasApplied))
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Geplant", "Planned"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.signed(cents: forecast.biasPlanned))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(forecast.biasPlanned > 0 ? .orange : .primary)
                }
            }
        }
        .financeCard(padding: 12)
    }

    private func eventsSection(_ forecast: PeriodForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Ereignisse", "Events"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Group {
                    if let path {
                        Button(L("Alle", "All")) { path.wrappedValue.append(FinanceRoute.transactions) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: FinanceRoute.transactions) {
                            Text(L("Alle", "All"))
                        }
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            if forecast.events.isEmpty {
                Text(L("In diesem Zeitraum liegen keine Ereignisse.", "There are no events in this period."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                let rows = Array(runningTotals(forecast.events).reversed())
                ForEach(rows, id: \.line.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.line.title)
                                .lineLimit(1)
                            Text(AppDate.numeric(row.line.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.signed(cents: row.line.amountCents))
                                .foregroundStyle(flowColor(row.line.amountCents))
                            Text(Money.signed(cents: row.subtotal))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body)
                }
            }
        }
        .financeCard(padding: 12)
    }

    private func flowTile(_ title: String, amount: Int, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(Money.signed(cents: amount))
                .font(.title3.weight(.semibold))
                .foregroundStyle(flowColor(amount))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(footnote ?? " ")
                .font(.footnote)
                .foregroundStyle(footnote == nil ? .clear : .secondary)
                .lineLimit(2)
        }
        .financeCard(padding: 12)
    }

    private func balanceTile(_ title: String, amount: Int, delta: Int? = nil, liquid: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(Money.string(cents: amount))
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(delta.map { Money.signed(cents: $0) } ?? " ")
                .font(.footnote)
                .foregroundStyle(delta.map { flowColor($0) } ?? .clear)
                .lineLimit(1)
            if let liquid {
                Text(L("Liquide", "Liquid"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money.string(cents: liquid))
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .financeCard(padding: 12)
    }

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var selectedPeriod: ForecastPeriod? {
        filters.period(in: periods)
    }

    private var filterAccounts: [Account] {
        accounts.filter { $0.kind != .savingsGroup }
    }

    private var selectedFilterAccount: Account? {
        filters.account(in: filterAccounts)
    }

    private var scopedAccounts: [Account] {
        if let selectedFilterAccount { return [selectedFilterAccount] }
        return accounts
    }

    private var scopedEntries: [LedgerEntry] {
        guard let account = selectedFilterAccount else { return entries }
        return entries.filter { entry in
            entry.accountID == account.id || entry.fromAccountID == account.id || entry.toAccountID == account.id
        }
    }

    private var scopedHoldings: [PortfolioHolding] {
        guard let account = selectedFilterAccount else { return holdings }
        return holdings.filter { $0.accountID == account.id }
    }

    private var includePlans: Bool {
        selectedFilterAccount == nil || selectedFilterAccount?.isMain == true
    }

    private func forecast(for period: ForecastPeriod) -> PeriodForecast {
        FinanceService.periodForecast(
            period: period,
            periods: periods,
            accounts: scopedAccounts,
            entries: scopedEntries,
            holdings: scopedHoldings,
            fixedCosts: includePlans ? fixedCosts : [],
            variableBudgets: includePlans ? variableBudgets : [],
            splits: splits,
            forecasts: includePlans ? forecasts : [],
            shopping: includePlans ? shopping : []
        )
    }

    private func liquidForecast(for period: ForecastPeriod) -> PeriodForecast {
        let liquid = accounts.filter { $0.isLiquid && $0.kind != .portfolio && $0.kind != .savingsGroup }
        return FinanceService.periodForecast(
            period: period,
            periods: periods,
            accounts: liquid,
            entries: entries,
            holdings: [],
            fixedCosts: fixedCosts,
            variableBudgets: variableBudgets,
            splits: splits,
            forecasts: forecasts,
            shopping: shopping
        )
    }

    private func presented(_ snapshot: PeriodForecast) -> PeriodForecast {
        guard let account = selectedFilterAccount, account.kind == .portfolio else { return snapshot }
        let value = FinanceService.balance(for: account, entries: entries, holdings: holdings)
        var copy = snapshot
        copy.netWorth = value
        copy.startBalance = value
        copy.endBalance = value
        return copy
    }

    private func incomeFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now) else { return nil }
        return "\(L("Offen", "Open")) \(Money.signed(cents: forecast.openIncome))"
    }

    private func expenseFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        openFootnote(forecast.openExpenses, period: period)
    }

    private func openFootnote(_ cents: Int, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now) else { return nil }
        return "\(L("Offen", "Open")) \(Money.signed(cents: -cents))"
    }

    private func netWorthCaption(_ period: ForecastPeriod) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        if period.contains(today) { return L("Heute", "Today") }
        if period.end < today { return L("Zum Periodenende", "At period end") }
        return L("Prognose zum Periodenende", "Forecast at period end")
    }

    private func runningTotals(_ lines: [ForecastLine]) -> [(line: ForecastLine, subtotal: Int)] {
        var sum = 0
        return lines.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }.map { line in
            sum += line.amountCents
            return (line, sum)
        }
    }

    private func flowColor(_ cents: Int) -> Color {
        if cents > 0 { return .green }
        if cents < 0 { return .red }
        return .primary
    }

}

private struct FinanceDestinationRegistration: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: FinanceRoute.self) { FinanceRouteScreen(route: $0) }
        } else {
            content
        }
    }
}

private struct FinanceMoreSection: View {
    var path: Binding<NavigationPath>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Weitere Bereiche", "More"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                sectionLink(L("Depot", "Portfolio"), systemImage: "chart.line.uptrend.xyaxis", route: .portfolio)
                Divider().padding(.leading, 54)
                sectionLink(L("Budgetpools", "Budget pools"), systemImage: "tray.full", route: .budgetPools)
                Divider().padding(.leading, 54)
                sectionLink(L("Ausgabengruppen", "Expense groups"), systemImage: "square.stack.3d.up", route: .expenseGroups)
                Divider().padding(.leading, 54)
                sectionLink(L("Schulden", "Debts"), systemImage: "person.2", route: .debts)
            }
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func sectionLink(_ title: String, systemImage: String, route: FinanceRoute) -> some View {
        Group {
            if let path {
                Button {
                    path.wrappedValue.append(route)
                } label: {
                    row(title, systemImage: systemImage)
                }
            } else {
                NavigationLink(value: route) {
                    row(title, systemImage: systemImage)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

private extension View {
    func financeCard(padding: CGFloat = 12) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(padding)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
