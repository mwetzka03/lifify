import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI

/// The variable budgets.
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
        FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts)
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
                            AppSymbolImage(name: IconPreferenceStore.icon(for: budget.id, fallback: VariableBudgetIcon.fallback))
                                .frame(width: 28)
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
                    .appAccentTint()
                }
                .appGlassRow()
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
        .appGlassList()
        .navigationTitle(L("Variable Kosten", "Variable costs"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { VariableBudgetForm(budget: nil) }
        .sheet(item: $editing) { VariableBudgetForm(budget: $0) }
    }

    /// Sums a budget's spending.
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

    /// Returns a budget's plan.
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

    /// Describes a budget's accounts.
    private func accountCaption(_ budget: VariableBudget) -> String {
        if VariableBudgetAccounts.storedIDs(for: budget.id) == nil, budget.accountID == nil {
            return L("Alle Konten", "All accounts")
        }
        let names = VariableBudgetAccounts.targets(for: budget, cashAccountIDs: cashIDs).compactMap { id in
            accounts.first { $0.id == id }?.name
        }
        return names.joined(separator: ", ")
    }

    /// Deletes a budget.
    private func delete(_ budget: VariableBudget) {
        VariableBudgetAccounts.remove(for: budget.id)
        IconPreferenceStore.remove(for: budget.id)
        BudgetPayeeRules.remove(for: budget.id)
        context.delete(budget)
        try? context.save()
    }
}

/// Details of a budget.
private struct VariableBudgetDetailView: View {
    let budget: VariableBudget
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]
    @State private var showingAdder = false
    @State private var editedEntry: LedgerEntry?
    @Environment(\.modelContext) private var context

    private var selectedPeriod: ForecastPeriod? {
        filters.period(in: FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts))
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
                .appGlassRow()
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            unassign(entry)
                        } label: {
                            Label(L("Lösen", "Unlink"), systemImage: "link.badge.minus")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { editedEntry = entry } label: {
                            Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                        }
                        .appAccentTint()
                    }
                }
            }
        }
        .appGlassList()
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdder = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L("Buchungen hinzufügen", "Add bookings"))
            }
        }
        .sheet(isPresented: $showingAdder) { BudgetBookingAdder(budget: budget) }
        .sheet(item: $editedEntry) { TransactionFormView(entry: $0, splits: splits) }
    }

    /// Takes a booking out of this variable cost; the booking itself stays.
    private func unassign(_ entry: LedgerEntry) {
        if entry.variableBudgetID == budget.id { entry.variableBudgetID = nil }
        splits
            .filter { $0.transactionID == entry.id && $0.kind == .variableBudget && $0.targetID == budget.id }
            .forEach { context.delete($0) }
        try? context.save()
    }
}

/// Creates or edits a budget.
struct VariableBudgetForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name: String
    @State private var amount: String
    @State private var notes: String
    @State private var selectedIDs: Set<UUID>
    @State private var icon: String
    @State private var rules: [String]
    @State private var newRule = ""
    @State private var showingPayeePicker = false
    private let existing: VariableBudget?

    init(budget: VariableBudget?) {
        existing = budget
        _name = State(initialValue: budget?.name ?? "")
        _amount = State(initialValue: budget.map { String(format: "%.2f", Double($0.monthlyAmountCents) / 100) } ?? "")
        _notes = State(initialValue: budget?.notes ?? "")
        _icon = State(initialValue: budget.map { IconPreferenceStore.icon(for: $0.id, fallback: VariableBudgetIcon.fallback) } ?? VariableBudgetIcon.fallback)
        _rules = State(initialValue: budget.map { BudgetPayeeRules.rules(for: $0.id) } ?? [])
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
            AppForm {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Monatsbetrag", "Monthly amount"), text: $amount).keyboardType(.decimalPad)
                SymbolPicker(title: L("Symbol", "Icon"), selection: $icon)
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
                .appGlassRow()
                PayeeRulesSection(rules: $rules, newRule: $newRule, showingPicker: $showingPayeePicker)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .payeeRulePicker(isPresented: $showingPayeePicker, rules: $rules)
            .appGlassList()
            .navigationTitle(existing == nil ? L("Neue variable Kosten", "New variable cost") : L("Variable Kosten bearbeiten", "Edit variable cost"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    /// Saves the budget.
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
        IconPreferenceStore.set(icon, for: budget.id)
        // A rule still typed in the field counts too, so it is not lost by tapping Save first.
        BudgetPayeeRules.set(rules + [newRule], for: budget.id)
        // Rules cover the past too: every earlier free expense that fits is assigned now.
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        BudgetPayeeRules.applyToExisting(budget, entries: entries)
        try? context.save()
        dismiss()
    }
}

/// The icon a variable cost shows until one is chosen.
enum VariableBudgetIcon {
    static let fallback = "cart"
}

/// Lists all expenses to give single ones to a variable cost by hand.
private struct BudgetBookingAdder: View {
    let budget: VariableBudget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var costs: [FixedCost]
    @Query private var budgets: [VariableBudget]
    @State private var query = ""
    @State private var chosen: Set<UUID> = []

    /// The expenses not yet in this variable cost, filtered by the search text.
    private var shown: [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return Array(entries.lazy.filter { entry in
            entry.kind == .expense && entry.variableBudgetID != budget.id
                && (text.isEmpty || entry.title.localizedCaseInsensitiveContains(text))
        }.prefix(300))
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    ForEach(shown) { entry in
                        Button {
                            if chosen.contains(entry.id) { chosen.remove(entry.id) } else { chosen.insert(entry.id) }
                        } label: {
                            entryRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L(
                        "Gewählte Buchungen gehören danach zu dieser variablen Kosten, auch wenn sie vorher woanders zugeordnet waren.",
                        "Picked bookings then belong to this variable cost, even if they were assigned elsewhere before."
                    ))
                }
            }
            .searchable(text: $query, prompt: L("Buchung suchen", "Search bookings"))
            .navigationTitle(L("Buchungen hinzufügen", "Add bookings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Hinzufügen", "Add")) {
                        entries.filter { chosen.contains($0.id) }.forEach(BookingTarget.variableBudget(budget.id).apply)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }

    /// One expense with its current assignment, so moving it is a conscious choice.
    private func entryRow(_ entry: LedgerEntry) -> some View {
        HStack {
            Image(systemName: chosen.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                .appAccentForeground()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).foregroundStyle(.primary).lineLimit(1)
                Text("\(AppDate.numeric(entry.date))\(currentAssignment(entry).map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Money.string(cents: entry.amountCents))
                .foregroundStyle(BookingClassification.differenceColor(entry.amountCents))
        }
    }

    /// The name of the fixed or variable cost a booking belongs to now, if any.
    private func currentAssignment(_ entry: LedgerEntry) -> String? {
        switch BookingTarget(of: entry) {
        case .none: nil
        case .fixedCost(let id): costs.first { $0.id == id }?.name
        case .variableBudget(let id): budgets.first { $0.id == id }?.name
        }
    }
}
