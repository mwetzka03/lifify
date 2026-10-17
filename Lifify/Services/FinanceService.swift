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
        monthKey: String,
        entries: [LedgerEntry],
        splits: [TransactionSplit]
    ) -> Int {
        let split = splits
            .filter { $0.kind == .variableBudget && $0.targetID == budgetID && $0.periodKey == monthKey }
            .reduce(0) { $0 + $1.amountCents }
        let splitTransactionIDs = Set(splits.filter { $0.kind == .variableBudget }.map(\.transactionID))
        let directWithoutSplit = entries
            .filter { $0.variableBudgetID == budgetID && $0.date.monthKey == monthKey && !splitTransactionIDs.contains($0.id) }
            .reduce(0) { $0 + abs($1.amountCents) }
        return directWithoutSplit + split
    }

    static func poolSpent(
        pool: BudgetPool,
        periodKey: String,
        splits: [TransactionSplit]
    ) -> Int {
        splits
            .filter { $0.kind == .budgetPool && $0.targetID == pool.id && $0.periodKey == periodKey }
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
        includePortfolioValue: Bool = false
    ) -> PeriodForecast {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let holdingsValue = holdings.reduce(0) {
            $0 + Int(($1.quantity * Double($1.currentPriceCents)).rounded())
        }
        let variablePlan = variableBudgets.reduce(0) { $0 + abs($1.monthlyAmountCents) }
        let activeFixed = fixedCosts.filter(\.isActive)
        let incomeDates = incomeOccurrences(forecasts: forecasts, from: period.start, through: period.end)
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
                guard calendar.startOfDay(for: occurrence.date) >= today else { return false }
                guard let match = matchingExpense(occurrence, entries: entries) else { return true }
                return match.date > now
            }
            .reduce(0) { $0 + $1.amount }
        let remainingVariable = period.end < today ? 0 : max(variablePlan - bookedVariable, 0)
        let bias = biasAmounts(shopping: shopping, period: period)
        let outstandingBias = period.end < today ? 0 : bias.planned
        let openingHoldings = includePortfolioValue
            ? HoldingMaintenance.marketValue(of: holdings, through: period.start)
            : 0
        let closingHoldings = includePortfolioValue
            ? HoldingMaintenance.marketValue(of: holdings, through: period.end)
            : 0
        let startBalance = projectedCash(
            on: period.start,
            chargeVariableThroughEnd: false,
            today: today,
            now: now,
            periods: periods,
            accounts: accounts,
            entries: entries,
            fixedCosts: activeFixed,
            forecasts: forecasts,
            shopping: shopping,
            variablePlan: variablePlan,
            budgets: variableBudgets,
            splits: splits
        )
        let endBalance = projectedCash(
            on: period.end,
            chargeVariableThroughEnd: true,
            today: today,
            now: now,
            periods: periods,
            accounts: accounts,
            entries: entries,
            fixedCosts: activeFixed,
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
            startBalance: startBalance + openingHoldings,
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
            now: now
        )
        let fixed = fixedStillToPay(
            costs: fixedCosts,
            entries: entries,
            from: today,
            through: target,
            now: now
        )
        let shoppingCost = shoppingStillToPay(shopping: shopping, entries: entries, through: target, now: now)
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
        let otherFutureExpenses = entries
            .filter { entry in
                guard entry.kind == .expense, entry.variableBudgetID == nil, entry.date > now else { return false }
                guard entry.date <= endOfDay(target) else { return false }
                if entry.fixedCostID != nil || entry.shoppingItemID != nil { return false }
                return !fixedOccurrences(costs: fixedCosts, from: today, through: target).contains { occurrence in
                    matchingExpense(occurrence, entries: [entry]) != nil
                }
            }
            .reduce(0) { $0 + abs($1.amountCents) }
        return actual + income - fixed - shoppingCost - variable - otherFutureExpenses
    }

    private static func incomeStillToReceive(
        forecasts: [IncomeForecast],
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        now: Date
    ) -> Int {
        let forecast = incomeOccurrences(forecasts: forecasts, from: from, through: through)
            .reduce(0) { $0 + $1.amount }
        let bookedThroughTarget = signedSum(entries: entries, kind: .income, from: from, through: through)
        let bookedInCash = entries
            .filter { $0.kind == .income && $0.date >= Calendar.current.startOfDay(for: from) && $0.date <= now }
            .reduce(0) { $0 + abs($1.amountCents) }
        return max(0, max(forecast, bookedThroughTarget) - bookedInCash)
    }

    private static func fixedStillToPay(
        costs: [FixedCost],
        entries: [LedgerEntry],
        from: Date,
        through: Date,
        now: Date
    ) -> Int {
        fixedOccurrences(costs: costs, from: from, through: through).reduce(0) { partial, occurrence in
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
        now: Date
    ) -> Int {
        let limit = Calendar.current.startOfDay(for: target)
        return shopping.reduce(0) { partial, item in
            guard !item.isPurchased, let planned = item.plannedDate else { return partial }
            guard Calendar.current.startOfDay(for: planned) <= limit else { return partial }
            if let entry = entries.first(where: { $0.shoppingItemID == item.id }), entry.date <= now {
                return partial
            }
            return partial + abs(item.amountCents)
        }
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
            return partial + max(variablePlan - spent, 0)
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
            let dates = CalendarService.nextOccurrences(
                firstDate: cost.firstChargeDate,
                cadence: cost.cadence,
                rule: cost.dueRule,
                day: cost.dayOfMonth,
                endDate: cost.endChargeDate,
                through: endOfDay(end)
            )
            for date in dates {
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end else { continue }
                result.append((
                    date: date,
                    amount: abs(cost.amountCents),
                    title: cost.name,
                    costID: cost.id
                ))
            }
        }
        return result
    }

    private static func matchingExpense(
        _ occurrence: (date: Date, amount: Int, title: String, costID: UUID),
        entries: [LedgerEntry]
    ) -> LedgerEntry? {
        entries.first { entry in
            guard entry.kind == .expense || entry.kind == .transfer else { return false }
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
            .reduce(0) { $0 + abs($1.amountCents) }
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
            $0.date >= start && $0.date <= end && ($0.kind == .income || $0.kind == .expense)
        }
        var lines: [ForecastLine] = periodEntries.map { entry in
            let amount = entry.kind == .expense ? -abs(entry.amountCents) : abs(entry.amountCents)
            return ForecastLine(id: entry.id.uuidString, date: entry.date, title: entry.title, amountCents: amount)
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
            if entries.contains(where: { $0.shoppingItemID == item.id }) { continue }
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
            .filter {
                guard let budgetID = $0.variableBudgetID, ids.contains(budgetID) else { return false }
                return $0.date >= start && $0.date <= end && !splitIDs.contains($0.id)
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

    private static func biasAmounts(
        shopping: [ShoppingItem],
        period: ForecastPeriod
    ) -> (applied: Int, planned: Int) {
        let start = Calendar.current.startOfDay(for: period.start)
        let end = Calendar.current.startOfDay(for: period.end)
        let items = shopping.filter { item in
            guard let planned = item.plannedDate else { return false }
            let day = Calendar.current.startOfDay(for: planned)
            return day >= start && day <= end
        }
        let applied = items.filter(\.isPurchased).reduce(0) { $0 + abs($1.amountCents) }
        let planned = items.filter { !$0.isPurchased }.reduce(0) { $0 + abs($1.amountCents) }
        return (applied, planned)
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
