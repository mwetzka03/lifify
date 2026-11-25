import Foundation
import LififyCore

/// The core finance calculations.
@MainActor
public enum FinanceService {
    /// Calculates an account's balance.
    public static func balance(
        for account: Account,
        entries: [LedgerEntry],
        holdings: [PortfolioHolding],
        through date: Date = .distantFuture
    ) -> Int {
        if account.kind == .portfolio {
            return holdings
                .filter { $0.accountID == account.id }
                .reduce(0) { $0 + Int((Double($1.currentPriceCents) * $1.quantity).rounded()) }
        }

        let relevant = entries.filter { $0.date <= date }
        let adjustments = relevant
            .filter { $0.kind == .adjustment && $0.accountID == account.id }
            .sorted { lhs, rhs in lhs.date == rhs.date ? lhs.createdAt < rhs.createdAt : lhs.date < rhs.date }
        let anchor = adjustments.last
        var value = anchor?.amountCents ?? 0

        for entry in relevant where isAfter(entry, anchor: anchor) {
            switch entry.kind {
            case .income, .expense:
                if entry.accountID == account.id { value += entry.amountCents }
            case .transfer:
                if entry.fromAccountID == account.id { value -= abs(entry.amountCents) }
                if entry.toAccountID == account.id { value += abs(entry.amountCents) }
            case .adjustment:
                break
            }
        }
        return value
    }

    /// Sums the balances of the accounts.
    public static func totalBalance(
        accounts: [Account],
        entries: [LedgerEntry],
        holdings: [PortfolioHolding],
        liquidOnly: Bool = false
    ) -> Int {
        accounts
            .filter { $0.kind != .savingsGroup && (!liquidOnly || $0.isLiquid) }
            .reduce(0) { $0 + balance(for: $1, entries: entries, holdings: holdings) }
    }

    /// Sums what was spent from a budget in a period.
    public static func variableSpent(
        budgetID: UUID,
        from: Date,
        through: Date,
        entries: [LedgerEntry],
        splits: [TransactionSplit],
        accountID: UUID? = nil
    ) -> Int {
        let start = Calendar.current.startOfDay(for: from)
        let end = endOfDay(through)
        guard end >= start else { return 0 }
        let splitIDs = Set(
            splits
                .filter { $0.kind == .variableBudget && $0.targetID == budgetID }
                .map(\.transactionID)
        )
        let direct = entries
            .filter { entry in
                guard countsTowardVariable(entry, budgetID: budgetID), !splitIDs.contains(entry.id) else { return false }
                guard entry.date >= start, entry.date <= end else { return false }
                return entryTouches(entry, accountID: accountID)
            }
            .reduce(0) { $0 + countedSlice($1, entries: entries, amount: $1.amountCents) }
        let split = splits
            .filter { item in
                guard item.kind == .variableBudget, item.targetID == budgetID else { return false }
                guard let entry = entries.first(where: { $0.id == item.transactionID }) else { return false }
                guard entry.date >= start, entry.date <= end else { return false }
                return entryTouches(entry, accountID: accountID)
            }
            .reduce(0) { total, item in
                guard let entry = entries.first(where: { $0.id == item.transactionID }) else { return total }
                return total + countedSlice(entry, entries: entries, amount: item.amountCents)
            }
        return direct + split
    }

    /// Sums what was spent from a budget, based on stored bookings.
    public static func variableSpent(
        budgetID: UUID,
        monthKey: String,
        entries: [LedgerEntry],
        splits: [TransactionSplit]
    ) -> Int {
        let split = splits
            .filter { $0.kind == .variableBudget && $0.targetID == budgetID && $0.periodKey == monthKey }
            .reduce(0) { total, item in
                guard let entry = entries.first(where: { $0.id == item.transactionID }) else { return total + abs(item.amountCents) }
                return total + countedSlice(entry, entries: entries, amount: item.amountCents)
            }
        let splitTransactionIDs = Set(splits.filter { $0.kind == .variableBudget }.map(\.transactionID))
        let directWithoutSplit = entries
            .filter { $0.variableBudgetID == budgetID && $0.date.monthKey == monthKey && !splitTransactionIDs.contains($0.id) }
            .reduce(0) { $0 + countedSlice($1, entries: entries, amount: $1.amountCents) }
        return directWithoutSplit + split
    }

