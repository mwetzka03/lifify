import SwiftData
import SwiftUI

struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var selected: PortfolioHolding?
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                let totals = portfolioPerformance
                LabeledContent(L("Depotwert", "Portfolio value"), value: Money.string(cents: totals.value))
                if let dayCents = totals.dayCents, let dayPercent = totals.dayPercent {
                    performanceRow(L("Heute", "Today"), cents: dayCents, percent: dayPercent)
                }
                performanceRow(L("Seit Kauf", "Since purchase"), cents: totals.purchaseCents, percent: totals.purchasePercent)
            }
            ForEach(holdings) { holding in
                let performance = performance(for: holding)
                Button {
                    selected = holding
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(holding.name).foregroundStyle(.primary)
                            Text("\(holding.quantity.formatted()) × \(Money.string(cents: holding.currentPriceCents))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let dayCents = performance.dayCents, let dayPercent = performance.dayPercent {
                                performanceText(L("Heute", "Today"), cents: dayCents, percent: dayPercent)
                            }
                            performanceText(L("Seit Kauf", "Since purchase"), cents: performance.purchaseCents, percent: performance.purchasePercent)
                        }
                        Spacer()
                        Text(Money.string(cents: performance.value))
                            .foregroundStyle(.primary)
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
        .sheet(isPresented: $showingNew) { HoldingForm(holding: nil) }
        .sheet(item: $edited) { HoldingForm(holding: $0) }
        .sheet(item: $selected) { HoldingDetailView(holding: $0) }
    }

    private func delete(_ holding: PortfolioHolding) {
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        context.delete(holding)
        try? context.save()
    }

    private var portfolioPerformance: HoldingPerformance {
        holdings.reduce(HoldingPerformance()) { total, holding in
            total.adding(performance(for: holding))
        }
    }

    private func performance(for holding: PortfolioHolding) -> HoldingPerformance {
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

    private func performanceRow(_ title: String, cents: Int, percent: Double?) -> some View {
        LabeledContent(title) {
            performanceText(nil, cents: cents, percent: percent)
        }
    }

    private func performanceText(_ title: String?, cents: Int, percent: Double?) -> some View {
        HStack(spacing: 4) {
            if let title {
                Text(title)
            }
            Text(signedMoney(cents))
            if let percent {
                Text("· \(signedPercent(percent))")
            }
        }
        .font(.caption)
        .foregroundStyle(cents < 0 ? .red : (cents > 0 ? .green : .secondary))
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
}

private struct HoldingDetailView: View {
    let holding: PortfolioHolding

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(L("Stückzahl", "Quantity"), value: holding.quantity.formatted())
                LabeledContent(L("Kurs", "Price"), value: Money.string(cents: holding.currentPriceCents))
                LabeledContent(L("Kaufkurs", "Purchase price"), value: Money.string(cents: holding.purchasePriceCents))
                if let previous = PreviousCloseStore.cents(for: holding.id), previous > 0 {
                    let dayCents = holding.currentPriceCents - previous
                    LabeledContent(L("Heute je Stück", "Today per share"), value: signedDetail(dayCents))
                    LabeledContent(L("Heute in Prozent", "Today in percent"), value: signedDetailPercent(Double(dayCents) / Double(previous)))
                }
                if holding.purchasePriceCents > 0 {
                    let purchaseCents = holding.currentPriceCents - holding.purchasePriceCents
                    LabeledContent(L("Seit Kauf je Stück", "Since purchase per share"), value: signedDetail(purchaseCents))
                    LabeledContent(
                        L("Seit Kauf in Prozent", "Since purchase in percent"),
                        value: signedDetailPercent(Double(purchaseCents) / Double(holding.purchasePriceCents))
                    )
                }
                if !holding.symbol.isEmpty {
                    LabeledContent("ISIN", value: holding.symbol)
                }
                LabeledContent(
                    L("Aktualisiert", "Updated"),
                    value: holding.updatedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            .navigationTitle(holding.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signedDetail(_ cents: Int) -> String {
        cents > 0 ? "+\(Money.string(cents: cents))" : Money.string(cents: cents)
    }

    private func signedDetailPercent(_ ratio: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = formatter.plusSign
        return formatter.string(from: NSNumber(value: ratio)) ?? "0 %"
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
                Picker(L("Depotkonto", "Portfolio account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts.filter { $0.kind == .portfolio }) { Text($0.name).tag(Optional($0.id)) }
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
                        let holding = existing ?? PortfolioHolding(name: selectedSuggestion.name, quantity: count, purchasePriceCents: purchase, currentPriceCents: current)
                        holding.accountID = accountID
                        holding.name = selectedSuggestion.name
                        holding.symbol = normalizedISIN
                        holding.quantity = count
                        holding.purchasePriceCents = purchase
                        holding.currentPriceCents = current
                        holding.updatedAt = .now
                        if existing == nil { context.insert(holding) }
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
