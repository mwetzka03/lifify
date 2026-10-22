import SwiftData
import SwiftUI

struct ForecastDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var splits: [TransactionSplit]
    @Query private var shopping: [ShoppingItem]
    @Query private var budgets: [VariableBudget]
    let item: ForecastListItem
    let period: ForecastPeriod
    var account: Account?
    @State private var chosen: UUID?
    @State private var selectedBooking: LedgerEntry?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Art", "Type"), value: kindTitle)
                    LabeledContent(L("Datum", "Date"), value: AppDate.numeric(item.date))
                    LabeledContent(L("Betrag", "Amount"), value: Money.signed(cents: displayedAmount))
                    if item.refKind == .variable, let remaining {
                        LabeledContent(L("Noch offen", "Still open"), value: Money.string(cents: remaining))
                    }
                }
                if item.refKind == .variable {
                    variableSection
                } else {
                    singleAssignmentSection
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Schließen", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern", "Save")) {
                        apply()
                        if item.refKind == .variable {
                            chosen = nil
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { chosen = initialChoice }
        }
        .sheet(item: $selectedBooking) { TransactionDetailView(entry: $0) }
    }

    private var singleAssignmentSection: some View {
        Section {
            Text(L(
                "Eine zugewiesene Buchung ersetzt diese Prognose für den ganzen Zeitraum. Die anderen Termine bleiben bestehen. Automatisch erkannte Buchungen gelten weiterhin.",
                "An assigned transaction replaces this forecast for the whole period. The other dates stay. Bookings recognized automatically still apply."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            if item.refKind == .shopping {
                if shoppingAssignments.isEmpty {
                    Text(L("Noch keine Buchung zugeordnet.", "No transaction is assigned yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(shoppingAssignments) { entry in
                    Button {
                        selectedBooking = entry
                    } label: {
                        bookingRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            } else if let current = coveringEntry {
                Button {
                    selectedBooking = current
                } label: {
                    bookingRow(current)
                }
                .buttonStyle(.plain)
            }
            assignmentPicker
        } header: {
            Text(L("Buchung zuweisen", "Assign transaction"))
        }
    }

    private var variableSection: some View {
        Section {
            Text(L(
                "Jede zugeordnete Buchung mindert den reservierten Betrag. Weitere Buchungen bleiben möglich, bis der Betrag aufgebraucht ist.",
                "Each assigned transaction reduces the reserved amount. More transactions can be added until the amount is used up."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            if variableAssignments.isEmpty {
                Text(L("Noch keine Buchung zugeordnet.", "No transaction is assigned yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(variableAssignments) { entry in
                Button {
                    selectedBooking = entry
                } label: {
                    bookingRow(entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        unlinkVariable(entry)
                    } label: {
                        Label(L("Entfernen", "Remove"), systemImage: "minus.circle")
                    }
                }
            }
            assignmentPicker
        } header: {
            Text(L("Buchungen zuweisen", "Assign transactions"))
        }
    }

    @ViewBuilder
    private var assignmentPicker: some View {
        if candidates.isEmpty {
            Text(L("In diesem Zeitraum liegt keine passende Buchung.", "This period has no matching transaction."))
                .foregroundStyle(.secondary)
        } else {
            Picker(item.refKind == .variable ? L("Weitere Buchung", "Another transaction") : L("Buchung", "Transaction"), selection: $chosen) {
                Text(L("Keine", "None")).tag(Optional<UUID>.none)
                ForEach(candidates) { entry in
                    Text(choiceLabel(entry)).tag(Optional(entry.id))
                }
            }
        }
    }

    private func bookingRow(_ entry: LedgerEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                Text(AppDate.numeric(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: -abs(entry.amountCents)))
                .foregroundStyle(.red)
        }
    }

    private var kindTitle: String {
        switch item.refKind {
        case .income: L("Einnahme", "Income")
        case .fixed: L("Fixkosten", "Fixed cost")
        case .transfer: L("Umbuchung", "Transfer")
        case .variable: L("Variable Kosten", "Variable cost")
        case .shopping: L("Einkaufszettel", "Shopping list")
        }
    }

    private var displayedAmount: Int {
        if item.refKind == .variable, let remaining { return -remaining }
        return item.signedCents
    }

    private var remaining: Int? {
        guard let budget = variableBudget else { return nil }
        let cashIDs = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id)
        let plan = VariableBudgetAccounts.planCents(
            budget: budget,
            scopedAccountIDs: account.map { Set([$0.id]) },
            cashAccountIDs: cashIDs
        )
        let spent = FinanceService.variableSpent(
            budgetID: budget.id,
            from: period.start,
            through: min(Date(), period.end),
            entries: entries,
            splits: splits,
            accountID: account?.id
        )
        return max(plan - spent, 0)
    }

    private var variableBudget: VariableBudget? {
        guard case .variable(let id) = item.kind else { return nil }
        return budgets.first { $0.id == id }
    }

    private var variableAssignments: [LedgerEntry] {
        guard let budget = variableBudget else { return [] }
        let splitIDs = Set(
            splits
                .filter { $0.kind == .variableBudget && $0.targetID == budget.id }
                .map(\.transactionID)
        )
        return entries.filter { entry in
            guard period.contains(entry.date), matchesAccount(entry) else { return false }
            if entry.variableBudgetID == budget.id || splitIDs.contains(entry.id) { return true }
            guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == .variable && link.id == budget.id
        }
        .sorted { $0.date > $1.date }
    }

    private var candidates: [LedgerEntry] {
        let taken = Set(variableAssignments.map(\.id))
        return entries.filter { entry in
            guard period.contains(entry.date), matchesAccount(entry) else { return false }
            if item.refKind == .variable, taken.contains(entry.id) { return false }
            switch item.refKind {
            case .income:
                return entry.kind == .income && !BookingClassification.isRefund(entry)
            case .fixed, .variable, .shopping:
                return entry.kind == .expense
            case .transfer:
                return entry.kind == .transfer
            }
        }
    }

    private var shoppingAssignments: [LedgerEntry] {
        guard case .shopping(let id) = item.kind else { return [] }
        return FinanceService.shoppingBookings(for: id, entries: entries, period: period)
            .filter { matchesAccount($0) }
    }

    private var initialChoice: UUID? {
        if item.refKind == .variable { return nil }
        if item.refKind == .shopping {
            return coveringEntryID ?? shoppingAssignments.first?.id
        }
        return coveringEntryID
    }

    private var coveringEntry: LedgerEntry? {
        guard let coveringEntryID else { return nil }
        return entries.first { $0.id == coveringEntryID }
    }

    private var coveringEntryID: UUID? {
        entries.first { entry in
            guard period.contains(entry.date), let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == item.refKind && link.id == item.sourceID
        }?.id
    }

    private func matchesAccount(_ entry: LedgerEntry) -> Bool {
        guard let account else { return true }
        return entry.accountID == account.id || entry.fromAccountID == account.id || entry.toAccountID == account.id
    }

    private func choiceLabel(_ entry: LedgerEntry) -> String {
        "\(entry.title) · \(AppDate.numeric(entry.date)) · \(Money.string(cents: abs(entry.amountCents)))"
    }

    private func apply() {
        switch item.kind {
        case .variable(let id):
            assignVariable(id)
        case .shopping(let id):
            replaceSingleLink()
            syncShopping(id)
        default:
            replaceSingleLink()
        }
    }

    private func assignVariable(_ budgetID: UUID) {
        guard let chosen, let entry = entries.first(where: { $0.id == chosen }) else { return }
        entry.variableBudgetID = budgetID
        if let link = ForecastPeriodLinkStore.link(for: entry.id), link.kind == .variable {
            ForecastPeriodLinkStore.clear(entryID: entry.id)
        }
        try? context.save()
    }

    private func unlinkVariable(_ entry: LedgerEntry) {
        guard let budgetID = variableBudget?.id else { return }
        if entry.variableBudgetID == budgetID {
            entry.variableBudgetID = nil
        }
        splits.filter { $0.transactionID == entry.id && $0.kind == .variableBudget && $0.targetID == budgetID }
            .forEach { context.delete($0) }
        if let link = ForecastPeriodLinkStore.link(for: entry.id), link.kind == .variable, link.id == budgetID {
            ForecastPeriodLinkStore.clear(entryID: entry.id)
        }
        try? context.save()
    }

    private func syncShopping(_ itemID: UUID) {
        let previous = entries.filter { entry in
            guard period.contains(entry.date) else { return false }
            if entry.shoppingItemID == itemID { return true }
            guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == .shopping && link.id == itemID
        }
        for entry in previous where entry.id != chosen && entry.shoppingItemID == itemID {
            entry.shoppingItemID = nil
        }
        if let chosen, let entry = entries.first(where: { $0.id == chosen }) {
            entry.shoppingItemID = itemID
        }
        if let shoppingItem = shopping.first(where: { $0.id == itemID }) {
            let stillLinked = entries.contains { entry in
                entry.shoppingItemID == itemID
                    || (ForecastPeriodLinkStore.link(for: entry.id).map { $0.kind == .shopping && $0.id == itemID } ?? false)
            }
            shoppingItem.isPurchased = stillLinked
        }
        try? context.save()
    }

    private func replaceSingleLink() {
        let previous = entries.filter { entry in
            guard period.contains(entry.date), let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == item.refKind && link.id == item.sourceID
        }
        for entry in previous where entry.id != chosen {
            clearLink(entry.id)
        }
        guard let chosen else { return }
        ForecastPeriodLinkStore.assign(entryID: chosen, kind: item.refKind, forecastID: item.sourceID)
        switch item.kind {
        case .income:
            IncomeAssignmentStore.assign(entryID: chosen, to: item.sourceID)
        case .transfer:
            TransferForecastAssignmentStore.assign(entryID: chosen, forecastID: item.sourceID)
        case .expense, .variable, .shopping:
            break
        }
    }

    private func clearLink(_ entryID: UUID) {
        ForecastPeriodLinkStore.clear(entryID: entryID)
        switch item.kind {
        case .income:
            IncomeAssignmentStore.clear(entryID: entryID)
        case .transfer:
            TransferForecastAssignmentStore.clear(entryID: entryID)
        case .expense, .variable, .shopping:
            break
        }
    }
}