    /// Sums what was spent from a pool in a period.
    public static func poolSpent(
        pool: BudgetPool,
        periodKey: String,
        splits: [TransactionSplit]
    ) -> Int {
        splits
            .filter {
                $0.kind == .budgetPool
                    && $0.targetID == pool.id
                    && CalendarService.splitCounts(in: periodKey, splitKey: $0.periodKey, pool: pool)
            }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// Calculates what a pool carries into a period.
    public static func poolCarry(
        pool: BudgetPool,
        currentPeriodKey: String,
        splits: [TransactionSplit]
    ) -> Int {
        guard pool.isScalable else { return 0 }
        let keys = CalendarService.periodKeys(from: pool.createdAt, through: FinanceClock.now, pool: pool)
        var carry = 0
        for key in keys {
            if key == currentPeriodKey { return carry }
            carry = pool.amountCents + carry - poolSpent(pool: pool, periodKey: key, splits: splits)
        }
        return carry
    }

    /// Says whether a booking comes after the opening anchor.
    private static func isAfter(_ entry: LedgerEntry, anchor: LedgerEntry?) -> Bool {
        guard let anchor else { return entry.kind != .adjustment }
        if entry.date != anchor.date { return entry.date > anchor.date }
        return entry.createdAt > anchor.createdAt
    }

    /// Calculates the liquid cash of the accounts.
    public static func cashBalance(
        accounts: [Account],
        entries: [LedgerEntry],
        through date: Date
    ) -> Int {
        accounts
            .filter { $0.kind != .savingsGroup && $0.kind != .portfolio }
            .reduce(0) { $0 + balance(for: $1, entries: entries, holdings: [], through: date) }
    }

    /// Cash on this account at the end of today. The last adjustment is the stand.
    public static func currentBalance(
        for account: Account,
        entries: [LedgerEntry],
        holdings: [PortfolioHolding] = []
    ) -> Int {
        balance(for: account, entries: entries, holdings: holdings, through: endOfDay(FinanceClock.now))
    }

    /// Cash at the end of the previous period. Adjustments dated on the period
    /// start stay in, so a Startsaldo on that day is the opening figure. Other
    /// bookings on the first day do not.
    private static func cashBalanceBeforePeriod(
        accounts: [Account],
        entries: [LedgerEntry],
        start: Date
    ) -> Int {
        let day = Calendar.current.startOfDay(for: start)
        let kept = entries.filter { entry in
            if entry.date < day { return true }
            return entry.kind == .adjustment && Calendar.current.isDate(entry.date, inSameDayAs: day)
        }
        return cashBalance(accounts: accounts, entries: kept, through: endOfDay(day))
    }

    /// Sums the savings plan executions in a range.
    public static func savingsPlanBookedCents(
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        accountIDs: Set<UUID>?
    ) -> Int {
        let start = Calendar.current.startOfDay(for: from)
        let end = endOfDay(through)
        return entries.reduce(0) { total, entry in
            guard BookingClassification.isSavingsPlan(entry) else { return total }
            guard entry.date >= start, entry.date <= end else { return total }
            if let accountIDs {
                let touched = [entry.accountID, entry.fromAccountID, entry.toAccountID].compactMap { $0 }
                guard touched.contains(where: accountIDs.contains) else { return total }
            }
            return total + abs(entry.amountCents)
        }
    }

    /// Builds the finance periods from the primary income or calendar months.
    public static func forecastPeriods(
        primary: IncomeForecast?,
        earliest: Date,
        latest: Date
    ) -> [ForecastPeriod] {
        let calendar = Calendar.current
        let floor = calendar.startOfDay(for: earliest)
        let horizon = calendar.startOfDay(for: latest)
        guard let primary else {
            return monthPeriods(from: floor, through: horizon)
        }
        let lookback = calendar.date(byAdding: .day, value: -45, to: floor) ?? floor
        let origin = min(calendar.startOfDay(for: primary.firstPaymentDate), lookback)
        let searchEnd = calendar.date(byAdding: .year, value: 1, to: horizon) ?? horizon
        let occurrences = CalendarService.nextOccurrences(
            firstDate: origin,
            cadence: primary.cadence,
            rule: primary.dueRule,
            day: primary.dayOfMonth,
            endDate: nil,
            through: searchEnd
        )
        .map { calendar.startOfDay(for: $0) }
        var unique: [Date] = []
        for date in occurrences where unique.last != date {
            unique.append(date)
        }
        var periods: [ForecastPeriod] = []
        for index in unique.indices.dropLast() {
            let start = unique[index]
            let next = unique[index + 1]
            guard let end = calendar.date(byAdding: .day, value: -1, to: next) else { continue }
            if let period = clippedPeriod(start: start, end: end, floor: floor, horizon: horizon) {
                periods.append(period)
            }
        }
        return periods.isEmpty ? monthPeriods(from: floor, through: horizon) : periods
    }

    /// Calculates all figures of one period.
    ///
    /// - Parameters:
    ///   - period: The period to calculate.
    ///   - periods: All periods, used to project future balances.
    ///   - accounts: The accounts in scope.
    ///   - entries: The bookings in scope.
    ///   - holdings: The depot positions in scope.
    ///   - fixedCosts: The fixed costs in scope.
    ///   - variableBudgets: The variable budgets in scope.
    ///   - splits: The booking splits.
    ///   - forecasts: The income forecasts in scope.
    ///   - shopping: The shopping items in scope.
    ///   - now: The current time.
    ///   - incomePredicate: Limits which income bookings count, if set.
    ///   - includePortfolioValue: Whether balances contain the depot's market value.
    ///   - countSavingsPlansInCash: Whether savings plans reduce projected cash.
    ///   - scopedCashAccountIDs: The cash accounts a view is limited to.
    ///   - householdCashAccountIDs: All cash accounts of the household.
    /// - Returns: Booked, open, and projected figures with the period's events.
    public static func periodForecast(
        period: ForecastPeriod,
        periods: [ForecastPeriod],
        accounts: [Account],
        entries: [LedgerEntry],
        holdings: [PortfolioHolding],
        fixedCosts: [FixedCost],
        variableBudgets: [VariableBudget],
        splits: [TransactionSplit],
        forecasts: [IncomeForecast],
        shopping: [ShoppingItem],
        now: Date = FinanceClock.now,
        incomePredicate: ((LedgerEntry) -> Bool)? = nil,
        includePortfolioValue: Bool = false,
        countSavingsPlansInCash: Bool = true,
        scopedCashAccountIDs: Set<UUID>? = nil,
        householdCashAccountIDs: [UUID] = []
    ) -> PeriodForecast {
        let cashIDs = householdCashAccountIDs.isEmpty
            ? accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id)
            : householdCashAccountIDs
        let activeFixed = fixedCosts.filter(\.isActive)
        var scope = ForecastScope(
            period: period,
            periods: periods,
            accounts: accounts,
            entries: entries,
            holdings: holdings,
            activeFixed: activeFixed,
            cashFixed: countSavingsPlansInCash ? activeFixed : activeFixed.filter { !SavingsPlanFixedCosts.isSavingsCost($0) },
            budgets: variableBudgets,
            splits: splits,
            forecasts: forecasts,
            shopping: shopping,
            now: now,
            today: Calendar.current.startOfDay(for: now),
            includePortfolioValue: includePortfolioValue,
            scopedCashAccountIDs: scopedCashAccountIDs,
            cashIDs: cashIDs,
            variablePlan: VariableBudgetAccounts.planCents(
                budgets: variableBudgets,
                scopedAccountIDs: scopedCashAccountIDs,
                cashAccountIDs: cashIDs
            ),
            dividends: DividendReportBuilder.plannedIncome(
                entries: entries,
                holdings: holdings,
                accountIDs: Set(accounts.map(\.id)),
                now: now
            )
        )
        let interest = interestIncome(scope)
        scope.dividends += interest
        let income = incomeFigures(scope, predicate: incomePredicate)
        let bookedExpenses = signedSum(entries: entries, kind: .expense, from: period.start, through: period.end)
        let fixedDates = fixedOccurrences(costs: activeFixed, from: period.start, through: period.end)
        let bookedVariable = variableSpent(
            in: period,
            budgets: variableBudgets,
            entries: entries,
            splits: splits,
            through: min(now, period.end)
        )
        let remainingFixed = remainingFixedCents(fixedDates, scope: scope)
        let remainingVariable = remainingVariableCents(scope, booked: bookedVariable)
        let bias = shoppingBias(shopping: shopping, entries: entries, period: period)
        let balances = periodBalances(scope)
        let isPast = period.end < scope.today
        var result = PeriodForecast(
            netWorth: netWorth(scope, balances: balances),
            income: income.total,
            expenses: bookedExpenses,
            startBalance: balances.start,
            endBalance: balances.end,
            remainingFixed: remainingFixed,
            remainingVariable: remainingVariable,
            biasApplied: bias.applied,
            biasPlanned: bias.planned,
            bookedIncome: income.booked,
            bookedExpenses: bookedExpenses,
            bookedFixed: bookedFixedAmount(occurrences: fixedDates, entries: entries, from: period.start, through: period.end),
            bookedVariable: bookedVariable,
            openIncome: income.open,
            openExpenses: isPast ? 0 : remainingFixed + remainingVariable + bias.planned,
            events: eventLines(
                period: period,
                entries: entries,
                accounts: accounts,
                fixedCosts: activeFixed,
                forecasts: forecasts,
                shopping: shopping,
                dividends: scope.dividends
            )
        )
        result.interest = interest.filter { period.contains(Calendar.current.startOfDay(for: $0.date)) }
        return result
    }

    /// The prepared inputs of one period's calculation.
    private struct ForecastScope {
        let period: ForecastPeriod
        let periods: [ForecastPeriod]
        var accounts: [Account]
        let entries: [LedgerEntry]
        let holdings: [PortfolioHolding]
        var activeFixed: [FixedCost]
        var cashFixed: [FixedCost]
        var budgets: [VariableBudget]
        let splits: [TransactionSplit]
        var forecasts: [IncomeForecast]
        var shopping: [ShoppingItem]
        let now: Date
        let today: Date
        let includePortfolioValue: Bool
        var scopedCashAccountIDs: Set<UUID>?
        var cashIDs: [UUID]
        var variablePlan: Int
        /// Expected dividends and interest that count as income while their switches are on.
        var dividends: [DividendForecastPayment]

        /// The depot at its current prices.
        var holdingsValue: Int {
            holdings.reduce(0) { $0 + Int(($1.quantity * Double($1.currentPriceCents)).rounded()) }
        }
    }

    /// Compares planned and booked income. Skipped and already covered forecasts do not count.
    private static func incomeFigures(
        _ scope: ForecastScope,
        predicate: ((LedgerEntry) -> Bool)?
    ) -> (total: Int, booked: Int, open: Int) {
        let period = scope.period
        let planned = (incomeOccurrences(forecasts: scope.forecasts, from: period.start, through: period.end)
            + dividendOccurrences(scope.dividends, from: period.start, through: period.end))
            .filter { item in
                if ForecastSkipStore.isSkipped(.income, id: item.forecastID, on: item.date) { return false }
                return !ForecastPeriodLinkStore.covers(.income, id: item.forecastID, entries: scope.entries, period: period)
            }
            .reduce(0) { $0 + $1.amount }
        let source = predicate.map { test in scope.entries.filter { $0.kind != .income || test($0) } } ?? scope.entries
        let booked = signedSum(entries: source, kind: .income, from: period.start, through: period.end)
        return (max(planned, booked), booked, max(0, planned - booked))
    }

