import SwiftData
import SwiftUI

struct DashboardView: View {
    let isMainTab: Bool
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var holdings: [PortfolioHolding]
    @Query private var fixedCosts: [FixedCost]
    @Query private var forecasts: [IncomeForecast]

    init(isMainTab: Bool = false) {
        self.isMainTab = isMainTab
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Gesamtvermögen", "Net worth"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(cents: FinanceService.totalBalance(accounts: accounts, entries: entries, holdings: holdings)))
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                    Text("\(L("Davon liquide", "Liquid")): \(Money.string(cents: FinanceService.totalBalance(accounts: accounts, entries: entries, holdings: holdings, liquidOnly: true)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section(L("Konten", "Accounts")) {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        L("Noch keine Konten", "No accounts yet"),
                        systemImage: "building.columns",
                        description: Text(L("Lege dein erstes Konto in den Einstellungen an.", "Create your first account in Settings."))
                    )
                }
                ForEach(accounts.filter { $0.kind != .savingsGroup }) { account in
                    HStack {
                        Label(account.name, systemImage: icon(for: account.kind))
                        Spacer()
                        Text(Money.string(cents: FinanceService.balance(for: account, entries: entries, holdings: holdings)))
                            .monospacedDigit()
                    }
                }
            }

            if isMainTab {
                Section(L("Bereiche", "Sections")) {
                    NavigationLink {
                        TransactionsView()
                    } label: {
                        Label(L("Buchungen", "Transactions"), systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        PlanningView()
                    } label: {
                        Label(L("Budgets und Planung", "Budgets and planning"), systemImage: "calendar")
                    }
                    NavigationLink {
                        OrganizationView()
                    } label: {
                        Label(L("Einkäufe, Schulden und Depot", "Shopping, debts and portfolio"), systemImage: "square.grid.2x2")
                    }
                }
            }

            Section(L("Nächste Planung", "Upcoming plan")) {
                let items = upcomingItems
                if items.isEmpty {
                    Text(L("Keine fälligen Planungen in den nächsten 45 Tagen.", "No planned items due in the next 45 days."))
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: item.amount))
                    }
                }
            }

            Section(L("Letzte Buchungen", "Recent transactions")) {
                ForEach(entries.prefix(5)) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.title)
                            Text(entry.date, format: .dateTime.day().month())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(cents: displayAmount(entry)))
                            .foregroundStyle(displayAmount(entry) < 0 ? .red : .primary)
                    }
                }
            }
        }
    }

    private var upcomingItems: [UpcomingItem] {
        let limit = Calendar.current.date(byAdding: .day, value: 45, to: .now) ?? .now
        let costs = fixedCosts.filter(\.isActive).flatMap { cost -> [UpcomingItem] in
            CalendarService.nextOccurrences(firstDate: cost.firstChargeDate, cadence: cost.cadence, rule: cost.dueRule, day: cost.dayOfMonth, endDate: cost.endChargeDate, through: limit)
                .filter { $0 >= Calendar.current.startOfDay(for: .now) }
                .map { UpcomingItem(id: "\(cost.id)-\($0)", title: cost.name, date: $0, amount: -abs(cost.amountCents)) }
        }
        let income = forecasts.filter(\.isActive).flatMap { forecast -> [UpcomingItem] in
            CalendarService.nextOccurrences(firstDate: forecast.firstPaymentDate, cadence: forecast.cadence, rule: forecast.dueRule, day: forecast.dayOfMonth, endDate: forecast.endPaymentDate, through: limit)
                .filter { $0 >= Calendar.current.startOfDay(for: .now) }
                .map { UpcomingItem(id: "\(forecast.id)-\($0)", title: forecast.name, date: $0, amount: abs(forecast.amountCents)) }
        }
        return (costs + income).sorted { $0.date < $1.date }
    }

    private func displayAmount(_ entry: LedgerEntry) -> Int {
        entry.kind == .transfer || entry.kind == .adjustment ? abs(entry.amountCents) : entry.amountCents
    }

    private func icon(for kind: AccountKind) -> String {
        switch kind {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .savingsGroup: "folder"
        case .portfolio: "chart.line.uptrend.xyaxis"
        }
    }
}

private struct UpcomingItem {
    let id: String
    let title: String
    let date: Date
    let amount: Int
}
