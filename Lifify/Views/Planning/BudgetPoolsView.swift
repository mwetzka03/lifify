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
    @Environment(\.modelContext) private var context
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
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            unlink(entry)
                        } label: {
                            Text(L("Lösen", "Unlink"))
                        }
                    }
                }
                Button {
                    showingBooking = true
                } label: {
                    Label(L("Buchung zuordnen", "Assign transaction"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Text(L(
                    "Eine bestehende Buchung wird verknüpft. Es entsteht keine neue Buchung.",
                    "An existing transaction is linked. No new booking is created."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(pool.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBooking) {
            PoolBookingPicker(pool: pool)
        }
    }

    private func unlink(_ entry: LedgerEntry) {
        splits
            .filter { $0.transactionID == entry.id && $0.kind == .budgetPool && $0.targetID == pool.id }
            .forEach { context.delete($0) }
        try? context.save()
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

private struct PoolBookingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var splits: [TransactionSplit]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    let pool: BudgetPool
    @State private var selected: Set<UUID> = []
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if availableEntries.isEmpty {
                    ContentUnavailableView(
                        L("Keine freien Buchungen", "No free transactions"),
                        systemImage: "tray",
                        description: Text(L(
                            "Jede Buchung, die diesem Pool noch nicht zugeordnet ist, erscheint hier.",
                            "Transactions that are not yet assigned to this pool appear here."
                        ))
                    )
                } else {
                    bookingList
                }
            }
            .searchable(text: $query, prompt: L("Buchung suchen", "Search transactions"))
            .navigationTitle(L("Buchung zuordnen", "Assign transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private var bookingList: some View {
        List(filtered) { entry in
                Button {
                    if selected.contains(entry.id) {
                        selected.remove(entry.id)
                    } else {
                        selected.insert(entry.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(entry.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Text(AppDate.numeric(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: abs(entry.amountCents)))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
    }

    private var availableEntries: [LedgerEntry] {
        let assigned = Set(
            splits
                .filter { $0.kind == .budgetPool && $0.targetID == pool.id }
                .map(\.transactionID)
        )
        return entries.filter { !assigned.contains($0.id) && $0.amountCents != 0 }
    }

    private var filtered: [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return availableEntries }
        return availableEntries.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.notes.localizedCaseInsensitiveContains(text)
        }
    }

    private func save() {
        for entry in entries where selected.contains(entry.id) {
            let absolute = abs(entry.amountCents)
            guard absolute > 0 else { continue }
            context.insert(TransactionSplit(
                transactionID: entry.id,
                targetID: pool.id,
                kind: .budgetPool,
                periodKey: CalendarService.periodKey(for: entry.date, pool: pool),
                amountCents: absolute
            ))
        }
        try? context.save()
        dismiss()
    }
}
