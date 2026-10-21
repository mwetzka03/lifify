import Foundation

struct HomeBudgetLine: Identifiable {
    var id: String
    var title: String
    var date: Date?
    var cents: Int
    var entry: LedgerEntry?
}

struct HomeBudgetSnapshot {
    var planned: Int
    var spent: Int
    var nextSalary: Date?
    var periodStart: Date
    var periodEnd: Date
    var countsAllExpenses: Bool
    var incomeLines: [HomeBudgetLine]
    var forecastLines: [HomeBudgetLine]
    var forecastAdjustment: Int
    var expenseLines: [HomeBudgetLine]
    var purchaseLines: [HomeBudgetLine]
    var variableLines: [HomeBudgetLine]
    var poolLines: [HomeBudgetLine]

    var remaining: Int { planned - spent }
}

@MainActor
enum HomeBudget {
    static func make(
        entries: [LedgerEntry],
        accounts: [Account],
        forecasts: [IncomeForecast],
        variableBudgets: [VariableBudget],
        pools: [BudgetPool],
        splits: [TransactionSplit],
        dashboardPeriod: String,
        now: Date = .now
    ) -> HomeBudgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let periodStart = budgetPeriodStart(
            now: now,
            forecasts: forecasts,
            dashboardPeriod: dashboardPeriod
        )
        let periodEnd = budgetPeriodEnd(
            start: periodStart,
            forecasts: forecasts,
            dashboardPeriod: dashboardPeriod
        )
        let incomeEntries = entries
            .filter {
                $0.kind == .income
                    && !BookingClassification.isRefund($0)
                    && $0.date >= periodStart
                    && $0.date <= periodEnd
                    && ExternalIncome.countsInHomeBudget($0, accounts: accounts)
            }
            .sorted { $0.date > $1.date }
        let booked = incomeEntries.reduce(0) { $0 + abs($1.amountCents) }
        let bookedFromToday = incomeEntries
            .filter { $0.date >= today }
            .reduce(0) { $0 + abs($1.amountCents) }
        let forecastLines = forecasts.filter(\.isActive).flatMap { forecast in
            occurrences(of: forecast, from: today, through: periodEnd).map { date in
                HomeBudgetLine(
                    id: "forecast-\(forecast.id.uuidString)-\(date.dayKey)",
                    title: forecast.name,
                    date: date,
                    cents: abs(forecast.amountCents)
                )
            }
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let upcoming = forecastLines.reduce(0) { $0 + $1.cents }
        let adjustment = min(upcoming, max(0, bookedFromToday))
        let planned = booked + max(0, upcoming - bookedFromToday)

        let portfolios = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        let purchaseEntries = entries
            .filter { entry in
                guard entry.date >= periodStart, entry.date <= now else { return false }
                return PortfolioCashFlow.isSecurityPurchase(entry, portfolioIDs: portfolios)
            }
            .sorted { $0.date > $1.date }
        let purchaseLines = purchaseEntries.map { entry in
            HomeBudgetLine(
                id: entry.id.uuidString,
                title: entry.title,
                date: entry.date,
                cents: abs(entry.amountCents),
                entry: entry
            )
        }
        let countsAllExpenses = forecasts.contains(where: \.isActive)
        let expenseEntries = entries
            .filter { $0.kind == .expense && $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date > $1.date }
        let expenseLines = expenseEntries.compactMap { entry -> HomeBudgetLine? in
            let cents = RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
            guard cents > 0 else { return nil }
            return HomeBudgetLine(
                id: entry.id.uuidString,
                title: entry.title,
                date: entry.date,
                cents: cents,
                entry: entry
            )
        }
        let variableLines = variableBudgets.map { budget in
            HomeBudgetLine(
                id: budget.id.uuidString,
                title: budget.name,
                date: nil,
                cents: FinanceService.variableSpent(
                    budgetID: budget.id,
                    monthKey: now.monthKey,
                    entries: entries,
                    splits: splits
                )
            )
        }
        .filter { $0.cents != 0 }
        let poolLines = pools.filter(\.isActive).map { pool in
            let key = CalendarService.periodKey(for: now, pool: pool)
            return HomeBudgetLine(
                id: pool.id.uuidString,
                title: pool.name,
                date: nil,
                cents: FinanceService.poolSpent(pool: pool, periodKey: key, splits: splits)
            )
        }
        .filter { $0.cents != 0 }
        let spent: Int
        if countsAllExpenses {
            spent = expenseLines.reduce(0) { $0 + $1.cents } + purchaseLines.reduce(0) { $0 + $1.cents }
        } else {
            spent = variableLines.reduce(0) { $0 + $1.cents }
                + poolLines.reduce(0) { $0 + $1.cents }
                + purchaseLines.reduce(0) { $0 + $1.cents }
        }
        return HomeBudgetSnapshot(
            planned: planned,
            spent: spent,
            nextSalary: nextSalaryDate(forecasts: forecasts, now: now),
            periodStart: periodStart,
            periodEnd: periodEnd,
            countsAllExpenses: countsAllExpenses,
            incomeLines: incomeEntries.map { entry in
                HomeBudgetLine(
                    id: entry.id.uuidString,
                    title: entry.title,
                    date: entry.date,
                    cents: abs(entry.amountCents),
                    entry: entry
                )
            },
            forecastLines: forecastLines,
            forecastAdjustment: adjustment,
            expenseLines: expenseLines,
            purchaseLines: purchaseLines,
            variableLines: variableLines,
            poolLines: poolLines
        )
    }

