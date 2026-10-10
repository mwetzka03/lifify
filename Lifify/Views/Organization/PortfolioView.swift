import SwiftData
import SwiftUI

struct PortfolioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @State private var showingNew = false
    @State private var edited: PortfolioHolding?
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                LabeledContent(
                    L("Depotwert", "Portfolio value"),
                    value: Money.string(cents: holdings.reduce(0) { $0 + Int((Double($1.currentPriceCents) * $1.quantity).rounded()) })
                )
            }
            ForEach(holdings) { holding in
                Button {
                    edited = holding
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(holding.name).foregroundStyle(.primary)
                            Text("\(holding.quantity.formatted()) × \(Money.string(cents: holding.currentPriceCents))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !holding.symbol.isEmpty {
                                Text("\(holding.symbol) · \(holding.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Money.string(cents: Int((holding.quantity * Double(holding.currentPriceCents)).rounded())))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { holdings[$0] }.forEach {
                    MarketSymbolStore.remove(for: $0.id)
                    context.delete($0)
                }
                try? context.save()
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
                                let cents: Int
                                if selectedSuggestion.symbol.isEmpty {
                                    cents = try await MarketDataService.currentPriceCents(for: normalizedISIN)
                                } else {
                                    cents = try await MarketDataService.currentPriceCents(for: selectedSuggestion)
                                }
                                holding.currentPriceCents = cents
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
