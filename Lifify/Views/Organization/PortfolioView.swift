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
                        delete(holding)
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
        }
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil) }
        .sheet(item: $edited) { HoldingForm(holding: $0) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0) }
    }

    private func delete(_ holding: PortfolioHolding) {
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
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

private func holdingPerformance(_ holding: PortfolioHolding) -> HoldingPerformance {
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

private struct HoldingPerformance {
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

private struct HoldingDetailView: View {
    let holding: PortfolioHolding
    @AppStorage("portfolioPerformanceBasis") private var basis = PortfolioBasis.today.rawValue
    @AppStorage("portfolioPerformanceUnit") private var unit = PortfolioUnit.percent.rawValue
    @State private var showingBuy = false
    @State private var showingSell = false

    var body: some View {
        let performance = holdingPerformance(holding)
        let selected = performance.selected(basis: basis, unit: unit)
        NavigationStack {
            Form {
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
                Button(L("Nachkaufen", "Buy more")) { showingBuy = true }
                Button(L("Verkaufen", "Sell")) { showingSell = true }
                    .disabled(holding.quantity <= 0)
            }
            .navigationTitle(holding.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingBuy) { HoldingTradeSheet(holding: holding, isSale: false) }
            .sheet(isPresented: $showingSell) { HoldingTradeSheet(holding: holding, isSale: true) }
        }
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

    init(holding: PortfolioHolding?) {
        existing = holding
        _accountID = State(initialValue: holding?.accountID)
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
                if checkingAccountID == nil { checkingAccountID = checkingAccounts.first?.id }
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
    let holding: PortfolioHolding
    let isSale: Bool
    @State private var quantity = ""
    @State private var price = ""
    @State private var date = Date.now
    @State private var checkingAccountID: UUID?
    @State private var depotName = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Stückzahl", "Quantity"), text: $quantity).keyboardType(.decimalPad)
                TextField(L("Kurs", "Price"), text: $price).keyboardType(.decimalPad)
                AppDateField(title: L("Datum", "Date"), selection: $date)
                if checkingAccounts.isEmpty {
                    Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(L("Girokonto", "Checking account"), selection: $checkingAccountID) {
                        ForEach(checkingAccounts) { Text($0.name).tag(Optional($0.id)) }
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
                if price.isEmpty {
                    price = String(format: "%.2f", Double(holding.currentPriceCents) / 100)
                }
                if checkingAccountID == nil { checkingAccountID = checkingAccounts.first?.id }
                if depotName.isEmpty { depotName = L("Depot", "Portfolio") }
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

    private var portfolioAccount: Account? {
        if let id = holding.accountID, let match = accounts.first(where: { $0.id == id && $0.kind == .portfolio }) {
            return match
        }
        return accounts.first { $0.kind == .portfolio }
    }

    private func save() {
        let normalized = quantity.replacingOccurrences(of: ",", with: ".")
        guard let count = Double(normalized), count > 0, let priceCents = Money.cents(from: price), priceCents > 0 else {
            validationMessage = L("Bitte Stückzahl und Kurs prüfen.", "Check the quantity and price.")
            return
        }
        if isSale, count > holding.quantity {
            validationMessage = L("Du kannst nicht mehr verkaufen, als im Depot liegt.", "You cannot sell more than the holding contains.")
            return
        }
        guard let checkingAccountID else {
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
        let amount = Int((count * Double(abs(priceCents))).rounded())
        if isSale {
            holding.quantity -= count
            context.insert(LedgerEntry(
                date: date,
                title: "\(L("Verkauf", "Sell")): \(holding.name)",
                amountCents: amount,
                kind: .transfer,
                fromAccountID: portfolio.id,
                toAccountID: checkingAccountID
            ))
        } else {
            let previousValue = holding.quantity * Double(holding.purchasePriceCents)
            let nextQuantity = holding.quantity + count
            holding.purchasePriceCents = Int(((previousValue + Double(amount)) / nextQuantity).rounded())
            holding.quantity = nextQuantity
            context.insert(LedgerEntry(
                date: date,
                title: "\(L("Kauf", "Buy")): \(holding.name)",
                amountCents: amount,
                kind: .transfer,
                fromAccountID: checkingAccountID,
                toAccountID: portfolio.id
            ))
        }
        holding.accountID = portfolio.id
        holding.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
