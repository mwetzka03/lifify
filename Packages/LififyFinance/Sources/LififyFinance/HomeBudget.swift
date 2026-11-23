import Foundation
import LififyCore

/// One line of the home budget breakdown.
public struct HomeBudgetLine: Identifiable {
    public var id: String
    public var title: String
    public var date: Date?
    public var cents: Int
    public var entry: LedgerEntry?

    public init(id: String, title: String, date: Date? = nil, cents: Int, entry: LedgerEntry? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.cents = cents
        self.entry = entry
    }
}

/// The calculated home budget.
public struct HomeBudgetSnapshot {
    public var planned: Int
    public var spent: Int
    public var nextSalary: Date?
    public var periodStart: Date
    public var periodEnd: Date
    public var countsAllExpenses: Bool
    public var incomeLines: [HomeBudgetLine]
    public var forecastLines: [HomeBudgetLine]
    public var forecastAdjustment: Int
    public var expenseLines: [HomeBudgetLine]
    public var purchaseLines: [HomeBudgetLine]
    public var variableLines: [HomeBudgetLine]
    public var poolLines: [HomeBudgetLine]

    public var remaining: Int { planned - spent }

    public init(planned: Int, spent: Int, nextSalary: Date? = nil, periodStart: Date, periodEnd: Date, countsAllExpenses: Bool, incomeLines: [HomeBudgetLine], forecastLines: [HomeBudgetLine], forecastAdjustment: Int, expenseLines: [HomeBudgetLine], purchaseLines: [HomeBudgetLine], variableLines: [HomeBudgetLine], poolLines: [HomeBudgetLine]) {
        self.planned = planned
        self.spent = spent
        self.nextSalary = nextSalary
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.countsAllExpenses = countsAllExpenses
        self.incomeLines = incomeLines
        self.forecastLines = forecastLines
        self.forecastAdjustment = forecastAdjustment
        self.expenseLines = expenseLines
        self.purchaseLines = purchaseLines
        self.variableLines = variableLines
        self.poolLines = poolLines
    }
}

/// Calculates the budget shown on Home.
@MainActor
public enum HomeBudget {
    /// Builds the home budget for the current period.
    ///
    /// - Parameters:
    ///   - entries: All bookings.
    ///   - accounts: All accounts.
    ///   - forecasts: The income forecasts.
    ///   - variableBudgets: The variable budgets.
    ///   - pools: The budget pools.
    ///   - splits: The booking splits.
    ///   - dashboardPeriod: The raw value of the chosen period mode.
    ///   - now: The current time.
    /// - Returns: Planned and spent amounts with their lines.
    public static func make(
        entries: [LedgerEntry],
        accounts: [Account],
        forecasts: [IncomeForecast],
        variableBudgets: [VariableBudget],
        pools: [BudgetPool],
        splits: [TransactionSplit],
        dashboardPeriod: String,
        now: Date = FinanceClock.now
    ) -> HomeBudgetSnapshot {
        let periodStart = budgetPeriodStart(now: now, forecasts: forecasts, dashboardPeriod: dashboardPeriod)
        let periodEnd = budgetPeriodEnd(start: periodStart, forecasts: forecasts, dashboardPeriod: dashboardPeriod)
        let today = Calendar.current.startOfDay(for: now)
        let income = incomeEntries(entries, accounts: accounts, from: periodStart, through: periodEnd)
        let upcoming = forecastLines(forecasts, from: today, through: periodEnd)
        let plan = plannedIncome(booked: income, upcoming: upcoming, today: today)
        let purchases = purchaseLines(entries, accounts: accounts, from: periodStart, through: now)
        let expenses = expenseLines(entries, from: periodStart, through: now)
        let variable = variableLines(variableBudgets, entries: entries, splits: splits, now: now)
        let poolRows = poolLines(pools, splits: splits, now: now)
        let countsAllExpenses = forecasts.contains(where: \.isActive)
        let counted = countsAllExpenses ? expenses + purchases : variable + poolRows + purchases
        return HomeBudgetSnapshot(
            planned: plan.planned,
            spent: counted.reduce(0) { $0 + $1.cents },
            nextSalary: nextSalaryDate(forecasts: forecasts, now: now),
            periodStart: periodStart,
            periodEnd: periodEnd,
            countsAllExpenses: countsAllExpenses,
            incomeLines: income.map { line(for: $0, cents: abs($0.amountCents)) },
            forecastLines: upcoming,
            forecastAdjustment: plan.adjustment,
            expenseLines: expenses,
            purchaseLines: purchases,
            variableLines: variable,
            poolLines: poolRows
        )
    }

    /// Builds the line of one booking.
    private static func line(for entry: LedgerEntry, cents: Int) -> HomeBudgetLine {
        HomeBudgetLine(id: entry.id.uuidString, title: entry.title, date: entry.date, cents: cents, entry: entry)
    }

