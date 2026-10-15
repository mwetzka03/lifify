import SwiftData
import SwiftUI

struct VariableBudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VariableBudget.name) private var budgets: [VariableBudget]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(budgets) { budget in
                let spent = FinanceService.variableSpent(budgetID: budget.id, monthKey: Date.now.monthKey, entries: entries, splits: splits)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(budget.name)
                        Spacer()
                        Text("\(Money.string(cents: spent)) / \(Money.string(cents: budget.monthlyAmountCents))")
                            .font(.subheadline)
                    }
                    ProgressView(value: min(Double(spent) / Double(max(budget.monthlyAmountCents, 1)), 1))
                    Text("\(L("Verfügbar", "Available")): \(Money.string(cents: budget.monthlyAmountCents - spent))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                offsets.map { budgets[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if budgets.isEmpty {
                ContentUnavailableView(L("Keine variablen Kosten", "No variable costs"), systemImage: "gauge.with.dots.needle.67percent")
            }
        }
        .navigationTitle(L("Variable Kosten", "Variable costs"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { VariableBudgetForm() }
    }
}

private struct VariableBudgetForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name = ""
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Monatsbetrag", "Monthly amount"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Konto", "Account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(L("Neue variable Kosten", "New variable cost"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
                        context.insert(VariableBudget(name: name, monthlyAmountCents: abs(cents), accountID: accountID, notes: notes))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
