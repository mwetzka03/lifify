import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI

/// The full depot screen with all positions.
struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @Query private var accounts: [Account]
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @AppStorage("portfolioSort") private var sort = PortfolioSort.value.rawValue
    @State private var model = PortfolioScreenModel()
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var selected: PortfolioHolding?
    @State private var isRefreshing = false
    @State private var savingsPlans: [SavingsPlanRecord] = []

    /// The last day of the selected period.
    private var day: Date {
        filters.projectionDay(entries: entries, forecasts: forecasts, accounts: accounts)
    }

    /// The calculated depot for the selected period.
    private var snapshot: PortfolioSnapshot {
        model.snapshot(holdings: holdings, through: day, sort: sort)
    }

    var body: some View {
        let content = snapshot
        return List {
            valueSection(content)
            Section {
                PortfolioOptionPicker<PortfolioBasis>(title: L("Zeitraum", "Period"), selection: $basis)
                PortfolioOptionPicker<PortfolioUnit>(title: L("Einheit", "Unit"), selection: $unit)
            }
            .appGlassRow()
            Section {
                PortfolioOptionPicker<PortfolioSort>(title: L("Sortierung", "Sort"), selection: $sort)
            }
            .appGlassRow()
            linksSection(content)
            ForEach(content.rows) { holdingRow($0) }
        }
        .overlay {
            if content.rows.isEmpty && savingsPlans.isEmpty {
                ContentUnavailableView(L("Keine Depotpositionen", "No holdings"), systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .appGlassList()
        .navigationTitle(L("Depot", "Portfolio"))
        .toolbar { toolbarButtons }
        .onAppear {
            HoldingMaintenance.backfillPurchaseDates(holdings)
            SavingsPlanRunner.bookDue(context: context)
            SavingsPlanFixedCosts.sync(context: context)
            savingsPlans = SavingsPlanStore.all()
        }
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil) }
        .sheet(item: $edited) { HoldingForm(holding: $0) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0, day: day, holdings: holdings) }
    }

    /// The depot value with its selected gain.
    private func valueSection(_ content: PortfolioSnapshot) -> some View {
        Section {
            PortfolioValueHeader(content: content, basis: basis, unit: unit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .appGlassRow()
    }

    /// Links to the savings plans and the share chart, when there is something to show.
    @ViewBuilder
    private func linksSection(_ content: PortfolioSnapshot) -> some View {
        if !savingsPlans.isEmpty || !content.rows.isEmpty {
            Section {
                if !savingsPlans.isEmpty {
                    NavigationLink(value: FinanceRoute.savingsPlans) {
                        Text(L("Sparpläne", "Savings plans"))
                    }
                }
                if !content.rows.isEmpty {
                    NavigationLink(value: FinanceRoute.portfolioShares) {
                        Label(L("Anteile", "Shares"), systemImage: "chart.pie")
                    }
                }
            }
            .appGlassRow()
        }
    }

    /// One position with swipe actions.
    private func holdingRow(_ row: PortfolioRow) -> some View {
        Button {
            selected = row.holding
        } label: {
            PortfolioRowContent(row: row, basis: basis, unit: unit)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                HoldingMaintenance.deletePosition(row.holding, context: context)
            } label: {
                Label(L("Löschen", "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                edited = row.holding
            } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            .appAccentTint()
        }
        .appGlassRow()
    }

    /// The refresh and add buttons.
    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                Task {
                    isRefreshing = true
                    await MarketDataService.refresh(holdings: holdings, context: context)
                    isRefreshing = false
                }
            } label: {
                if isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(isRefreshing || holdings.isEmpty)
            Button { showingNew = true } label: { Image(systemName: "plus") }
        }
    }
}

/// A segmented control for one depot option, stored by raw value.
private struct PortfolioOptionPicker<Option: PortfolioOption>: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Option.allCases)) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A gain in the selected basis and unit, green or red by its sign.
private struct PortfolioPerformanceLabel: View {
    let performance: HoldingPerformance
    let basis: String
    let unit: String

    var body: some View {
        let selected = performance.selected(basis: basis, unit: unit)
        Text(selected.text)
            .font(.caption.bold())
            .foregroundStyle(selected.cents < 0 ? .red : (selected.cents > 0 ? .green : .secondary))
    }
}

/// The depot value with its total gain.
private struct PortfolioValueHeader: View {
    let content: PortfolioSnapshot
    let basis: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Depotwert", "Portfolio value"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.string(cents: content.marketValueCents))
                .font(.title2.bold())
            PortfolioPerformanceLabel(performance: content.totals, basis: basis, unit: unit)
            if content.usesScenario {
                Label(L("Szenario mit historischer ETF-Rendite", "Scenario with historic ETF return"), systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Name, shares, price, value, and gain of one position.
private struct PortfolioRowContent: View {
    let row: PortfolioRow
    let basis: String
    let unit: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.holding.name).foregroundStyle(.primary)
                Text("\(row.quantity.formatted()) × \(Money.string(cents: row.shownPriceCents))\(ReturnScenario.isEnabled && ReturnScenario.isETF(row.holding) ? " · ETF" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string(cents: row.valueCents))
                    .foregroundStyle(.primary)
                PortfolioPerformanceLabel(performance: row.performance, basis: basis, unit: unit)
            }
        }
    }
}

/// A plated link row with a title and a chevron.
private struct PortfolioCardLink<Title: View>: View {
    let path: Binding<NavigationPath>?
    let route: FinanceRoute
    @ViewBuilder let title: Title

