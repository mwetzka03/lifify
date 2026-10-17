import SwiftData
import SwiftUI

struct FixedCostsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \FixedCost.name) private var costs: [FixedCost]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var edited: FixedCost?
    @State private var showingNew = false

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    var body: some View {
        List {
            if let period = filters.period(in: periods) {
                Text("\(L("Offen im Zeitraum", "Open in")) \(AppDate.range(from: period.start, to: period.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(costs) { cost in
                Button {
                    edited = cost
                } label: {
                    HStack {
                        Image(systemName: IconPreferenceStore.icon(for: cost.id, fallback: "repeat"))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cost.name).foregroundStyle(.primary)
                            Text(detail(for: cost))
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
                offsets.map { costs[$0] }.forEach(delete)
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
        .onAppear { SavingsPlanFixedCosts.sync(context: context) }
    }

    private func detail(for cost: FixedCost) -> String {
        guard cost.isActive else {
            return "\(cost.cadence.label) · \(L("Beendet", "Ended"))"
        }
        let next = FinanceService.nextChargeDate(for: cost, entries: entries)
        let nextText = next.map { "\(L("Nächste", "Next")) \(AppDate.numeric($0))" }
            ?? L("Keine weitere Abbuchung", "No further debit")
        let open = openCount(for: cost)
        let openText = open == 1 ? L("1 offen", "1 open") : "\(open) \(L("offen", "open"))"
        if SavingsPlanFixedCosts.isSavingsCost(cost) {
            return "\(cost.cadence.label) · \(nextText) · \(openText)"
        }
        return "\(cost.cadence.label) · \(cost.dueRule.label) · \(nextText) · \(openText)"
    }

    private func openCount(for cost: FixedCost) -> Int {
        guard let period = filters.period(in: periods) else { return 0 }
        return FinanceService.openChargeCount(
            for: cost,
            entries: entries,
            from: period.start,
            through: period.end
        )
    }

    private func delete(_ cost: FixedCost) {
        SavingsPlanFixedCosts.removePlan(for: cost)
        IconPreferenceStore.remove(for: cost.id)
        context.delete(cost)
        try? context.save()
    }
}

struct FixedCostForm: View {
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
    private let managed: Bool

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
        managed = cost.map { SavingsPlanFixedCosts.isManagedName($0.name) } ?? false
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
                if managed {
                    Text(CalendarService.savingsPlanScheduleText(cadence: cadence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    AppDateField(title: L("Erste Fälligkeit", "First due date"), selection: $firstDate)
                    Picker(L("Fälligkeitsregel", "Due rule"), selection: $dueRule) {
                        ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                    }
                    if dueRule == .calendarDay {
                        Stepper("\(L("Tag", "Day")): \(day)", value: $day, in: 1...31)
                    }
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
                        cost.dueRule = managed ? .calendarDay : dueRule
                        cost.dayOfMonth = managed ? 2 : day
                        cost.isActive = active
                        if managed && !SavingsPlanFixedCosts.isManagedName(cost.name) {
                            cost.name = "\(SavingsPlanFixedCosts.namePrefix)\(name)"
                        }
                        if existing == nil { context.insert(cost) }
                        IconPreferenceStore.set(icon, for: cost.id)
                        if managed {
                            SavingsPlanFixedCosts.adopt(cost)
                        }
                        try? context.save()
                        if managed {
                            SavingsPlanFixedCosts.sync(context: context)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
