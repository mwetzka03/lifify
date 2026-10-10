import SwiftData
import SwiftUI

struct FixedCostsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCost.name) private var costs: [FixedCost]
    @State private var edited: FixedCost?
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(costs) { cost in
                Button {
                    edited = cost
                } label: {
                    HStack {
                        Image(systemName: IconPreferenceStore.icon(for: cost.id, fallback: "repeat"))
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(cost.name).foregroundStyle(.primary)
                            Text("\(cost.cadence.label) · \(cost.dueRule.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: -abs(cost.amountCents)))
                            .foregroundStyle(.red)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { costs[$0] }.forEach {
                    IconPreferenceStore.remove(for: $0.id)
                    context.delete($0)
                }
                try? context.save()
            }
        }
        .overlay {
            if costs.isEmpty {
                ContentUnavailableView(L("Keine Fixkosten", "No fixed costs"), systemImage: "repeat")
            }
        }
        .navigationTitle(L("Fixkosten", "Fixed costs"))
        .toolbar {
            Button { showingNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showingNew) { FixedCostForm(cost: nil) }
        .sheet(item: $edited) { FixedCostForm(cost: $0) }
    }
}

private struct FixedCostForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    private let existing: FixedCost?
    @State private var name: String
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var cadence: Cadence
    @State private var firstDate: Date
    @State private var dueRule: DueRule
    @State private var day: Int
    @State private var active: Bool
    @State private var icon: String

    init(cost: FixedCost?) {
        existing = cost
        _name = State(initialValue: cost?.name ?? "")
        _amount = State(initialValue: cost.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _accountID = State(initialValue: cost?.accountID)
        _cadence = State(initialValue: cost?.cadence ?? .monthly)
        _firstDate = State(initialValue: cost?.firstChargeDate ?? .now)
        _dueRule = State(initialValue: cost?.dueRule ?? .calendarDay)
        _day = State(initialValue: cost?.dayOfMonth ?? 1)
        _active = State(initialValue: cost?.isActive ?? true)
        _icon = State(initialValue: cost.map { IconPreferenceStore.icon(for: $0.id, fallback: "repeat") } ?? "repeat")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Betrag", "Amount"), text: $amount).keyboardType(.decimalPad)
                SymbolPicker(title: L("Symbol", "Icon"), selection: $icon)
                Picker(L("Konto", "Account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Picker(L("Rhythmus", "Cadence"), selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.label).tag($0) }
                }
                DatePicker(L("Erste Fälligkeit", "First due date"), selection: $firstDate, displayedComponents: .date)
                Picker(L("Fälligkeitsregel", "Due rule"), selection: $dueRule) {
                    ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                }
                if dueRule == .calendarDay {
                    Stepper("\(L("Tag", "Day")): \(day)", value: $day, in: 1...31)
                }
                Toggle(L("Aktiv", "Active"), isOn: $active)
            }
            .navigationTitle(L("Fixkosten", "Fixed cost"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
                        let cost = existing ?? FixedCost(name: name, amountCents: abs(cents))
                        cost.name = name
                        cost.amountCents = abs(cents)
                        cost.accountID = accountID
                        cost.cadence = cadence
                        cost.firstChargeDate = firstDate
                        cost.dueRule = dueRule
                        cost.dayOfMonth = day
                        cost.isActive = active
                        if existing == nil { context.insert(cost) }
                        IconPreferenceStore.set(icon, for: cost.id)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
