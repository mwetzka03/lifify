import SwiftData
import SwiftUI

struct ExpenseGroupsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseGroup.date, order: .reverse) private var groups: [ExpenseGroup]
    @Query private var lines: [ExpenseGroupLine]
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(groups) { group in
                NavigationLink {
                    ExpenseGroupDetailView(group: group)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text(group.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: lines.filter { $0.groupID == group.id }.reduce(0) { $0 + $1.amountCents }))
                    }
                }
            }
            .onDelete { offsets in
                for group in offsets.map({ groups[$0] }) {
                    lines.filter { $0.groupID == group.id }.forEach(context.delete)
                    context.delete(group)
                }
                try? context.save()
            }
        }
        .overlay {
            if groups.isEmpty { ContentUnavailableView(L("Keine Ausgabengruppen", "No expense groups"), systemImage: "square.stack.3d.up") }
        }
        .navigationTitle(L("Ausgabengruppen", "Expense groups"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { ExpenseGroupForm() }
    }
}

private struct ExpenseGroupDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var allLines: [ExpenseGroupLine]
    let group: ExpenseGroup
    @State private var showingNew = false

    private var lines: [ExpenseGroupLine] {
        allLines.filter { $0.groupID == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            if !group.notes.isEmpty { Section { Text(group.notes) } }
            Section {
                ForEach(lines) { line in
                    LabeledContent(line.name, value: Money.string(cents: line.amountCents))
                }
                .onDelete { offsets in
                    offsets.map { lines[$0] }.forEach(context.delete)
                    try? context.save()
                }
            } header: {
                Text("\(L("Summe", "Total")): \(Money.string(cents: lines.reduce(0) { $0 + $1.amountCents }))")
            }
        }
        .navigationTitle(group.name)
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { ExpenseLineForm(groupID: group.id, sortOrder: lines.count) }
    }
}

private struct ExpenseGroupForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var date = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                DatePicker(L("Datum", "Date"), selection: $date, displayedComponents: .date)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(L("Neue Gruppe", "New group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !name.isEmpty else { return }
                        context.insert(ExpenseGroup(name: name, date: date, notes: notes))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ExpenseLineForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let groupID: UUID
    let sortOrder: Int
    @State private var name = ""
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Position", "Line item"), text: $name)
                TextField(L("Betrag", "Amount"), text: $amount).keyboardType(.decimalPad)
            }
            .navigationTitle(L("Neue Position", "New line"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
                        context.insert(ExpenseGroupLine(groupID: groupID, name: name, amountCents: abs(cents), sortOrder: sortOrder))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
