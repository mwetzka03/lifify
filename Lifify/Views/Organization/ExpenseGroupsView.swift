import SwiftData
import SwiftUI

struct ExpenseGroupsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseGroup.date, order: .reverse) private var groups: [ExpenseGroup]
    @Query private var lines: [ExpenseGroupLine]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @AppStorage(ExpenseGroupAssignmentStore.revisionKey) private var assignmentRevision = 0
    @State private var showingNew = false
    @State private var edited: ExpenseGroup?

    var body: some View {
        let _ = assignmentRevision
        List {
            ForEach(groups) { group in
                NavigationLink {
                    ExpenseGroupDetailView(group: group)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text(AppDate.numeric(group.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: total(for: group)))
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete(group) } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { edited = group } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .overlay {
            if groups.isEmpty { ContentUnavailableView(L("Keine Ausgabengruppen", "No expense groups"), systemImage: "square.stack.3d.up") }
        }
        .navigationTitle(L("Ausgabengruppen", "Expense groups"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { ExpenseGroupForm(group: nil) }
        .sheet(item: $edited) { ExpenseGroupForm(group: $0) }
    }

    private func total(for group: ExpenseGroup) -> Int {
        let ids = Set(ExpenseGroupAssignmentStore.entryIDs(in: group.id))
        return entries.filter { ids.contains($0.id) }.reduce(0) { $0 + abs($1.amountCents) }
    }

    private func delete(_ group: ExpenseGroup) {
        lines.filter { $0.groupID == group.id }.forEach(context.delete)
        ExpenseGroupAssignmentStore.removeGroup(group.id)
        context.delete(group)
        try? context.save()
    }
}

private struct ExpenseGroupDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @AppStorage(ExpenseGroupAssignmentStore.revisionKey) private var assignmentRevision = 0
    let group: ExpenseGroup
    @State private var showingAssign = false

    private var assigned: [LedgerEntry] {
        _ = assignmentRevision
        let ids = Set(ExpenseGroupAssignmentStore.entryIDs(in: group.id))
        return entries.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            if !group.notes.isEmpty { Section { Text(group.notes) } }
            Section {
                if assigned.isEmpty {
                    Text(L("Noch keine Buchung zugeordnet.", "No transaction assigned yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(assigned) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(AppDate.numeric(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: abs(entry.amountCents)))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            ExpenseGroupAssignmentStore.clear(entryID: entry.id)
                        } label: {
                            Label(L("Entfernen", "Remove"), systemImage: "minus.circle")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("\(L("Summe", "Total")): \(Money.string(cents: assigned.reduce(0) { $0 + abs($1.amountCents) }))")
            } footer: {
                Text(L(
                    "Die Gruppe gilt nur hier. Die Buchung selbst bleibt unverändert.",
                    "The group applies only here. The transaction itself stays unchanged."
                ))
            }
        }
        .navigationTitle(group.name)
        .toolbar { Button { showingAssign = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingAssign) { ExpenseBookingPicker(groupID: group.id) }
    }
}

private struct ExpenseGroupForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let existing: ExpenseGroup?
    @State private var name: String
    @State private var date: Date
    @State private var notes: String

    init(group: ExpenseGroup?) {
        existing = group
        _name = State(initialValue: group?.name ?? "")
        _date = State(initialValue: group?.date ?? .now)
        _notes = State(initialValue: group?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                AppDateField(title: L("Datum", "Date"), selection: $date)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(existing == nil ? L("Neue Gruppe", "New group") : L("Gruppe bearbeiten", "Edit group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !name.isEmpty else { return }
                        if let existing {
                            existing.name = name
                            existing.date = date
                            existing.notes = notes
                        } else {
                            context.insert(ExpenseGroup(name: name, date: date, notes: notes))
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ExpenseBookingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    let groupID: UUID
    @State private var selected: Set<UUID> = []
    @State private var query = ""

    var body: some View {
        NavigationStack {
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
            .searchable(text: $query, prompt: L("Buchung suchen", "Search transactions"))
            .navigationTitle(L("Buchungen zuweisen", "Assign transactions"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selected = Set(ExpenseGroupAssignmentStore.entryIDs(in: groupID))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        ExpenseGroupAssignmentStore.replace(groupID: groupID, entryIDs: selected)
                        dismiss()
                    }
                }
            }
        }
    }

    private var filtered: [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.notes.localizedCaseInsensitiveContains(text)
        }
    }
}
