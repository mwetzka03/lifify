import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @State private var search = ""
    @State private var showingNew = false
    @State private var editing: LedgerEntry?
    @State private var selected: LedgerEntry?

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
                    selected = entry
                } label: {
                    TransactionRow(entry: entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(entry)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        editing = entry
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
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
        .sheet(item: $selected) { entry in
            TransactionDetailView(entry: entry)
        }
    }

    private func delete(_ entry: LedgerEntry) {
        splits.filter { $0.transactionID == entry.id }.forEach { context.delete($0) }
        IconPreferenceStore.remove(for: entry.id)
        context.delete(entry)
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
        let fallback: String = switch entry.kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        case .adjustment: "equal.circle"
        }
        return IconPreferenceStore.icon(for: entry.id, fallback: fallback)
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

private struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    let entry: LedgerEntry

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Art", "Type"), value: entry.kind.label)
                    LabeledContent(L("Betrag", "Amount"), value: Money.string(cents: displayAmount))
                    LabeledContent(
                        L("Datum", "Date"),
                        value: entry.date.formatted(date: .long, time: .omitted)
                    )
                }
                Section(L("Konten", "Accounts")) {
                    if let account = account(entry.accountID) {
                        LabeledContent(L("Konto", "Account"), value: account.name)
                        if !account.iban.isEmpty {
                            LabeledContent("IBAN", value: account.iban)
                        }
                    }
                    if let account = account(entry.fromAccountID) {
                        LabeledContent(L("Von", "From"), value: account.name)
                    }
                    if let account = account(entry.toAccountID) {
                        LabeledContent(L("Nach", "To"), value: account.name)
                    }
                }
                if !entry.notes.isEmpty {
                    Section(L("Buchungsdetails", "Transaction details")) {
                        if !importDetails.isEmpty {
                            Text(importDetails)
                                .textSelection(.enabled)
                        }
                        if !importIBANs.sender.isEmpty {
                            LabeledContent(
                                L("Sender-IBAN", "Sender IBAN"),
                                value: importIBANs.sender
                            )
                        }
                        if !importIBANs.recipient.isEmpty {
                            LabeledContent(
                                L("Empfänger-IBAN", "Recipient IBAN"),
                                value: importIBANs.recipient
                            )
                        }
                    }
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { dismiss() }
                }
            }
        }
    }

    private func account(_ id: UUID?) -> Account? {
        accounts.first { $0.id == id }
    }

    private var importIBANs: (sender: String, recipient: String) {
        BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents)
    }

    private var importDetails: String {
        let normalizedNotes = entry.notes
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        if normalizedNotes == importIBANs.sender || normalizedNotes == importIBANs.recipient {
            return ""
        }
        return entry.notes.components(separatedBy: .newlines)
            .filter {
                let label = $0.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
                return !label.contains("sender")
                    && !label.contains("empfänger")
                    && !label.contains("recipient")
            }
            .joined(separator: "\n")
    }

    private var displayAmount: Int {
        entry.kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents)
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
                    SymbolPicker(title: L("Symbol", "Icon"), selection: $viewModel.icon)
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
