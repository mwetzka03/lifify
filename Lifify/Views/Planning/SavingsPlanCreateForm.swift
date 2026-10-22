import SwiftData
import SwiftUI

/// Creates a savings plan from an existing holding. The next debit stays in the future.
struct SavingsPlanCreateForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var holdingID: UUID?
    @State private var name = ""
    @State private var amount = ""
    @State private var cadence: Cadence = .monthly
    @State private var checkingAccountID: UUID?

    private var debitAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    var body: some View {
        NavigationStack {
            Form {
                if holdings.isEmpty {
                    Text(L(
                        "Lege zuerst eine Depotposition an. Ein Sparplan hängt an einer Position.",
                        "Create a holding first. A savings plan belongs to a holding."
                    ))
                    .foregroundStyle(.secondary)
                } else {
                    Picker(L("Position", "Holding"), selection: $holdingID) {
                        Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                        ForEach(holdings) { holding in
                            Text(holding.name).tag(Optional(holding.id))
                        }
                    }
                    TextField(L("Name", "Name"), text: $name)
                    TextField(L("Betrag", "Amount"), text: $amount)
                        .keyboardType(.decimalPad)
                    Picker(L("Rhythmus", "Cadence"), selection: $cadence) {
                        ForEach(Cadence.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Picker(L("Abbuchungskonto", "Debit account"), selection: $checkingAccountID) {
                        Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                        ForEach(debitAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    Text(CalendarService.savingsPlanScheduleText(cadence: cadence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Neuer Sparplan", "New savings plan"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: holdingID) { _, newValue in
                applyHolding(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                        .disabled(holdings.isEmpty)
                }
            }
        }
    }

    private func applyHolding(_ id: UUID?) {
        guard let holding = holdings.first(where: { $0.id == id }) else { return }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = holding.name
        }
        guard checkingAccountID == nil else { return }
        if let portfolioID = holding.accountID,
           let linked = PortfolioLinkStore.checkingID(for: portfolioID),
           debitAccounts.contains(where: { $0.id == linked }) {
            checkingAccountID = linked
            return
        }
        if let preferred = TradeAccountPreference.accountID(),
           debitAccounts.contains(where: { $0.id == preferred }) {
            checkingAccountID = preferred
            return
        }
        checkingAccountID = debitAccounts.first?.id
    }

    private func save() {
        guard let holding = holdings.first(where: { $0.id == holdingID }),
              let portfolioID = holding.accountID,
              let checkingAccountID,
              debitAccounts.contains(where: { $0.id == checkingAccountID }),
              let cents = Money.cents(from: amount),
              cents > 0
        else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let today = Calendar.current.startOfDay(for: .now)
        let nextDebit = CalendarService.nextSavingsPlanDate(cadence: cadence, onOrAfter: today)
        let anchor: Date
        if let nextDebit, Calendar.current.isDate(nextDebit, inSameDayAs: today) {
            anchor = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        } else {
            anchor = today
        }
        let plan = SavingsPlanRecord(
            id: UUID(),
            isin: symbol.isEmpty ? holding.id.uuidString : symbol,
            name: title,
            amountCents: cents,
            cadenceRaw: cadence.rawValue,
            checkingAccountID: checkingAccountID,
            portfolioAccountID: portfolioID,
            holdingID: holding.id,
            lastExecution: anchor,
            historyThrough: anchor,
            active: true
        )
        SavingsPlanStore.upsert(plan)
        SavingsPlanFixedCosts.sync(context: context)
        dismiss()
    }
}
