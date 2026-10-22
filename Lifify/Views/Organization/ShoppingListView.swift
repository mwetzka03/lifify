import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \ShoppingItem.createdAt, order: .reverse) private var items: [ShoppingItem]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var showingNew = false
    @State private var edited: ShoppingItem?
    @State private var selected: ShoppingItem?

    private var period: ForecastPeriod? {
        filters.period(in: FinancePeriods.all(entries: entries, forecasts: forecasts))
    }

    private var bias: (applied: Int, planned: Int) {
        guard let period else { return (0, 0) }
        return FinanceService.shoppingBias(shopping: items, entries: entries, period: period)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            itemList
        }
        .navigationTitle(L("Einkaufszettel", "Shopping list"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { ShoppingItemForm(item: nil) }
        .sheet(item: $edited) { ShoppingItemForm(item: $0) }
        .sheet(item: $selected) { ShoppingItemDetailView(item: $0) }
        .onAppear(perform: markAssignedPurchased)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let period {
                Text(AppDate.range(from: period.start, to: period.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Angewendet", "Applied"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: bias.applied))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Geplant", "Planned"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: bias.planned))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var itemList: some View {
        List {
            ForEach(items) { item in
                HStack {
                    Button {
                        togglePurchased(item)
                    } label: {
                        Image(systemName: isChecked(item) ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        selected = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).strikethrough(isChecked(item))
                                if let planned = item.plannedDate {
                                    Text(AppDate.numeric(planned))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !item.groupName.isEmpty {
                                    Text(item.groupName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(rowAmount(item))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { edited = item } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(item)
                        try? context.save()
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView(L("Einkaufszettel ist leer", "Shopping list is empty"), systemImage: "cart") }
        }
    }

    private func isChecked(_ item: ShoppingItem) -> Bool {
        item.isPurchased || !FinanceService.shoppingBookings(for: item.id, entries: entries).isEmpty
    }

    private func rowAmount(_ item: ShoppingItem) -> String {
        let bookings = FinanceService.shoppingBookings(for: item.id, entries: entries, period: period)
        let cents = bookings.isEmpty ? item.amountCents : bookings.reduce(0) { $0 + abs($1.amountCents) }
        guard cents > 0 else { return "" }
        return Money.string(cents: cents)
    }

    private func togglePurchased(_ item: ShoppingItem) {
        guard FinanceService.shoppingBookings(for: item.id, entries: entries).isEmpty else { return }
        item.isPurchased.toggle()
        try? context.save()
    }

    private func markAssignedPurchased() {
        var changed = false
        for item in items where !item.isPurchased && !FinanceService.shoppingBookings(for: item.id, entries: entries).isEmpty {
            item.isPurchased = true
            changed = true
        }
        if changed { try? context.save() }
    }
}

struct ShoppingItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    let item: ShoppingItem
    @State private var selectedBooking: LedgerEntry?

    private var bookings: [LedgerEntry] {
        FinanceService.shoppingBookings(for: item.id, entries: entries)
    }

    private var isChecked: Bool {
        item.isPurchased || !bookings.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Artikel", "Item"), value: item.name)
                    LabeledContent(L("Geplanter Betrag", "Planned amount"), value: Money.string(cents: item.amountCents))
                    if let planned = item.plannedDate {
                        LabeledContent(L("Geplant am", "Planned on"), value: AppDate.numeric(planned))
                    }
                    HStack {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isChecked ? Color.green : Color.secondary)
                        Text(isChecked ? L("Gekauft", "Purchased") : L("Offen", "Open"))
                        Spacer()
                    }
                }
                Section(L("Buchungen", "Transactions")) {
                    if bookings.isEmpty {
                        Text(L("Noch keine Buchung zugeordnet.", "No transaction is assigned yet."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(bookings) { entry in
                        Button {
                            selectedBooking = entry
                        } label: {
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
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { dismiss() }
                }
            }
        }
        .sheet(item: $selectedBooking) { TransactionDetailView(entry: $0) }
    }
}

struct ShoppingItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let existing: ShoppingItem?
    @State private var name: String
    @State private var amount: String
    @State private var group: String
    @State private var url: String
    @State private var notes: String
    @State private var plansDate: Bool
    @State private var plannedDate: Date

    init(item: ShoppingItem?) {
        existing = item
        _name = State(initialValue: item?.name ?? "")
        _amount = State(initialValue: item.map { Self.amountText($0.amountCents) } ?? "")
        _group = State(initialValue: item?.groupName ?? "")
        _url = State(initialValue: item?.urlString ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _plansDate = State(initialValue: item?.plannedDate != nil || item == nil)
        _plannedDate = State(initialValue: item?.plannedDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Artikel", "Item"), text: $name)
                TextField(L("Geplanter Betrag", "Planned amount"), text: $amount).keyboardType(.decimalPad)
                TextField(L("Gruppe", "Group"), text: $group)
                TextField("URL", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
                Toggle(L("Für einen Gehaltszeitraum planen", "Plan for a salary period"), isOn: $plansDate)
                if plansDate {
                    AppDateField(title: L("Geplant am", "Planned on"), selection: $plannedDate)
                }
            }
            .navigationTitle(existing == nil ? L("Neuer Artikel", "New item") : L("Artikel", "Item"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private static func amountText(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppDate.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? ""
    }

    private func save() {
        guard !name.isEmpty else { return }
        let cents = abs(Money.cents(from: amount) ?? 0)
        let date = plansDate ? plannedDate : nil
        if let existing {
            existing.name = name
            existing.amountCents = cents
            existing.groupName = group
            existing.urlString = url
            existing.notes = notes
            existing.plannedDate = date
        } else {
            context.insert(ShoppingItem(
                name: name,
                amountCents: cents,
                plannedDate: date,
                groupName: group,
                urlString: url,
                notes: notes
            ))
        }
        try? context.save()
        dismiss()
    }
}
