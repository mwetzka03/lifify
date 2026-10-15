import SwiftData
import SwiftUI

struct FilteredLedgerView: View {
    let kind: LedgerKind
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \IncomeForecast.name) private var forecasts: [IncomeForecast]
    @State private var selected: LedgerEntry?
    @State private var showingNewForecast = false
    @State private var editedForecast: IncomeForecast?

    private var filterAccounts: [Account] {
        accounts.filter { $0.kind != .savingsGroup }
    }

    private var periods: [ForecastPeriod] {
        FinancePeriods.all(entries: entries, forecasts: forecasts)
    }

    private var selectedPeriod: ForecastPeriod? {
        filters.period(in: periods)
    }

    private var selectedAccount: Account? {
        filters.account(in: filterAccounts)
    }

    private var visibleEntries: [LedgerEntry] {
        entries.filter { entry in
            entry.kind == kind && FinancePeriods.includes(entry, period: selectedPeriod, account: selectedAccount)
        }
    }

    private var portfolioLines: [PortfolioCashFlow.Line] {
        PortfolioCashFlow.lines(
            kind: kind,
            entries: entries,
            accounts: accounts,
            period: selectedPeriod,
            account: selectedAccount
        )
    }

    private var flowRows: [FlowRow] {
        let booked = visibleEntries.map { entry in
            FlowRow(
                id: entry.id.uuidString,
                entry: entry,
                title: entry.title,
                date: entry.date,
                signedCents: kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents),
                counts: true,
                isTransfer: false
            )
        }
        let trades = portfolioLines.map { line in
            FlowRow(
                id: "trade-\(line.id)",
                entry: line.entry,
                title: line.entry.title,
                date: line.entry.date,
                signedCents: line.signedCents,
                counts: line.counts,
                isTransfer: true
            )
        }
        return (booked + trades).sorted { $0.date > $1.date }
    }

    private var countedTotal: Int {
        flowRows.filter(\.counts).reduce(0) { $0 + abs($1.signedCents) }
    }

    var body: some View {
        VStack(spacing: 8) {
            FinanceFilterControls(periods: periods, accounts: filterAccounts)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            List {
                if kind == .income {
                    Section {
                        if upcomingForecasts.isEmpty {
                            Text(L("Keine offenen Prognosen.", "No open forecasts."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upcomingForecasts) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.forecast.name)
                                    Text(AppDate.numeric(item.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.string(cents: item.amount))
                                    .foregroundStyle(.green)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editedForecast = item.forecast }
                            .contextMenu {
                                Button(L("Bearbeiten", "Edit")) { editedForecast = item.forecast }
                                Button(L("Löschen", "Delete"), role: .destructive) {
                                    context.delete(item.forecast)
                                    try? context.save()
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(L("Einnahmeprognosen", "Income forecasts"))
                            Spacer()
                            Button {
                                showingNewForecast = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .accessibilityLabel(L("Prognose hinzufügen", "Add forecast"))
                        }
                    }
                }
                if flowRows.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(L("Summe", "Total"))
                        Spacer()
                        Text(Money.signed(cents: kind == .expense ? -countedTotal : countedTotal))
                            .foregroundStyle(countedTotal == 0 ? Color.secondary : (kind == .expense ? .red : .green))
                    }
                }
                ForEach(flowRows) { row in
                    Button { selected = row.entry } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.title).foregroundStyle(.primary)
                                Spacer()
                                Text(Money.signed(cents: row.signedCents))
                                    .foregroundStyle(row.signedCents < 0 ? .red : .green)
                            }
                            HStack {
                                Text(AppDate.numeric(row.date))
                                if row.isTransfer && !row.counts {
                                    Text(L("Umbuchung, nicht in der Summe", "Transfer, not included in the total"))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .appCanvas()
        .navigationTitle(kind == .income ? L("Einnahmen", "Income") : L("Ausgaben", "Expenses"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
        .sheet(isPresented: $showingNewForecast) { IncomeForecastForm(forecast: nil) }
        .sheet(item: $editedForecast) { IncomeForecastForm(forecast: $0) }
    }

    private var upcomingForecasts: [ForecastOccurrence] {
        guard let period = selectedPeriod else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard period.end >= today else { return [] }
        var items: [ForecastOccurrence] = []
        for forecast in forecasts where forecast.isActive {
            let dates = CalendarService.nextOccurrences(
                firstDate: forecast.firstPaymentDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endPaymentDate,
                through: period.end
            )
            guard let date = dates.first(where: { candidate in
                let day = calendar.startOfDay(for: candidate)
                return day >= today && period.contains(day) && !forecastIsBooked(forecast, period: period, day: day)
            }) else { continue }
            let day = calendar.startOfDay(for: date)
            items.append(ForecastOccurrence(
                id: "\(forecast.id.uuidString)-\(day.dayKey)",
                forecast: forecast,
                date: day,
                amount: abs(forecast.amountCents)
            ))
        }
        return items.sorted { $0.date < $1.date }
    }

    private func forecastIsBooked(_ forecast: IncomeForecast, period: ForecastPeriod?, day: Date) -> Bool {
        let ibans = IncomeAssignmentStore.ibans(for: forecast.id)
        return entries.contains { entry in
            guard entry.kind == .income else { return false }
            if let period {
                guard period.contains(entry.date) else { return false }
            } else {
                guard Calendar.current.isDate(entry.date, inSameDayAs: day) else { return false }
            }
            if IncomeAssignmentStore.forecastID(forEntryID: entry.id) == forecast.id { return true }
            guard !ibans.isEmpty else { return false }
            let notes = entry.notes.replacingOccurrences(of: " ", with: "").uppercased()
            return ibans.contains { notes.contains($0) }
        }
    }

    private var emptyText: String {
        kind == .income
            ? L("Keine Einnahmen in diesem Zeitraum.", "No income in this period.")
            : L("Keine Ausgaben in diesem Zeitraum.", "No expenses in this period.")
    }
}

private struct FlowRow: Identifiable {
    var id: String
    var entry: LedgerEntry
    var title: String
    var date: Date
    var signedCents: Int
    var counts: Bool
    var isTransfer: Bool
}

private struct ForecastOccurrence: Identifiable {
    var id: String
    var forecast: IncomeForecast
    var date: Date
    var amount: Int
}
