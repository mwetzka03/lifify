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
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @State private var selectedBooking: LedgerEntry?
    @State private var editingBooking: LedgerEntry?
    @State private var showingNewBooking = false
    @State private var bookingQuery = ""
    @State private var editedTransfer: TransferForecastRecord?
    @AppStorage("portfolioPerformanceBasis") private var portfolioBasis = "today"
    @AppStorage("portfolioPerformanceUnit") private var portfolioUnit = "percent"

    init(isMainTab: Bool = false, path: Binding<NavigationPath>? = nil) {
        self.isMainTab = isMainTab
        self.path = path
    }

    var body: some View {
        Group {
            if let period = selectedPeriod {
                VStack(spacing: 0) {
                    FinanceFilterControls(periods: periods, accounts: filterAccounts)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    List {
                    Section {
                        financeSummary(period)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    Section {
                        bookingSearchRow
                        if filteredBookings.isEmpty && openTransferForecasts.isEmpty {
                            Text(bookingQuery.isEmpty
                                ? L("In diesem Zeitraum liegen keine Buchungen.", "There are no transactions in this period.")
                                : L("Keine Buchung gefunden.", "No transaction found."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(openTransferForecasts) { item in
                            Button {
                                editedTransfer = item.forecast
                            } label: {
                                openTransferRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(filteredBookings) { entry in
                            Button {
                                selectedBooking = entry
                            }                             label: {
                                TransactionRow(
                                    entry: entry,
                                    accounts: accounts,
                                    holdings: holdings,
                                    ledgerEntries: entries,
                                    viewedAccountID: filters.showsDepot ? nil : selectedFilterAccount?.id,
                                    scope: bookingScope
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteBooking(entry)
                                } label: {
                                    Label(L("Löschen", "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editingBooking = entry
                                } label: {
                                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        Text(L("Buchungen", "Transactions"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ContentUnavailableView(
                        L("Noch kein Zeitraum", "No period yet"),
                        systemImage: "calendar",
                        description: Text(L(
                            "Lege ein Konto und eine Haupteinnahme an.",
                            "Create an account and a primary income."
                        ))
                    )
                    if isMainTab && !filters.showsDepot { FinanceMoreSection(path: path) }
                }
                .padding(12)
            }
        }
        .appCanvas()
        .toolbar(isMainTab ? .hidden : .automatic, for: .navigationBar)
        .navigationTitle(isMainTab ? "" : L("Finanzen", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(FinanceDestinationRegistration(isEnabled: path == nil))
        .onAppear {
            SavingsPlanRunner.bookDue(context: context)
            SavingsPlanFixedCosts.sync(context: context)
        }
        .sheet(item: $editingBooking) { entry in
            TransactionFormView(entry: entry, splits: splits)
        }
        .sheet(isPresented: $showingNewBooking) {
            TransactionFormView(entry: nil, splits: splits)
        }
        .sheet(item: $selectedBooking) { entry in
            TransactionDetailView(entry: entry)
        }
        .sheet(item: $editedTransfer) { forecast in
            TransferForecastForm(forecast: forecast)
        }
    }

    @ViewBuilder
    private func financeSummary(_ period: ForecastPeriod) -> some View {
        let snapshot = presented(forecast(for: period), period: period)
        let prognose = snapshot.bookedIncome + snapshot.openIncome - snapshot.bookedExpenses - snapshot.openExpenses
        VStack(alignment: .leading, spacing: 8) {
            netWorthCard(snapshot, period: period)
            if filters.showsDepot {
                PortfolioElementsView(accountID: nil, showsValueHeader: false, path: path)
            } else {
                let liquid = selectedFilterAccount == nil ? liquidForecast(for: period) : nil
                let openingBalance = balanceTile(
                    L("Startsaldo", "Opening balance"),
                    amount: snapshot.startBalance,
                    liquid: liquid?.startBalance
                )
                let closingBalance = balanceTile(
                    L("Endsaldo (Prognose)", "Closing balance (forecast)"),
                    amount: snapshot.startBalance + prognose,
                    liquid: liquid?.endBalance
                )
                EqualHeightTileRow {
                    linked(.income) {
                        flowTile(L("Einnahmen", "Income"), amount: snapshot.income, footnote: incomeFootnote(snapshot, period: period), fillsRow: true)
                    }
                    linked(.expenses) {
                        flowTile(L("Ausgaben", "Expenses"), amount: -snapshot.bookedExpenses, footnote: expenseFootnote(snapshot, period: period), fillsRow: true)
                    }
                    flowTile(
                        L("Differenz", "Difference"),
                        amount: snapshot.realDifference,
                        footnote: forecastFootnote(prognose, period: period),
                        fillsRow: true
                    )
                }
                EqualHeightTileRow {
                    openingBalance
                    closingBalance
                }
                EqualHeightTileRow {
                    linked(.fixedCosts) {
                        flowTile(
                            L("Fixkosten", "Fixed costs"),
                            amount: -snapshot.bookedFixed,
                            footnote: openFootnote(snapshot.remainingFixed, period: period),
                            fillsRow: true
                        )
                    }
                    linked(.variableCosts) {
                        flowTile(
                            L("Variable Kosten", "Variable costs"),
                            amount: -snapshot.bookedVariable,
                            footnote: openFootnote(snapshot.remainingVariable, period: period),
                            fillsRow: true
                        )
                    }
                }
                linked(.shopping) { biasCard(snapshot) }
            }
            if isMainTab && !filters.showsDepot { FinanceMoreSection(path: path) }
        }
    }

    private var bookingSearchRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Buchung suchen", "Search transactions"), text: $bookingQuery)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !bookingQuery.isEmpty {
                    Button {
                        bookingQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(AppSurface.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .clipShape(Capsule())
            Button {
                showingNewBooking = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .boundedBubble(circle: true)
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityLabel(L("Buchung hinzufügen", "Add transaction"))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var filteredBookings: [LedgerEntry] {
        guard let period = selectedPeriod else { return [] }
        let depotIDs = filters.showsDepot ? Set(accounts.filter { $0.kind == .portfolio }.map(\.id)) : []
        let query = bookingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            guard FinancePeriods.includes($0, period: period, account: selectedFilterAccount, depotIDs: depotIDs) else { return false }
            guard !query.isEmpty else { return true }
            return $0.title.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private func deleteBooking(_ entry: LedgerEntry) {
        splits.filter { $0.transactionID == entry.id }.forEach { context.delete($0) }
        IconPreferenceStore.remove(for: entry.id)
        RefundLinkStore.removeAll(touching: entry.id)
        TransferForecastAssignmentStore.clear(entryID: entry.id)
        context.delete(entry)
        try? context.save()
    }

    private var openTransferForecasts: [OpenTransferForecast] {
        guard let period = selectedPeriod, !filters.showsDepot else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard period.end >= today else { return [] }
        return TransferForecastStore.all().filter(\.active).flatMap { forecast -> [OpenTransferForecast] in
            if transferForecastIsBooked(forecast, period: period) { return [] }
            if let account = selectedFilterAccount {
                guard forecast.fromAccountID == account.id || forecast.toAccountID == account.id else { return [] }
            }
            return CalendarService.nextOccurrences(
                firstDate: forecast.firstDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endDate,
                through: period.end
            )
            .map { calendar.startOfDay(for: $0) }
            .filter { period.contains($0) && $0 >= today }
            .map { day in
                OpenTransferForecast(
                    id: "\(forecast.id.uuidString)-\(day.dayKey)",
                    forecast: forecast,
                    date: day
                )
            }
        }
        .sorted { $0.date < $1.date }
    }

    private func transferForecastIsBooked(_ forecast: TransferForecastRecord, period: ForecastPeriod) -> Bool {
        entries.contains { entry in
            guard period.contains(entry.date) else { return false }
            return TransferForecastAssignmentStore.forecastID(for: entry.id) == forecast.id
        }
    }

    private func openTransferRow(_ item: OpenTransferForecast) -> some View {
        let signed = transferForecastSigned(item.forecast)
        return HStack(spacing: 12) {
            Image(systemName: BookingCategory.transfer.systemImage)
                .frame(width: 28)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.forecast.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(L("Umbuchung", "Transfer")) · \(AppDate.numeric(item.date)) · \(L("Prognose", "Forecast"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: signed))
                .foregroundStyle(selectedFilterAccount == nil ? Color.primary : BookingClassification.differenceColor(signed))
                .monospacedDigit()
        }
    }

    private func transferForecastSigned(_ forecast: TransferForecastRecord) -> Int {
        let amount = abs(forecast.amountCents)
        guard let account = selectedFilterAccount else { return amount }
        if forecast.fromAccountID == account.id { return -amount }
        if forecast.toAccountID == account.id { return amount }
        return amount
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
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func netWorthCard(_ forecast: PeriodForecast, period: ForecastPeriod) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Gesamtvermögen", "Net worth"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(Money.string(cents: forecast.netWorth))
                .font(.largeTitle.bold())
                .lineLimit(1)
            if filters.showsDepot {
                let change = portfolioChange
                Text(change.text)
                    .font(.subheadline.bold())
                    .foregroundStyle(change.cents < 0 ? .red : (change.cents > 0 ? .green : .secondary))
            } else {
                Text(netWorthCaption(period))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                        .foregroundStyle(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Geplant", "Planned"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: forecast.biasPlanned))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .financeCard(padding: 12)
    }

    private func flowTile(_ title: String, amount: Int, footnote: String? = nil, fillsRow: Bool = false) -> some View {
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
        .financeCard(padding: 12, fillsRow: fillsRow)
    }

    private func balanceTile(
        _ title: String,
        amount: Int,
        liquid: Int? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(Money.string(cents: amount))
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            if let liquid {
                Text(L("Liquide", "Liquid"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money.string(cents: liquid))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .financeCard(padding: 12, fillsRow: true)
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

    private var portfolioChange: (text: String, cents: Int) {
        let total = scopedHoldings.reduce(HoldingPerformance()) { $0.adding(holdingPerformance($1)) }
        return total.selected(basis: portfolioBasis, unit: portfolioUnit)
    }

    private var scopedHoldings: [PortfolioHolding] {
        guard let account = selectedFilterAccount else { return holdings }
        return holdings.filter { $0.accountID == account.id }
    }

    private var includePlans: Bool {
        selectedFilterAccount == nil || selectedFilterAccount?.isMain == true
    }

    private var forecastFixedCosts: [FixedCost] {
        FixedCostScope.applicable(
            costs: fixedCosts,
            account: selectedFilterAccount,
            showsDepot: filters.showsDepot,
            includeHousehold: includePlans
        )
    }

    private var bookingScope: BookingScope {
        if filters.showsDepot { return .depot }
        if selectedFilterAccount != nil { return .account }
        return .combined
    }

    private var cashAccountIDs: [UUID] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id)
    }

    private func forecast(for period: ForecastPeriod) -> PeriodForecast {
        let combined = selectedFilterAccount == nil && !filters.showsDepot
        var snapshot = FinanceService.periodForecast(
            period: period,
            periods: periods,
            accounts: scopedAccounts,
            entries: scopedEntries,
            holdings: filters.showsDepot ? holdings : scopedHoldings,
            fixedCosts: forecastFixedCosts,
            variableBudgets: filters.showsDepot ? [] : variableBudgets,
            splits: splits,
            forecasts: includePlans && !filters.showsDepot ? forecasts : [],
            shopping: includePlans && !filters.showsDepot ? shopping : [],
            incomePredicate: combined ? { ExternalIncome.countsInCombinedFinance($0, accounts: accounts) } : nil,
            includePortfolioValue: combined,
            countSavingsPlansInCash: true,
            scopedCashAccountIDs: selectedFilterAccount.map { [$0.id] },
            householdCashAccountIDs: cashAccountIDs
        )
        guard !filters.showsDepot else { return snapshot }
        let tradedIncome = PortfolioCashFlow.countedCents(
            kind: .income,
            entries: scopedEntries,
            accounts: accounts,
            holdings: holdings,
            period: period,
            account: selectedFilterAccount
        )
        let tradedExpenses = PortfolioCashFlow.countedCents(
            kind: .expense,
            entries: scopedEntries,
            accounts: accounts,
            holdings: holdings,
            period: period,
            account: selectedFilterAccount
        )
        snapshot.bookedIncome += tradedIncome
        snapshot.bookedExpenses += tradedExpenses
        snapshot.income += tradedIncome
        snapshot.expenses += tradedExpenses
        if combined {
            snapshot.startBalance = combinedOpening(for: period)
        }
        return snapshot
    }

    /// All-accounts opening is each account's own opening plus the depot on the day before.
    private func combinedOpening(for period: ForecastPeriod) -> Int {
        let cashAccounts = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
        let cash = cashAccounts.reduce(0) { partial, account in
            let touched = entries.filter {
                $0.accountID == account.id || $0.fromAccountID == account.id || $0.toAccountID == account.id
            }
            let household = account.isMain
            let opening = FinanceService.periodForecast(
                period: period,
                periods: periods,
                accounts: [account],
                entries: touched,
                holdings: [],
                fixedCosts: FixedCostScope.applicable(
                    costs: fixedCosts,
                    account: account,
                    showsDepot: false,
                    includeHousehold: household
                ),
                variableBudgets: variableBudgets,
                splits: splits,
                forecasts: household ? forecasts : [],
                shopping: household ? shopping : [],
                includePortfolioValue: false,
                countSavingsPlansInCash: true,
                scopedCashAccountIDs: [account.id],
                householdCashAccountIDs: cashAccountIDs
            ).startBalance
            return partial + opening
        }
        let start = Calendar.current.startOfDay(for: period.start)
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        return cash + HoldingMaintenance.marketValue(of: holdings, through: dayBefore)
    }

    private func liquidForecast(for period: ForecastPeriod) -> PeriodForecast {
        let liquid = accounts.filter { $0.isLiquid && $0.kind != .portfolio && $0.kind != .savingsGroup }
        let liquidIDs = Set(liquid.map(\.id))
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
            shopping: shopping,
            scopedCashAccountIDs: liquidIDs,
            householdCashAccountIDs: cashAccountIDs
        )
    }

    private func presented(_ snapshot: PeriodForecast, period: ForecastPeriod) -> PeriodForecast {
        guard filters.showsDepot else { return snapshot }
        var copy = snapshot
        copy.netWorth = HoldingMaintenance.marketValue(of: holdings, through: period.end)
        return copy
    }

    private func incomeFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now) else { return nil }
        return "\(L("Offen", "Open")) \(Money.signed(cents: forecast.openIncome))"
    }

    private func expenseFootnote(_ forecast: PeriodForecast, period: ForecastPeriod) -> String? {
        openFootnote(forecast.openExpenses, period: period)
    }

    private func forecastFootnote(_ cents: Int, period: ForecastPeriod) -> String? {
        guard period.end >= Calendar.current.startOfDay(for: .now) else { return nil }
        return "\(L("Prognose", "Forecast")) \(Money.signed(cents: cents))"
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
                sectionLink(L("Umbuchungsprognosen", "Transfer forecasts"), systemImage: "arrow.left.arrow.right", route: .transferForecasts)
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

private struct TileHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TileRowHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var tileRowHeight: CGFloat {
        get { self[TileRowHeightKey.self] }
        set { self[TileRowHeightKey.self] = newValue }
    }
}

private struct EqualHeightTileRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content()
        }
        .environment(\.tileRowHeight, height)
        .onPreferenceChange(TileHeightPreference.self) { height = $0 }
    }
}

private struct OpenTransferForecast: Identifiable {
    var id: String
    var forecast: TransferForecastRecord
    var date: Date
}

private struct FinanceCardModifier: ViewModifier {
    var padding: CGFloat
    var fillsRow: Bool
    @Environment(\.tileRowHeight) private var rowHeight

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                if fillsRow {
                    GeometryReader { geo in
                        Color.clear.preference(key: TileHeightPreference.self, value: geo.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: fillsRow && rowHeight > 0 ? rowHeight : 0, alignment: .topLeading)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension View {
    func financeCard(padding: CGFloat = 12, fillsRow: Bool = false) -> some View {
        modifier(FinanceCardModifier(padding: padding, fillsRow: fillsRow))
    }
}