    /// Sums the fixed costs not yet paid, skipped, or covered.
    private static func remainingFixedCents(
        _ occurrences: [(date: Date, amount: Int, title: String, costID: UUID)],
        scope: ForecastScope
    ) -> Int {
        occurrences
            .filter { occurrence in
                if ForecastSkipStore.isSkipped(.fixed, id: occurrence.costID, on: occurrence.date) { return false }
                if ForecastPeriodLinkStore.covers(.fixed, id: occurrence.costID, entries: scope.entries, period: scope.period) {
                    return false
                }
                guard let match = matchingExpense(occurrence, entries: scope.entries) else { return true }
                return match.date > scope.now
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Returns the variable budget still open. A finished period has none.
    private static func remainingVariableCents(_ scope: ForecastScope, booked: Int) -> Int {
        guard scope.period.end >= scope.today else { return 0 }
        let suppressed = scope.budgets.reduce(0) { partial, budget in
            guard ForecastSkipStore.isSkipped(.variable, id: budget.id, on: scope.period.end) else { return partial }
            let plan = VariableBudgetAccounts.planCents(
                budget: budget,
                scopedAccountIDs: scope.scopedCashAccountIDs,
                cashAccountIDs: scope.cashIDs
            )
            let spent = variableSpent(
                budgetID: budget.id,
                from: scope.period.start,
                through: min(scope.now, scope.period.end),
                entries: scope.entries,
                splits: scope.splits
            )
            return partial + max(plan - spent, 0)
        }
        return max(scope.variablePlan - booked - suppressed, 0)
    }

    /// Calculates the opening and closing balance of the period.
    private static func periodBalances(_ scope: ForecastScope) -> (start: Int, end: Int, closingHoldings: Int) {
        let calendar = Calendar.current
        let periodStart = calendar.startOfDay(for: scope.period.start)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: periodStart) ?? periodStart
        let opening = scope.includePortfolioValue ? HoldingMaintenance.marketValue(of: scope.holdings, through: dayBefore) : 0
        let closing = scope.includePortfolioValue ? HoldingMaintenance.marketValue(of: scope.holdings, through: scope.period.end) : 0
        let startCash = periodStart <= scope.today
            ? cashBalanceBeforePeriod(accounts: scope.accounts, entries: scope.entries, start: periodStart)
            : projectedCash(on: dayBefore, scope: scope)
        return (startCash + opening, projectedCash(on: scope.period.end, scope: scope) + closing, closing)
    }

    /// Projects cash with the scope's plans.
    private static func projectedCash(on day: Date, scope: ForecastScope) -> Int {
        projectedCash(
            on: day,
            chargeVariableThroughEnd: true,
            today: scope.today,
            now: scope.now,
            periods: scope.periods,
            accounts: scope.accounts,
            entries: scope.entries,
            fixedCosts: scope.cashFixed,
            forecasts: scope.forecasts,
            shopping: scope.shopping,
            variablePlan: scope.variablePlan,
            budgets: scope.budgets,
            splits: scope.splits,
            dividends: scope.dividends
        )
    }

    /// Returns live net worth now, the closing value of a past period, or the forecast of a future one.
    private static func netWorth(_ scope: ForecastScope, balances: (start: Int, end: Int, closingHoldings: Int)) -> Int {
        if scope.period.contains(scope.today) {
            let depot = scope.includePortfolioValue
                ? HoldingMaintenance.marketValue(of: scope.holdings, through: scope.now)
                : scope.holdingsValue
            return cashBalance(accounts: scope.accounts, entries: scope.entries, through: endOfDay(scope.now)) + depot
        }
        if scope.period.end < scope.today {
            return cashBalance(accounts: scope.accounts, entries: scope.entries, through: endOfDay(scope.period.end))
                + balances.closingHoldings
        }
        return balances.end + (scope.includePortfolioValue ? 0 : scope.holdingsValue)
    }

    /// Builds calendar month periods.
    private static func monthPeriods(from floor: Date, through horizon: Date) -> [ForecastPeriod] {
        let calendar = Calendar.current
        var periods: [ForecastPeriod] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: floor)) ?? floor
        while cursor <= horizon {
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor),
                  let end = calendar.date(byAdding: .day, value: -1, to: next)
            else { break }
            if let period = clippedPeriod(start: cursor, end: end, floor: floor, horizon: horizon) {
                periods.append(period)
            }
            cursor = next
        }
        return periods
    }

    /// The first period starts on the first booking or opening balance, not on an earlier payday.
    private static func clippedPeriod(start: Date, end: Date, floor: Date, horizon: Date) -> ForecastPeriod? {
        let calendar = Calendar.current
        var start = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: end)
        if end < floor || start > horizon { return nil }
        if start < floor { start = floor }
        guard start <= end else { return nil }
        return ForecastPeriod(start: start, end: end)
    }

    /// Projects the cash balance on a future day.
    private static func projectedCash(
        on day: Date,
        chargeVariableThroughEnd: Bool,
        today: Date,
        now: Date,
        periods: [ForecastPeriod],
        accounts: [Account],
        entries: [LedgerEntry],
        fixedCosts: [FixedCost],
        forecasts: [IncomeForecast],
        shopping: [ShoppingItem],
        variablePlan: Int,
        budgets: [VariableBudget],
        splits: [TransactionSplit],
        dividends: [DividendForecastPayment] = []
    ) -> Int {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: day)
        if target < today {
            return cashBalance(accounts: accounts, entries: entries, through: endOfDay(day))
        }
        let actual = cashBalance(accounts: accounts, entries: entries, through: endOfDay(now))
        let income = incomeStillToReceive(
            forecasts: forecasts,
            entries: entries,
            from: today,
            through: target,
            now: now,
            periods: periods,
            dividends: dividends
        )
        let fixed = fixedStillToPay(
            costs: fixedCosts,
            entries: entries,
            from: today,
            through: target,
            now: now,
            periods: periods
        )
        let shoppingCost = shoppingStillToPay(
            shopping: shopping,
            entries: entries,
            through: target,
            now: now,
            periods: periods
        )
        let variable = variableStillToPay(
            through: target,
            chargeThroughEnd: chargeVariableThroughEnd,
            today: today,
            now: now,
            periods: periods,
            variablePlan: variablePlan,
            budgets: budgets,
            entries: entries,
            splits: splits
        )
        let occurrences = fixedOccurrences(costs: fixedCosts, from: today, through: target)
        var coveredExpenses = Set<UUID>()
        for occurrence in occurrences {
            if let match = matchingExpense(occurrence, entries: entries) {
                coveredExpenses.insert(match.id)
            }
        }
        let limit = endOfDay(target)
        let otherFutureExpenses = entries.reduce(0) { partial, entry in
            guard entry.kind == .expense, entry.variableBudgetID == nil, entry.date > now else { return partial }
            guard entry.date <= limit else { return partial }
            if entry.fixedCostID != nil || entry.shoppingItemID != nil { return partial }
            guard !coveredExpenses.contains(entry.id) else { return partial }
            return partial + abs(entry.amountCents)
        }
        let futureRefunds = entries
            .filter { BookingClassification.isRefund($0) && $0.date > now && $0.date <= endOfDay(target) }
            .reduce(0) { $0 + abs($1.amountCents) }
        let transfers = transferForecastNet(
            accounts: accounts,
            entries: entries,
            from: today,
            through: target,
            now: now,
            periods: periods
        )
        return actual + income - fixed - shoppingCost - variable - otherFutureExpenses + futureRefunds + transfers
    }

    /// Sums income still expected before a day.
    private static func incomeStillToReceive(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        now: Date,
        periods: [ForecastPeriod],
        dividends: [DividendForecastPayment] = []
    ) -> Int {
        let forecast = (incomeOccurrences(forecasts: forecasts, from: from, through: through)
            + dividendOccurrences(dividends, from: from, through: through))
            .filter { !forecastHidden(.income, id: $0.forecastID, on: $0.date, entries: entries, periods: periods) }
            .reduce(0) { $0 + $1.amount }
        let bookedThroughTarget = signedSum(entries: entries, kind: .income, from: from, through: through)
        let bookedInCash = entries
            .filter {
                $0.kind == .income
                    && !BookingClassification.isRefund($0)
                    && $0.date >= Calendar.current.startOfDay(for: from)
                    && $0.date <= now
            }
            .reduce(0) { $0 + abs($1.amountCents) }
        return max(0, max(forecast, bookedThroughTarget) - bookedInCash)
    }

    /// Sums fixed costs still to pay before a day.
    private static func fixedStillToPay(
        costs: [FixedCost],
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        now: Date,
        periods: [ForecastPeriod]
    ) -> Int {
        fixedOccurrences(costs: costs, from: from, through: through).reduce(0) { partial, occurrence in
            if forecastHidden(.fixed, id: occurrence.costID, on: occurrence.date, entries: entries, periods: periods) {
                return partial
            }
            if let match = matchingExpense(occurrence, entries: entries) {
                return match.date > now ? partial + abs(match.amountCents) : partial
            }
            return partial + occurrence.amount
        }
    }

    /// Sums shopping items still to pay before a day.
    private static func shoppingStillToPay(
        shopping: [ShoppingItem],
        entries: [LedgerEntry],
        through target: Date,
        now: Date,
        periods: [ForecastPeriod]
    ) -> Int {
        let limit = Calendar.current.startOfDay(for: target)
        return shopping.reduce(0) { partial, item in
            guard !item.isPurchased, let planned = item.plannedDate else { return partial }
            let day = Calendar.current.startOfDay(for: planned)
            guard day <= limit else { return partial }
            if forecastHidden(.shopping, id: item.id, on: day, entries: entries, periods: periods) { return partial }
            if let entry = entries.first(where: { $0.shoppingItemID == item.id }), entry.date <= now {
                return partial
            }
            return partial + abs(item.amountCents)
        }
    }

    /// Says whether a forecast is skipped or already covered.
    private static func forecastHidden(
        _ kind: ForecastRefKind,
        id: UUID,
        on day: Date,
        entries: [LedgerEntry],
        periods: [ForecastPeriod]
    ) -> Bool {
        if ForecastSkipStore.isSkipped(kind, id: id, on: day) { return true }
        guard let period = periods.first(where: { $0.contains(day) }) else { return false }
        return ForecastPeriodLinkStore.covers(kind, id: id, entries: entries, period: period)
    }

    /// Sums variable budget still to spend before a day.
    private static func variableStillToPay(
        through target: Date,
        chargeThroughEnd: Bool,
        today: Date,
        now: Date,
        periods: [ForecastPeriod],
        variablePlan: Int,
        budgets: [VariableBudget],
        entries: [LedgerEntry],
        splits: [TransactionSplit]
    ) -> Int {
        let day = Calendar.current.startOfDay(for: target)
        return periods.reduce(0) { partial, period in
            let include = chargeThroughEnd ? period.end <= day : period.end < day
            guard include, period.end >= today else { return partial }
            let spent = period.start <= today
                ? variableSpent(in: period, budgets: budgets, entries: entries, splits: splits, through: now)
                : 0
            let full = budgets.reduce(0) { $0 + abs($1.monthlyAmountCents) }
            let suppressedFull = budgets.reduce(0) { sum, budget in
                guard ForecastSkipStore.isSkipped(.variable, id: budget.id, on: period.end) else { return sum }
                return sum + abs(budget.monthlyAmountCents)
            }
            let suppressed = full > 0 ? Int((Double(variablePlan) * Double(suppressedFull) / Double(full)).rounded()) : 0
            return partial + max(variablePlan - spent - suppressed, 0)
        }
    }

    /// Lists income due dates in a period.
    /// Forecast interest on the depot's cash account, compounded monthly.
    ///
    /// Each month end's projected balance of that account earns a twelfth of the yearly rate,
    /// paid on the next first. Earlier payouts are part of later balances, so interest earns
    /// interest. Only payouts after today count.
    ///
    /// - Parameter scope: The period's inputs.
    /// - Returns: The payouts through the period end, or none while the switch is off.
    private static func interestIncome(_ scope: ForecastScope) -> [DividendForecastPayment] {
        guard CashInterest.isEnabled,
              let accountID = CashInterest.accountID(in: scope.accounts),
              let account = scope.accounts.first(where: { $0.id == accountID }) else { return [] }
        var own = accountScope(scope, account: account)
        var paid: [DividendForecastPayment] = []
        for month in CashInterest.payouts(after: scope.now, through: scope.period.end) {
            let balance = projectedCash(on: month.monthEnd, scope: own)
            let cents = CashInterest.monthlyCents(on: balance, percent: CashInterest.annualPercent)
            guard cents > 0 else { continue }
            let payout = DividendForecastPayment(
                key: account.id.uuidString,
                name: L("Zinsen (Prognose)", "Interest (forecast)"),
                date: month.payout,
                cents: cents,
                accountID: account.id
            )
            paid.append(payout)
            own.dividends.append(payout)
        }
        return paid
    }

    /// The same inputs, narrowed to one cash account.
    private static func accountScope(_ scope: ForecastScope, account: Account) -> ForecastScope {
        var own = scope
        own.accounts = [account]
        own.activeFixed = scope.activeFixed.filter { $0.accountID == account.id }
        own.cashFixed = scope.cashFixed.filter { $0.accountID == account.id }
        own.budgets = scope.budgets.filter { $0.accountID == account.id }
        own.forecasts = scope.forecasts.filter { $0.accountID == account.id }
        own.shopping = []
        own.scopedCashAccountIDs = [account.id]
        own.cashIDs = [account.id]
        own.variablePlan = VariableBudgetAccounts.planCents(budgets: own.budgets, scopedAccountIDs: [account.id], cashAccountIDs: [account.id])
        own.dividends = scope.dividends.filter { $0.accountID == account.id }
        return own
    }

    /// Expected dividends in a range, shaped like income forecast dates.
    ///
    /// A projection always belongs to a held position, so its key is that position's identifier.
    ///
    /// - Parameters:
    ///   - dividends: The expected payments.
    ///   - from: The first day.
    ///   - through: The last day.
    /// - Returns: The payments inside the range.
    private static func dividendOccurrences(
        _ dividends: [DividendForecastPayment],
        from: Date,
        through: Date
    ) -> [(date: Date, amount: Int, title: String, forecastID: UUID)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        return dividends
            .filter { calendar.startOfDay(for: $0.date) >= start && calendar.startOfDay(for: $0.date) <= end }
            .compactMap { item in
                UUID(uuidString: item.key).map { (item.date, item.cents, item.name, $0) }
            }
    }

    private static func incomeOccurrences(
        forecasts: [IncomeForecast],
        from: Date,
        through: Date
    ) -> [(date: Date, amount: Int, title: String, forecastID: UUID)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        var result: [(date: Date, amount: Int, title: String, forecastID: UUID)] = []
        for forecast in forecasts where forecast.isActive {
            let first = calendar.startOfDay(for: forecast.firstPaymentDate)
            let dates = CalendarService.nextOccurrences(
                firstDate: forecast.firstPaymentDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endPaymentDate,
                through: endOfDay(end)
            )
            for date in dates {
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end, day >= first else { continue }
                result.append((
                    date: date,
                    amount: abs(forecast.amountCents),
                    title: forecast.name,
                    forecastID: forecast.id
                ))
            }
        }
        return result
    }

    /// Lists charges of fixed costs with their paid state.
    public static func scheduledCharges(
        costs: [FixedCost],
        entries: [LedgerEntry],
        from: Date,
        through: Date
    ) -> [ScheduledCharge] {
        let calendar = Calendar.current
        return fixedOccurrences(costs: costs, from: from, through: through).map { item in
            let day = calendar.startOfDay(for: item.date)
            return ScheduledCharge(
                id: "\(item.costID.uuidString)-\(day.dayKey)",
                date: day,
                amount: item.amount,
                title: item.title,
                costID: item.costID,
                isPaid: matchingExpense(item, entries: entries) != nil
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Bookings tied to a fixed cost: stored link, fixed-cost id, or the same-day automatic match.
    public static func assignedBookings(for cost: FixedCost, entries: [LedgerEntry]) -> [LedgerEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: FinanceClock.now)
        var matched: [UUID: LedgerEntry] = [:]
        for entry in entries {
            if ForecastMatchRejectionStore.isRejected(costID: cost.id, entryID: entry.id) { continue }
            if entry.fixedCostID == cost.id {
                matched[entry.id] = entry
                continue
            }
            if let link = ForecastPeriodLinkStore.link(for: entry.id), link.kind == .fixed, link.id == cost.id {
                matched[entry.id] = entry
            }
        }
        let start = calendar.startOfDay(for: cost.firstChargeDate)
        if start <= today {
            for charge in scheduledCharges(costs: [cost], entries: entries, from: start, through: today) {
                let occurrence = (date: charge.date, amount: charge.amount, title: charge.title, costID: charge.costID)
                if let entry = matchingExpense(occurrence, entries: entries) {
                    matched[entry.id] = entry
                }
            }
        }
        return matched.values.sorted { $0.date > $1.date }
    }

    /// The next scheduled dates, including ones a booking already covers.
    public static func upcomingCharges(for cost: FixedCost, entries: [LedgerEntry], limit: Int = 3) -> [ScheduledCharge] {
        guard cost.isActive, limit > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: FinanceClock.now)
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: today) else { return [] }
        return Array(
            scheduledCharges(costs: [cost], entries: entries, from: today, through: horizon)
                .filter { !ForecastSkipStore.isSkipped(.fixed, id: cost.id, on: $0.date) }
                .prefix(limit)
        )
    }

    /// Returns the next open charge of a cost.
    public static func nextChargeDate(for cost: FixedCost, entries: [LedgerEntry]) -> Date? {
        guard cost.isActive else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: FinanceClock.now)
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: today) else { return nil }
        return scheduledCharges(costs: [cost], entries: entries, from: today, through: horizon)
            .first { !$0.isPaid }?
            .date
    }

    /// Counts the open charges of a cost.
    public static func openChargeCount(
        for cost: FixedCost,
        entries: [LedgerEntry],
        from: Date,
        through: Date
    ) -> Int {
        guard cost.isActive else { return 0 }
        return scheduledCharges(costs: [cost], entries: entries, from: from, through: through)
            .filter { !$0.isPaid }
            .count
    }

    /// Lists fixed cost due dates in a period.
    private static func fixedOccurrences(
        costs: [FixedCost],
        from: Date,
        through: Date
    ) -> [(date: Date, amount: Int, title: String, costID: UUID)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        var result: [(date: Date, amount: Int, title: String, costID: UUID)] = []
        for cost in costs {
            let dates = occurrenceDates(for: cost, from: start, through: end)
            for date in dates {
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end else { continue }
                result.append((
                    date: day,
                    amount: abs(cost.amountCents),
                    title: cost.name,
                    costID: cost.id
                ))
            }
        }
        return result
    }

    /// Lists the due dates of one cost.
    private static func occurrenceDates(for cost: FixedCost, from: Date, through: Date) -> [Date] {
        let calendar = Calendar.current
        if SavingsPlanFixedCosts.isSavingsCost(cost) {
            let lower = calendar.startOfDay(for: cost.firstChargeDate)
            let start = max(calendar.startOfDay(for: from), lower)
            let month = cost.cadence == .yearly ? calendar.component(.month, from: cost.firstChargeDate) : nil
            return CalendarService.savingsPlanDates(
                cadence: cost.cadence,
                from: start,
                through: through,
                endDate: cost.endChargeDate,
                yearlyMonth: month
            )
        }
        return CalendarService.nextOccurrences(
            firstDate: cost.firstChargeDate,
            cadence: cost.cadence,
            rule: cost.dueRule,
            day: cost.dayOfMonth,
            endDate: cost.endChargeDate,
            through: endOfDay(through)
        )
    }

    /// Finds the booking that pays a charge.
    private static func matchingExpense(
        _ occurrence: (date: Date, amount: Int, title: String, costID: UUID),
        entries: [LedgerEntry]
    ) -> LedgerEntry? {
        ExpenseDayIndex.candidates(on: occurrence.date, in: entries).first { entry in
            if ForecastMatchRejectionStore.isRejected(costID: occurrence.costID, entryID: entry.id) { return false }
            if entry.fixedCostID == occurrence.costID { return true }
            let sameAmount = abs(entry.amountCents) == occurrence.amount
            if entry.kind == .transfer {
                guard sameAmount, SavingsPlanFixedCosts.isManagedName(occurrence.title) else { return false }
                let planName = SavingsPlanFixedCosts.planName(inFixedCostName: occurrence.title)
                return !planName.isEmpty && entry.title.localizedCaseInsensitiveContains(planName)
            }
            let title = occurrence.title
            let sameTitle = !title.isEmpty && (
                entry.title.localizedCaseInsensitiveContains(title) ||
                title.localizedCaseInsensitiveContains(entry.title)
            )
            return sameAmount && sameTitle
        }
    }

    /// Sums bookings of a kind in a range.
    private static func signedSum(entries: [LedgerEntry], kind: LedgerKind, from: Date, through: Date) -> Int {
        let start = Calendar.current.startOfDay(for: from)
        let end = endOfDay(through)
        return entries
            .filter { $0.kind == kind && $0.date >= start && $0.date <= end }
            .reduce(0) { total, entry in
                if kind == .income, BookingClassification.isRefund(entry) { return total }
                if kind == .expense {
                    return total + RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
                }
                return total + abs(entry.amountCents)
            }
    }

    /// A partial refund still counts its share of a variable assignment.
    private static func countedSlice(_ entry: LedgerEntry, entries: [LedgerEntry], amount: Int) -> Int {
        let full = abs(entry.amountCents)
        guard full > 0 else { return 0 }
        let counted = RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
        if counted >= full { return abs(amount) }
        return Int((Double(abs(amount)) * Double(counted) / Double(full)).rounded())
    }

    /// Unreplaced transfer forecasts move cash between today and the target day.
    /// A real transfer assigned in the same period replaces those occurrences and is applied once if it is still in the future.
    private static func transferForecastNet(
        accounts: [Account],
        entries: [LedgerEntry],
        from today: Date,
        through target: Date,
        now: Date,
        periods: [ForecastPeriod]
    ) -> Int {
        let scope = Set(accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id))
        guard !scope.isEmpty else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let limit = calendar.startOfDay(for: target)
        guard limit >= start else { return 0 }
        var net = 0
        for forecast in TransferForecastStore.all() where forecast.active {
            let dates = CalendarService.nextOccurrences(
                firstDate: forecast.firstDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endDate,
                through: endOfDay(target)
            )
            .map { calendar.startOfDay(for: $0) }
            .filter { day in
                day >= start && day <= limit && !ForecastSkipStore.isSkipped(.transfer, id: forecast.id, on: day)
            }
            let amount = abs(forecast.amountCents)
            for day in dates where !transferForecastIsReplaced(forecast.id, on: day, periods: periods, entries: entries) {
                net += scopedTransferCents(amount: amount, from: forecast.fromAccountID, to: forecast.toAccountID, scope: scope)
            }
        }
        for entry in entries {
            guard entry.kind == .transfer, entry.date > now, entry.date <= endOfDay(target) else { continue }
            guard TransferForecastAssignmentStore.forecastID(for: entry.id) != nil else { continue }
            guard !isPortfolioMovement(entry) else { continue }
            net += scopedTransferCents(
                amount: abs(entry.amountCents),
                from: entry.fromAccountID,
                to: entry.toAccountID,
                scope: scope
            )
        }
        return net
    }

    /// Says whether a real booking replaced a planned transfer.
    private static func transferForecastIsReplaced(
        _ forecastID: UUID,
        on day: Date,
        periods: [ForecastPeriod],
        entries: [LedgerEntry]
    ) -> Bool {
        let calendar = Calendar.current
        let window: ForecastPeriod
        if let period = periods.first(where: { $0.contains(day) }) {
            window = period
        } else {
            let parts = calendar.dateComponents([.year, .month], from: day)
            let start = calendar.date(from: parts) ?? day
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? day
            window = ForecastPeriod(start: start, end: end)
        }
        if ForecastPeriodLinkStore.covers(.transfer, id: forecastID, entries: entries, period: window) { return true }
        return entries.contains { entry in
            guard TransferForecastAssignmentStore.forecastID(for: entry.id) == forecastID else { return false }
            return window.contains(entry.date)
        }
    }

    /// Returns a transfer's net effect on the accounts in scope.
    private static func scopedTransferCents(amount: Int, from: UUID?, to: UUID?, scope: Set<UUID>) -> Int {
        var net = 0
        if let from, scope.contains(from) { net -= amount }
        if let to, scope.contains(to) { net += amount }
        return net
    }

    /// Says whether the booking moves money into or out of a depot.
    private static func isPortfolioMovement(_ entry: LedgerEntry) -> Bool {
        if BookingClassification.isSavingsPlan(entry) { return true }
        let prefixes = [
            "Kauf:", "Purchase:", "Buy:",
            "Verkauf:", "Sale:", "Sell:",
            "Sparplan:", "Savings plan:"
        ]
        return prefixes.contains { entry.title.hasPrefix($0) }
    }

    /// Sums the booked amounts of fixed cost occurrences.
    private static func bookedFixedAmount(
        occurrences: [(date: Date, amount: Int, title: String, costID: UUID)],
        entries: [LedgerEntry],
        from: Date,
        through: Date
    ) -> Int {
        let start = Calendar.current.startOfDay(for: from)
        let end = endOfDay(through)
        var used = Set<UUID>()
        var total = 0
        for occurrence in occurrences {
            guard let match = matchingExpense(occurrence, entries: entries),
                  match.date >= start, match.date <= end, used.insert(match.id).inserted else { continue }
            total += abs(match.amountCents)
        }
        for entry in entries where entry.kind == .expense && entry.fixedCostID != nil && entry.date >= start && entry.date <= end {
            guard used.insert(entry.id).inserted else { continue }
            total += abs(entry.amountCents)
        }
        for entry in entries where BookingClassification.isSavingsPlan(entry) && entry.date >= start && entry.date <= end {
            guard used.insert(entry.id).inserted else { continue }
            total += abs(entry.amountCents)
        }
        return total
    }

    /// Builds the forecast lines of a period.
    private static func eventLines(
        period: ForecastPeriod,
        entries: [LedgerEntry],
        accounts: [Account],
        fixedCosts: [FixedCost],
        forecasts: [IncomeForecast],
        shopping: [ShoppingItem],
        dividends: [DividendForecastPayment] = []
    ) -> [ForecastLine] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: period.start)
        let end = endOfDay(period.end)
        let periodEntries = entries.filter {
            guard $0.date >= start, $0.date <= end else { return false }
            if $0.kind == .expense { return true }
            if $0.kind == .income { return !BookingClassification.isRefund($0) }
            return false
        }
        var lines: [ForecastLine] = []
        for entry in periodEntries {
            let amount: Int
            if entry.kind == .expense {
                let counted = RefundLinkStore.countedExpenseCents(of: entry, entries: entries)
                guard counted > 0 else { continue }
                amount = -counted
            } else {
                amount = abs(entry.amountCents)
            }
            lines.append(ForecastLine(id: entry.id.uuidString, date: entry.date, title: entry.title, amountCents: amount))
        }
        let bookedIncomeDays = Set(periodEntries.filter { $0.kind == .income }.map { calendar.startOfDay(for: $0.date) })
        for item in incomeOccurrences(forecasts: forecasts, from: period.start, through: period.end)
            + dividendOccurrences(dividends, from: period.start, through: period.end) {
            let day = calendar.startOfDay(for: item.date)
            if bookedIncomeDays.contains(day) { continue }
            lines.append(ForecastLine(
                id: "income-\(item.forecastID.uuidString)-\(day.dayKey)",
                date: item.date,
                title: item.title,
                amountCents: item.amount
            ))
        }
        for item in fixedOccurrences(costs: fixedCosts, from: period.start, through: period.end)
        where matchingExpense(item, entries: entries) == nil {
            let day = calendar.startOfDay(for: item.date)
            lines.append(ForecastLine(
                id: "fixed-\(item.costID.uuidString)-\(day.dayKey)",
                date: item.date,
                title: item.title,
                amountCents: -item.amount
            ))
        }
        for item in shopping {
            guard let planned = item.plannedDate else { continue }
            let day = calendar.startOfDay(for: planned)
            guard day >= start, day <= calendar.startOfDay(for: period.end) else { continue }
            if item.isPurchased || !shoppingBookings(for: item.id, entries: entries, period: period).isEmpty { continue }
            lines.append(ForecastLine(
                id: "bias-\(item.id.uuidString)",
                date: planned,
                title: item.name,
                amountCents: -abs(item.amountCents)
            ))
        }
        let portfolioIDs = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        for entry in entries where entry.kind == .transfer && entry.date >= start && entry.date <= end {
            let fromPortfolio = entry.fromAccountID.map { portfolioIDs.contains($0) } ?? false
            let toPortfolio = entry.toAccountID.map { portfolioIDs.contains($0) } ?? false
            guard fromPortfolio != toPortfolio else { continue }
            lines.append(ForecastLine(
                id: entry.id.uuidString,
                date: entry.date,
                title: entry.title,
                amountCents: toPortfolio ? -abs(entry.amountCents) : abs(entry.amountCents)
            ))
        }
        return lines.sorted {
            $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date
        }
    }

    /// Sums spending of budgets in a period.
    private static func variableSpent(
        in period: ForecastPeriod,
        budgets: [VariableBudget],
        entries: [LedgerEntry],
        splits: [TransactionSplit],
        through limit: Date
    ) -> Int {
        let start = Calendar.current.startOfDay(for: period.start)
        let end = min(endOfDay(period.end), endOfDay(limit))
        guard end >= start else { return 0 }
        let ids = Set(budgets.map(\.id))
        let splitIDs = Set(splits.filter { $0.kind == .variableBudget && ids.contains($0.targetID) }.map(\.transactionID))
        let direct = entries
            .filter { entry in
                guard !splitIDs.contains(entry.id), entry.date >= start, entry.date <= end else { return false }
                return ids.contains { countsTowardVariable(entry, budgetID: $0) }
            }
            .reduce(0) { $0 + abs($1.amountCents) }
        let split = splits
            .filter { split in
                guard split.kind == .variableBudget, ids.contains(split.targetID) else { return false }
                guard let entry = entries.first(where: { $0.id == split.transactionID }) else { return false }
                return entry.date >= start && entry.date <= end
            }
            .reduce(0) { $0 + abs($1.amountCents) }
        return direct + split
    }

    /// Applied uses the assigned booking amount. Planned stays the unchecked item amount.
    public static func shoppingBias(
        shopping: [ShoppingItem],
        entries: [LedgerEntry],
        period: ForecastPeriod
    ) -> (applied: Int, planned: Int) {
        let start = Calendar.current.startOfDay(for: period.start)
        let end = Calendar.current.startOfDay(for: period.end)
        var applied = 0
        var planned = 0
        for item in shopping {
            guard let plannedDate = item.plannedDate else { continue }
            let day = Calendar.current.startOfDay(for: plannedDate)
            guard day >= start, day <= end else { continue }
            if ForecastSkipStore.isSkipped(.shopping, id: item.id, on: day) { continue }
            let bookings = shoppingBookings(for: item.id, entries: entries, period: period)
            if item.isPurchased || !bookings.isEmpty {
                applied += bookings.isEmpty
                    ? abs(item.amountCents)
                    : bookings.reduce(0) { $0 + abs($1.amountCents) }
            } else {
                planned += abs(item.amountCents)
            }
        }
        return (applied, planned)
    }

    /// Lists the bookings of a shopping item.
    public static func shoppingBookings(for itemID: UUID, entries: [LedgerEntry], period: ForecastPeriod? = nil) -> [LedgerEntry] {
        entries.filter { entry in
            if let period, !period.contains(entry.date) { return false }
            if entry.shoppingItemID == itemID { return true }
            guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == .shopping && link.id == itemID
        }
        .sorted { $0.date > $1.date }
    }

    /// Says whether a booking counts toward a budget.
    private static func countsTowardVariable(_ entry: LedgerEntry, budgetID: UUID) -> Bool {
        if entry.variableBudgetID == budgetID { return true }
        guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
        return link.kind == .variable && link.id == budgetID
    }

    /// Says whether a booking touches the account.
    private static func entryTouches(_ entry: LedgerEntry, accountID: UUID?) -> Bool {
        guard let accountID else { return true }
        return entry.accountID == accountID || entry.fromAccountID == accountID || entry.toAccountID == accountID
    }

    /// Returns the start of the next day.
    private static func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))?.addingTimeInterval(-1) ?? date
    }
}

