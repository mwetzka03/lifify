import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt, order: .reverse) private var items: [ShoppingItem]
    @State private var showingNew = false
    @State private var edited: ShoppingItem?

    var body: some View {
        List {
            ForEach(items) { item in
                HStack {
                    Button {
                        item.isPurchased.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    }
                    Button {
                        edited = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).strikethrough(item.isPurchased)
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
                            if item.amountCents > 0 { Text(Money.string(cents: item.amountCents)) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { offsets in
                offsets.map { items[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView(L("Einkaufszettel ist leer", "Shopping list is empty"), systemImage: "cart") }
        }
        .navigationTitle(L("Einkaufszettel", "Shopping list"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { ShoppingItemForm(item: nil) }
        .sheet(item: $edited) { ShoppingItemForm(item: $0) }
    }
}

private struct ShoppingItemForm: View {
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
