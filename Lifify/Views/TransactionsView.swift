import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @State private var search = ""
    @State private var showingNew = false
    @State private var editing: LedgerEntry?

    private var filtered: [LedgerEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.notes.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { entry in
                Button {
                    editing = entry
                } label: {
                    TransactionRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    L("Keine Buchungen", "No transactions"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(L("Erfasse eine Einnahme, Ausgabe, Umbuchung oder Saldo-Korrektur.", "Add income, an expense, a transfer or a balance adjustment."))
                )
            }
        }
        .navigationTitle(L("Buchungen", "Transactions"))
        .searchable(text: $search, prompt: L("Titel oder Notiz", "Title or note"))
        .toolbar {
            Button {
                showingNew = true
            } label: {
                Label(L("Buchung hinzufügen", "Add transaction"), systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNew) {
            TransactionFormView(entry: nil, splits: splits)
        }
        .sheet(item: $editing) { entry in
            TransactionFormView(entry: entry, splits: splits)
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let entry = filtered[offset]
            splits.filter { $0.transactionID == entry.id }.forEach { context.delete($0) }
            context.delete(entry)
        }
        try? context.save()
    }
}

private struct TransactionRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                Text("\(entry.kind.label) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: entry.kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents)))
                .foregroundStyle(entry.kind == .expense ? .red : (entry.kind == .income ? .green : .primary))
                .monospacedDigit()
        }
    }

    private var icon: String {
        switch entry.kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        case .adjustment: "equal.circle"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .income: .green
        case .expense: .red
        case .transfer: .blue
        case .adjustment: .orange
        }
    }
}

private struct TransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \FixedCost.name) private var fixedCosts: [FixedCost]
    @Query(sort: \VariableBudget.name) private var variableBudgets: [VariableBudget]
    @Query(sort: \BudgetPool.name) private var pools: [BudgetPool]
    @Query(sort: \ShoppingItem.name) private var shopping: [ShoppingItem]
    @Query private var allSplits: [TransactionSplit]
    @StateObject private var viewModel: TransactionFormViewModel

    init(entry: LedgerEntry?, splits: [TransactionSplit]) {
        _viewModel = StateObject(wrappedValue: TransactionFormViewModel(entry: entry, splits: splits))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Art", "Type"), selection: $viewModel.kind) {
                        ForEach(LedgerKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(L("Titel", "Title"), text: $viewModel.title)
                    TextField(L("Betrag", "Amount"), text: $viewModel.amountText)
                        .keyboardType(.decimalPad)
                    DatePicker(L("Datum", "Date"), selection: $viewModel.date, displayedComponents: .date)
                    TextField(L("Notiz", "Note"), text: $viewModel.notes, axis: .vertical)
                }

                Section(L("Konten", "Accounts")) {
                    if viewModel.kind == .transfer {
                        accountPicker(L("Von", "From"), selection: $viewModel.fromAccountID)
                        accountPicker(L("Nach", "To"), selection: $viewModel.toAccountID)
                    } else {
                        accountPicker(L("Konto", "Account"), selection: $viewModel.accountID)
                    }
                }

                if viewModel.kind == .expense {
                    Section(L("Zuordnung", "Assignment")) {
                        optionalPicker(L("Fixkosten", "Fixed cost"), selection: $viewModel.fixedCostID, values: fixedCosts.map { ($0.id, $0.name) })
                        optionalPicker(L("Variable Kosten", "Variable cost"), selection: $viewModel.variableBudgetID, values: variableBudgets.map { ($0.id, $0.name) })
                        optionalPicker(L("Einkauf", "Shopping"), selection: $viewModel.shoppingItemID, values: shopping.map { ($0.id, $0.name) })
                    }
                    SplitSection(
                        title: L("Variable Kosten aufteilen", "Split variable costs"),
                        drafts: $viewModel.variableSplits,
                        values: variableBudgets.map { ($0.id, $0.name) }
                    )
                    SplitSection(
                        title: L("Budgetpools aufteilen", "Split budget pools"),
                        drafts: $viewModel.poolSplits,
                        values: pools.map { ($0.id, $0.name) }
                    )
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(viewModel.title.isEmpty ? L("Neue Buchung", "New transaction") : viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        if viewModel.save(context: context, pools: pools, allSplits: allSplits) { dismiss() }
                    }
                }
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
            ForEach(accounts.filter { $0.kind != .savingsGroup }) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
    }

    private func optionalPicker(_ title: String, selection: Binding<UUID?>, values: [(UUID, String)]) -> some View {
        Picker(title, selection: selection) {
            Text(L("Keine", "None")).tag(Optional<UUID>.none)
            ForEach(values, id: \.0) { value in
                Text(value.1).tag(Optional(value.0))
            }
        }
    }
}

private struct SplitSection: View {
    let title: String
    @Binding var drafts: [SplitDraft]
    let values: [(UUID, String)]

    var body: some View {
        Section(title) {
            ForEach($drafts) { $draft in
                HStack {
                    Picker(L("Ziel", "Target"), selection: $draft.targetID) {
                        Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                        ForEach(values, id: \.0) { value in
                            Text(value.1).tag(Optional(value.0))
                        }
                    }
                    .labelsHidden()
                    TextField(L("Betrag", "Amount"), text: $draft.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .onDelete { drafts.remove(atOffsets: $0) }
            Button {
                drafts.append(SplitDraft())
            } label: {
                Label(L("Split hinzufügen", "Add split"), systemImage: "plus")
            }
        }
    }
}
