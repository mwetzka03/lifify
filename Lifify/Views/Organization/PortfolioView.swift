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
                offsets.map { holdings[$0] }.forEach(context.delete)
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

    init(holding: PortfolioHolding?) {
        existing = holding
        _accountID = State(initialValue: holding?.accountID)
        _name = State(initialValue: holding?.name ?? "")
        _symbol = State(initialValue: holding?.symbol ?? "")
        _quantity = State(initialValue: holding.map { String($0.quantity) } ?? "")
        _purchasePrice = State(initialValue: holding.map { String(format: "%.2f", Double($0.purchasePriceCents) / 100) } ?? "")
        _currentPrice = State(initialValue: holding.map { String(format: "%.2f", Double($0.currentPriceCents) / 100) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("Depotkonto", "Portfolio account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts.filter { $0.kind == .portfolio }) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField(L("Name", "Name"), text: $name)
                TextField("ISIN", text: $symbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
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
                        let holding = existing ?? PortfolioHolding(name: name, quantity: count, purchasePriceCents: purchase, currentPriceCents: current)
                        holding.accountID = accountID
                        holding.name = name
                        holding.symbol = normalizedISIN
                        holding.quantity = count
                        holding.purchasePriceCents = purchase
                        holding.currentPriceCents = current
                        holding.updatedAt = .now
                        if existing == nil { context.insert(holding) }
                        try? context.save()
                        Task {
                            do {
                                let cents = try await MarketDataService.currentPriceCents(for: normalizedISIN)
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
}
