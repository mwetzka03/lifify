import Foundation
import LififyCore
import SwiftData

/// The switches and thresholds of the budget warnings.
public struct BudgetAlertSettings: Equatable {
    public static let enabledKey = "lifify.budgetAlerts.enabled"
    public static let budgetsKey = "lifify.budgetAlerts.budgets"
    public static let dailyKey = "lifify.budgetAlerts.daily"
    public static let firstKey = "lifify.budgetAlerts.first"
    public static let secondKey = "lifify.budgetAlerts.second"
    public static let defaultFirst = 80
    public static let defaultSecond = 100

    public var enabled = true
    public var budgets = true
    public var daily = true
    public var firstPercent = defaultFirst
    public var secondPercent = defaultSecond

    /// Creates settings with the defaults.
    public init() {}

    /// Reads the stored settings.
    public static var current: BudgetAlertSettings {
        let store = AppDefaults.store
        var settings = BudgetAlertSettings()
        settings.enabled = store.object(forKey: enabledKey) as? Bool ?? true
        settings.budgets = store.object(forKey: budgetsKey) as? Bool ?? true
        settings.daily = store.object(forKey: dailyKey) as? Bool ?? true
        settings.firstPercent = store.object(forKey: firstKey) as? Int ?? defaultFirst
        settings.secondPercent = store.object(forKey: secondKey) as? Int ?? defaultSecond
        return settings
    }
}

/// One warning for the person.
public struct BudgetAlert: Equatable {
    public let key: String
    public let text: String

    /// Creates a warning.
    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

public extension HomeBudget {
    /// Calculates the home budget from the store with the chosen period mode.
    static func current(context: ModelContext, now: Date = FinanceClock.now) -> HomeBudgetSnapshot {
        make(
            entries: (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? [],
            accounts: (try? context.fetch(FetchDescriptor<Account>())) ?? [],
            forecasts: (try? context.fetch(FetchDescriptor<IncomeForecast>())) ?? [],
            variableBudgets: (try? context.fetch(FetchDescriptor<VariableBudget>())) ?? [],
            pools: (try? context.fetch(FetchDescriptor<BudgetPool>())) ?? [],
            splits: (try? context.fetch(FetchDescriptor<TransactionSplit>())) ?? [],
            dashboardPeriod: AppDefaults.store.string(forKey: "dashboardPeriodMode") ?? DashboardPeriodMode.calendarMonth.rawValue,
            now: now
        )
    }
}

public extension HomeBudgetSnapshot {
    /// The whole days until the next salary.
    func daysUntilSalary(now: Date = FinanceClock.now) -> Int? {
        guard let nextSalary else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: nextSalary)).day
    }

    /// What may still be spent per day until the next salary.
    func dailyAllowance(now: Date = FinanceClock.now) -> Int? {
        guard remaining > 0, let days = daysUntilSalary(now: now) else { return nil }
        return remaining / max(days, 1)
    }

    /// The amount spent today.
    func spentToday(now: Date = FinanceClock.now) -> Int {
        let calendar = Calendar.current
        return (expenseLines + purchaseLines)
            .filter { $0.date.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
            .reduce(0) { $0 + $1.cents }
    }

    /// How far today's spending lies above today's budget, or `nil` when it fits.
    func dailyOverrun(now: Date = FinanceClock.now) -> Int? {
        guard let days = daysUntilSalary(now: now) else { return nil }
        let today = spentToday(now: now)
        guard today > 0 else { return nil }
        let budget = max(remaining + today, 0) / max(days, 1)
        return today > budget ? today - budget : nil
    }
}

/// Decides which warnings are new. Only the running period counts, so old imports stay silent.
@MainActor
public enum BudgetAlerts {
    /// The stored rows a check reads.
    public struct Inputs {
        public var budgets: [VariableBudget]
        public var pools: [BudgetPool]
        public var entries: [LedgerEntry]
        public var splits: [TransactionSplit]
        public var home: HomeBudgetSnapshot?

        /// Bundles the stored rows.
        public init(budgets: [VariableBudget], pools: [BudgetPool], entries: [LedgerEntry], splits: [TransactionSplit], home: HomeBudgetSnapshot?) {
            self.budgets = budgets
            self.pools = pools
            self.entries = entries
            self.splits = splits
            self.home = home
        }
    }

    /// The result of one check.
    public struct Evaluation: Equatable {
        public var alerts: [BudgetAlert] = []
        public var sent = Set<String>()
    }

