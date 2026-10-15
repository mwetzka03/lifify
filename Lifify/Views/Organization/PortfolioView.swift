import SwiftData
import SwiftUI

struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @AppStorage("portfolioSort") private var sort = PortfolioSort.value.rawValue
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var selected: PortfolioHolding?
    @State private var isRefreshing = false
    @State private var savingsPlans: [SavingsPlanRecord] = []
    @Query(sort: \Account.name) private var planAccounts: [Account]

    var body: some View {
        List {
            Section {
                let totals = portfolioPerformance
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Depotwert", "Portfolio value"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: totals.value))
                        .font(.title2.bold())
                    selectedPerformanceLabel(totals)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            Section {
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
            }
            Section {
                Picker(L("Sortierung", "Sort"), selection: $sort) {
                    ForEach(PortfolioSort.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if !savingsPlans.isEmpty {
                Section(L("Sparpläne", "Savings plans")) {
                    ForEach(savingsPlans) { plan in
                        SavingsPlanLabel(plan: plan, checkingName: planAccounts.first { $0.id == plan.checkingAccountID }?.name ?? "")
                    }
                }
            }
            ForEach(sortedHoldings) { holding in
                let performance = holdingPerformance(holding)
                Button {
                    selected = holding
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(holding.name).foregroundStyle(.primary)
                            Text("\(holding.quantity.formatted()) × \(Money.string(cents: holding.currentPriceCents))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.string(cents: performance.value))
                                .foregroundStyle(.primary)
                            selectedPerformanceLabel(performance)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteHolding(holding)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        edited = holding
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .overlay {
            if holdings.isEmpty { ContentUnavailableView(L("Keine Depotpositionen", "No holdings"), systemImage: "chart.line.uptrend.xyaxis") }
        }
        .navigationTitle(L("Depot", "Portfolio"))
        .toolbar {
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
        .onAppear {
            for holding in holdings where HoldingPurchaseDateStore.date(for: holding.id) == nil {
                HoldingPurchaseDateStore.set(holding.updatedAt, for: holding.id)
            }
            SavingsPlanRunner.bookDue(context: context)
            savingsPlans = SavingsPlanStore.all()
        }
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil) }
        .sheet(item: $edited) { HoldingForm(holding: $0) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0) }
    }

    fileprivate func deleteHolding(_ holding: PortfolioHolding) {
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
        HoldingLotStore.removeAll(for: holding.id)
        context.delete(holding)
        try? context.save()
    }

    private var sortedHoldings: [PortfolioHolding] {
        switch PortfolioSort(rawValue: sort) ?? .value {
        case .value:
            return holdings.sorted { holdingPerformance($0).value > holdingPerformance($1).value }
        case .purchase:
            return holdings.sorted { lhs, rhs in
                let left = HoldingPurchaseDateStore.date(for: lhs.id) ?? .distantPast
                let right = HoldingPurchaseDateStore.date(for: rhs.id) ?? .distantPast
                if left != right { return left > right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .name:
            return holdings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var portfolioPerformance: HoldingPerformance {
        holdings.reduce(HoldingPerformance()) { total, holding in
            total.adding(holdingPerformance(holding))
        }
    }

    private func selectedPerformanceLabel(_ performance: HoldingPerformance) -> some View {
        let selected = performance.selected(basis: basis, unit: unit)
        return Text(selected.text)
            .font(.caption.bold())
            .foregroundStyle(selected.cents < 0 ? .red : (selected.cents > 0 ? .green : .secondary))
    }
}

struct PortfolioElementsView: View {
    var accountID: UUID?
    var showsValueHeader = true
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @AppStorage("portfolioSort") private var sort = PortfolioSort.value.rawValue
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var selected: PortfolioHolding?
    @State private var isRefreshing = false
    @State private var savingsPlans: [SavingsPlanRecord] = []
    @Query(sort: \Account.name) private var accounts: [Account]

    private var visibleHoldings: [PortfolioHolding] {
        guard let accountID else { return holdings }
        return holdings.filter { $0.accountID == accountID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsValueHeader {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Depotwert", "Portfolio value"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: portfolioTotals.value))
                        .font(.title2.bold())
                    performanceLabel(portfolioTotals)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
            }
            savingsPlanCard

            VStack(alignment: .leading, spacing: 8) {
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
                Picker(L("Sortierung", "Sort"), selection: $sort) {
                    ForEach(PortfolioSort.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button {
                    Task {
                        isRefreshing = true
                        await MarketDataService.refresh(holdings: visibleHoldings, context: context)
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label(L("Kurse", "Quotes"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || visibleHoldings.isEmpty)
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    Label(L("Position", "Holding"), systemImage: "plus")
                }
            }
            .font(.body.weight(.semibold))

            if sortedHoldings.isEmpty {
                Text(L("Keine Depotpositionen", "No holdings"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(sortedHoldings) { holding in
                    holdingRow(holding)
                }
            }
        }
        .onAppear {
            for holding in visibleHoldings where HoldingPurchaseDateStore.date(for: holding.id) == nil {
                HoldingPurchaseDateStore.set(holding.updatedAt, for: holding.id)
            }
            SavingsPlanRunner.bookDue(context: context)
            savingsPlans = SavingsPlanStore.all()
        }
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil, preferredAccountID: accountID) }
        .sheet(item: $edited) { HoldingForm(holding: $0, preferredAccountID: accountID) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0) }
    }

    private var visiblePlans: [SavingsPlanRecord] {
        savingsPlans.filter { accountID == nil || $0.portfolioAccountID == accountID }
    }

    @ViewBuilder
    private var savingsPlanCard: some View {
        if !visiblePlans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Sparpläne", "Savings plans"))
                    .font(.headline)
                ForEach(visiblePlans) { plan in
                    SavingsPlanLabel(
                        plan: plan,
                        checkingName: accounts.first { $0.id == plan.checkingAccountID }?.name ?? ""
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var portfolioTotals: HoldingPerformance {
        visibleHoldings.reduce(HoldingPerformance()) { $0.adding(holdingPerformance($1)) }
    }

    private func holdingRow(_ holding: PortfolioHolding) -> some View {
        let performance = holdingPerformance(holding)
        return Button {
            selected = holding
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(holding.name).foregroundStyle(.primary)
                    Text("\(holding.quantity.formatted()) × \(Money.string(cents: holding.currentPriceCents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.string(cents: performance.value))
                        .foregroundStyle(.primary)
                    performanceLabel(performance)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Bearbeiten", "Edit")) { edited = holding }
            Button(L("Löschen", "Delete"), role: .destructive) {
                delete(holding)
            }
        }
    }

    private func delete(_ holding: PortfolioHolding) {
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
        HoldingLotStore.removeAll(for: holding.id)
        context.delete(holding)
        try? context.save()
    }

    private var sortedHoldings: [PortfolioHolding] {
        switch PortfolioSort(rawValue: sort) ?? .value {
        case .value:
            return visibleHoldings.sorted { holdingPerformance($0).value > holdingPerformance($1).value }
        case .purchase:
            return visibleHoldings.sorted { lhs, rhs in
                let left = HoldingPurchaseDateStore.date(for: lhs.id) ?? .distantPast
                let right = HoldingPurchaseDateStore.date(for: rhs.id) ?? .distantPast
                if left != right { return left > right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .name:
            return visibleHoldings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func performanceLabel(_ performance: HoldingPerformance) -> some View {
        let selected = performance.selected(basis: basis, unit: unit)
        return Text(selected.text)
            .font(.caption.bold())
            .foregroundStyle(selected.cents < 0 ? .red : (selected.cents > 0 ? .green : .secondary))
    }
}

private enum PortfolioBasis: String, CaseIterable, Identifiable {
    case today
    case purchase

    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: L("Heute", "Today")
        case .purchase: L("Seit Kauf", "Since purchase")
        }
    }
}

private enum PortfolioSort: String, CaseIterable, Identifiable {
    case value
    case purchase
    case name

    var id: String { rawValue }
    var label: String {
        switch self {
        case .value: L("Wert", "Value")
        case .purchase: L("Kauf", "Purchase")
        case .name: "A–Z"
        }
    }
}

private enum PortfolioUnit: String, CaseIterable, Identifiable {
    case percent
    case eur

    var id: String { rawValue }
    var label: String {
        switch self {
        case .percent: "%"
        case .eur: "€"
        }
    }
}

func holdingPerformance(_ holding: PortfolioHolding) -> HoldingPerformance {
    let value = Int((holding.quantity * Double(holding.currentPriceCents)).rounded())
    let purchaseValue = Int((holding.quantity * Double(holding.purchasePriceCents)).rounded())
    let previous = PreviousCloseStore.cents(for: holding.id)
    let day: (cents: Int, base: Int)?
    if let previous, previous > 0 {
        day = (
            value - Int((holding.quantity * Double(previous)).rounded()),
            Int((holding.quantity * Double(previous)).rounded())
        )
    } else {
        day = nil
    }
    return HoldingPerformance(
        value: value,
        dayCents: day?.cents,
        dayBase: day?.base ?? 0,
        purchaseCents: value - purchaseValue,
        purchaseBase: purchaseValue
    )
}

struct HoldingPerformance {
    var value = 0
    var dayCents: Int?
    var dayBase = 0
    var purchaseCents = 0
    var purchaseBase = 0

    var dayPercent: Double? {
        guard dayCents != nil, dayBase > 0 else { return nil }
        return Double(dayCents ?? 0) / Double(dayBase)
    }

    var purchasePercent: Double? {
        guard purchaseBase > 0 else { return nil }
        return Double(purchaseCents) / Double(purchaseBase)
    }

    func adding(_ other: HoldingPerformance) -> HoldingPerformance {
        HoldingPerformance(
            value: value + other.value,
            dayCents: dayCents == nil && other.dayCents == nil ? nil : (dayCents ?? 0) + (other.dayCents ?? 0),
            dayBase: dayBase + other.dayBase,
            purchaseCents: purchaseCents + other.purchaseCents,
            purchaseBase: purchaseBase + other.purchaseBase
        )
    }

    func selected(basis: String, unit: String) -> (text: String, cents: Int) {
        let useToday = basis != PortfolioBasis.purchase.rawValue
        let useEuro = unit == PortfolioUnit.eur.rawValue
        if useToday {
            guard let cents = dayCents else {
                return (L("Kein Vortageskurs", "No previous close"), 0)
            }
            if useEuro { return (signedMoney(cents), cents) }
            guard let percent = dayPercent else {
                return (L("Kein Vortageskurs", "No previous close"), cents)
            }
            return (signedPercent(percent), cents)
        }
        if useEuro { return (signedMoney(purchaseCents), purchaseCents) }
        guard let percent = purchasePercent else { return (signedMoney(purchaseCents), purchaseCents) }
        return (signedPercent(percent), purchaseCents)
    }

    private func signedMoney(_ cents: Int) -> String {
        cents > 0 ? "+\(Money.string(cents: cents))" : Money.string(cents: cents)
    }

    private func signedPercent(_ ratio: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = formatter.plusSign
        return formatter.string(from: NSNumber(value: ratio)) ?? "0 %"
    }
}

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
        if plan.active, let next = plan.nextExecution() {
            return "\(plan.cadence.label) · \(L("Aktiv", "Active")) · \(L("Nächste", "Next")) \(AppDate.numeric(next)) · \(account)"
        }
        return "\(plan.cadence.label) · \(L("Beendet", "Ended")) · \(L("Letzte", "Last")) \(AppDate.numeric(plan.lastExecution)) · \(account)"
    }
}

private struct HoldingDetailView: View {
    let holding: PortfolioHolding
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @State private var showingBuy = false
    @State private var showingSell = false
    @State private var lots: [HoldingLot] = []

    var body: some View {
        let performance = holdingPerformance(holding)
        let selected = performance.selected(basis: basis, unit: unit)
        NavigationStack {
            Form {
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
                .listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Money.string(cents: performance.value))
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
                LabeledContent(L("Stückzahl", "Quantity"), value: holding.quantity.formatted())
                LabeledContent(L("Kurs", "Price"), value: Money.string(cents: holding.currentPriceCents))
                LabeledContent(L("Kaufkurs", "Purchase price"), value: Money.string(cents: holding.purchasePriceCents))
                if !holding.symbol.isEmpty {
                    LabeledContent("ISIN", value: holding.symbol)
                }
                LabeledContent(
                    L("Aktualisiert", "Updated"),
                    value: "\(AppDate.numeric(holding.updatedAt)) \(AppDate.time(holding.updatedAt))"
                )
                if !lots.isEmpty {
                    Section(L("Einzelpositionen", "Individual positions")) {
                        ForEach(lots) { lot in
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
                        }
                    }
                }
            }
            .navigationTitle(holding.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: reloadLots)
            .sheet(isPresented: $showingBuy, onDismiss: reloadLots) { HoldingTradeSheet(holding: holding, isSale: false) }
            .sheet(isPresented: $showingSell, onDismiss: reloadLots) { HoldingTradeSheet(holding: holding, isSale: true) }
        }
    }

    private func reloadLots() {
        lots = HoldingLotStore.lots(for: holding.id).sorted { $0.date < $1.date }
    }

    private func lotTitle(_ lot: HoldingLot) -> String {
        if lot.isSale { return L("Verkauf", "Sale") }
        if lot.isSavingsPlan { return L("Sparplan", "Savings plan") }
        return L("Kauf", "Purchase")
    }

    private func tradeIcon(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

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
            Form {
                if portfolioAccounts.isEmpty {
                    Text(L(
                        "Für eine Aktie brauchst du ein Depotkonto. Es wird als nicht liquide angelegt.",
                        "A stock needs a portfolio account. It is created as non-liquid."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextField(L("Depotname", "Portfolio name"), text: $depotName)
                } else {
                    Picker(L("Depotkonto", "Portfolio account"), selection: $accountID) {
                        ForEach(portfolioAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if existing == nil {
                    Toggle(L("Kauf vom Girokonto abbuchen", "Debit the purchase from a checking account"), isOn: $bookPurchase)
                    if bookPurchase {
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
                .disabled(isSearching || !MarketDataService.isValidISIN(symbol))

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
            .navigationTitle(L("Depotposition", "Holding"))
            .onAppear {
                if accountID == nil { accountID = portfolioAccounts.first?.id }
                if checkingAccountID == nil {
                    if let id = TradeAccountPreference.accountID(),
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
                        guard MarketDataService.isValidISIN(normalizedISIN) || unchangedLegacyIdentifier else {
                            validationMessage = L("Bitte eine gültige zwölfstellige ISIN eingeben.", "Enter a valid twelve-character ISIN.")
                            return
                        }
                        guard let selectedSuggestion else {
                            validationMessage = L("Bitte zuerst eine Aktie aus den Vorschlägen auswählen.", "Select a stock from the suggestions first.")
                            return
                        }
                        if bookPurchase && existing == nil && checkingAccountID == nil {
                            validationMessage = L("Bitte ein Girokonto auswählen.", "Select a checking account.")
                            return
                        }
                        let portfolioAccount = resolvedPortfolioAccount()
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
            Form {
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
                if !isTransfer {
                    if checkingAccounts.isEmpty {
                        Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(L("Girokonto", "Checking account"), selection: $checkingAccountID) {
                            ForEach(checkingAccounts) { Text($0.name).tag(Optional($0.id)) }
                        }
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
        if let id = TradeAccountPreference.accountID(),
           let match = checkingAccounts.first(where: { $0.id == id }) {
            return match
        }
        return checkingAccounts.first
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
        if let existing = portfolioAccount {
            portfolio = existing
        } else {
            let trimmed = depotName.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = Account(
                name: trimmed.isEmpty ? L("Depot", "Portfolio") : trimmed,
                kind: .portfolio,
                isLiquid: false
            )
            context.insert(account)
            portfolio = account
        }
        let appliedFee = booksCash ? feeCents : 0
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: count,
                unitPriceCents: priceCents,
                amountCents: isSale ? sharesValue - appliedFee : -(sharesValue + appliedFee),
                isSale: isSale,
                isSavingsPlan: false
            ),
            holdingID: holding.id
        )
        if isSale {
            holding.quantity -= count
            if let checkingAccountID {
                context.insert(LedgerEntry(
                    date: date,
                    title: "\(L("Verkauf", "Sell")): \(holding.name)",
                    notes: feeNote(appliedFee),
                    amountCents: sharesValue - appliedFee,
                    kind: .transfer,
                    fromAccountID: portfolio.id,
                    toAccountID: checkingAccountID
                ))
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

    private func feeNote(_ cents: Int) -> String {
        guard cents > 0 else { return "" }
        return "\(L("Gebühr", "Fee")): \(Money.string(cents: cents))"
    }
}