    /// Lists the period's real income, newest first. Refunds and own transfers do not count.
    private static func incomeEntries(
        _ entries: [LedgerEntry],
        accounts: [Account],
        from start: Date,
        through end: Date
    ) -> [LedgerEntry] {
        entries
            .filter {
                $0.kind == .income
                    && !BookingClassification.isRefund($0)
                    && $0.date >= start
                    && $0.date <= end
                    && ExternalIncome.countsInHomeBudget($0, accounts: accounts)
            }
            .sorted { $0.date > $1.date }
    }

    /// Lists the income still expected from today to the period's end.
    private static func forecastLines(_ forecasts: [IncomeForecast], from today: Date, through end: Date) -> [HomeBudgetLine] {
        forecasts.filter(\.isActive).flatMap { forecast in
            occurrences(of: forecast, from: today, through: end).map { date in
                HomeBudgetLine(
                    id: "forecast-\(forecast.id.uuidString)-\(date.dayKey)",
                    title: forecast.name,
                    date: date,
                    cents: abs(forecast.amountCents)
                )
            }
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// Adds expected income to booked income. Money booked from today on replaces its forecast.
    ///
    /// - Parameters:
    ///   - booked: The period's income bookings.
    ///   - upcoming: The income still expected.
    ///   - today: The start of the current day.
    /// - Returns: The planned total and the amount of forecast already covered.
    private static func plannedIncome(
        booked: [LedgerEntry],
        upcoming: [HomeBudgetLine],
        today: Date
    ) -> (planned: Int, adjustment: Int) {
        let total = booked.reduce(0) { $0 + abs($1.amountCents) }
        let fromToday = booked.filter { $0.date >= today }.reduce(0) { $0 + abs($1.amountCents) }
        let expected = upcoming.reduce(0) { $0 + $1.cents }
        return (total + max(0, expected - fromToday), min(expected, max(0, fromToday)))
    }

    /// Lists the period's security purchases, newest first.
    private static func purchaseLines(
        _ entries: [LedgerEntry],
        accounts: [Account],
        from start: Date,
        through now: Date
    ) -> [HomeBudgetLine] {
        let portfolios = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        return entries
            .filter { entry in
                guard entry.date >= start, entry.date <= now else { return false }
                return PortfolioCashFlow.isSecurityPurchase(entry, portfolioIDs: portfolios)
            }
            .sorted { $0.date > $1.date }
            .map { line(for: $0, cents: abs($0.amountCents)) }
    }

    /// Lists the period's expenses after refunds, newest first.
    private static func expenseLines(_ entries: [LedgerEntry], from start: Date, through now: Date) -> [HomeBudgetLine] {
        entries
            .filter { $0.kind == .expense && $0.date >= start && $0.date <= now }
            .sorted { $0.date > $1.date }
            .compactMap { entry in
                let cents = RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
                return cents > 0 ? line(for: entry, cents: cents) : nil
            }
    }

    /// Lists this month's spending per variable budget.
    private static func variableLines(
        _ budgets: [VariableBudget],
        entries: [LedgerEntry],
        splits: [TransactionSplit],
        now: Date
    ) -> [HomeBudgetLine] {
        budgets.map { budget in
            HomeBudgetLine(
                id: budget.id.uuidString,
                title: budget.name,
                date: nil,
                cents: FinanceService.variableSpent(budgetID: budget.id, monthKey: now.monthKey, entries: entries, splits: splits)
            )
        }
        .filter { $0.cents != 0 }
    }

    /// Lists the current spending per active pool.
    private static func poolLines(_ pools: [BudgetPool], splits: [TransactionSplit], now: Date) -> [HomeBudgetLine] {
        pools.filter(\.isActive).map { pool in
            HomeBudgetLine(
                id: pool.id.uuidString,
                title: pool.name,
                date: nil,
                cents: FinanceService.poolSpent(
                    pool: pool,
                    periodKey: CalendarService.periodKey(for: now, pool: pool),
                    splits: splits
                )
            )
        }
        .filter { $0.cents != 0 }
    }

    /// Lists a forecast's due dates in a range.
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

    /// Finds the next salary date.
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

    /// Returns the primary income forecast.
    private static func primaryForecast(in forecasts: [IncomeForecast]) -> IncomeForecast? {
        guard let idString = IncomeAssignmentStore.primaryForecastID?.uuidString,
              let id = UUID(uuidString: idString)
        else {
            return forecasts.first(where: \.isActive)
        }
        return forecasts.first { $0.id == id } ?? forecasts.first(where: \.isActive)
    }

    /// Finds the start of the current budget period.
    private static func budgetPeriodStart(
        now: Date,
        forecasts: [IncomeForecast],
        dashboardPeriod: String
    ) -> Date {
        let calendar = Calendar.current
        guard DashboardPeriodMode(rawValue: dashboardPeriod) == .salaryPeriod,
              let idString = IncomeAssignmentStore.primaryForecastID?.uuidString,
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

    /// Finds the end of the current budget period.
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
              let idString = IncomeAssignmentStore.primaryForecastID?.uuidString,
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
