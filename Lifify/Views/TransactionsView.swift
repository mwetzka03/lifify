import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @Query private var splits: [TransactionSplit]
    @State private var search = ""
    @State private var showingNew = false
    @State private var editing: LedgerEntry?
    @State private var selected: LedgerEntry?

    private var filterAccounts: [Account] {
        accounts.filter { $0.kind != .savingsGroup }
    }

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var filtered: [LedgerEntry] {
        let period = filters.period(in: periods)
        let account = filters.account(in: filterAccounts)
        let depotIDs = filters.showsDepot ? Set(accounts.filter { $0.kind == .portfolio }.map(\.id)) : []
        return entries.filter { entry in
            guard FinancePeriods.includes(entry, period: period, account: account, depotIDs: depotIDs) else { return false }
            guard !search.isEmpty else { return true }
            return entry.title.localizedCaseInsensitiveContains(search)
                || entry.notes.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            FinanceFilterControls(periods: periods, accounts: filterAccounts)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            transactionList
        }
        .appCanvas()
        .navigationTitle(L("Buchungen", "Transactions"))
        .navigationBarTitleDisplayMode(.inline)
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

    private var transactionList: some View {
        List {
            ForEach(filtered) { entry in
                Button {
                    selected = entry
                }                 label: {
                    TransactionRow(
                        entry: entry,
                        accounts: accounts,
                        viewedAccountID: filters.showsDepot ? nil : filters.account(in: filterAccounts)?.id
                    )
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    L("Keine Buchungen", "No transactions"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(entries.isEmpty
                        ? L("Erfasse eine Einnahme, Ausgabe, Umbuchung oder Saldo-Korrektur.", "Add income, an expense, a transfer or a balance adjustment.")
                        : L("In diesem Zeitraum und Konto liegen keine Buchungen.", "There are no transactions in this period and account."))
                )
            }
        }
    }

    private func delete(_ entry: LedgerEntry) {
        splits.filter { $0.transactionID == entry.id }.forEach { context.delete($0) }
        IconPreferenceStore.remove(for: entry.id)
        context.delete(entry)
        try? context.save()
    }
}

struct TransactionRow: View {
    let entry: LedgerEntry
    var accounts: [Account] = []
    var viewedAccountID: UUID? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .frame(width: 28)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(category.label) · \(AppDate.numeric(entry.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: signedAmount))
                .foregroundStyle(BookingClassification.amountColor(category: category, signed: signedAmount))
                .monospacedDigit()
        }
    }

    private var category: BookingCategory {
        BookingClassification.category(of: entry, accounts: accounts, viewedAccountID: viewedAccountID)
    }

    private var signedAmount: Int {
        BookingClassification.signedAmount(of: entry, category: category, viewedAccountID: viewedAccountID)
    }
}

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    let entry: LedgerEntry

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Kategorie", "Category"), value: category.label)
                    HStack {
                        Text(L("Betrag", "Amount"))
                        Spacer()
                        Text(Money.string(cents: displayAmount))
                            .foregroundStyle(BookingClassification.amountColor(category: category, signed: displayAmount))
                    }
                    LabeledContent(
                        L("Datum", "Date"),
                        value: AppDate.weekdayAndNumeric(entry.date)
                    )
                }
                if let from = account(entry.fromAccountID), let to = account(entry.toAccountID) {
                    Section(L("Beide Buchungen", "Both transactions")) {
                        accountLine(from, signed: -abs(entry.amountCents))
                        accountLine(to, signed: abs(entry.amountCents))
                    }
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

    private func accountLine(_ account: Account, signed: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: signed < 0 ? BookingCategory.expense.systemImage : BookingCategory.income.systemImage)
                .frame(width: 28)
                .foregroundStyle(.primary)
            Text(account.name)
            Spacer()
            Text(Money.string(cents: signed))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }

    private var category: BookingCategory {
        BookingClassification.category(of: entry, accounts: accounts, viewedAccountID: nil)
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
        BookingClassification.signedAmount(of: entry, category: category, viewedAccountID: nil)
    }
}

struct TransactionFormView: View {
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
                    Picker(L("Kategorie", "Category"), selection: $viewModel.category) {
                        ForEach(BookingCategory.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(L("Titel", "Title"), text: $viewModel.title)
                    TextField(L("Betrag", "Amount"), text: $viewModel.amountText)
                        .keyboardType(.decimalPad)
                    AppDateField(title: L("Datum", "Date"), selection: $viewModel.date)
                    TextField(L("Notiz", "Note"), text: $viewModel.notes, axis: .vertical)
                }

                Section(L("Konten", "Accounts")) {
                    if viewModel.category.usesTwoAccounts {
                        accountPicker(L("Von", "From"), selection: $viewModel.fromAccountID)
                        accountPicker(L("Nach", "To"), selection: $viewModel.toAccountID)
                    } else {
                        accountPicker(L("Konto", "Account"), selection: $viewModel.accountID)
                    }
                }

                if viewModel.category == .expense {
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
            .onAppear { viewModel.refineIfNeeded(accounts: accounts) }
            .onChange(of: viewModel.category) { _, category in
                viewModel.fillAccounts(for: category, accounts: accounts)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        if viewModel.save(context: context, pools: pools, allSplits: allSplits, accounts: accounts) { dismiss() }
                    }
                }
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
            ForEach(accounts.filter { $0.kind != .savingsGroup }) { account in
                Text(account.kind == .checking ? account.name : "\(account.name) · \(account.kind.label)")
                    .tag(Optional(account.id))
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