    var body: some View {
        Group {
            if let path {
                Button {
                    path.wrappedValue.append(route)
                } label: {
                    label
                }
            } else {
                NavigationLink(value: route) {
                    label
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appTintedPlate(radius: 14)
    }

    /// The title with its chevron.
    private var label: some View {
        HStack {
            title
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

/// The depot section embedded in Finance, optionally limited to one account.
struct PortfolioElementsView: View {
    var accountID: UUID?
    var showsValueHeader = true
    var path: Binding<NavigationPath>? = nil
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @Query private var accounts: [Account]
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @AppStorage("portfolioSort") private var sort = PortfolioSort.value.rawValue
    @State private var model = PortfolioScreenModel()
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var selected: PortfolioHolding?
    @State private var isRefreshing = false
    @State private var savingsPlans: [SavingsPlanRecord] = []

    /// The positions of the shown account, or all of them.
    private var scopedHoldings: [PortfolioHolding] {
        holdings.filter { accountID == nil || $0.accountID == accountID }
    }

    /// The last day of the selected period.
    private var day: Date {
        filters.projectionDay(entries: entries, forecasts: forecasts, accounts: accounts)
    }

    /// The calculated depot for the selected period and account.
    private var snapshot: PortfolioSnapshot {
        model.snapshot(holdings: scopedHoldings, through: day, sort: sort)
    }

    /// The savings plans of the shown account.
    private var visiblePlans: [SavingsPlanRecord] {
        savingsPlans.filter { accountID == nil || $0.portfolioAccountID == accountID }
    }

    var body: some View {
        let content = snapshot
        return VStack(alignment: .leading, spacing: 8) {
            if showsValueHeader {
                PortfolioValueHeader(content: content, basis: basis, unit: unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .appTintedPlate(radius: 14)
            }
            if !visiblePlans.isEmpty {
                PortfolioCardLink(path: path, route: .savingsPlans) {
                    Text(L("Sparpläne", "Savings plans"))
                }
            }
            if !content.rows.isEmpty {
                PortfolioCardLink(path: path, route: .portfolioShares) {
                    Label(L("Anteile", "Shares"), systemImage: "chart.pie")
                }
            }
            optionsCard
            actionButtons(content)
            holdingList(content)
        }
        .onAppear {
            HoldingMaintenance.backfillPurchaseDates(content.rows.map(\.holding))
            savingsPlans = SavingsPlanStore.all()
        }
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil, preferredAccountID: accountID) }
        .sheet(item: $edited) { HoldingForm(holding: $0, preferredAccountID: accountID) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0, day: day, holdings: scopedHoldings) }
    }

    /// The period, unit, and sort controls.
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PortfolioOptionPicker<PortfolioBasis>(title: L("Zeitraum", "Period"), selection: $basis)
            PortfolioOptionPicker<PortfolioUnit>(title: L("Einheit", "Unit"), selection: $unit)
            PortfolioOptionPicker<PortfolioSort>(title: L("Sortierung", "Sort"), selection: $sort)
        }
        .padding(12)
        .appTintedPlate(radius: 14)
    }

    /// The refresh and add buttons.
    private func actionButtons(_ content: PortfolioSnapshot) -> some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    isRefreshing = true
                    await MarketDataService.refresh(holdings: content.rows.map(\.holding), context: context)
                    isRefreshing = false
                }
            } label: {
                Group {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label(L("Kurse aktualisieren", "Refresh quotes"), systemImage: "arrow.clockwise")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .liquidGlassSurface()
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .disabled(isRefreshing || content.rows.isEmpty)
            Button {
                showingNew = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .boundedBubble(circle: true)
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityLabel(L("Position", "Holding"))
        }
    }

    /// The positions, or a note when there are none.
    @ViewBuilder
    private func holdingList(_ content: PortfolioSnapshot) -> some View {
        if content.rows.isEmpty {
            Text(L("Keine Depotpositionen", "No holdings"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .appTintedPlate(radius: 14)
        } else {
            ForEach(content.rows) { holdingRow($0) }
        }
    }

    /// One plated position with its context menu.
    private func holdingRow(_ row: PortfolioRow) -> some View {
        Button {
            selected = row.holding
        } label: {
            PortfolioRowContent(row: row, basis: basis, unit: unit)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appTintedPlate(radius: 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Bearbeiten", "Edit")) { edited = row.holding }
            Button(L("Löschen", "Delete"), role: .destructive) {
                HoldingMaintenance.deletePosition(row.holding, context: context)
            }
        }
    }
}

/// The savings plans.
struct SavingsPlansView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var plans: [SavingsPlanRecord] = []
    @State private var editedPlan: SavingsPlanRecord?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Alle aktiven Sparpläne", "All active savings plans"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Pro Woche", "Per week"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Money.string(cents: SavingsPlanFixedCosts.weeklyCostCents(of: plans)))
                                .font(.title3.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("Pro Monat", "Per month"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Money.string(cents: SavingsPlanFixedCosts.monthlyCostCents(of: plans)))
                                .font(.title3.weight(.semibold))
                        }
                    }
                    Text(CalendarService.savingsPlanScheduleText(cadence: .weekly))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .appGlassRow()
            if plans.isEmpty {
                Text(L("Keine Sparpläne.", "No savings plans."))
                    .foregroundStyle(.secondary)
                    .appGlassRow()
            } else {
                ForEach(plans) { plan in
                    savingsPlanRow(plan, accounts: accounts, onEdit: { editedPlan = $0 }, onDelete: { delete($0) })
                        .appGlassRow()
                }
            }
            Section {
                if bookedExecutions.isEmpty {
                    Text(L("In diesem Zeitraum liegt keine Ausführung.", "There is no execution in this period."))
                        .foregroundStyle(.secondary)
                }
                ForEach(bookedExecutions) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(AppDate.numeric(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: abs(entry.amountCents)))
                    }
                }
            } header: {
                Text(L("Gebuchte Sparpläne", "Booked savings plans"))
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Sparpläne", "Savings plans"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $editedPlan) { plan in
            SavingsPlanEditor(plan: plan) { saved in
                SavingsPlanStore.upsert(saved)
                SavingsPlanFixedCosts.sync(context: context)
                reload()
            }
        }
    }

    private var bookedExecutions: [LedgerEntry] {
        let periods = FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts)
        guard let period = filters.period(in: periods) else { return [] }
        return entries
            .filter { BookingClassification.isSavingsPlan($0) && period.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    /// Reloads the plans.
    private func reload() {
        SavingsPlanRunner.bookDue(context: context)
        SavingsPlanFixedCosts.sync(context: context)
        plans = SavingsPlanStore.all()
    }

    /// Deletes a plan.
    private func delete(_ plan: SavingsPlanRecord) {
        SavingsPlanStore.remove(id: plan.id)
        SavingsPlanFixedCosts.sync(context: context)
        plans = SavingsPlanStore.all()
    }
}

