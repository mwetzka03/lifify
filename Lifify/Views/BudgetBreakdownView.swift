import SwiftData
import SwiftUI

struct BudgetBreakdownView: View {
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var entries: [LedgerEntry]
    @Query private var accounts: [Account]
    @Query private var splits: [TransactionSplit]
    @Query private var forecasts: [IncomeForecast]
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @State private var selected: LedgerEntry?

    private var budget: HomeBudgetSnapshot {
        HomeBudget.make(
            entries: entries,
            accounts: accounts,
            forecasts: forecasts,
            variableBudgets: variableBudgets,
            pools: pools,
            splits: splits,
            dashboardPeriod: dashboardPeriod
        )
    }

    var body: some View {
        let snapshot = budget
        List {
            Section {
                LabeledContent(L("Gesamt", "Total"), value: Money.string(cents: snapshot.planned))
                LabeledContent(L("Verbraucht", "Spent"), value: Money.string(cents: snapshot.spent))
                LabeledContent(L("Offen", "Remaining"), value: Money.string(cents: snapshot.remaining))
                Text(AppDate.range(from: snapshot.periodStart, to: snapshot.periodEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(explanation(snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Einnahmen", "Income")) {
                if snapshot.incomeLines.isEmpty {
                    Text(L("Keine passenden Einnahmen.", "No matching income."))
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.incomeLines) { line in
                    lineRow(line, color: .green)
                }
                totalRow(snapshot.incomeLines.reduce(0) { $0 + $1.cents }, expense: false)
            }
            Section(L("Einnahmeprognosen", "Income forecasts")) {
                if snapshot.forecastLines.isEmpty {
                    Text(L("Keine offenen Prognosen.", "No open forecasts."))
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.forecastLines) { line in
                    lineRow(line, color: .green)
                }
                if snapshot.forecastAdjustment > 0 {
                    HStack {
                        Text(L("Schon in den Einnahmen", "Already in income"))
                        Spacer()
                        Text(Money.signed(cents: -snapshot.forecastAdjustment))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if snapshot.countsAllExpenses {
                Section(L("Ausgaben", "Expenses")) {
                    if snapshot.expenseLines.isEmpty {
                        Text(L("Keine Ausgaben.", "No expenses."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.expenseLines) { line in
                        lineRow(line, color: .red)
                    }
                    totalRow(snapshot.expenseLines.reduce(0) { $0 + $1.cents }, expense: true)
                }
            } else {
                Section(L("Variable Budgets", "Variable budgets")) {
                    if snapshot.variableLines.isEmpty {
                        Text(L("Nichts verbraucht.", "Nothing spent."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.variableLines) { line in
                        lineRow(line, color: .red)
                    }
                }
                Section(L("Budgetpools", "Budget pools")) {
                    if snapshot.poolLines.isEmpty {
                        Text(L("Nichts verbraucht.", "Nothing spent."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.poolLines) { line in
                        lineRow(line, color: .red)
                    }
                }
            }
            Section(L("Käufe und Sparpläne", "Purchases and savings plans")) {
                if snapshot.purchaseLines.isEmpty {
                    Text(L("Keine Käufe in diesem Zeitraum.", "No purchases in this period."))
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.purchaseLines) { line in
                    lineRow(line, color: .red)
                }
                totalRow(snapshot.purchaseLines.reduce(0) { $0 + $1.cents }, expense: true)
            }
        }
        .navigationTitle(L("Budget", "Budget"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
    }

    private func explanation(_ snapshot: HomeBudgetSnapshot) -> String {
        if snapshot.countsAllExpenses {
            return L(
                "Gesamt sind fremde Einnahmen plus offene Gehaltsprognosen. Verbraucht sind Ausgaben sowie Aktienkäufe und Sparplan-Ausführungen.",
                "The total is external income plus open salary forecasts. Spent is expenses plus stock purchases and savings-plan executions."
            )
        }
        return L(
            "Ohne aktive Einnahmeprognose zählen variable Budgets, Budgetpools und Käufe.",
            "Without an active income forecast, variable budgets, budget pools and purchases count."
        )
    }

    @ViewBuilder
    private func lineRow(_ line: HomeBudgetLine, color: Color) -> some View {
        let row = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                if let date = line.date {
                    Text(AppDate.numeric(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Money.string(cents: line.cents))
                .foregroundStyle(color)
        }
        if let entry = line.entry {
            Button {
                selected = entry
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func totalRow(_ cents: Int, expense: Bool) -> some View {
        HStack {
            Text(L("Summe", "Total"))
            Spacer()
            Text(Money.signed(cents: expense ? -cents : cents))
                .foregroundStyle(cents == 0 ? Color.secondary : (expense ? .red : .green))
        }
    }
}
