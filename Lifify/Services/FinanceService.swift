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
}