/// Expenses and transfers by day, in their original order. One forecast asks this thousands of times.
/// It holds the array it indexed, and unsaved edits skip the index.
@MainActor
public enum ExpenseDayIndex {
    private static var indexed: [LedgerEntry] = []
    private static var generation = -1
    private static var byDay: [Date: [LedgerEntry]] = [:]

    /// Returns the bookings of a day from an index.
    public static func candidates(on date: Date, in entries: [LedgerEntry]) -> [LedgerEntry] {
        let calendar = Calendar.current
        if entries.first?.modelContext?.hasChanges == true {
            return entries.filter {
                ($0.kind == .expense || $0.kind == .transfer) && calendar.isDate($0.date, inSameDayAs: date)
            }
        }
        let current = ModelChangeCounter.value
        if generation != current || !sameArray(indexed, entries) {
            indexed = entries
            generation = current
            byDay = [:]
            for entry in entries where entry.kind == .expense || entry.kind == .transfer {
                byDay[calendar.startOfDay(for: entry.date), default: []].append(entry)
            }
        }
        return byDay[calendar.startOfDay(for: date)] ?? []
    }

    /// Compares two booking lists by identity.
    private static func sameArray(_ lhs: [LedgerEntry], _ rhs: [LedgerEntry]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
        }
    }
}

