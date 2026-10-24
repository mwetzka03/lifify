import Foundation

@MainActor
enum FinanceService {
    static func balance(
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

    static func totalBalance(
        accounts: [Account],
        entries: [LedgerEntry],
        holdings: [PortfolioHolding],
        liquidOnly: Bool = false
    ) -> Int {
        accounts
            .filter { $0.kind != .savingsGroup && (!liquidOnly || $0.isLiquid) }
            .reduce(0) { $0 + balance(for: $1, entries: entries, holdings: holdings) }
    }

    static func variableSpent(
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

    static func variableSpent(
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

    static func poolSpent(
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

    static func poolCarry(
        pool: BudgetPool,
        currentPeriodKey: String,
        splits: [TransactionSplit]
    ) -> Int {
        guard pool.isScalable else { return 0 }
        let keys = CalendarService.periodKeys(from: pool.createdAt, through: .now, pool: pool)
        var carry = 0
        for key in keys {
            if key == currentPeriodKey { return carry }
            carry = pool.amountCents + carry - poolSpent(pool: pool, periodKey: key, splits: splits)
        }
        return carry
    }

    private static func isAfter(_ entry: LedgerEntry, anchor: LedgerEntry?) -> Bool {
        guard let anchor else { return entry.kind != .adjustment }
        if entry.date != anchor.date { return entry.date > anchor.date }
        return entry.createdAt > anchor.createdAt
    }

    static func cashBalance(
        accounts: [Account],
        entries: [LedgerEntry],
        through date: Date
    ) -> Int {
        accounts
            .filter { $0.kind != .savingsGroup && $0.kind != .portfolio }
            .reduce(0) { $0 + balance(for: $1, entries: entries, holdings: [], through: date) }
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

    static func savingsPlanBookedCents(
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

    static func forecastPeriods(
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
            if end < floor || start > horizon { continue }
            periods.append(ForecastPeriod(start: start, end: calendar.startOfDay(for: end)))
        }
        return periods.isEmpty ? monthPeriods(from: floor, through: horizon) : periods
    }

    static func periodForecast(
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
        now: Date = .now,
        incomePredicate: ((LedgerEntry) -> Bool)? = nil,
        includePortfolioValue: Bool = false,
        countSavingsPlansInCash: Bool = true,
        scopedCashAccountIDs: Set<UUID>? = nil,
        householdCashAccountIDs: [UUID] = []
    ) -> PeriodForecast {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let holdingsValue = holdings.reduce(0) {
            $0 + Int(($1.quantity * Double($1.currentPriceCents)).rounded())
        }
        let cashIDs = householdCashAccountIDs.isEmpty
            ? accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id)
            : householdCashAccountIDs
        let variablePlan = VariableBudgetAccounts.planCents(
            budgets: variableBudgets,
            scopedAccountIDs: scopedCashAccountIDs,
            cashAccountIDs: cashIDs
        )
        let activeFixed = fixedCosts.filter(\.isActive)
        let cashFixed = countSavingsPlansInCash
            ? activeFixed
            : activeFixed.filter { !SavingsPlanFixedCosts.isSavingsCost($0) }
        let incomeDates = incomeOccurrences(forecasts: forecasts, from: period.start, through: period.end)
            .filter { item in
                if ForecastSkipStore.isSkipped(.income, id: item.forecastID, on: item.date) { return false }
                return !ForecastPeriodLinkStore.covers(.income, id: item.forecastID, entries: entries, period: period)
            }
        let plannedIncome = incomeDates.reduce(0) { $0 + $1.amount }
        let incomeSource = incomePredicate.map { predicate in
            entries.filter { $0.kind != .income || predicate($0) }
        } ?? entries
        let bookedIncome = signedSum(entries: incomeSource, kind: .income, from: period.start, through: period.end)
        let income = max(plannedIncome, bookedIncome)
        let openIncome = max(0, plannedIncome - bookedIncome)
        let bookedExpenses = signedSum(entries: entries, kind: .expense, from: period.start, through: period.end)
        let fixedDates = fixedOccurrences(costs: activeFixed, from: period.start, through: period.end)
        let bookedFixed = bookedFixedAmount(occurrences: fixedDates, entries: entries, from: period.start, through: period.end)
        let bookedVariable = variableSpent(
            in: period,
            budgets: variableBudgets,
            entries: entries,
            splits: splits,
            through: min(now, period.end)
        )
        let remainingFixed = fixedDates
            .filter { occurrence in
                if ForecastSkipStore.isSkipped(.fixed, id: occurrence.costID, on: occurrence.date) { return false }
                if ForecastPeriodLinkStore.covers(.fixed, id: occurrence.costID, entries: entries, period: period) { return false }
                guard let match = matchingExpense(occurrence, entries: entries) else { return true }
                return match.date > now
            }
            .reduce(0) { $0 + $1.amount }
        let suppressedVariable = variableBudgets.reduce(0) { partial, budget in
            let skipped = ForecastSkipStore.isSkipped(.variable, id: budget.id, on: period.end)
            guard skipped else { return partial }
            let plan = VariableBudgetAccounts.planCents(
                budget: budget,
                scopedAccountIDs: scopedCashAccountIDs,
                cashAccountIDs: cashIDs
            )
            let spent = variableSpent(
                budgetID: budget.id,
                from: period.start,
                through: min(now, period.end),
                entries: entries,
                splits: splits
            )
            return partial + max(plan - spent, 0)
        }
        let remainingVariable = period.end < today ? 0 : max(variablePlan - bookedVariable - suppressedVariable, 0)
        let bias = shoppingBias(shopping: shopping, entries: entries, period: period)
        let outstandingBias = period.end < today ? 0 : bias.planned
        let periodStart = calendar.startOfDay(for: period.start)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: periodStart) ?? periodStart
        let openingHoldings = includePortfolioValue
            ? HoldingMaintenance.marketValue(of: holdings, through: dayBefore)
            : 0
        let closingHoldings = includePortfolioValue
            ? HoldingMaintenance.marketValue(of: holdings, through: period.end)
            : 0
        let startCash: Int
        if periodStart <= today {
            startCash = cashBalanceBeforePeriod(accounts: accounts, entries: entries, start: periodStart)
        } else {
            startCash = projectedCash(
                on: dayBefore,
                chargeVariableThroughEnd: true,
                today: today,
                now: now,
                periods: periods,
                accounts: accounts,
                entries: entries,
                fixedCosts: cashFixed,
                forecasts: forecasts,
                shopping: shopping,
                variablePlan: variablePlan,
                budgets: variableBudgets,
                splits: splits
            )
        }
        let startBalance = startCash + openingHoldings
        let endBalance = projectedCash(
            on: period.end,
            chargeVariableThroughEnd: true,
            today: today,
            now: now,
            periods: periods,
            accounts: accounts,
            entries: entries,
            fixedCosts: cashFixed,
            forecasts: forecasts,
            shopping: shopping,
            variablePlan: variablePlan,
            budgets: variableBudgets,
            splits: splits
        ) + closingHoldings
        let portfolioNow = includePortfolioValue
            ? HoldingMaintenance.marketValue(of: holdings, through: now)
            : holdingsValue
        let netWorth: Int
        if period.contains(today) {
            netWorth = cashBalance(accounts: accounts, entries: entries, through: endOfDay(now)) + portfolioNow
        } else if period.end < today {
            netWorth = cashBalance(accounts: accounts, entries: entries, through: endOfDay(period.end)) + closingHoldings
        } else {
            netWorth = endBalance + (includePortfolioValue ? 0 : holdingsValue)
        }
        let openExpenses = period.end < today ? 0 : remainingFixed + remainingVariable + outstandingBias
        let events = eventLines(
            period: period,
            entries: entries,
            accounts: accounts,
            fixedCosts: activeFixed,
            forecasts: forecasts,
            shopping: shopping
        )
        return PeriodForecast(
            netWorth: netWorth,
            income: income,
            expenses: bookedExpenses,
            startBalance: startBalance,
            endBalance: endBalance,
            remainingFixed: remainingFixed,
            remainingVariable: remainingVariable,
            biasApplied: bias.applied,
            biasPlanned: bias.planned,
            bookedIncome: bookedIncome,
            bookedExpenses: bookedExpenses,
            bookedFixed: bookedFixed,
            bookedVariable: bookedVariable,
            openIncome: openIncome,
            openExpenses: openExpenses,
            events: events
        )
    }

    private static func monthPeriods(from floor: Date, through horizon: Date) -> [ForecastPeriod] {
        let calendar = Calendar.current
        var periods: [ForecastPeriod] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: floor)) ?? floor
        while cursor <= horizon {
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor),
                  let end = calendar.date(byAdding: .day, value: -1, to: next)
            else { break }
            if end >= floor {
                periods.append(ForecastPeriod(start: cursor, end: calendar.startOfDay(for: end)))
            }
            cursor = next
        }
        return periods
    }

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
        splits: [TransactionSplit]
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
            periods: periods
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

