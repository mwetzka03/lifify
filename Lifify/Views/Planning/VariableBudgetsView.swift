import SwiftData
import SwiftUI

struct VariableBudgetsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \VariableBudget.name) private var budgets: [VariableBudget]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]
    @State private var showingNew = false
    @State private var editing: VariableBudget?

    private var cashAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    private var cashIDs: [UUID] {
        cashAccounts.map(\.id)
    }

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var selectedPeriod: ForecastPeriod? {
        filters.period(in: periods)
    }

    private var selectedAccount: Account? {
        filters.account(in: accounts.filter { $0.kind != .savingsGroup })
    }

    private var visibleBudgets: [VariableBudget] {
        guard let account = selectedAccount, account.kind != .portfolio else { return budgets }
        return budgets.filter { budget in
            VariableBudgetAccounts.planCents(
                budget: budget,
                scopedAccountIDs: [account.id],
                cashAccountIDs: cashIDs
            ) > 0 || spent(budget) > 0
        }
    }

    var body: some View {
        List {
            ForEach(visibleBudgets) { budget in
                let spent = spent(budget)
                let planned = planned(budget)
                NavigationLink {
                    VariableBudgetDetailView(budget: budget)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(budget.name)
                            Spacer()
                            Text("\(Money.string(cents: spent)) / \(Money.string(cents: planned))")
                                .font(.subheadline)
                        }
                        ProgressView(value: min(Double(spent) / Double(max(planned, 1)), 1))
                        Text("\(L("Verfügbar", "Available")): \(Money.string(cents: planned - spent))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(accountCaption(budget))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(budget)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        editing = budget
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onDelete { offsets in
                offsets.map { visibleBudgets[$0] }.forEach(delete)
            }
        }
        .overlay {
            if visibleBudgets.isEmpty {
                ContentUnavailableView(L("Keine variablen Kosten", "No variable costs"), systemImage: "gauge.with.dots.needle.67percent")
            }
        }
        .navigationTitle(L("Variable Kosten", "Variable costs"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { VariableBudgetForm(budget: nil) }
        .sheet(item: $editing) { VariableBudgetForm(budget: $0) }
    }

    private func spent(_ budget: VariableBudget) -> Int {
        guard let period = selectedPeriod else {
            return FinanceService.variableSpent(
                budgetID: budget.id,
                monthKey: Date.now.monthKey,
                entries: entries,
                splits: splits
            )
        }
        return FinanceService.variableSpent(
            budgetID: budget.id,
            from: period.start,
            through: period.end,
            entries: entries,
            splits: splits,
            accountID: selectedAccount?.kind == .portfolio ? nil : selectedAccount?.id
        )
    }

    private func planned(_ budget: VariableBudget) -> Int {
        let scope: Set<UUID>?
        if let account = selectedAccount, account.kind != .portfolio {
            scope = [account.id]
        } else {
            scope = nil
        }
        return VariableBudgetAccounts.planCents(
            budget: budget,
            scopedAccountIDs: scope,
            cashAccountIDs: cashIDs
        )
    }

    private func accountCaption(_ budget: VariableBudget) -> String {
        if VariableBudgetAccounts.storedIDs(for: budget.id) == nil, budget.accountID == nil {
            return L("Alle Konten", "All accounts")
        }
        let names = VariableBudgetAccounts.targets(for: budget, cashAccountIDs: cashIDs).compactMap { id in
            accounts.first { $0.id == id }?.name
        }
        return names.joined(separator: ", ")
    }

    private func delete(_ budget: VariableBudget) {
        VariableBudgetAccounts.remove(for: budget.id)
        context.delete(budget)
        try? context.save()
    }
}

private struct VariableBudgetDetailView: View {
    let budget: VariableBudget
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]

    private var selectedPeriod: ForecastPeriod? {
        filters.period(in: FinancePeriods.all(entries: entries, forecasts: forecasts))
    }

    private var selectedAccount: Account? {
        let account = filters.account(in: accounts.filter { $0.kind != .savingsGroup })
        return account?.kind == .portfolio ? nil : account
    }

    private var assigned: [LedgerEntry] {
        let splitIDs = Set(
            splits
                .filter { $0.kind == .variableBudget && $0.targetID == budget.id }
                .map(\.transactionID)
        )
        return entries
            .filter { entry in
                let matches = entry.variableBudgetID == budget.id || splitIDs.contains(entry.id)
                guard matches else { return false }
                if let period = selectedPeriod, !period.contains(entry.date) { return false }
                if let account = selectedAccount {
                    return entry.accountID == account.id || entry.fromAccountID == account.id || entry.toAccountID == account.id
                }
                return true
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if let period = selectedPeriod {
                Section {
                    Text("\(AppDate.numeric(period.start)) – \(AppDate.numeric(period.end))")
                        .foregroundStyle(.secondary)
                }
            }
            if assigned.isEmpty {
                Text(L(
                    "In diesem Zeitraum sind keine Buchungen zugeordnet.",
                    "No transactions are assigned in this period."
                ))
                .foregroundStyle(.secondary)
            } else {
                ForEach(assigned) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(AppDate.numeric(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: -abs(entry.amountCents)))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VariableBudgetForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name: String
    @State private var amount: String
    @State private var notes: String
    @State private var selectedIDs: Set<UUID>
    private let existing: VariableBudget?

    init(budget: VariableBudget?) {
        existing = budget
        _name = State(initialValue: budget?.name ?? "")
        _amount = State(initialValue: budget.map { String(format: "%.2f", Double($0.monthlyAmountCents) / 100) } ?? "")
        _notes = State(initialValue: budget?.notes ?? "")
        if let budget, let stored = VariableBudgetAccounts.storedIDs(for: budget.id) {
            _selectedIDs = State(initialValue: Set(stored))
        } else if let id = budget?.accountID {
            _selectedIDs = State(initialValue: [id])
        } else {
            _selectedIDs = State(initialValue: [])
        }
    }

    private var cashAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Monatsbetrag", "Monthly amount"), text: $amount).keyboardType(.decimalPad)
                Section {
                    ForEach(cashAccounts) { account in
                        Button {
                            if selectedIDs.contains(account.id) {
                                selectedIDs.remove(account.id)
                            } else {
                                selectedIDs.insert(account.id)
                            }
                        } label: {
                            HStack {
                                Text(account.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIDs.contains(account.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text(L("Konten", "Accounts"))
                } footer: {
                    Text(L(
                        "Der Betrag wird gleichmäßig auf die gewählten Konten verteilt. Ohne Auswahl gilt er für alle Konten.",
                        "The amount is split evenly across the selected accounts. With no selection it applies to every account."
                    ))
                }
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(existing == nil ? L("Neue variable Kosten", "New variable cost") : L("Variable Kosten bearbeiten", "Edit variable cost"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private func save() {
        guard let cents = Money.cents(from: amount), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let ordered = cashAccounts.map(\.id).filter { selectedIDs.contains($0) }
        let accountID = ordered.count == 1 ? ordered.first : nil
        let budget: VariableBudget
        if let existing {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.monthlyAmountCents = abs(cents)
            existing.notes = notes
            existing.accountID = accountID
            budget = existing
        } else {
            budget = VariableBudget(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                monthlyAmountCents: abs(cents),
                accountID: accountID,
                notes: notes
            )
            context.insert(budget)
        }
        VariableBudgetAccounts.set(ordered, for: budget.id)
        try? context.save()
        dismiss()
    }
}
