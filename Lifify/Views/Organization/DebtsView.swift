import SwiftData
import SwiftUI

struct DebtsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DebtEntry.date, order: .reverse) private var debts: [DebtEntry]
    @State private var showingNew = false

    var body: some View {
        List {
            Section {
                LabeledContent(L("Bekomme ich", "Owed to me"), value: Money.string(cents: total(.owedToMe)))
                LabeledContent(L("Schulde ich", "I owe"), value: Money.string(cents: total(.iOwe)))
            }
            ForEach(debts) { debt in
                HStack {
                    Button {
                        debt.isSettled.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: debt.isSettled ? "checkmark.circle.fill" : "circle")
                    }
                    VStack(alignment: .leading) {
                        Text(debt.contactName)
                        Text(debt.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.string(cents: debt.amountCents))
                }
            }
            .onDelete { offsets in
                offsets.map { debts[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .navigationTitle(L("Schulden", "Debts"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { DebtForm() }
    }

    private func total(_ direction: DebtDirection) -> Int {
        debts.filter { !$0.isSettled && $0.direction == direction }.reduce(0) { $0 + $1.amountCents }
    }
}

private struct DebtForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var contact = ""
    @State private var title = ""
    @State private var amount = ""
    @State private var direction = DebtDirection.owedToMe
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Kontakt", "Contact"), text: $contact)
                TextField(L("Beschreibung", "Description"), text: $title)
                TextField(L("Betrag", "Amount"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Richtung", "Direction"), selection: $direction) {
                    ForEach(DebtDirection.allCases) { Text($0.label).tag($0) }
                }
                DatePicker(L("Datum", "Date"), selection: $date, displayedComponents: .date)
            }
            .navigationTitle(L("Neue Schuld", "New debt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !contact.isEmpty else { return }
                        context.insert(DebtEntry(contactName: contact, title: title, amountCents: abs(cents), direction: direction, date: date))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