/// A plan's name and schedule.
private struct SavingsPlanLabel: View {
    let plan: SavingsPlanRecord
    var checkingName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(plan.name)
                Spacer()
                Text(Money.string(cents: plan.amountCents))
                    .foregroundStyle(.primary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let account = checkingName.isEmpty ? L("Girokonto", "Checking account") : checkingName
        if let next = plan.nextExecution() {
            return "\(plan.cadence.label) · \(L("Nächste", "Next")) \(AppDate.numeric(next)) · \(account)"
        }
        return "\(plan.cadence.label) · \(L("Letzte", "Last")) \(AppDate.numeric(plan.lastExecution)) · \(account)"
    }
}

/// One plan row with its actions.
@MainActor
private func savingsPlanRow(
    _ plan: SavingsPlanRecord,
    accounts: [Account],
    onEdit: @escaping @MainActor (SavingsPlanRecord) -> Void,
    onDelete: @escaping @MainActor (SavingsPlanRecord) -> Void
) -> some View {
    SavingsPlanLabel(
        plan: plan,
        checkingName: accounts.first { $0.id == plan.checkingAccountID }?.name ?? ""
    )
    .contextMenu {
        Button(L("Bearbeiten", "Edit")) { onEdit(plan) }
        Button(L("Löschen", "Delete"), role: .destructive) { onDelete(plan) }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) { onDelete(plan) } label: {
            Label(L("Löschen", "Delete"), systemImage: "trash")
        }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
        Button { onEdit(plan) } label: {
            Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
        }
        .appAccentTint()
    }
}

