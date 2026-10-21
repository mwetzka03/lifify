import SwiftData
import SwiftUI

struct FilteredLedgerView: View {
    let kind: LedgerKind
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \IncomeForecast.name) private var forecasts: [IncomeForecast]
    @Query(sort: \FixedCost.name) private var fixedCosts: [FixedCost]
    @Query private var holdings: [PortfolioHolding]
    @State private var selected: LedgerEntry?
    @State private var showingNewForecast = false
    @State private var editedForecast: IncomeForecast?
    @State private var editedCost: FixedCost?
    @State private var preparedRows: [FlowRow] = []
    @State private var rowsToken: Int?

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
            guard entry.kind == kind else { return false }
            if kind == .income, BookingClassification.isRefund(entry) { return false }
            guard FinancePeriods.includes(entry, period: selectedPeriod, account: selectedAccount, depotIDs: depotIDs) else { return false }
            guard selectedAccount == nil, !filters.showsDepot, kind == .income else { return true }
            return ExternalIncome.countsInCombinedFinance(entry, accounts: accounts)
        }
    }

    private var depotIDs: Set<UUID> {
        guard filters.showsDepot else { return [] }
        return Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
    }

    private var portfolioLines: [PortfolioCashFlow.Line] {
        let lines = PortfolioCashFlow.lines(
            kind: kind,
            entries: entries,
            accounts: accounts,
            holdings: holdings,
            period: selectedPeriod,
            account: filters.showsDepot ? nil : selectedAccount
        )
        guard filters.showsDepot else { return lines }
        return lines.filter { line in
            if let from = line.entry.fromAccountID, depotIDs.contains(from) { return true }
            if let to = line.entry.toAccountID, depotIDs.contains(to) { return true }
            return false
        }
    }

    private var flowRows: [FlowRow] {
        let booked = visibleEntries.map { entry in
            let remainder = kind == .expense ? RefundLinkStore.realExpenseCents(of: entry, entries: entries) : nil
            let counted = kind == .expense
                ? RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
                : abs(entry.amountCents)
            return FlowRow(
                id: entry.id.uuidString,
                entry: entry,
                title: entry.title,
                date: entry.date,
                signedCents: kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents),
                counts: counted > 0,
                isTransfer: false,
                realCents: remainder,
                countedCents: counted
            )
        }
        let trades = portfolioLines.map { line in
            FlowRow(
                id: "trade-\(line.id)",
                entry: line.entry,
                title: line.title,
                date: line.entry.date,
                signedCents: line.signedCents,
                counts: line.counts,
                isTransfer: line.caption == nil,
                caption: line.caption
            )
        }
        return (booked + trades).sorted { $0.date > $1.date }
    }

    private var countedTotal: Int {
        preparedRows.reduce(0) { total, row in
            guard row.counts else { return total }
            if let counted = row.countedCents { return total + counted }
            return total + abs(row.signedCents)
        }
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
                            HStack(spacing: 12) {
                                Image(systemName: BookingCategory.income.systemImage)
                                    .frame(width: 28)
                                    .foregroundStyle(.primary)
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
                if kind == .expense && !filters.showsDepot {
                    Section {
                        if upcomingCharges.isEmpty {
                            Text(L("Keine offenen Prognosen.", "No open forecasts."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upcomingCharges) { item in
                            let savings = SavingsPlanFixedCosts.isManagedName(item.title)
                            let paint = BookingClassification.paint(
                                category: savings ? .savingsPlan : .expense,
                                signed: -item.amount,
                                scope: bookingScope
                            )
                            HStack(spacing: 12) {
                                Image(systemName: savings ? BookingCategory.savingsPlan.systemImage : BookingCategory.expense.systemImage)
                                    .frame(width: 28)
                                    .foregroundStyle(savings ? paint.iconColor : .primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(AppDate.numeric(item.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.string(cents: -item.amount))
                                    .foregroundStyle(savings ? paint.amountColor : .red)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editedCost = fixedCosts.first { $0.id == item.costID }
                            }
                        }
                    } header: {
                        Text(L("Prognoseausgaben", "Expense forecasts"))
                    }
                }
                if rowsToken != ledgerToken {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.large)
                            Text(L("Wird geladen", "Loading"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else if preparedRows.isEmpty {
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
                if rowsToken == ledgerToken {
                ForEach(preparedRows) { row in
                    Button { selected = row.entry } label: {
                        let category = rowCategory(row)
                        let economics = category == .portfolioSale
                            ? HoldingMaintenance.saleEconomics(for: row.entry, holdings: holdings)
                            : nil
                        let paint = BookingClassification.paint(
                            category: category,
                            signed: row.signedCents,
                            scope: bookingScope,
                            differenceCents: row.caption == nil ? (row.realCents ?? economics?.differenceCents) : nil
                        )
                        let amountColor = row.caption == nil
                            ? paint.amountColor
                            : BookingClassification.differenceColor(row.signedCents)
                        let iconColor = row.caption == nil ? paint.iconColor : amountColor
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 12) {
                                Image(systemName: category.systemImage)
                                    .frame(width: 28)
                                    .foregroundStyle(iconColor)
                                Text(row.title).foregroundStyle(.primary)
                                Spacer()
                                BookingAmountStack(
                                    amount: row.signedCents,
                                    amountColor: amountColor,
                                    difference: paint.differenceCents,
                                    showsExplicitSign: true
                                )
                            }
                            HStack {
                                Text(category.label)
                                Text(AppDate.numeric(row.date))
                                if let caption = row.caption {
                                    Text(caption)
                                } else if row.isTransfer && !row.counts {
                                    Text(L("Umbuchung, nicht in der Summe", "Transfer, not included in the total"))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 40)
                        }
                    }
                    .buttonStyle(.plain)
                }
                }
            }
        }
        .task(id: ledgerToken) {
            await refreshRows()
        }
        .appCanvas()
        .navigationTitle(kind == .income ? L("Einnahmen", "Income") : L("Ausgaben", "Expenses"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
        .sheet(isPresented: $showingNewForecast) { IncomeForecastForm(forecast: nil) }
        .sheet(item: $editedForecast) { IncomeForecastForm(forecast: $0) }
        .sheet(item: $editedCost) { FixedCostForm(cost: $0) }
    }

    private var bookingScope: BookingScope {
        if filters.showsDepot { return .depot }
        if selectedAccount != nil { return .account }
        return .combined
    }

    private func rowCategory(_ row: FlowRow) -> BookingCategory {
        BookingClassification.category(
            of: row.entry,
            accounts: accounts,
            viewedAccountID: filters.showsDepot ? nil : selectedAccount?.id
        )
    }

    private var applicableFixedCosts: [FixedCost] {
        FixedCostScope.applicable(
            costs: fixedCosts,
            account: selectedAccount,
            showsDepot: filters.showsDepot,
            includeHousehold: selectedAccount == nil || selectedAccount?.isMain == true
        )
    }

    private var upcomingCharges: [ScheduledCharge] {
        guard kind == .expense, let period = selectedPeriod else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        guard period.end >= today else { return [] }
        return FinanceService.scheduledCharges(
            costs: applicableFixedCosts.filter(\.isActive),
            entries: entries,
            from: period.start,
            through: period.end
        )
        .filter { !$0.isPaid }
    }

    private var upcomingForecasts: [ForecastOccurrence] {
        guard let period = selectedPeriod else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard period.end >= today else { return [] }
        var items: [ForecastOccurrence] = []
        for forecast in forecasts where forecast.isActive && forecastBelongsToSelection(forecast) {
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

    private func forecastBelongsToSelection(_ forecast: IncomeForecast) -> Bool {
        guard !filters.showsDepot else { return false }
        guard let account = selectedAccount else { return true }
        return forecast.accountID == account.id
    }

    private var ledgerToken: Int {
        var hasher = Hasher()
        hasher.combine(kind.rawValue)
        hasher.combine(filters.showsDepot)
        hasher.combine(selectedAccount?.id)
        hasher.combine(selectedPeriod?.id)
        hasher.combine(RefundLinkStore.fingerprint())
        hasher.combine(HoldingLotStore.cacheRevision)
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.amountCents)
            hasher.combine(entry.kindRaw)
            hasher.combine(entry.accountID)
            hasher.combine(entry.fromAccountID)
            hasher.combine(entry.toAccountID)
            hasher.combine(entry.title)
            hasher.combine(entry.notes)
        }
        for holding in holdings {
            hasher.combine(holding.id)
            hasher.combine(holding.accountID)
            hasher.combine(holding.symbol)
            hasher.combine(holding.quantity)
            hasher.combine(holding.currentPriceCents)
        }
        for account in accounts {
            hasher.combine(account.id)
            hasher.combine(account.kindRaw)
            hasher.combine(account.isMain)
        }
        return hasher.finalize()
    }

    private func refreshRows() async {
        let token = ledgerToken
        await Task.yield()
        guard !Task.isCancelled else { return }
        _ = SavingsPlanStore.all()
        _ = ClosedPositionStore.all()
        if let holding = holdings.first {
            _ = HoldingLotStore.lots(for: holding.id)
            _ = HistoricalPriceStore.cents(for: holding.id, dayKey: Date.now.dayKey)
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let rows = flowRows
        guard !Task.isCancelled else { return }
        preparedRows = rows
        rowsToken = token
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
    var caption: String? = nil
    var realCents: Int? = nil
    var countedCents: Int? = nil
}

private struct ForecastOccurrence: Identifiable {
    var id: String
    var forecast: IncomeForecast
    var date: Date
    var amount: Int
}
