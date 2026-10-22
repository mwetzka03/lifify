import SwiftData
import SwiftUI

struct FixedCostsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \FixedCost.name) private var costs: [FixedCost]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var edited: FixedCost?
    @State private var selected: FixedCost?
    @State private var showingNew = false

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var filterAccounts: [Account] {
        accounts.filter { $0.kind != .savingsGroup }
    }

    private var selectedAccount: Account? {
        filters.account(in: filterAccounts)
    }

    private var regularCosts: [FixedCost] {
        costs.filter { !SavingsPlanFixedCosts.isSavingsCost($0) }
    }

    private var savingsCosts: [FixedCost] {
        FixedCostScope.applicable(
            costs: costs.filter { SavingsPlanFixedCosts.isSavingsCost($0) },
            account: selectedAccount,
            showsDepot: filters.showsDepot,
            includeHousehold: false
        )
    }

    var body: some View {
        List {
            if let period = filters.period(in: periods) {
                Text("\(L("Offen im Zeitraum", "Open in")) \(AppDate.range(from: period.start, to: period.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !savingsCosts.isEmpty {
                NavigationLink(value: FinanceRoute.savingsPlans) {
                    savingsSummaryRow
                }
                ForEach(savingsCosts) { cost in
                    costRow(cost)
                }
                .onDelete { offsets in
                    offsets.map { savingsCosts[$0] }.forEach(delete)
                }
            }
            ForEach(regularCosts) { cost in
                costRow(cost)
            }
            .onDelete { offsets in
                offsets.map { regularCosts[$0] }.forEach(delete)
            }
        }
        .overlay {
            if regularCosts.isEmpty && savingsCosts.isEmpty {
                ContentUnavailableView(L("Keine Fixkosten", "No fixed costs"), systemImage: "repeat")
            }
        }
        .navigationTitle(L("Fixkosten", "Fixed costs"))
        .toolbar {
            Button { showingNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showingNew) { FixedCostForm(cost: nil) }
        .sheet(item: $edited) { FixedCostForm(cost: $0) }
        .sheet(item: $selected) { FixedCostDetailView(cost: $0) }
        .onAppear { SavingsPlanFixedCosts.sync(context: context) }
    }

    private func costRow(_ cost: FixedCost) -> some View {
        let savings = SavingsPlanFixedCosts.isSavingsCost(cost)
        return Button {
            selected = cost
        } label: {
            HStack {
                Image(systemName: savings ? BookingCategory.savingsPlan.systemImage : IconPreferenceStore.icon(for: cost.id, fallback: "repeat"))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(savings ? SavingsPlanFixedCosts.planName(inFixedCostName: cost.name) : cost.name)
                        .foregroundStyle(.primary)
                    Text(detail(for: cost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(cents: -abs(cost.amountCents)))
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                edited = cost
            } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
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

    private var savingsSummaryRow: some View {
        let summary = savingsSummary
        return HStack(spacing: 12) {
            Image(systemName: BookingCategory.savingsPlan.systemImage)
                .frame(width: 28)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Sparpläne", "Savings plans"))
                    .foregroundStyle(.primary)
                Text("\(L("Gebucht", "Booked")) \(Money.string(cents: summary.booked)) · \(L("Offen", "Open")) \(Money.string(cents: summary.open))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: -(summary.booked + summary.open)))
                .foregroundStyle(.red)
        }
    }

    private var savingsSummary: (booked: Int, open: Int) {
        let ids = Set(savingsCosts.compactMap(\.accountID))
        let accountIDs: Set<UUID>? = selectedAccount == nil ? nil : ids
        guard let period = filters.period(in: periods) else {
            let monthly = savingsCosts.filter(\.isActive).reduce(0) { $0 + abs($1.amountCents) }
            return (0, monthly)
        }
        let booked = FinanceService.savingsPlanBookedCents(
            entries: entries,
            from: period.start,
            through: period.end,
            accountIDs: accountIDs
        )
        let open = FinanceService.scheduledCharges(
            costs: savingsCosts.filter(\.isActive),
            entries: entries,
            from: period.start,
            through: period.end
        )
        .filter { !$0.isPaid }
        .reduce(0) { $0 + $1.amount }
        return (booked, open)
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
            .navigationTitle(existing == nil ? L("Neue Fixkosten", "New fixed cost") : L("Fixkosten bearbeiten", "Edit fixed cost"))
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