/// One finance period.
public struct ForecastPeriod: Equatable, Identifiable {
    public var start: Date
    public var end: Date
    public var id: String { "\(start.dayKey)|\(end.dayKey)" }

    /// Says whether the date lies in the period.
    public func contains(_ date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return day >= Calendar.current.startOfDay(for: start) && day <= Calendar.current.startOfDay(for: end)
    }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// All calculated figures of one period.
public struct PeriodForecast {
    public var netWorth: Int
    public var income: Int
    public var expenses: Int
    public var startBalance: Int
    public var endBalance: Int
    public var remainingFixed: Int
    public var remainingVariable: Int
    public var biasApplied: Int
    public var biasPlanned: Int
    public var bookedIncome: Int
    public var bookedExpenses: Int
    public var bookedFixed: Int
    public var bookedVariable: Int
    public var openIncome: Int
    public var openExpenses: Int
    public var events: [ForecastLine]
    /// The forecast interest payouts inside the period, empty while the switch is off.
    public var interest: [DividendForecastPayment] = []
    public var realDifference: Int { bookedIncome - bookedExpenses }
    public var balanceChange: Int { endBalance - startBalance }

    public init(netWorth: Int, income: Int, expenses: Int, startBalance: Int, endBalance: Int, remainingFixed: Int, remainingVariable: Int, biasApplied: Int, biasPlanned: Int, bookedIncome: Int, bookedExpenses: Int, bookedFixed: Int, bookedVariable: Int, openIncome: Int, openExpenses: Int, events: [ForecastLine]) {
        self.netWorth = netWorth
        self.income = income
        self.expenses = expenses
        self.startBalance = startBalance
        self.endBalance = endBalance
        self.remainingFixed = remainingFixed
        self.remainingVariable = remainingVariable
        self.biasApplied = biasApplied
        self.biasPlanned = biasPlanned
        self.bookedIncome = bookedIncome
        self.bookedExpenses = bookedExpenses
        self.bookedFixed = bookedFixed
        self.bookedVariable = bookedVariable
        self.openIncome = openIncome
        self.openExpenses = openExpenses
        self.events = events
    }
}

/// One planned or booked line of a period.
public struct ForecastLine: Identifiable {
    public var id: String
    public var date: Date
    public var title: String
    public var amountCents: Int

