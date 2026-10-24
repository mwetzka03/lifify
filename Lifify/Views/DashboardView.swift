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
    @State private var newBookingCategory: BookingCategory?
    @State private var bookingQuery = ""
    @State private var editedTransfer: TransferForecastRecord?
    @State private var editedIncomeForecast: IncomeForecast?
    @State private var editedFixedCost: FixedCost?
    @State private var editedBudget: VariableBudget?
    @State private var editedShopping: ShoppingItem?
    @State private var selectedForecast: ForecastListItem?
    @State private var forecastQuery = ""
    @State private var showingNewIncome = false
    @State private var showingNewTransfer = false
    @State private var showingNewFixedCost = false
    @State private var showingNewBudget = false
    @State private var showingNewSavingsPlan = false
    @State private var savingsForecastsExpanded = true
    @State private var summary: PreparedSummary?
    @State private var summarySelection: Int?
    @AppStorage(ForecastSkipStore.revisionKey) private var forecastSkipRevision = 0
    @AppStorage(ForecastPeriodLinkStore.revisionKey) private var forecastLinkRevision = 0
    @AppStorage(ForecastMatchRejectionStore.revisionKey) private var forecastRejectionRevision = 0
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
                        if filters.showsDepot {
                            depotContent(period)
                        } else if let summary, summarySelection == selectionToken {
                            financeSummary(
                                summary.forecast,
                                period: period,
                                liquidStart: summary.liquidStart,
                                liquidEnd: summary.liquidEnd
                            )
                        } else {
                            summaryLoading
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    if !filters.showsDepot {
                        Section {
                            forecastSearchRow
                            if visibleForecasts(period).isEmpty {
                                Text(forecastQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? L("In diesem Zeitraum liegen keine Prognosen.", "There are no forecasts in this period.")
                                    : L("Keine Prognose gefunden.", "No forecast found."))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(visibleForecasts(period)) { line in
                                if line.isSavingsHeader {
                                    savingsForecastHeader(bookedCents: line.bookedCents, openCents: line.openCents)
                                } else if let item = line.item {
                                    forecastButton(item)
                                }
                            }
                        } header: {
                            Text(L("Prognosen", "Forecasts"))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }
                    Section {
                        bookingSearchRow
                        if filteredBookings.isEmpty {
                            Text(bookingQuery.isEmpty
                                ? L("In diesem Zeitraum liegen keine Buchungen.", "There are no transactions in this period.")
                                : L("Keine Buchung gefunden.", "No transaction found."))
                                .foregroundStyle(.secondary)
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
                .task(id: filters.showsDepot ? 0 : forecastToken) {
                    if filters.showsDepot {
                        summary = nil
                        summarySelection = nil
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await refreshSummary()
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
        .sheet(item: $newBookingCategory) { category in
            TransactionFormView(entry: nil, splits: splits, lockedCategory: category)
        }
        .sheet(item: $selectedBooking) { entry in
            TransactionDetailView(entry: entry)
        }
        .sheet(item: $editedTransfer) { forecast in
            TransferForecastForm(forecast: forecast)
        }
        .sheet(item: $editedIncomeForecast) { forecast in
            IncomeForecastForm(forecast: forecast)
        }
        .sheet(item: $editedFixedCost) { cost in
            FixedCostForm(cost: cost)
        }
        .sheet(item: $editedBudget) { budget in
            VariableBudgetForm(budget: budget)
        }
        .sheet(item: $editedShopping) { item in
            ShoppingItemForm(item: item)
        }
        .sheet(item: $selectedForecast) { item in
            if let period = selectedPeriod {
                ForecastDetailView(item: item, period: period, account: selectedFilterAccount)
            }
        }
        .sheet(isPresented: $showingNewIncome) { IncomeForecastForm(forecast: nil) }
        .sheet(isPresented: $showingNewTransfer) { TransferForecastForm(forecast: nil) }
        .sheet(isPresented: $showingNewFixedCost) { FixedCostForm(cost: nil) }
        .sheet(isPresented: $showingNewBudget) { VariableBudgetForm(budget: nil) }
        .sheet(isPresented: $showingNewSavingsPlan) { SavingsPlanCreateForm() }
    }

    @ViewBuilder
    private func financeSummary(
        _ snapshot: PeriodForecast,
        period: ForecastPeriod,
        liquidStart: Int?,
        liquidEnd: Int?
    ) -> some View {
        let prognose = snapshot.bookedIncome + snapshot.openIncome - snapshot.bookedExpenses - snapshot.openExpenses
        let future = isFuturePeriod(period)
        let showNotes = showsForecastNotes(period)
        VStack(alignment: .leading, spacing: 8) {
            netWorthCard(snapshot, period: period)
            if filters.showsDepot {
                PortfolioElementsView(accountID: nil, showsValueHeader: false, path: path)
            } else {
                let openingBalance = balanceTile(
                    L("Startsaldo", "Opening balance"),
                    amount: snapshot.startBalance,
                    liquid: liquidStart
                )
                let closingBalance = balanceTile(
                    L("Endsaldo (Prognose)", "Closing balance (forecast)"),
                    amount: snapshot.startBalance + prognose,
                    liquid: liquidEnd
                )
                EqualHeightTileRow {
                    linked(.income) {
                        flowTile(
                            L("Einnahmen", "Income"),
                            amount: snapshot.income,
                            note: showNotes ? FlowNote(title: L("Offen", "Open"), cents: snapshot.openIncome) : nil,
                            fillsRow: true
                        )
                    }
                    linked(.expenses) {
                        flowTile(
                            L("Ausgaben", "Expenses"),
                            amount: future ? -(snapshot.bookedExpenses + snapshot.openExpenses) : -snapshot.bookedExpenses,
                            note: showNotes ? FlowNote(title: L("Offen", "Open"), cents: -snapshot.openExpenses) : nil,
                            fillsRow: true
                        )
                    }
                    flowTile(
                        L("Differenz", "Difference"),
                        amount: future ? prognose : snapshot.realDifference,
                        note: showNotes ? FlowNote(title: L("Prognose", "Forecast"), cents: prognose) : nil,
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
                            amount: future ? -(snapshot.bookedFixed + snapshot.remainingFixed) : -snapshot.bookedFixed,
                            note: showNotes ? FlowNote(title: L("Offen", "Open"), cents: -snapshot.remainingFixed) : nil,
                            fillsRow: true
                        )
                    }
                    linked(.variableCosts) {
                        flowTile(
                            L("Variable Kosten", "Variable costs"),
                            amount: future ? -(snapshot.bookedVariable + snapshot.remainingVariable) : -snapshot.bookedVariable,
                            note: showNotes ? FlowNote(title: L("Offen", "Open"), cents: -snapshot.remainingVariable) : nil,
                            fillsRow: true
                        )
                    }
                }
                linked(.shopping) { biasCard(snapshot) }
            }
            if isMainTab && !filters.showsDepot { FinanceMoreSection(path: path) }
        }
    }

    private func depotContent(_ period: ForecastPeriod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Gesamtvermögen", "Net worth"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(Money.string(cents: HoldingMaintenance.marketValue(of: holdings, through: period.end)))
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                let change = portfolioChange
                Text(change.text)
                    .font(.subheadline.bold())
                    .foregroundStyle(change.cents < 0 ? .red : (change.cents > 0 ? .green : .secondary))
            }
            .financeCard()
            PortfolioElementsView(accountID: nil, showsValueHeader: false, path: path)
        }
    }

    private func forecastButton(_ item: ForecastListItem) -> some View {
        Button {
            selectedForecast = item
        } label: {
            forecastRow(item)
        }
        .buttonStyle(.plain)
        .opacity(item.settled ? 0.45 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ForecastSkipStore.skip(item.refKind, id: item.sourceID, on: item.date)
            } label: {
                Label(L("Löschen", "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editForecast(item)
            } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var forecastSearchRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Prognose suchen", "Search forecasts"), text: $forecastQuery)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !forecastQuery.isEmpty {
                    Button {
                        forecastQuery = ""
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
            Menu {
                Button(L("Einnahmeprognose", "Income forecast")) { showingNewIncome = true }
                Button(L("Umbuchungsprognose", "Transfer forecast")) { showingNewTransfer = true }
                Button(L("Sparplan", "Savings plan")) { showingNewSavingsPlan = true }
                Button(L("Fixkosten", "Fixed cost")) { showingNewFixedCost = true }
                Button(L("Variable Kosten", "Variable cost")) { showingNewBudget = true }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .boundedBubble(circle: true)
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityLabel(L("Prognose hinzufügen", "Add forecast"))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func savingsForecastHeader(bookedCents: Int, openCents: Int) -> some View {
        let expanded = savingsForecastsExpanded || !forecastQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let total = bookedCents + openCents
        return Button {
            savingsForecastsExpanded.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: BookingCategory.savingsPlan.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Sparpläne", "Savings plans"))
                        .foregroundStyle(.primary)
                    Text("\(L("Gesamt", "Total")) \(Money.string(cents: total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(L("Gebucht", "Booked")) \(Money.string(cents: bookedCents)) · \(L("Offen", "Open")) \(Money.string(cents: openCents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func visibleForecasts(_ period: ForecastPeriod) -> [ForecastDisplayLine] {
        let query = forecastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupTitle = L("Sparpläne", "Savings plans")
        let groupQuery = !query.isEmpty && groupTitle.localizedCaseInsensitiveContains(query)
        let items = forecastItems(period).filter { item in
            guard !query.isEmpty else { return true }
            if isSavingsForecast(item), groupQuery { return true }
            return item.title.localizedCaseInsensitiveContains(query)
        }
        let savings = items.filter(isSavingsForecast).sorted { $0.date < $1.date }
        let others = items.filter { !isSavingsForecast($0) }
        guard let first = savings.first else {
            return others.map { ForecastDisplayLine(item: $0) }
        }
        let expanded = savingsForecastsExpanded || !forecastQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var lines: [ForecastDisplayLine] = []
        var inserted = false
        let figures = savingsForecastFigures(period: period)
        let header = ForecastDisplayLine(
            id: "savings-group",
            bookedCents: figures.booked,
            openCents: figures.open
        )
        func appendSavings() {
            lines.append(header)
            if expanded {
                lines.append(contentsOf: savings.map { ForecastDisplayLine(item: $0) })
            }
        }
        for item in others {
            if !inserted && item.date >= first.date {
                appendSavings()
                inserted = true
            }
            lines.append(ForecastDisplayLine(item: item))
        }
        if !inserted { appendSavings() }
        return lines
    }

    private func isSavingsForecast(_ item: ForecastListItem) -> Bool {
        guard item.fixedCostID != nil else { return false }
        if let cost = fixedCosts.first(where: { $0.id == item.fixedCostID }) {
            return SavingsPlanFixedCosts.isSavingsCost(cost)
        }
        return SavingsPlanFixedCosts.isManagedName(item.title)
    }

    private func savingsForecastFigures(period: ForecastPeriod) -> (booked: Int, open: Int) {
        let savings = forecastItems(period).filter(isSavingsForecast)
        let open = savings.filter { !$0.settled }.reduce(0) { $0 + abs($1.signedCents) }
        let accountIDs: Set<UUID>? = selectedFilterAccount.map { Set([$0.id]) }
        let booked = FinanceService.savingsPlanBookedCents(
            entries: entries,
            from: period.start,
            through: period.end,
            accountIDs: accountIDs
        )
        return (booked, open)
    }

    private func forecastItems(_ period: ForecastPeriod) -> [ForecastListItem] {
        _ = forecastRejectionRevision
        return ForecastSchedule.financeView(
            forecasts: forecasts,
            costs: fixedCosts,
            entries: entries,
            period: period,
            account: selectedFilterAccount,
            showsDepot: filters.showsDepot,
            budgets: variableBudgets,
            splits: splits,
            shopping: shopping,
            cashAccountIDs: cashAccountIDs
        )
    }

    private func editForecast(_ item: ForecastListItem) {
        switch item.kind {
        case .income(let forecast):
            editedIncomeForecast = forecast
        case .expense(let id):
            editedFixedCost = fixedCosts.first { $0.id == id }
        case .transfer(let forecast):
            editedTransfer = forecast
        case .variable(let id):
            editedBudget = variableBudgets.first { $0.id == id }
        case .shopping(let id):
            editedShopping = shopping.first { $0.id == id }
        }
    }

    private func forecastRow(_ item: ForecastListItem) -> some View {
        let savings = item.fixedCostID != nil && SavingsPlanFixedCosts.isManagedName(item.title)
        let category: BookingCategory = switch item.kind {
        case .income: .income
        case .expense: savings ? .savingsPlan : .expense
        case .transfer: .transfer
        case .variable, .shopping: .expense
        }
        let paint = BookingClassification.paint(category: category, signed: item.signedCents, scope: bookingScope)
        let caption: String = switch item.kind {
        case .income: L("Einnahme", "Income")
        case .expense: savings ? L("Sparplan", "Savings plan") : L("Fixkosten", "Fixed cost")
        case .transfer: L("Umbuchung", "Transfer")
        case .variable: L("Variable Kosten", "Variable cost")
        case .shopping: L("Einkaufszettel", "Shopping list")
        }
        let symbol: String = switch item.kind {
        case .variable: "gauge.with.dots.needle.67percent"
        case .shopping: "cart"
        default: category.systemImage
        }
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(category == .income || category == .expense ? Color.primary : paint.iconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(caption) · \(AppDate.numeric(item.date)) · \(item.settled ? L("Gebucht", "Booked") : L("Prognose", "Forecast"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.signed(cents: item.signedCents))
                .foregroundStyle(forecastAmountColor(category: category, signed: item.signedCents, paint: paint))
                .monospacedDigit()
        }
    }

    private func forecastAmountColor(category: BookingCategory, signed: Int, paint: BookingPaint) -> Color {
        switch category {
        case .income: return .green
        case .expense: return .red
        case .savingsPlan, .transfer: return paint.amountColor
        case .interest, .dividend, .refund, .portfolioBuy, .portfolioSale, .adjustment: return paint.amountColor
        }
    }

    private var summaryLoading: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text(L("Wird geladen", "Loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .financeCard()
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
            Menu {
                ForEach(BookingCategory.allCases.filter(\.allowsManualEntry)) { category in
                    Button(category.label) { newBookingCategory = category }
                }
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
        ForecastPeriodLinkStore.clear(entryID: entry.id)
        IncomeAssignmentStore.clear(entryID: entry.id)
        context.delete(entry)
        try? context.save()
    }

    private func transferForecastIsBooked(_ forecast: TransferForecastRecord, period: ForecastPeriod) -> Bool {
        if ForecastPeriodLinkStore.covers(.transfer, id: forecast.id, entries: entries, period: period) { return true }
        return entries.contains { entry in
            guard period.contains(entry.date) else { return false }
            return TransferForecastAssignmentStore.forecastID(for: entry.id) == forecast.id
        }
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

    private func flowTile(_ title: String, amount: Int, note: FlowNote? = nil, fillsRow: Bool = false) -> some View {
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
            if let note {
                Text(note.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(Money.signed(cents: note.cents))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(flowColor(note.cents))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
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

    private func forecast(for period: ForecastPeriod) async -> PeriodForecast {
        let combined = selectedFilterAccount == nil && !filters.showsDepot
        await Task.yield()
        var snapshot = FinanceService.periodForecast(
            period: period,
            periods: periods,
            accounts: scopedAccounts,
            entries: scopedEntries,
            holdings: filters.showsDepot ? holdings : scopedHoldings,
            fixedCosts: forecastFixedCosts,
            variableBudgets: filters.showsDepot ? [] : variableBudgets,
            splits: splits,
            forecasts: accountScopedForecasts,
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
        if let account = selectedFilterAccount, !filters.showsDepot {
            let transfer = openTransferTotals(for: account, period: period)
            snapshot.openIncome += transfer.income
            snapshot.income += transfer.income
            snapshot.openExpenses += transfer.expenses
            snapshot.expenses += transfer.expenses
        }
        if combined {
            snapshot.startBalance = await combinedOpening(for: period)
        }
        return snapshot
    }

    /// All-accounts opening is each account's own opening plus the depot on the day before.
    private func combinedOpening(for period: ForecastPeriod) async -> Int {
        let cashAccounts = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
        var cash = 0
        for account in cashAccounts {
            await Task.yield()
            if Task.isCancelled { return cash }
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
                forecasts: forecasts.filter { $0.accountID == account.id },
                shopping: household ? shopping : [],
                includePortfolioValue: false,
                countSavingsPlansInCash: true,
                scopedCashAccountIDs: [account.id],
                householdCashAccountIDs: cashAccountIDs
            ).startBalance
            cash += opening
        }
        await Task.yield()
        if Task.isCancelled { return cash }
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
            forecasts: forecasts.filter { forecast in
                guard let id = forecast.accountID else { return true }
                return liquidIDs.contains(id)
            },
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

    private var accountScopedForecasts: [IncomeForecast] {
        guard !filters.showsDepot else { return [] }
        guard let account = selectedFilterAccount else { return forecasts }
        return forecasts.filter { $0.accountID == account.id }
    }

    /// A period that has not started yet folds planned amounts into the main figure.
    private func isFuturePeriod(_ period: ForecastPeriod) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: period.start) > calendar.startOfDay(for: .now)
    }

    private func showsForecastNotes(_ period: ForecastPeriod) -> Bool {
        !isFuturePeriod(period) && period.end >= Calendar.current.startOfDay(for: .now)
    }

    private func openTransferTotals(for account: Account, period: ForecastPeriod) -> (income: Int, expenses: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard period.end >= today else { return (0, 0) }
        var income = 0
        var expenses = 0
        for forecast in TransferForecastStore.all() where forecast.active {
            if transferForecastIsBooked(forecast, period: period) { continue }
            let incoming = forecast.toAccountID == account.id
            let outgoing = forecast.fromAccountID == account.id
            guard incoming || outgoing else { continue }
            let count = CalendarService.nextOccurrences(
                firstDate: forecast.firstDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endDate,
                through: period.end
            )
            .map { calendar.startOfDay(for: $0) }
            .filter { period.contains($0) && !ForecastSkipStore.isSkipped(.transfer, id: forecast.id, on: $0) }
            .count
            let amount = abs(forecast.amountCents) * count
            if incoming { income += amount }
            if outgoing { expenses += amount }
        }
        return (income, expenses)
    }

    private var forecastToken: Int {
        var hasher = Hasher()
        hasher.combine(filters.showsDepot)
        hasher.combine(selectedFilterAccount?.id)
        hasher.combine(selectedPeriod?.id)
        hasher.combine(forecastSkipRevision)
        hasher.combine(forecastLinkRevision)
        hasher.combine(IncomeAssignmentStore.fingerprint())
        hasher.combine(ForecastSkipStore.fingerprint())
        hasher.combine(ForecastPeriodLinkStore.fingerprint())
        hasher.combine(ForecastMatchRejectionStore.fingerprint())
        hasher.combine(RefundLinkStore.fingerprint())
        hasher.combine(TransferForecastAssignmentStore.fingerprint())
        hasher.combine(VariableBudgetAccounts.fingerprint())
        hasher.combine(SavingsPlanStore.cacheRevision)
        hasher.combine(HoldingLotStore.cacheRevision)
        hasher.combine(HistoricalPriceStore.cacheRevision)
        for forecast in TransferForecastStore.all().sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(forecast)
        }
        for account in accounts {
            hasher.combine(account.id)
            hasher.combine(account.kindRaw)
            hasher.combine(account.isMain)
            hasher.combine(account.isLiquid)
        }
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.amountCents)
            hasher.combine(entry.kindRaw)
            hasher.combine(entry.accountID)
            hasher.combine(entry.fromAccountID)
            hasher.combine(entry.toAccountID)
            hasher.combine(entry.fixedCostID)
            hasher.combine(entry.variableBudgetID)
            hasher.combine(entry.shoppingItemID)
            hasher.combine(entry.title)
            hasher.combine(entry.notes)
        }
        for holding in holdings {
            hasher.combine(holding.id)
            hasher.combine(holding.accountID)
            hasher.combine(holding.symbol)
            hasher.combine(holding.quantity)
            hasher.combine(holding.currentPriceCents)
            hasher.combine(holding.purchasePriceCents)
        }
        for cost in fixedCosts {
            hasher.combine(cost.id)
            hasher.combine(cost.accountID)
            hasher.combine(cost.amountCents)
            hasher.combine(cost.cadenceRaw)
            hasher.combine(cost.dueRuleRaw)
            hasher.combine(cost.dayOfMonth)
            hasher.combine(cost.firstChargeDate)
            hasher.combine(cost.endChargeDate)
            hasher.combine(cost.isActive)
            hasher.combine(cost.name)
        }
        for forecast in forecasts {
            hasher.combine(forecast.id)
            hasher.combine(forecast.accountID)
            hasher.combine(forecast.amountCents)
            hasher.combine(forecast.cadenceRaw)
            hasher.combine(forecast.dueRuleRaw)
            hasher.combine(forecast.dayOfMonth)
            hasher.combine(forecast.firstPaymentDate)
            hasher.combine(forecast.endPaymentDate)
            hasher.combine(forecast.isActive)
            hasher.combine(forecast.name)
        }
        for budget in variableBudgets {
            hasher.combine(budget.id)
            hasher.combine(budget.accountID)
            hasher.combine(budget.monthlyAmountCents)
            hasher.combine(budget.name)
        }
        for item in shopping {
            hasher.combine(item.id)
            hasher.combine(item.amountCents)
            hasher.combine(item.isPurchased)
            hasher.combine(item.plannedDate)
            hasher.combine(item.name)
        }
        for split in splits {
            hasher.combine(split.id)
            hasher.combine(split.transactionID)
            hasher.combine(split.targetID)
            hasher.combine(split.amountCents)
            hasher.combine(split.kindRaw)
            hasher.combine(split.periodKey)
        }
        return hasher.finalize()
    }

    private func refreshSummary() async {
        let selection = selectionToken
        await Task.yield()
        guard !Task.isCancelled else { return }
        warmFinanceStores()
        await Task.yield()
        guard !Task.isCancelled else { return }
        guard let period = selectedPeriod else {
            summary = nil
            summarySelection = nil
            return
        }
        let raw = await forecast(for: period)
        guard !Task.isCancelled else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let snapshot = presented(raw, period: period)
        guard !Task.isCancelled else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let liquid = selectedFilterAccount == nil && !filters.showsDepot ? liquidForecast(for: period) : nil
        guard !Task.isCancelled, selection == selectionToken else { return }
        summary = PreparedSummary(
            forecast: snapshot,
            liquidStart: liquid?.startBalance,
            liquidEnd: liquid?.endBalance
        )
        summarySelection = selection
    }

    private var selectionToken: Int {
        var hasher = Hasher()
        hasher.combine(filters.showsDepot)
        hasher.combine(selectedFilterAccount?.id)
        hasher.combine(selectedPeriod?.id)
        return hasher.finalize()
    }

    private func warmFinanceStores() {
        _ = SavingsPlanStore.all()
        _ = ClosedPositionStore.all()
        if let holding = holdings.first {
            _ = HoldingLotStore.lots(for: holding.id)
            _ = HistoricalPriceStore.cents(for: holding.id, dayKey: Date.now.dayKey)
        }
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

private struct FlowNote {
    var title: String
    var cents: Int
}

private struct ForecastDisplayLine: Identifiable {
    var id: String
    var item: ForecastListItem?
    var bookedCents: Int = 0
    var openCents: Int = 0

    var isSavingsHeader: Bool { item == nil }

    init(item: ForecastListItem) {
        id = item.id
        self.item = item
    }

    init(id: String, bookedCents: Int, openCents: Int) {
        self.id = id
        self.bookedCents = bookedCents
        self.openCents = openCents
    }
}

private struct PreparedSummary {
    var forecast: PeriodForecast
    var liquidStart: Int?
    var liquidEnd: Int?
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
