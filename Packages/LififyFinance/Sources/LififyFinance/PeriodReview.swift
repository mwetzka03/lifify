import Foundation
import LififyCore

/// One spending category of a finished period, compared with earlier periods.
public struct PeriodReviewLine: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let spentCents: Int
    public let averageCents: Int

    /// How far the period lies above or below the average.
    public var differenceCents: Int { spentCents - averageCents }
}

/// The review of the last finished period.
public struct PeriodReview: Equatable {
    public let period: ForecastPeriod
    public let totalCents: Int
    public let averageTotalCents: Int
    public let comparedPeriods: Int
    /// The categories, with the largest deviation first.
    public let lines: [PeriodReviewLine]
}

/// Compares the spending of the last finished period with up to six earlier ones.
@MainActor
public enum PeriodReviewBuilder {
    /// The most earlier periods used for the average.
    public static let maxComparedPeriods = 6

    /// The stored rows a review reads.
    public struct Inputs {
        public var entries: [LedgerEntry]
        public var splits: [TransactionSplit]
        public var costs: [FixedCost]
        public var budgets: [VariableBudget]
        public var pools: [BudgetPool]

        /// Bundles the stored rows.
        public init(entries: [LedgerEntry], splits: [TransactionSplit], costs: [FixedCost], budgets: [VariableBudget], pools: [BudgetPool]) {
            self.entries = entries
            self.splits = splits
            self.costs = costs
            self.budgets = budgets
            self.pools = pools
        }
    }

    /// Returns the periods of the chosen mode, as the rest of Finance shows them.
    ///
    /// - Parameters:
    ///   - mode: The raw value of a ``DashboardPeriodMode``.
    ///   - entries: All bookings.
    ///   - forecasts: The income forecasts.
    ///   - accounts: All accounts.
    ///   - now: The current time.
    /// - Returns: The periods in ascending order.
    public static func periods(
        mode: String,
        entries: [LedgerEntry],
        forecasts: [IncomeForecast],
        accounts: [Account],
        now: Date = FinanceClock.now
    ) -> [ForecastPeriod] {
        guard mode == DashboardPeriodMode.calendarMonth.rawValue else {
            return FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts)
        }
        guard let earliest = entries.map(\.date).min() else { return [] }
        return FinanceService.forecastPeriods(primary: nil, earliest: earliest, latest: now)
    }

    /// Builds the review of the last period that has ended.
    ///
    /// - Parameters:
    ///   - inputs: The stored rows.
    ///   - periods: The finance periods in ascending order.
    ///   - now: The current time.
    /// - Returns: The review, or `nil` before a period has ended.
    public static func make(_ inputs: Inputs, periods: [ForecastPeriod], now: Date = FinanceClock.now) -> PeriodReview? {
        let today = Calendar.current.startOfDay(for: now)
        let finished = periods.filter { $0.end < today }.sorted { $0.start < $1.start }
        guard let period = finished.last else { return nil }
        let earlier = Array(finished.dropLast().suffix(maxComparedPeriods))
        let names = categoryNames(inputs)
        let spent = spending(in: period, inputs: inputs, names: names)
        let history = earlier.map { spending(in: $0, inputs: inputs, names: names) }
        let keys = Set(spent.keys).union(history.flatMap(\.keys))
        let lines = keys.map { key in
            PeriodReviewLine(
                id: key,
                title: names[key] ?? otherTitle,
                spentCents: spent[key] ?? 0,
                averageCents: average(history.map { $0[key] ?? 0 })
            )
        }
        return PeriodReview(
            period: period,
            totalCents: spent.values.reduce(0, +),
            averageTotalCents: average(history.map { $0.values.reduce(0, +) }),
            comparedPeriods: earlier.count,
            lines: lines.sorted(by: isLargerDeviation)
        )
    }

    /// The category of expenses without a plan.
    private static var otherTitle: String { L("Sonstiges", "Other") }

    /// Orders by the size of the deviation, then by name.
    private static func isLargerDeviation(_ lhs: PeriodReviewLine, _ rhs: PeriodReviewLine) -> Bool {
        let left = abs(lhs.differenceCents)
        let right = abs(rhs.differenceCents)
        return left != right ? left > right : lhs.title < rhs.title
    }

    /// Returns the rounded average.
    private static func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// Maps category keys to their names.
    private static func categoryNames(_ inputs: Inputs) -> [String: String] {
        var names = ["other": otherTitle]
        inputs.costs.forEach { names[$0.id.uuidString] = $0.name }
        inputs.budgets.forEach { names[$0.id.uuidString] = $0.name }
        inputs.pools.forEach { names[$0.id.uuidString] = $0.name }
        return names
    }

    /// Sums a period's expenses per category. Refunds reduce the expense they belong to.
    private static func spending(in period: ForecastPeriod, inputs: Inputs, names: [String: String]) -> [String: Int] {
        let splitsByEntry = Dictionary(grouping: inputs.splits, by: \.transactionID)
        var totals: [String: Int] = [:]
        for entry in inputs.entries where entry.kind == .expense && period.contains(entry.date) {
            var open = RefundLinkStore.countedExpenseCents(of: entry, entries: inputs.entries)
            for split in splitsByEntry[entry.id] ?? [] {
                let part = min(open, abs(split.amountCents))
                totals[known(split.targetID, names: names), default: 0] += part
                open -= part
            }
            if open > 0 { totals[baseCategory(of: entry, names: names), default: 0] += open }
        }
        return totals.filter { $0.value != 0 }
    }

    /// Returns the fixed cost or budget of a booking, or the other category.
    private static func baseCategory(of entry: LedgerEntry, names: [String: String]) -> String {
        known(entry.fixedCostID ?? entry.variableBudgetID, names: names)
    }

    /// Uses a category key only when that category still exists.
    private static func known(_ id: UUID?, names: [String: String]) -> String {
        guard let key = id?.uuidString, names[key] != nil else { return "other" }
        return key
    }
}

/// Announces a finished period's review once, when the person turned that on.
@MainActor
public enum PeriodReviewNotifier {
    public static let enabledKey = "lifify.periodReviewNotice"
    public static let lastPeriodKey = "lifify.periodReviewLast"
    /// The route a tap on the notification opens.
    public static let route = "periodReview"

    /// Returns the period to announce and remembers it. The first check only sets the starting point.
    ///
    /// - Parameter period: The last finished period.
    /// - Returns: The period when it is new and notices are on.
    public static func periodToAnnounce(_ period: ForecastPeriod?) -> ForecastPeriod? {
        guard let period, AppDefaults.store.bool(forKey: enabledKey) else { return nil }
        let last = AppDefaults.store.string(forKey: lastPeriodKey)
        guard last != period.id else { return nil }
        AppDefaults.store.set(period.id, forKey: lastPeriodKey)
        return last == nil ? nil : period
    }

    /// Sends the notification that opens the review.
    public static func announce(_ period: ForecastPeriod) async {
        guard await LififyNotifications.requestAccess() else { return }
        LififyNotifications.send(
            id: "lifify.periodReview.\(period.id)",
            title: L("Dein Rückblick ist da", "Your review is ready"),
            body: L("Sieh dir an, wo du im letzten Zeitraum mehr oder weniger ausgegeben hast.", "See where you spent more or less last period."),
            route: route
        )
    }
}