    public init(id: String, date: Date, title: String, amountCents: Int) {
        self.id = id
        self.date = date
        self.title = title
        self.amountCents = amountCents
    }
}

/// One due charge of a fixed cost.
public struct ScheduledCharge: Identifiable {
    public var id: String
    public var date: Date
    public var amount: Int
    public var title: String
    public var costID: UUID
    public var isPaid: Bool

    public init(id: String, date: Date, amount: Int, title: String, costID: UUID, isPaid: Bool) {
        self.id = id
        self.date = date
        self.amount = amount
        self.title = title
        self.costID = costID
        self.isPaid = isPaid
    }
}

/// One entry of a forecast list.
public struct ForecastListItem: Identifiable {
    /// The source of a forecast entry.
    public enum Kind {
        case income(IncomeForecast)
        case expense(UUID)
        case transfer(TransferForecastRecord)
        case variable(UUID)
        case shopping(UUID)
    }

    public var id: String
    public var title: String
    public var date: Date
    public var signedCents: Int
    public var kind: Kind
    /// A booking already covers this date, manually or automatically. The row stays visible.
    public var settled: Bool = false

    public var fixedCostID: UUID? {
        if case .expense(let id) = kind { return id }
        return nil
    }

    public var sourceID: UUID {
        switch kind {
        case .income(let forecast): forecast.id
        case .expense(let id), .variable(let id), .shopping(let id): id
        case .transfer(let forecast): forecast.id
        }
    }