    private static func incomeStillToReceive(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        now: Date,
        periods: [ForecastPeriod]
    ) -> Int {
        let forecast = incomeOccurrences(forecasts: forecasts, from: from, through: through)
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

    static func scheduledCharges(
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
    static func assignedBookings(for cost: FixedCost, entries: [LedgerEntry]) -> [LedgerEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
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
    static func upcomingCharges(for cost: FixedCost, entries: [LedgerEntry], limit: Int = 3) -> [ScheduledCharge] {
        guard cost.isActive, limit > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: today) else { return [] }
        return Array(
            scheduledCharges(costs: [cost], entries: entries, from: today, through: horizon)
                .filter { !ForecastSkipStore.isSkipped(.fixed, id: cost.id, on: $0.date) }
                .prefix(limit)
        )
    }

    static func nextChargeDate(for cost: FixedCost, entries: [LedgerEntry]) -> Date? {
        guard cost.isActive else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: today) else { return nil }
        return scheduledCharges(costs: [cost], entries: entries, from: today, through: horizon)
            .first { !$0.isPaid }?
            .date
    }

    static func openChargeCount(
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

    private static func matchingExpense(
        _ occurrence: (date: Date, amount: Int, title: String, costID: UUID),
        entries: [LedgerEntry]
    ) -> LedgerEntry? {
        entries.first { entry in
            guard entry.kind == .expense || entry.kind == .transfer else { return false }
            if ForecastMatchRejectionStore.isRejected(costID: occurrence.costID, entryID: entry.id) { return false }
            guard Calendar.current.isDate(entry.date, inSameDayAs: occurrence.date) else { return false }
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

    private static func scopedTransferCents(amount: Int, from: UUID?, to: UUID?, scope: Set<UUID>) -> Int {
        var net = 0
        if let from, scope.contains(from) { net -= amount }
        if let to, scope.contains(to) { net += amount }
        return net
    }

    private static func isPortfolioMovement(_ entry: LedgerEntry) -> Bool {
        if BookingClassification.isSavingsPlan(entry) { return true }
        let prefixes = [
            "Kauf:", "Purchase:", "Buy:",
            "Verkauf:", "Sale:", "Sell:",
            "Sparplan:", "Savings plan:"
        ]
        return prefixes.contains { entry.title.hasPrefix($0) }
    }

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

    private static func eventLines(
        period: ForecastPeriod,
        entries: [LedgerEntry],
        accounts: [Account],
        fixedCosts: [FixedCost],
        forecasts: [IncomeForecast],
        shopping: [ShoppingItem]
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
        for item in incomeOccurrences(forecasts: forecasts, from: period.start, through: period.end) {
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
    static func shoppingBias(
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

    static func shoppingBookings(for itemID: UUID, entries: [LedgerEntry], period: ForecastPeriod? = nil) -> [LedgerEntry] {
        entries.filter { entry in
            if let period, !period.contains(entry.date) { return false }
            if entry.shoppingItemID == itemID { return true }
            guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == .shopping && link.id == itemID
        }
        .sorted { $0.date > $1.date }
    }

    private static func countsTowardVariable(_ entry: LedgerEntry, budgetID: UUID) -> Bool {
        if entry.variableBudgetID == budgetID { return true }
        guard let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
        return link.kind == .variable && link.id == budgetID
    }

    private static func entryTouches(_ entry: LedgerEntry, accountID: UUID?) -> Bool {
        guard let accountID else { return true }
        return entry.accountID == accountID || entry.fromAccountID == accountID || entry.toAccountID == accountID
    }

    private static func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))?.addingTimeInterval(-1) ?? date
    }
}

struct ForecastPeriod: Equatable, Identifiable {
    var start: Date
    var end: Date
    var id: String { "\(start.dayKey)|\(end.dayKey)" }

    func contains(_ date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return day >= Calendar.current.startOfDay(for: start) && day <= Calendar.current.startOfDay(for: end)
    }
}

struct PeriodForecast {
    var netWorth: Int
    var income: Int
    var expenses: Int
    var startBalance: Int
    var endBalance: Int
    var remainingFixed: Int
    var remainingVariable: Int
    var biasApplied: Int
    var biasPlanned: Int
    var bookedIncome: Int
    var bookedExpenses: Int
    var bookedFixed: Int
    var bookedVariable: Int
    var openIncome: Int
    var openExpenses: Int
    var events: [ForecastLine]
    var realDifference: Int { bookedIncome - bookedExpenses }
    var balanceChange: Int { endBalance - startBalance }
}

struct ForecastLine: Identifiable {
    var id: String
    var date: Date
    var title: String
    var amountCents: Int
}

struct ScheduledCharge: Identifiable {
    var id: String
    var date: Date
    var amount: Int
    var title: String
    var costID: UUID
    var isPaid: Bool
}

struct ForecastListItem: Identifiable {
    enum Kind {
        case income(IncomeForecast)
        case expense(UUID)
        case transfer(TransferForecastRecord)
        case variable(UUID)
        case shopping(UUID)
    }

    var id: String
    var title: String
    var date: Date
    var signedCents: Int
    var kind: Kind
    /// A booking already covers this date, manually or automatically. The row stays visible.
    var settled: Bool = false

    var fixedCostID: UUID? {
        if case .expense(let id) = kind { return id }
        return nil
    }

    var sourceID: UUID {
        switch kind {
        case .income(let forecast): forecast.id
        case .expense(let id), .variable(let id), .shopping(let id): id
        case .transfer(let forecast): forecast.id
        }
    }

    var refKind: ForecastRefKind {
        switch kind {
        case .income: .income
        case .expense: .fixed
        case .transfer: .transfer
        case .variable: .variable
        case .shopping: .shopping
        }
    }
}

/// Open income, expense, and transfer forecasts for the selected account and period.
@MainActor
enum ForecastSchedule {
    static func incomeView(
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

    static func expenseView(
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

    static func financeView(
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

    private enum TransferDirection {
        case incoming
        case outgoing
        case both
    }

    private static func incomeItems(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
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

    private static func expenseItems(
        costs: [FixedCost],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
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
        let today = Calendar.current.startOfDay(for: .now)
        guard period.end >= today else { return [] }
        let scope = account.map { Set([$0.id]) }
        let spentThrough = min(Date(), period.end)
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

    private static func shoppingItems(
        shopping: [ShoppingItem],
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool
    ) -> [ForecastListItem] {
        guard !showsDepot else { return [] }
        guard account == nil || account?.isMain == true else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
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

    private static func transferItems(
        entries: [LedgerEntry],
        period: ForecastPeriod,
        account: Account?,
        showsDepot: Bool,
        direction: TransferDirection
    ) -> [ForecastListItem] {
        guard !showsDepot, let account else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
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

    private static func transferIsBooked(_ forecastID: UUID, entries: [LedgerEntry], period: ForecastPeriod) -> Bool {
        if ForecastPeriodLinkStore.covers(.transfer, id: forecastID, entries: entries, period: period) { return true }
        return entries.contains { entry in
            period.contains(entry.date) && TransferForecastAssignmentStore.forecastID(for: entry.id) == forecastID
        }
    }
}

@MainActor
enum FixedCostScope {
    static func applicable(
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

@MainActor
enum VariableBudgetAccounts {
    private static let key = "lifify.variableBudgetAccounts"

    static func storedIDs(for budgetID: UUID) -> [UUID]? {
        let map = all()
        guard map.keys.contains(budgetID.uuidString) else { return nil }
        return map[budgetID.uuidString]
    }

    static func set(_ ids: [UUID], for budgetID: UUID) {
        var map = all()
        if ids.isEmpty {
            map.removeValue(forKey: budgetID.uuidString)
        } else {
            map[budgetID.uuidString] = ids
        }
        save(map)
    }

    static func remove(for budgetID: UUID) {
        var map = all()
        map.removeValue(forKey: budgetID.uuidString)
        save(map)
    }

    /// Chosen cash accounts. An empty result means every cash account.
    static func targets(for budget: VariableBudget, cashAccountIDs: [UUID]) -> [UUID] {
        if let stored = storedIDs(for: budget.id) {
            let kept = stored.filter { cashAccountIDs.contains($0) }
            if !kept.isEmpty { return cashAccountIDs.filter { kept.contains($0) } }
        }
        if storedIDs(for: budget.id) == nil, let id = budget.accountID, cashAccountIDs.contains(id) {
            return [id]
        }
        return cashAccountIDs
    }

    static func planCents(
        budgets: [VariableBudget],
        scopedAccountIDs: Set<UUID>?,
        cashAccountIDs: [UUID]
    ) -> Int {
        budgets.reduce(0) { partial, budget in
            partial + planCents(budget: budget, scopedAccountIDs: scopedAccountIDs, cashAccountIDs: cashAccountIDs)
        }
    }

    static func planCents(
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

    static func share(total: Int, accountID: UUID, targets: [UUID]) -> Int {
        guard let index = targets.firstIndex(of: accountID), !targets.isEmpty else { return 0 }
        let base = total / targets.count
        let remainder = total % targets.count
        return base + (index < remainder ? 1 : 0)
    }

    static func fingerprint() -> Int {
        var hasher = Hasher()
        for pair in all().sorted(by: { $0.key < $1.key }) {
            hasher.combine(pair.key)
            for id in pair.value {
                hasher.combine(id)
            }
        }
        return hasher.finalize()
    }

    private static func all() -> [String: [UUID]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [UUID]].self, from: data) else { return [:] }
        return decoded
    }

    private static func save(_ map: [String: [UUID]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
