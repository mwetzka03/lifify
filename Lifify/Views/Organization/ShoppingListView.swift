import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt, order: .reverse) private var items: [ShoppingItem]
    @State private var showingNew = false

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
                    VStack(alignment: .leading) {
                        Text(item.name).strikethrough(item.isPurchased)
                        if !item.groupName.isEmpty {
                            Text(item.groupName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if item.amountCents > 0 { Text(Money.string(cents: item.amountCents)) }
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
        .sheet(isPresented: $showingNew) { ShoppingItemForm() }
    }
}

private struct ShoppingItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var amount = ""
    @State private var group = ""
    @State private var url = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Artikel", "Item"), text: $name)
                TextField(L("Geplanter Betrag", "Planned amount"), text: $amount).keyboardType(.decimalPad)
                TextField(L("Gruppe", "Group"), text: $group)
                TextField("URL", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(L("Neuer Artikel", "New item"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !name.isEmpty else { return }
                        context.insert(ShoppingItem(name: name, amountCents: abs(Money.cents(from: amount) ?? 0), groupName: group, urlString: url, notes: notes))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