    public var refKind: ForecastRefKind {
        switch kind {
        case .income: .income
        case .expense: .fixed
        case .transfer: .transfer
        case .variable: .variable
        case .shopping: .shopping
        }
    }

    public init(id: String, title: String, date: Date, signedCents: Int, kind: Kind, settled: Bool = false) {
        self.id = id
        self.title = title
        self.date = date
        self.signedCents = signedCents
        self.kind = kind
        self.settled = settled
    }
}

/// Open income, expense, and transfer forecasts for the selected account and period.
@MainActor
public enum ForecastSchedule {
    /// Lists income forecasts for the income view.
    public static func incomeView(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        (
            incomeItems(forecasts: forecasts, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + transferItems(entries: entries, period: period, account: account, showsDepot: showsDepot, direction: .incoming)
        )
        .sorted { $0.date < $1.date }
    }

    /// Lists expense forecasts for the expense view.
    public static func expenseView(
        costs: [FixedCost],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool,
        budgets: [VariableBudget],
        splits: [TransactionSplit],
        shopping: [ShoppingItem],
        cashAccountIDs: [UUID]
    ) -> [ForecastListItem] {
        (
            expenseItems(costs: costs, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + variableItems(
                    budgets: budgets,
                    entries: entries,
                    splits: splits,
                    period: period,
                    account: account,
                    showsDepot: showsDepot,
                    cashAccountIDs: cashAccountIDs
                )
                + shoppingItems(shopping: shopping, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + transferItems(entries: entries, period: period, account: account, showsDepot: showsDepot, direction: .outgoing)
        )
        .sorted { $0.date < $1.date }
    }

    /// Lists all forecasts for the finance view.
    public static func financeView(
        forecasts: [IncomeForecast],
        costs: [FixedCost],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool,
        budgets: [VariableBudget],
        splits: [TransactionSplit],
        shopping: [ShoppingItem],
        cashAccountIDs: [UUID]
    ) -> [ForecastListItem] {
        (
            incomeItems(forecasts: forecasts, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + expenseItems(costs: costs, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + variableItems(
                    budgets: budgets,
                    entries: entries,
                    splits: splits,
                    period: period,
                    account: account,
                    showsDepot: showsDepot,
                    cashAccountIDs: cashAccountIDs
                )
                + shoppingItems(shopping: shopping, entries: entries, period: period, account: account, showsDepot: showsDepot)
                + transferItems(entries: entries, period: period, account: account, showsDepot: showsDepot, direction: .both)
        )
        .sorted { $0.date < $1.date }
    }

    /// Whether a transfer comes in or goes out.
    private enum TransferDirection {
        case incoming
        case outgoing
        case both
    }

    /// Builds the income entries.
    private static func incomeItems(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: FinanceClock.now)
        guard period.end >= today else { return [] }
        let chosen = forecasts.filter { forecast in
            guard forecast.isActive else { return false }
            guard let account else { return true }
            return forecast.accountID == account.id
        }
        var items: [ForecastListItem] = []
        for forecast in chosen {
            let settled = incomeIsBooked(forecast, entries: entries, period: period)
                || ForecastPeriodLinkStore.covers(.income, id: forecast.id, entries: entries, period: period)
            let dates = CalendarService.nextOccurrences(
                firstDate: forecast.firstPaymentDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endPaymentDate,
                through: period.end
            )
            for date in dates {
                let day = calendar.startOfDay(for: date)
                guard period.contains(day) else { continue }
                if ForecastSkipStore.isSkipped(.income, id: forecast.id, on: day) { continue }
                items.append(ForecastListItem(
                    id: "income-\(forecast.id.uuidString)-\(day.dayKey)",
                    title: forecast.name,
                    date: day,
                    signedCents: abs(forecast.amountCents),
                    kind: .income(forecast),
                    settled: settled
                ))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    /// Builds the fixed cost entries.
    private static func expenseItems(
        costs: [FixedCost],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        let today = Calendar.current.startOfDay(for: FinanceClock.now)
        guard period.end >= today else { return [] }
        let chosen = FixedCostScope.applicable(
            costs: costs.filter(\.isActive),
            account: account,
            showsDepot: showsDepot,
            includeHousehold: account == nil || account?.isMain == true
        )
        return FinanceService.scheduledCharges(
            costs: chosen,
            entries: entries,
            from: period.start,
            through: period.end
        )
        .filter { charge in
            !ForecastSkipStore.isSkipped(.fixed, id: charge.costID, on: charge.date)
        }
        .map { charge in
            let linked = ForecastPeriodLinkStore.covers(.fixed, id: charge.costID, entries: entries, period: period)
            return ForecastListItem(
                id: charge.id,
                title: charge.title,
                date: charge.date,
                signedCents: -charge.amount,
                kind: .expense(charge.costID),
                settled: charge.isPaid || linked
            )
        }
    }

    /// Builds the variable budget entries.
    private static func variableItems(
        budgets: [VariableBudget],
        entries: [LedgerEntry],
        splits: [TransactionSplit],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool,
        cashAccountIDs: [UUID]
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        let today = Calendar.current.startOfDay(for: FinanceClock.now)
        guard period.end >= today else { return [] }
        let scope = account.map { Set([$0.id]) }
        let spentThrough = min(FinanceClock.now, period.end)
        return budgets.compactMap { budget in
            let plan = VariableBudgetAccounts.planCents(
                budget: budget,
                scopedAccountIDs: scope,
                cashAccountIDs: cashAccountIDs
            )
            guard plan > 0 else { return nil }
            let spent = FinanceService.variableSpent(
                budgetID: budget.id,
                from: period.start,
                through: spentThrough,
                entries: entries,
                splits: splits,
                accountID: account?.id
            )
            let open = max(plan - spent, 0)
            if ForecastSkipStore.isSkipped(.variable, id: budget.id, on: period.end) { return nil }
            let settled = open == 0
            guard settled || open > 0 else { return nil }
            return ForecastListItem(
                id: "variable-\(budget.id.uuidString)-\(period.id)",
                title: budget.name,
                date: period.end,
                signedCents: -(open > 0 ? open : plan),
                kind: .variable(budget.id),
                settled: settled
            )
        }
    }

    /// Builds the shopping entries.
    private static func shoppingItems(
        shopping: [ShoppingItem],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        guard account == nil || account?.isMain == true else { return [] }
        let today = Calendar.current.startOfDay(for: FinanceClock.now)
        guard period.end >= today else { return [] }
        let calendar = Calendar.current
        return shopping.compactMap { item in
            guard let planned = item.plannedDate else { return nil }
            let day = calendar.startOfDay(for: planned)
            guard period.contains(day) else { return nil }
            if ForecastSkipStore.isSkipped(.shopping, id: item.id, on: day) { return nil }
            let bookings = FinanceService.shoppingBookings(for: item.id, entries: entries, period: period)
            let amount = bookings.isEmpty
                ? abs(item.amountCents)
                : bookings.reduce(0) { $0 + abs($1.amountCents) }
            return ForecastListItem(
                id: "shopping-\(item.id.uuidString)",
                title: item.name,
                date: day,
                signedCents: -amount,
                kind: .shopping(item.id),
                settled: item.isPurchased || !bookings.isEmpty
            )
        }
    }

    /// Builds the planned transfer entries.
    private static func transferItems(
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool,
        direction: TransferDirection
    ) -> [ForecastListItem] {
        guard !showsDepot, let account else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: FinanceClock.now)
        guard period.end >= today else { return [] }
        var items: [ForecastListItem] = []
        for forecast in TransferForecastStore.all() where forecast.active {
            let settled = transferIsBooked(forecast.id, entries: entries, period: period)
            let amount = abs(forecast.amountCents)
            let signed: Int
            switch direction {
            case .incoming:
                guard forecast.toAccountID == account.id else { continue }
                signed = amount
            case .outgoing:
                guard forecast.fromAccountID == account.id else { continue }
                signed = -amount
            case .both:
                if forecast.fromAccountID == account.id {
                    signed = -amount
                } else if forecast.toAccountID == account.id {
                    signed = amount
                } else {
                    continue
                }
            }
            let dates = CalendarService.nextOccurrences(
                firstDate: forecast.firstDate,
                cadence: forecast.cadence,
                rule: forecast.dueRule,
                day: forecast.dayOfMonth,
                endDate: forecast.endDate,
                through: period.end
            )
            for date in dates {
                let day = calendar.startOfDay(for: date)
                guard period.contains(day) else { continue }
                if ForecastSkipStore.isSkipped(.transfer, id: forecast.id, on: day) { continue }
                items.append(ForecastListItem(
                    id: "transfer-\(forecast.id.uuidString)-\(day.dayKey)",
                    title: forecast.name,
                    date: day,
                    signedCents: signed,
                    kind: .transfer(forecast),
                    settled: settled
                ))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    /// Says whether the income is already booked.
    private static func incomeIsBooked(_ forecast: IncomeForecast, entries: [LedgerEntry], period: ForecastPeriod) -> Bool {
        let ibans = IncomeAssignmentStore.ibans(for: forecast.id)
        return entries.contains { entry in
            guard entry.kind == .income, period.contains(entry.date) else { return false }
            if IncomeAssignmentStore.forecastID(forEntryID: entry.id) == forecast.id { return true }
            guard !ibans.isEmpty else { return false }
            let notes = entry.notes.replacingOccurrences(of: " ", with: "").uppercased()
            return ibans.contains { notes.contains($0) }
        }
    }

    /// Says whether the planned transfer is booked.
    private static func transferIsBooked(_ forecastID: UUID, entries: [LedgerEntry], period: ForecastPeriod) -> Bool {
        if ForecastPeriodLinkStore.covers(.transfer, id: forecastID, entries: entries, period: period) { return true }
        return entries.contains { entry in
            period.contains(entry.date) && TransferForecastAssignmentStore.forecastID(for: entry.id) == forecastID
        }
    }
}

/// Decides which fixed costs apply to a view.
@MainActor
public enum FixedCostScope {
    /// Filters fixed costs by account and view.
    public static func applicable(
        costs: [FixedCost],
        account: Account?,
        showsDepot: Bool,
        includeHousehold: Bool
    ) -> [FixedCost] {
        if showsDepot { return [] }
        guard let account else { return costs }
        let savings = costs.filter { SavingsPlanFixedCosts.isSavingsCost($0) && $0.accountID == account.id }
        guard includeHousehold else { return savings }
        let household = costs.filter { !SavingsPlanFixedCosts.isSavingsCost($0) }
        var seen = Set(household.map(\.id))
        return household + savings.filter { seen.insert($0.id).inserted }
    }
}

/// Assigns variable budgets to accounts.
@MainActor
public enum VariableBudgetAccounts {
    /// Returns the stored accounts of a budget.
    public static func storedIDs(for budgetID: UUID) -> [UUID]? {
        let map = all()
        guard map.keys.contains(budgetID.uuidString) else { return nil }
        return map[budgetID.uuidString]
    }

    /// Stores the accounts of a budget.
    public static func set(_ ids: [UUID], for budgetID: UUID) {
        var map = all()
        if ids.isEmpty {
            map.removeValue(forKey: budgetID.uuidString)
        } else {
            map[budgetID.uuidString] = ids
        }
        save(map)
    }

    /// Removes the assignment of a budget.
    public static func remove(for budgetID: UUID) {
        var map = all()
        map.removeValue(forKey: budgetID.uuidString)
        save(map)
    }

    /// Chosen cash accounts. An empty result means every cash account.
    public static func targets(for budget: VariableBudget, cashAccountIDs: [UUID]) -> [UUID] {
        if let stored = storedIDs(for: budget.id) {
            let kept = stored.filter { cashAccountIDs.contains($0) }
            if !kept.isEmpty { return cashAccountIDs.filter { kept.contains($0) } }
        }
        if storedIDs(for: budget.id) == nil, let id = budget.accountID, cashAccountIDs.contains(id) {
            return [id]
        }
        return cashAccountIDs
    }

    /// Sums the budgets' plan for an account.
    public static func planCents(
        budgets: [VariableBudget],
        scopedAccountIDs: Set<UUID>?,
        cashAccountIDs: [UUID]
    ) -> Int {
        budgets.reduce(0) { partial, budget in
            partial + planCents(budget: budget, scopedAccountIDs: scopedAccountIDs, cashAccountIDs: cashAccountIDs)
        }
    }

    /// Returns one budget's plan for an account.
    public static func planCents(
        budget: VariableBudget,
        scopedAccountIDs: Set<UUID>?,
        cashAccountIDs: [UUID]
    ) -> Int {
        let total = abs(budget.monthlyAmountCents)
        guard let scopedAccountIDs else { return total }
        let chosen = targets(for: budget, cashAccountIDs: cashAccountIDs)
        return scopedAccountIDs.reduce(0) { partial, id in
            partial + share(total: total, accountID: id, targets: chosen)
        }
    }

    /// Splits a total evenly, and gives the remainder to the first accounts.
    public static func share(total: Int, accountID: UUID, targets: [UUID]) -> Int {
        guard let index = targets.firstIndex(of: accountID), !targets.isEmpty else { return 0 }
        let base = total / targets.count
        let remainder = total % targets.count
        return base + (index < remainder ? 1 : 0)
    }

    /// Hashes the assignments, so views notice a change.
    public static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in all().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            for id in pair.value {
                hasher.combine(id)
            }
        }
        return hasher.finalize()
    }

    /// Removes all assignments.
    public static func reset() {
        LinkTable.clear(.budgetAccounts)
    }

    /// Reads the assignments.
    private static func all() -> [String: [UUID]] {
        LinkTable.map(.budgetAccounts).mapValues { raw in
            raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
    }

    /// Writes the assignments.
    private static func save(_ map: [String: [UUID]]) {
        LinkTable.replace(.budgetAccounts, with: map.mapValues { ids in
            ids.map(\.uuidString).joined(separator: ",")
        })
    }
}