/// Edits a plan.
private struct SavingsPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name: String
    @State private var amount: String
    @State private var cadence: Cadence
    @State private var checkingAccountID: UUID
    @State private var lastExecution: Date
    private let plan: SavingsPlanRecord
    private let onSave: (SavingsPlanRecord) -> Void

    init(plan: SavingsPlanRecord, onSave: @escaping (SavingsPlanRecord) -> Void) {
        self.plan = plan
        self.onSave = onSave
        _name = State(initialValue: plan.name)
        _amount = State(initialValue: String(format: "%.2f", Double(plan.amountCents) / 100))
        _cadence = State(initialValue: plan.cadence)
        _checkingAccountID = State(initialValue: plan.checkingAccountID)
        _lastExecution = State(initialValue: plan.lastExecution)
    }

    private var debitAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    var body: some View {
        NavigationStack {
            AppForm {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Betrag", "Amount"), text: $amount)
                    .keyboardType(.decimalPad)
                Picker(L("Rhythmus", "Cadence"), selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Abbuchungskonto", "Debit account"), selection: $checkingAccountID) {
                    ForEach(debitAccounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                DatePicker(L("Letzte Ausführung", "Last execution"), selection: $lastExecution, displayedComponents: .date)
            }
            .appGlassList()
            .navigationTitle(L("Sparplan bearbeiten", "Edit savings plan"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fillDefaultAccount)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    /// Fills the default checking account.
    private func fillDefaultAccount() {
        if debitAccounts.contains(where: { $0.id == checkingAccountID }) { return }
        if let preferred = TradeAccountPreference.accountID(),
           debitAccounts.contains(where: { $0.id == preferred }) {
            checkingAccountID = preferred
            return
        }
        if let first = debitAccounts.first {
            checkingAccountID = first.id
        }
    }

    /// Saves the plan.
    private func save() {
        guard let cents = Money.cents(from: amount), cents > 0 else { return }
        guard debitAccounts.contains(where: { $0.id == checkingAccountID }) else { return }
        var updated = plan
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.amountCents = cents
        updated.cadenceRaw = cadence.rawValue
        updated.checkingAccountID = checkingAccountID
        updated.active = true
        updated.lastExecution = lastExecution
        onSave(updated)
        dismiss()
    }
}

/// Edits one lot.
private struct LotEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let holding: PortfolioHolding
    let lot: HoldingLot
    var onFinish: (Bool) -> Void
    @State private var date: Date
    @State private var quantity: String
    @State private var amount: String
    @State private var kind: LotKind

    init(holding: PortfolioHolding, lot: HoldingLot, onFinish: @escaping (Bool) -> Void) {
        self.holding = holding
        self.lot = lot
        self.onFinish = onFinish
        _date = State(initialValue: lot.date)
        _quantity = State(initialValue: String(lot.quantity))
        _amount = State(initialValue: String(format: "%.2f", Double(abs(lot.amountCents)) / 100))
        if lot.isSale {
            _kind = State(initialValue: .sale)
        } else if lot.isSavingsPlan {
            _kind = State(initialValue: .savings)
        } else {
            _kind = State(initialValue: .buy)
        }
    }

    var body: some View {
        NavigationStack {
            AppForm {
                DatePicker(L("Datum", "Date"), selection: $date, displayedComponents: .date)
                TextField(L("Stückzahl", "Quantity"), text: $quantity)
                    .keyboardType(.decimalPad)
                TextField(L("Betrag", "Amount"), text: $amount)
                    .keyboardType(.decimalPad)
                Picker(L("Art", "Type"), selection: $kind) {
                    ForEach(LotKind.allCases) { Text($0.label).tag($0) }
                }
            }
            .appGlassList()
            .navigationTitle(L("Einzelposition", "Individual position"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    /// Saves the lot and its booking.
    private func save() {
        let count = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard count > 0, let cents = Money.cents(from: amount), cents > 0 else { return }
        var updated = lot
        updated.date = date
        updated.quantity = count
        updated.unitPriceCents = Int((Double(cents) / count).rounded())
        updated.amountCents = kind == .sale ? cents : -cents
        updated.isSale = kind == .sale
        updated.isSavingsPlan = kind == .savings
        var lots = HoldingLotStore.lots(for: holding.id)
        if let index = lots.firstIndex(where: { $0.id == lot.id }) {
            lots[index] = updated
            HoldingLotStore.replace(lots, holdingID: holding.id)
        }
        HoldingMaintenance.updateLedger(previous: lot, updated: updated, holding: holding, context: context)
        let kept = HoldingMaintenance.sync(holding, context: context)
        onFinish(kept)
        dismiss()
    }
}

/// Whether a lot is a buy, sale, or savings plan.
private enum LotKind: String, CaseIterable, Identifiable {
    case buy, savings, sale
    var id: String { rawValue }
    var label: String {
        switch self {
        case .buy: L("Kauf", "Purchase")
        case .savings: L("Sparplan", "Savings plan")
        case .sale: L("Verkauf", "Sale")
        }
    }
}

/// Details of a position.
private struct HoldingDetailView: View {
    let holding: PortfolioHolding
    /// The last day of the selected period. Lots after it stay out; a future day adds the planned purchases.
    let day: Date
    let holdings: [PortfolioHolding]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @State private var showingBuy = false
    @State private var showingSell = false
    @State private var lots: [HoldingLot] = []
    @State private var editedLot: HoldingLot?

    /// Whether the selected period is not the running one.
    private var timing: (isToday: Bool, isFuture: Bool) {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: FinanceClock.now)
        return (target == today, target > today)
    }

    /// The lots held through the selected day.
    private var shownLots: [HoldingLot] {
        guard !timing.isToday else { return lots }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) ?? day
        return lots.filter { $0.date < end }
    }

    /// The forecast savings plan purchases until a future day.
    private var plannedPurchases: [PlannedPurchase] {
        timing.isFuture ? HoldingMaintenance.plannedPurchases(of: holding, through: day, holdings: holdings) : []
    }

    var body: some View {
        let performance = projectedPerformance(holding, through: day, holdings: holdings)
        let selected = performance.selected(basis: basis, unit: unit)
        let quantity = HoldingMaintenance.quantity(of: holding, through: day, holdings: holdings)
        let value = timing.isToday ? performance.value : HoldingMaintenance.marketValue(of: holding, through: day, holdings: holdings)
        NavigationStack {
            AppForm {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        if !timing.isToday {
                            Text("\(L("Stand", "As of")) \(AppDate.numeric(day))\(timing.isFuture ? " (\(L("Prognose", "forecast")))" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(Money.string(cents: value))
                            .font(.title2.bold())
                        Text(selected.text)
                            .font(.subheadline.bold())
                            .foregroundStyle(selected.cents < 0 ? .red : (selected.cents > 0 ? .green : .secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Picker(L("Zeitraum", "Period"), selection: $basis) {
                        ForEach(PortfolioBasis.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Picker(L("Einheit", "Unit"), selection: $unit) {
                        ForEach(PortfolioUnit.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    LabeledContent(L("Stückzahl", "Quantity"), value: quantity.formatted())
                    LabeledContent(
                        timing.isFuture ? L("Kurs (Prognose)", "Price (forecast)") : L("Kurs", "Price"),
                        value: Money.string(cents: timing.isToday || quantity <= 0 ? holding.currentPriceCents : Int((Double(value) / quantity).rounded()))
                    )
                    LabeledContent(L("Kaufkurs", "Purchase price"), value: Money.string(cents: holding.purchasePriceCents))
                    if !holding.symbol.isEmpty {
                        LabeledContent("ISIN", value: holding.symbol)
                    }
                    LabeledContent(
                        L("Aktualisiert", "Updated"),
                        value: "\(AppDate.numeric(holding.updatedAt)) \(AppDate.time(holding.updatedAt))"
                    )
                }
                .appGlassRow()
                if !shownLots.isEmpty || !plannedPurchases.isEmpty {
                    Section(L("Einzelpositionen", "Individual positions")) {
                        ForEach(shownLots) { lot in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(lotTitle(lot))
                                    Spacer()
                                    Text(AppDate.numeric(lot.date))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(lot.quantity.formatted()) × \(Money.string(cents: lot.unitPriceCents)) · \(Money.string(cents: abs(lot.amountCents)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteLot(lot)
                                } label: {
                                    Label(L("Löschen", "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { editedLot = lot } label: {
                                    Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                                }
                                .appAccentTint()
                            }
                        }
                        ForEach(Array(plannedPurchases.enumerated()), id: \.offset) { _, purchase in
                            plannedRow(purchase)
                        }
                    }
                    .appGlassRow()
                }
            }
            .appGlassList()
            .contentMargins(.top, 4, for: .scrollContent)
            .listSectionSpacing(10)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    tradeIcon(L("Nachkauf", "Buy more"), systemImage: "plus.circle.fill") {
                        showingBuy = true
                    }
                    tradeIcon(
                        L("Verkaufen", "Sell"),
                        systemImage: "minus.circle.fill",
                        disabled: holding.quantity <= 0
                    ) {
                        showingSell = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .background(AppPlayfulCanvas())
            .navigationTitle(holding.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .onAppear(perform: reloadLots)
            .sheet(isPresented: $showingBuy, onDismiss: reloadLots) { HoldingTradeSheet(holding: holding, isSale: false) }
            .sheet(isPresented: $showingSell, onDismiss: reloadLots) { HoldingTradeSheet(holding: holding, isSale: true) }
            .sheet(item: $editedLot) { lot in
                LotEditor(holding: holding, lot: lot) { kept in
                    if kept {
                        reloadLots()
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }

    /// A forecast savings plan purchase. It cannot be edited because it has not happened.
    private func plannedRow(_ purchase: PlannedPurchase) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(L("Sparplan", "Savings plan")) (\(L("Prognose", "forecast")))")
                Spacer()
                Text(AppDate.numeric(purchase.date))
                    .foregroundStyle(.secondary)
            }
            Text("\(purchase.quantity.formatted(.number.precision(.fractionLength(0...4)))) × \(Money.string(cents: purchase.unitPriceCents)) · \(Money.string(cents: purchase.amountCents))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
    }

    /// Deletes a lot and its booking.
    private func deleteLot(_ lot: HoldingLot) {
        HoldingMaintenance.deleteLedger(lot, holding: holding, context: context)
        HoldingLotStore.remove(lotID: lot.id, holdingID: holding.id)
        if HoldingMaintenance.sync(holding, context: context) {
            reloadLots()
        } else {
            dismiss()
        }
    }

    /// Reloads the lots.
    private func reloadLots() {
        lots = HoldingLotStore.lots(for: holding.id).sorted { $0.date < $1.date }
    }

    /// Describes a lot.
    private func lotTitle(_ lot: HoldingLot) -> String {
        if lot.isSale { return L("Verkauf", "Sale") }
        if lot.isSavingsPlan { return L("Sparplan", "Savings plan") }
        if lot.source == "cashback" { return "Cashback" }
        if lot.source == "gift" { return L("Depotgeschenk", "Portfolio gift") }
        if lot.source == "opening" { return L("Anfangsbestand", "Opening position") }
        return L("Kauf", "Purchase")
    }

    /// The icon of a trade.
    private func tradeIcon(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .semibold))
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .liquidGlassSurface()
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

/// Creates or edits a position.
private struct HoldingForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    private let existing: PortfolioHolding?
    @State private var accountID: UUID?
    @State private var name: String
    @State private var symbol: String
    @State private var quantity: String
    @State private var purchasePrice: String
    @State private var currentPrice: String
    @State private var validationMessage: String?
    @State private var suggestions: [StockSuggestion] = []
    @State private var selectedSuggestion: StockSuggestion?
    @State private var isSearching = false
    @State private var depotName = ""
    @State private var bookPurchase = false
    @State private var checkingAccountID: UUID?

    init(holding: PortfolioHolding?, preferredAccountID: UUID? = nil) {
        existing = holding
        _accountID = State(initialValue: holding?.accountID ?? preferredAccountID)
        _name = State(initialValue: holding?.name ?? "")
        _symbol = State(initialValue: holding?.symbol ?? "")
        _quantity = State(initialValue: holding.map { String($0.quantity) } ?? "")
        _purchasePrice = State(initialValue: holding.map { String(format: "%.2f", Double($0.purchasePriceCents) / 100) } ?? "")
        _currentPrice = State(initialValue: holding.map { String(format: "%.2f", Double($0.currentPriceCents) / 100) } ?? "")
        _selectedSuggestion = State(initialValue: holding.map {
            StockSuggestion(
                symbol: MarketSymbolStore.symbol(for: $0.id) ?? "",
                name: $0.name,
                exchange: ""
            )
        })
    }

    var body: some View {
        NavigationStack {
            AppForm {
                if portfolioAccounts.isEmpty {
                    Text(L(
                        "Für eine Aktie brauchst du ein Depotkonto. Es wird als nicht liquide angelegt und mit einem Girokonto verknüpft.",
                        "A stock needs a portfolio account. It is created as non-liquid and linked to a checking account."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextField(L("Depotname", "Portfolio name"), text: $depotName)
                    checkingLinkPicker
                } else {
                    Picker(L("Depotkonto", "Portfolio account"), selection: $accountID) {
                        ForEach(portfolioAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if selectedPortfolioNeedsLink {
                        checkingLinkPicker
                    }
                }
                if existing == nil {
                    Toggle(L("Kauf vom Girokonto abbuchen", "Debit the purchase from a checking account"), isOn: $bookPurchase)
                    if bookPurchase && !portfolioAccounts.isEmpty && !selectedPortfolioNeedsLink {
                        if checkingAccounts.isEmpty {
                            Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(L("Girokonto", "Checking account"), selection: $checkingAccountID) {
                                ForEach(checkingAccounts) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                    }
                }
                TextField("ISIN", text: $symbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: symbol) {
                        suggestions = []
                        selectedSuggestion = nil
                        name = ""
                    }
                Button {
                    Task { await search() }
                } label: {
                    if isSearching {
                        ProgressView()
                    } else {
                        Label(L("Aktie suchen", "Search stock"), systemImage: "magnifyingglass")
                    }
                }
                .disabled(isSearching || !MarketDataService.isQuoteable(symbol))

                ForEach(suggestions) { suggestion in
                    Button {
                        Task { await select(suggestion) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(suggestion.name).foregroundStyle(.primary)
                                Text("\(suggestion.symbol) · \(suggestion.exchange)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedSuggestion == suggestion {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                    }
                }
                if let selectedSuggestion {
                    LabeledContent(
                        L("Ausgewählt", "Selected"),
                        value: selectedSuggestion.name
                    )
                }
                TextField(L("Stückzahl", "Quantity"), text: $quantity).keyboardType(.decimalPad)
                TextField(L("Kaufkurs", "Purchase price"), text: $purchasePrice).keyboardType(.decimalPad)
                TextField(L("Aktueller Kurs (Fallback)", "Current price (fallback)"), text: $currentPrice).keyboardType(.decimalPad)
                Text(L(
                    "Der aktuelle Kurs wird anhand der ISIN online gesucht. Der Fallback bleibt erhalten, falls der Abruf fehlschlägt.",
                    "The current price is looked up online using the ISIN. The fallback remains if the request fails."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }
            .appGlassList()
            .navigationTitle(L("Depotposition", "Holding"))
            .onAppear {
                if accountID == nil { accountID = portfolioAccounts.first?.id }
                if checkingAccountID == nil {
                    if let accountID, let linked = PortfolioLinkStore.checkingID(for: accountID) {
                        checkingAccountID = linked
                    } else if let id = TradeAccountPreference.accountID(),
                       checkingAccounts.contains(where: { $0.id == id }) {
                        checkingAccountID = id
                    } else {
                        checkingAccountID = checkingAccounts.first?.id
                    }
                }
                if depotName.isEmpty { depotName = L("Depot", "Portfolio") }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        let normalizedQuantity = quantity.replacingOccurrences(of: ",", with: ".")
                        let normalizedISIN = symbol
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()
                        guard let count = Double(normalizedQuantity),
                              let purchase = Money.cents(from: purchasePrice),
                              !name.isEmpty else {
                            validationMessage = L("Bitte alle Werte prüfen.", "Please check all values.")
                            return
                        }
                        let current = Money.cents(from: currentPrice) ?? purchase
                        let unchangedLegacyIdentifier = existing.map {
                            $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedISIN
                        } ?? false
                        guard MarketDataService.isQuoteable(normalizedISIN) || unchangedLegacyIdentifier else {
                            validationMessage = L("Bitte eine gültige zwölfstellige ISIN eingeben.", "Enter a valid twelve-character ISIN.")
                            return
                        }
                        guard let selectedSuggestion else {
                            validationMessage = L("Bitte zuerst eine Aktie aus den Vorschlägen auswählen.", "Select a stock from the suggestions first.")
                            return
                        }
                        if (portfolioAccounts.isEmpty || selectedPortfolioNeedsLink || bookPurchase), checkingAccountID == nil {
                            validationMessage = L(
                                "Ein Depot muss mit einem Girokonto verknüpft sein.",
                                "A portfolio must be linked to a checking account."
                            )
                            return
                        }
                        let portfolioAccount = resolvedPortfolioAccount()
                        if let checkingAccountID, PortfolioLinkStore.checkingID(for: portfolioAccount.id) == nil {
                            PortfolioLinkStore.link(portfolio: portfolioAccount.id, to: checkingAccountID)
                        }
                        let holding = existing ?? PortfolioHolding(name: selectedSuggestion.name, quantity: count, purchasePriceCents: purchase, currentPriceCents: current)
                        holding.accountID = portfolioAccount.id
                        holding.name = selectedSuggestion.name
                        holding.symbol = normalizedISIN
                        holding.quantity = count
                        holding.purchasePriceCents = purchase
                        holding.currentPriceCents = current
                        holding.updatedAt = .now
                        if existing == nil {
                            context.insert(holding)
                            HoldingPurchaseDateStore.set(.now, for: holding.id)
                            HoldingLotStore.add(
                                HoldingLot(
                                    date: .now,
                                    quantity: count,
                                    unitPriceCents: purchase,
                                    amountCents: -Int((count * Double(abs(purchase))).rounded()),
                                    isSale: false,
                                    isSavingsPlan: false
                                ),
                                holdingID: holding.id
                            )
                            if bookPurchase, let checkingAccountID {
                                let cost = Int((count * Double(abs(purchase))).rounded())
                                context.insert(LedgerEntry(
                                    date: .now,
                                    title: "\(L("Kauf", "Buy")): \(holding.name)",
                                    amountCents: cost,
                                    kind: .transfer,
                                    fromAccountID: checkingAccountID,
                                    toAccountID: portfolioAccount.id
                                ))
                            }
                        }
                        if !selectedSuggestion.symbol.isEmpty {
                            MarketSymbolStore.set(selectedSuggestion.symbol, for: holding.id)
                        }
                        try? context.save()
                        Task {
                            do {
                                let quote: MarketQuote
                                if selectedSuggestion.symbol.isEmpty {
                                    quote = try await MarketDataService.quote(for: normalizedISIN)
                                } else {
                                    quote = try await MarketDataService.quote(for: selectedSuggestion)
                                }
                                holding.currentPriceCents = quote.priceCents
                                if let previous = quote.previousCloseCents {
                                    PreviousCloseStore.set(previous, for: holding.id)
                                }
                                holding.updatedAt = .now
                                try? context.save()
                            } catch {
                                // Keep the manually entered fallback price.
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var portfolioAccounts: [Account] {
        accounts.filter { $0.kind == .portfolio }
    }

    private var checkingAccounts: [Account] {
        accounts.filter { $0.kind == .checking }
    }

    private var selectedPortfolioNeedsLink: Bool {
        guard let accountID else { return portfolioAccounts.isEmpty }
        return PortfolioLinkStore.checkingID(for: accountID) == nil
    }

    @ViewBuilder
    private var checkingLinkPicker: some View {
        if checkingAccounts.isEmpty {
            Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker(L("Verknüpftes Girokonto", "Linked checking account"), selection: $checkingAccountID) {
                ForEach(checkingAccounts) { Text($0.name).tag(Optional($0.id)) }
            }
        }
    }

    /// Finds or creates the depot account.
    private func resolvedPortfolioAccount() -> Account {
        if let accountID, let match = portfolioAccounts.first(where: { $0.id == accountID }) {
            return match
        }
        if let existingAccount = portfolioAccounts.first {
            return existingAccount
        }
        let trimmed = depotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(
            name: trimmed.isEmpty ? L("Depot", "Portfolio") : trimmed,
            kind: .portfolio,
            isLiquid: false
        )
        context.insert(account)
        return account
    }

    /// Searches for the entered ISIN.
    @MainActor
    private func search() async {
        isSearching = true
        validationMessage = nil
        defer { isSearching = false }
        do {
            suggestions = try await MarketDataService.suggestions(for: symbol)
            if suggestions.isEmpty {
                validationMessage = L("Keine passende Aktie gefunden.", "No matching stock found.")
            }
        } catch {
            validationMessage = L("Die Aktiensuche ist fehlgeschlagen.", "The stock search failed.")
        }
    }

    /// Applies a found security.
    @MainActor
    private func select(_ suggestion: StockSuggestion) async {
        selectedSuggestion = suggestion
        name = suggestion.name
        do {
            let cents = try await MarketDataService.currentPriceCents(for: suggestion)
            currentPrice = String(format: "%.2f", Double(cents) / 100)
        } catch {
            validationMessage = L("Der aktuelle Kurs konnte nicht geladen werden.", "The current price could not be loaded.")
        }
    }
}

/// Books a buy or sale.
private struct HoldingTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @AppStorage(TradeFeePreference.storageKey) private var defaultFeeCents = TradeFeePreference.defaultCents
    let holding: PortfolioHolding
    let isSale: Bool
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = ""
    @State private var includeFee = false
    @State private var sellByPercent = false
    @State private var percentText = "100"
    @State private var isTransfer = false
    @State private var date = Date.now
    @State private var checkingAccountID: UUID?
    @State private var depotName = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            AppForm {
                if !isSale {
                    Picker(L("Art", "Type"), selection: $isTransfer) {
                        Text(L("Kauf", "Purchase")).tag(false)
                        Text(L("Übertrag", "Transfer")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isTransfer {
                        Text(L("Ohne Abbuchung vom Girokonto.", "No debit from the checking account."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if isSale {
                    Picker(L("Menge", "Amount"), selection: $sellByPercent) {
                        Text(L("Stückzahl", "Quantity")).tag(false)
                        Text(L("Prozent", "Percent")).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if isSale && sellByPercent {
                    TextField(L("Prozent", "Percent"), text: $percentText).keyboardType(.decimalPad)
                    HStack {
                        ForEach([25, 50, 75, 100], id: \.self) { value in
                            Button("\(value) %") { percentText = "\(value)" }
                                .buttonStyle(.bordered)
                        }
                    }
                    Text(L("Das sind \(sharePreview) Stück.", "That is \(sharePreview) shares."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField(L("Stückzahl", "Quantity"), text: $quantity).keyboardType(.decimalPad)
                }
                TextField(L("Kurs", "Price"), text: $price, prompt: Text(isSale ? L("Kurs", "Price") : L("Kurs eingeben", "Enter price")))
                    .keyboardType(.decimalPad)
                if !isTransfer {
                    Toggle(L("Gebühr", "Fee"), isOn: $includeFee)
                    if includeFee {
                        TextField(L("Gebühr", "Fee"), text: $fee).keyboardType(.decimalPad)
                        Text(L(
                            "Die Gebühr gilt einmal für diese Buchung, unabhängig von der Stückzahl.",
                            "The fee applies once to this booking, regardless of quantity."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                AppDateField(title: L("Datum", "Date"), selection: $date)
                if let linked = preferredCheckingAccount, portfolioAccount != nil, !portfolioNeedsLink {
                    LabeledContent(L("Girokonto", "Checking account"), value: linked.name)
                } else if !isTransfer || portfolioAccount == nil || portfolioNeedsLink {
                    if checkingAccounts.isEmpty {
                        Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(L("Girokonto", "Checking account"), selection: $checkingAccountID) {
                            ForEach(checkingAccounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Text(L(
                            "Dieses Girokonto bleibt an dem Depot. Ein zweites Depot bekommt ein eigenes.",
                            "This checking account stays with this portfolio. A second portfolio gets its own."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if portfolioAccount == nil {
                    Text(L(
                        "Für die Buchung wird ein nicht liquides Depotkonto angelegt.",
                        "A non-liquid portfolio account is created for this booking."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextField(L("Depotname", "Portfolio name"), text: $depotName)
                }
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }
            .appGlassList()
            .navigationTitle(isSale ? L("Verkaufen", "Sell") : L("Nachkaufen", "Buy more"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isSale, price.isEmpty {
                    price = String(format: "%.2f", Double(holding.currentPriceCents) / 100)
                }
                if checkingAccountID == nil { checkingAccountID = preferredCheckingAccount?.id }
                if depotName.isEmpty { depotName = L("Depot", "Portfolio") }
            }
            .onChange(of: includeFee) {
                guard includeFee, fee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                fee = TradeFeePreference.editString(cents: defaultFeeCents)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Buchen", "Book")) { save() } }
            }
        }
    }

    private var checkingAccounts: [Account] {
        accounts.filter { $0.kind == .checking }
    }

    private var preferredCheckingAccount: Account? {
        if let portfolio = portfolioAccount,
           let linked = PortfolioLinkStore.checkingID(for: portfolio.id),
           let match = checkingAccounts.first(where: { $0.id == linked }) {
            return match
        }
        if let id = TradeAccountPreference.accountID(),
           let match = checkingAccounts.first(where: { $0.id == id }) {
            return match
        }
        return checkingAccounts.first
    }

    private var portfolioNeedsLink: Bool {
        guard let portfolio = portfolioAccount else { return true }
        return PortfolioLinkStore.checkingID(for: portfolio.id) == nil
    }

    private var sharePreview: String {
        let percent = Double(percentText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return max(0, holding.quantity * percent / 100).formatted()
    }

    private var portfolioAccount: Account? {
        if let id = holding.accountID, let match = accounts.first(where: { $0.id == id && $0.kind == .portfolio }) {
            return match
        }
        return accounts.first { $0.kind == .portfolio }
    }

    /// Saves the trade with its booking.
    private func save() {
        let count: Double
        if isSale && sellByPercent {
            let percent = Double(percentText.replacingOccurrences(of: ",", with: ".")) ?? -1
            guard percent > 0, percent <= 100 else {
                validationMessage = L("Bitte einen Prozentwert zwischen 0 und 100 eingeben.", "Enter a percentage between 0 and 100.")
                return
            }
            count = percent >= 99.995 ? holding.quantity : holding.quantity * percent / 100
        } else {
            count = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        guard count > 0, let priceCents = Money.cents(from: price), priceCents > 0 else {
            validationMessage = L("Bitte Stückzahl und Kurs prüfen.", "Check the quantity and price.")
            return
        }
        if isSale, count > holding.quantity {
            validationMessage = L("Du kannst nicht mehr verkaufen, als im Depot liegt.", "You cannot sell more than the holding contains.")
            return
        }
        let feeCents = resolvedFeeCents
        guard feeCents >= 0 else {
            validationMessage = L("Bitte die Gebühr prüfen.", "Check the fee.")
            return
        }
        let sharesValue = Int((count * Double(abs(priceCents))).rounded())
        if !isTransfer, isSale, feeCents > sharesValue {
            validationMessage = L("Die Gebühr ist höher als der Verkaufserlös.", "The fee is higher than the sale proceeds.")
            return
        }
        let booksCash = !isTransfer
        if booksCash, checkingAccountID == nil {
            validationMessage = L("Bitte ein Girokonto auswählen.", "Select a checking account.")
            return
        }
        let portfolio: Account
        let createdPortfolio: Account?
        if let existing = portfolioAccount {
            portfolio = existing
            createdPortfolio = nil
        } else {
            let trimmed = depotName.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = Account(
                name: trimmed.isEmpty ? L("Depot", "Portfolio") : trimmed,
                kind: .portfolio,
                isLiquid: false
            )
            context.insert(account)
            portfolio = account
            createdPortfolio = account
        }
        if let linked = PortfolioLinkStore.checkingID(for: portfolio.id) {
            checkingAccountID = linked
        } else if PortfolioLinkStore.checkingID(for: portfolio.id) == nil {
            guard let checkingAccountID else {
                if let createdPortfolio { context.delete(createdPortfolio) }
                validationMessage = L(
                    "Ein Depot muss mit einem Girokonto verknüpft sein.",
                    "A portfolio must be linked to a checking account."
                )
                return
            }
            PortfolioLinkStore.link(portfolio: portfolio.id, to: checkingAccountID)
        }
        let appliedFee = booksCash ? feeCents : 0
        var lot = HoldingLot(
            date: date,
            quantity: count,
            unitPriceCents: priceCents,
            amountCents: isSale ? sharesValue - appliedFee : -(sharesValue + appliedFee),
            isSale: isSale,
            isSavingsPlan: false
        )
        if isSale {
            holding.quantity -= count
            if let checkingAccountID {
                let entry = LedgerEntry(
                    date: date,
                    title: "\(L("Verkauf", "Sell")): \(holding.name)",
                    notes: feeNote(appliedFee),
                    amountCents: sharesValue - appliedFee,
                    kind: .transfer,
                    fromAccountID: portfolio.id,
                    toAccountID: checkingAccountID
                )
                context.insert(entry)
                lot.ledgerEntryID = entry.id
            }
        } else {
            let addedCost = sharesValue + appliedFee
            let previousValue = holding.quantity * Double(holding.purchasePriceCents)
            let nextQuantity = holding.quantity + count
            holding.purchasePriceCents = Int(((previousValue + Double(addedCost)) / nextQuantity).rounded())
            holding.quantity = nextQuantity
            if booksCash, let checkingAccountID {
                context.insert(LedgerEntry(
                    date: date,
                    title: "\(L("Kauf", "Buy")): \(holding.name)",
                    notes: feeNote(appliedFee),
                    amountCents: addedCost,
                    kind: .transfer,
                    fromAccountID: checkingAccountID,
                    toAccountID: portfolio.id
                ))
            }
        }
        HoldingLotStore.add(lot, holdingID: holding.id)
        holding.accountID = portfolio.id
        holding.updatedAt = .now
        try? context.save()
        dismiss()
    }

    private var resolvedFeeCents: Int {
        if isTransfer || !includeFee { return 0 }
        let trimmed = fee.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return Money.cents(from: trimmed) ?? -1
    }

    /// Describes the fee.
    private func feeNote(_ cents: Int) -> String {
        guard cents > 0 else { return "" }
        return "\(L("Gebühr", "Fee")): \(Money.string(cents: cents))"
    }
}