    private static func occurrences(of forecast: IncomeForecast, from today: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        let limit = calendar.startOfDay(for: end)
        return CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: end
        )
        .filter {
            let day = calendar.startOfDay(for: $0)
            return day >= today && day <= limit
        }
    }

    private static func nextSalaryDate(forecasts: [IncomeForecast], now: Date) -> Date? {
        guard let forecast = primaryForecast(in: forecasts),
              let limit = Calendar.current.date(byAdding: .year, value: 2, to: now)
        else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        return CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: limit
        )
        .first { Calendar.current.startOfDay(for: $0) > today }
    }

    private static func primaryForecast(in forecasts: [IncomeForecast]) -> IncomeForecast? {
        guard let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString)
        else {
            return forecasts.first(where: \.isActive)
        }
        return forecasts.first { $0.id == id } ?? forecasts.first(where: \.isActive)
    }

    private static func budgetPeriodStart(
        now: Date,
        forecasts: [IncomeForecast],
        dashboardPeriod: String
    ) -> Date {
        let calendar = Calendar.current
        guard DashboardPeriodMode(rawValue: dashboardPeriod) == .salaryPeriod,
              let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString),
              let forecast = forecasts.first(where: { $0.id == id })
        else {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                ?? calendar.startOfDay(for: now)
        }
        let occurrences = CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: now
        )
        if let latest = occurrences.last(where: { $0 <= now }) {
            return latest
        }
        let current = calendar.dateComponents([.year, .month], from: now)
        let candidate = CalendarService.dueDate(
            year: current.year ?? calendar.component(.year, from: now),
            month: current.month ?? calendar.component(.month, from: now),
            day: forecast.dayOfMonth,
            rule: forecast.dueRule
        )
        if candidate <= now { return candidate }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = calendar.dateComponents([.year, .month], from: previousMonth)
        return CalendarService.dueDate(
            year: previous.year ?? calendar.component(.year, from: previousMonth),
            month: previous.month ?? calendar.component(.month, from: previousMonth),
            day: forecast.dayOfMonth,
            rule: forecast.dueRule
        )
    }

    private static func budgetPeriodEnd(
        start: Date,
        forecasts: [IncomeForecast],
        dashboardPeriod: String
    ) -> Date {
        let calendar = Calendar.current
        let fallback = calendar.date(byAdding: .month, value: 1, to: start)
            .flatMap { calendar.date(byAdding: .second, value: -1, to: $0) }
            ?? start
        guard DashboardPeriodMode(rawValue: dashboardPeriod) == .salaryPeriod,
              let idString = UserDefaults.standard.string(forKey: "primaryIncomeForecastID"),
              let id = UUID(uuidString: idString),
              let forecast = forecasts.first(where: { $0.id == id }),
              let limit = calendar.date(byAdding: .year, value: 2, to: start)
        else { return fallback }
        let nextOccurrence = CalendarService.nextOccurrences(
            firstDate: forecast.firstPaymentDate,
            cadence: forecast.cadence,
            rule: forecast.dueRule,
            day: forecast.dayOfMonth,
            endDate: forecast.endPaymentDate,
            through: limit
        )
        .first { $0 > start }
        guard let nextOccurrence else { return fallback }
        return calendar.date(byAdding: .second, value: -1, to: nextOccurrence) ?? fallback
    }
}
