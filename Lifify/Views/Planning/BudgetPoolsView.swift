import SwiftData
import SwiftUI

struct BudgetPoolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetPool.name) private var pools: [BudgetPool]
    @Query private var splits: [TransactionSplit]
    @State private var showingNew = false
    @State private var edited: BudgetPool?

    var body: some View {
        List {
            ForEach(pools) { pool in
                let key = CalendarService.periodKey(for: .now, pool: pool)
                let spent = FinanceService.poolSpent(pool: pool, periodKey: key, splits: splits)
                let carry = FinanceService.poolCarry(pool: pool, currentPeriodKey: key, splits: splits)
                NavigationLink {
                    BudgetPoolDetailView(pool: pool)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(pool.name)
                            if pool.isScalable { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue) }
                            Spacer()
                            Text(Money.string(cents: pool.amountCents + carry - spent))
                        }
                        Text("\(pool.periodMode.label) · \(key)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if pool.isScalable {
                            Text("\(L("Übertrag", "Carryover")): \(Money.string(cents: carry))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(pool)
                        try? context.save()
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { edited = pool } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .overlay {
            if pools.isEmpty {
                ContentUnavailableView(L("Keine Budgetpools", "No budget pools"), systemImage: "tray.full")
            }
        }
        .navigationTitle(L("Budgetpools", "Budget pools"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { BudgetPoolForm(pool: nil) }
        .sheet(item: $edited) { BudgetPoolForm(pool: $0) }
    }
}

private struct BudgetPoolDetailView: View {
    @Query private var splits: [TransactionSplit]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    let pool: BudgetPool
    @State private var showingBooking = false

    var body: some View {
        let key = CalendarService.periodKey(for: .now, pool: pool)
        let spent = FinanceService.poolSpent(pool: pool, periodKey: key, splits: splits)
        let carry = FinanceService.poolCarry(pool: pool, currentPeriodKey: key, splits: splits)
        let remaining = pool.amountCents + carry - spent
        List {
            Section {
                LabeledContent(L("Budget", "Budget"), value: Money.string(cents: pool.amountCents))
                LabeledContent(L("Zeitraum", "Period"), value: pool.periodMode.label)
                LabeledContent(L("Aktuell", "Current"), value: key)
                LabeledContent(L("Verbraucht", "Spent"), value: Money.string(cents: spent))
                if pool.isScalable {
                    LabeledContent(L("Übertrag", "Carryover"), value: Money.string(cents: carry))
                }
                LabeledContent(L("Rest", "Remaining"), value: Money.string(cents: remaining))
                LabeledContent(L("Skalierbar", "Scalable"), value: pool.isScalable ? L("Ja", "Yes") : L("Nein", "No"))
            }
            Section(L("Buchungen", "Transactions")) {
                if assignedEntries.isEmpty {
                    Text(L("In diesem Zeitraum ist nichts zugeordnet.", "Nothing is assigned in this period."))
                        .foregroundStyle(.secondary)
                }
                ForEach(assignedEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(AppDate.numeric(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: assignedAmount(entry)))
                    }
                }
                Button {
                    showingBooking = true
                } label: {
                    Label(L("Buchung hinzufügen", "Add transaction"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle(pool.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBooking) {
            PoolBookingForm(pool: pool)
        }
    }

    private var periodSplits: [TransactionSplit] {
        let key = CalendarService.periodKey(for: .now, pool: pool)
        return splits.filter {
            $0.kind == .budgetPool
                && $0.targetID == pool.id
                && CalendarService.splitCounts(in: key, splitKey: $0.periodKey, pool: pool)
        }
    }

    private var assignedEntries: [LedgerEntry] {
        let ids = Set(periodSplits.map(\.transactionID))
        return entries.filter { ids.contains($0.id) }
    }

    private func assignedAmount(_ entry: LedgerEntry) -> Int {
        periodSplits.filter { $0.transactionID == entry.id }.reduce(0) { $0 + $1.amountCents }
    }
}

private struct BudgetPoolForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let existing: BudgetPool?
    @State private var name: String
    @State private var amount: String
    @State private var mode: BudgetPeriodMode
    @State private var scalable: Bool

    init(pool: BudgetPool?) {
        existing = pool
        _name = State(initialValue: pool?.name ?? "")
        _amount = State(initialValue: pool.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _mode = State(initialValue: pool?.periodMode ?? .salaryPeriod)
        _scalable = State(initialValue: pool?.isScalable ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Budget", "Budget"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Zeitraum", "Period"), selection: $mode) {
                    ForEach(BudgetPeriodMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("Skalierbar", "Scalable"), isOn: $scalable)
                Text(L(
                    "Bleibt Geld übrig, wird es in den nächsten Zeitraum mitgenommen. Der Pool gehört zu keinem Konto.",
                    "Money left over is carried into the next period. The pool is not tied to an account."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(existing == nil ? L("Neuer Pool", "New pool") : L("Pool bearbeiten", "Edit pool"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private func save() {
        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
        if let existing {
            existing.name = name
            existing.amountCents = abs(cents)
            existing.accountID = nil
            existing.periodMode = mode
            existing.isScalable = scalable
        } else {
            context.insert(BudgetPool(
                name: name,
                amountCents: abs(cents),
                accountID: nil,
                periodMode: mode,
                salaryStartDay: 1,
                isScalable: scalable
            ))
        }
        try? context.save()
        dismiss()
    }
}

private struct PoolBookingForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    let pool: BudgetPool
    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date.now
    @State private var accountID: UUID?
    @State private var notes = ""

    private var cashAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Betrag", "Amount"), text: $amount)
                    .keyboardType(.decimalPad)
                AppDateField(title: L("Datum", "Date"), selection: $date)
                Picker(L("Konto", "Account"), selection: $accountID) {
                    Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                    ForEach(cashAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
                Text(L(
                    "Die Buchung wird diesem Pool im Zeitraum des Datums zugeordnet.",
                    "The transaction is assigned to this pool for the period of its date."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(L("Buchung hinzufügen", "Add transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard accountID == nil else { return }
                accountID = cashAccounts.first(where: \.isMain)?.id ?? cashAccounts.first?.id
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cents = Money.cents(from: amount), cents != 0, !trimmed.isEmpty, let accountID else { return }
        let absolute = abs(cents)
        let entry = LedgerEntry(
            date: date,
            title: trimmed,
            notes: notes,
            amountCents: -absolute,
            kind: .expense,
            accountID: accountID
        )
        context.insert(entry)
        context.insert(TransactionSplit(
            transactionID: entry.id,
            targetID: pool.id,
            kind: .budgetPool,
            periodKey: CalendarService.periodKey(for: date, pool: pool),
            amountCents: absolute
        ))
        try? context.save()
        dismiss()
    }
}
