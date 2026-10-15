import SwiftData
import SwiftUI

struct BudgetPoolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetPool.name) private var pools: [BudgetPool]
    @Query private var splits: [TransactionSplit]
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(pools) { pool in
                let key = CalendarService.periodKey(for: .now, pool: pool)
                let spent = FinanceService.poolSpent(pool: pool, periodKey: key, splits: splits)
                let carry = FinanceService.poolCarry(pool: pool, currentPeriodKey: key, splits: splits)
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
            .onDelete { offsets in
                offsets.map { pools[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if pools.isEmpty {
                ContentUnavailableView(L("Keine Budgetpools", "No budget pools"), systemImage: "tray.full")
            }
        }
        .navigationTitle(L("Budgetpools", "Budget pools"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { BudgetPoolForm() }
    }
}

private struct BudgetPoolForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name = ""
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var mode = BudgetPeriodMode.salaryPeriod
    @State private var startDay = 1
    @State private var scalable = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Budget", "Budget"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Konto", "Account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker(L("Zeitraum", "Period"), selection: $mode) {
                    ForEach(BudgetPeriodMode.allCases) { Text($0.label).tag($0) }
                }
                if mode == .salaryPeriod {
                    Stepper("\(L("Starttag", "Start day")): \(startDay)", value: $startDay, in: 1...31)
                }
                Toggle(L("Rest übertragen", "Carry remaining amount"), isOn: $scalable)
            }
            .navigationTitle(L("Neuer Pool", "New pool"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
                        context.insert(BudgetPool(name: name, amountCents: abs(cents), accountID: accountID, periodMode: mode, salaryStartDay: startDay, isScalable: scalable))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
