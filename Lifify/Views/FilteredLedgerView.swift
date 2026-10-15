import SwiftData
import SwiftUI

struct FilteredLedgerView: View {
    let kind: LedgerKind
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var selected: LedgerEntry?

    private var filterAccounts: [Account] {
        accounts.filter { $0.kind != .savingsGroup }
    }

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var visibleEntries: [LedgerEntry] {
        let period = filters.period(in: periods)
        let account = filters.account(in: filterAccounts)
        return entries.filter { entry in
            entry.kind == kind && FinancePeriods.includes(entry, period: period, account: account)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            FinanceFilterControls(periods: periods, accounts: filterAccounts)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            List {
                if visibleEntries.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleEntries) { entry in
                    Button { selected = entry } label: { TransactionRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .appCanvas()
        .navigationTitle(kind == .income ? L("Einnahmen", "Income") : L("Ausgaben", "Expenses"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == .income {
                NavigationLink(value: FinanceRoute.incomeForecasts) {
                    Text(L("Prognosen", "Forecasts"))
                }
            }
        }
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
    }

    private var emptyText: String {
        kind == .income
            ? L("Keine Einnahmen in diesem Zeitraum.", "No income in this period.")
            : L("Keine Ausgaben in diesem Zeitraum.", "No expenses in this period.")
    }
}