    /// Finds the new warnings. A jump past both thresholds gives one warning.
    ///
    /// - Parameters:
    ///   - inputs: The stored rows.
    ///   - settings: The switches and thresholds.
    ///   - sent: The warnings already given.
    ///   - now: The current time.
    /// - Returns: The new warnings and the updated record of given ones.
    public static func evaluate(
        _ inputs: Inputs,
        settings: BudgetAlertSettings,
        sent: Set<String>,
        now: Date = FinanceClock.now
    ) -> Evaluation {
        var result = Evaluation(sent: sent)
        guard settings.enabled else { return result }
        if settings.budgets {
            for budget in inputs.budgets {
                let spent = FinanceService.variableSpent(budgetID: budget.id, monthKey: now.monthKey, entries: inputs.entries, splits: inputs.splits)
                check(name: budget.name, key: "budget|\(budget.id.uuidString)|\(now.monthKey)", spent: spent, limit: budget.monthlyAmountCents, settings: settings, into: &result)
            }
            for pool in inputs.pools where pool.isActive {
                let period = CalendarService.periodKey(for: now, pool: pool)
                let spent = FinanceService.poolSpent(pool: pool, periodKey: period, splits: inputs.splits)
                let carry = FinanceService.poolCarry(pool: pool, currentPeriodKey: period, splits: inputs.splits)
                check(name: pool.name, key: "pool|\(pool.id.uuidString)|\(period)", spent: spent, limit: pool.amountCents + carry, settings: settings, into: &result)
            }
        }
        if settings.daily, let overrun = inputs.home?.dailyOverrun(now: now) {
            let key = "daily|\(now.dayKey)"
            if result.sent.insert(key).inserted {
                result.alerts.append(BudgetAlert(key: key, text: L("Tagesbudget um \(Money.string(cents: overrun)) überschritten", "Daily budget exceeded by \(Money.string(cents: overrun))")))
            }
        }
        return result
    }

    /// Records the crossed thresholds of one budget and warns about the highest new one.
    private static func check(
        name: String,
        key: String,
        spent: Int,
        limit: Int,
        settings: BudgetAlertSettings,
        into result: inout Evaluation
    ) {
        guard limit > 0 else { return }
        let thresholds = Set([settings.firstPercent, settings.secondPercent]).sorted()
        let crossed = thresholds.filter { spent * 100 >= limit * $0 }
        guard let highest = crossed.last else { return }
        let highestKey = "\(key)|\(highest)"
        let isNew = !result.sent.contains(highestKey)
        crossed.forEach { result.sent.insert("\(key)|\($0)") }
        guard isNew else { return }
        let percent = spent * 100 / limit
        result.alerts.append(BudgetAlert(key: highestKey, text: L("\(name): \(percent) % verbraucht", "\(name): \(percent) % used")))
    }

    /// Builds one notification for all new warnings.
    ///
    /// - Parameter alerts: The new warnings.
    /// - Returns: Title and text, or `nil` without warnings.
    public static func message(for alerts: [BudgetAlert]) -> (title: String, body: String)? {
        guard let first = alerts.first else { return nil }
        guard alerts.count > 1 else { return (L("Budget-Warnung", "Budget warning"), first.text) }
        return (L("\(alerts.count) Budget-Warnungen", "\(alerts.count) budget warnings"), alerts.map(\.text).joined(separator: "\n"))
    }
}

/// Runs the budget check after new bookings and sends one bundled notification.
@MainActor
public enum BudgetAlertService {
    private static let sentKey = "lifify.budgetAlerts.sent"

    /// Checks the running period and notifies about new warnings.
    public static func check(context: ModelContext, now: Date = FinanceClock.now) async {
        let settings = BudgetAlertSettings.current
        guard settings.enabled else { return }
        let inputs = loadInputs(context: context, now: now)
        let stored = Set(AppDefaults.store.stringArray(forKey: sentKey) ?? [])
        let result = BudgetAlerts.evaluate(inputs, settings: settings, sent: stored, now: now)
        guard result.sent != stored else { return }
        AppDefaults.store.set(currentKeys(result.sent, now: now), forKey: sentKey)
        guard let message = BudgetAlerts.message(for: result.alerts),
              await LififyNotifications.requestAccess()
        else { return }
        LififyNotifications.schedule(
            id: "lifify.budgetAlert.\(UUID().uuidString)",
            title: message.title,
            body: message.body,
            at: FinanceClock.now.addingTimeInterval(1)
        )
    }

    /// Reads what the check needs from the store.
    private static func loadInputs(context: ModelContext, now: Date) -> BudgetAlerts.Inputs {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>())) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<VariableBudget>())) ?? []
        let pools = (try? context.fetch(FetchDescriptor<BudgetPool>())) ?? []
        let home = HomeBudget.current(context: context, now: now)
        return BudgetAlerts.Inputs(budgets: budgets, pools: pools, entries: entries, splits: splits, home: home)
    }

    /// Drops daily records of earlier days, so the stored list stays small.
    private static func currentKeys(_ keys: Set<String>, now: Date) -> [String] {
        keys.filter { !$0.hasPrefix("daily|") || $0 == "daily|\(now.dayKey)" }.sorted()
    }
}
