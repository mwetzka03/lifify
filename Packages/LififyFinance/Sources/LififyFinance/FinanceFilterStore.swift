import Combine
import LififyCore
import Foundation

/// The period and account selected across the finance screens.
@MainActor
public final class FinanceFilterStore: ObservableObject {
    public init() {}

    @Published public var accountID: UUID? {
        didSet {
            if accountID != nil { showsDepot = false }
        }
    }
    @Published public var periodID: String?
    @Published public var showsDepot = false {
        didSet {
            if showsDepot, accountID != nil { accountID = nil }
        }
    }

    /// Shows all accounts.
    public func selectAllAccounts() {
        showsDepot = false
        accountID = nil
    }

    /// Shows the depot.
    public func selectDepot() {
        accountID = nil
        showsDepot = true
    }

    /// Shows one account.
    public func select(account id: UUID) {
        showsDepot = false
        accountID = id
    }

    /// Returns the selected period, or the one containing today.
    public func period(in periods: [ForecastPeriod]) -> ForecastPeriod? {
        if let periodID, let match = periods.first(where: { $0.id == periodID }) {
            return match
        }
        return periods.first { $0.contains(.now) } ?? periods.last
    }

    /// Returns the selected account.
    public func account(in accounts: [Account]) -> Account? {
        guard let accountID else { return nil }
        return accounts.first { $0.id == accountID }
    }

    /// Moves the selection by a number of periods.
    public func shiftPeriod(in periods: [ForecastPeriod], by delta: Int) {
        guard let current = period(in: periods),
              let index = periods.firstIndex(of: current) else { return }
        let next = index + delta
        guard periods.indices.contains(next) else { return }
        periodID = periods[next].id
    }

    /// Selects the period containing today.
    public func jumpToToday(in periods: [ForecastPeriod]) {
        periodID = periods.first { $0.contains(.now) }?.id
    }
}

/// Builds the finance periods and decides what falls into them.
@MainActor
public enum FinancePeriods {
    /// Everything the period list depends on.
    private struct MemoKey: Equatable {
        var generation: Int
        var day: Date
        var entryCount: Int
        var mainID: UUID?
        var primaryID: UUID?
        var primaryFirstDate: Date?
        var primaryCadence: String?
        var primaryRule: String?
        var primaryDay: Int?
    }

    private static var memo: (key: MemoKey, periods: [ForecastPeriod])?

    /// Views ask for the periods many times per frame. The answer is reused until stored data changes.
    /// Unsaved edits skip the memo, so a changed date is never answered from an old result.
    @MainActor
    public static func all(entries: [LedgerEntry], forecasts: [IncomeForecast], accounts: [Account]) -> [ForecastPeriod] {
        let main = accounts.first(where: \.isMain)
        let primary = primaryForecast(in: forecasts)
        let key = MemoKey(
            generation: ModelChangeCounter.value,
            day: Calendar.current.startOfDay(for: .now),
            entryCount: entries.count,
            mainID: main?.id,
            primaryID: primary?.id,
            primaryFirstDate: primary?.firstPaymentDate,
            primaryCadence: primary?.cadenceRaw,
            primaryRule: primary?.dueRuleRaw,
            primaryDay: primary?.dayOfMonth
        )
        let pending = entries.first?.modelContext?.hasChanges == true
        if !pending, let memo, memo.key == key { return memo.periods }
        let periods = computeAll(entries: entries, primary: primary, main: main)
        memo = pending ? nil : (key, periods)
        return periods
    }

    /// Calculates the periods from the main account's bookings.
    private static func computeAll(entries: [LedgerEntry], primary: IncomeForecast?, main: Account?) -> [ForecastPeriod] {
        let relevant = entries.filter { entry in
            guard let main else { return false }
            return entry.accountID == main.id
                || entry.fromAccountID == main.id
                || entry.toAccountID == main.id
        }
        guard let earliest = relevant.map(\.date).min() else { return [] }
        let latest = Calendar.current.date(byAdding: .month, value: 18, to: .now) ?? .now
        return FinanceService.forecastPeriods(
            primary: primary,
            earliest: earliest,
            latest: latest
        )
    }

    /// Returns the primary income forecast.
    public static func primaryForecast(in forecasts: [IncomeForecast]) -> IncomeForecast? {
        guard let id = IncomeAssignmentStore.primaryForecastID else {
            return nil
        }
        return forecasts.first { $0.id == id }
    }

    /// Says whether a booking belongs to the period and account.
    public static func includes(
        _ entry: LedgerEntry,
        period: ForecastPeriod?,
        account: Account?,
        depotIDs: Set<UUID> = []
    ) -> Bool {
        if let period, !period.contains(entry.date) { return false }
        if account == nil, !depotIDs.isEmpty {
            return entry.fromAccountID.map { depotIDs.contains($0) } == true
                || entry.toAccountID.map { depotIDs.contains($0) } == true
                || entry.accountID.map { depotIDs.contains($0) } == true
        }
        guard let account else { return true }
        return entry.accountID == account.id
            || entry.fromAccountID == account.id
            || entry.toAccountID == account.id
    }
}

/// Cheap change token for finance screens. Full title/notes hashing on every frame made the tab hitch.
public enum FinanceRenderToken {
    /// Adds the bookings' values to a change hash.
    public static func mix(entries: [LedgerEntry], into hasher: inout Hasher) {
        hasher.combine(entries.count)
        var amounts = 0
        for entry in entries {
            amounts = amounts &+ entry.amountCents
        }
        hasher.combine(amounts)
        hasher.combine(entries.first?.id)
        hasher.combine(entries.last?.id)
        hasher.combine(entries.first?.date)
        hasher.combine(entries.last?.date)
    }

    /// Adds the holdings' values to a change hash.
    public static func mix(holdings: [PortfolioHolding], into hasher: inout Hasher) {
        hasher.combine(holdings.count)
        var mix = 0
        for holding in holdings {
            mix = mix &+ holding.quantity.hashValue &+ holding.currentPriceCents &+ holding.purchasePriceCents
        }
        hasher.combine(mix)
        hasher.combine(holdings.first?.id)
        hasher.combine(holdings.last?.id)
    }
}

/// The default checking account for trades.
public enum TradeAccountPreference {
    public static let storageKey = "defaultTradeCheckingAccountID"

    /// Returns the stored account.
    public static func accountID() -> UUID? {
        AppDefaults.store.string(forKey: storageKey).flatMap(UUID.init(uuidString:))
    }
}

/// The default fee for trades.
public enum TradeFeePreference {
    public static let storageKey = "defaultTradeFeeCents"
    public static let defaultCents = 100

    /// Formats the fee for editing.
    public static func editString(cents: Int) -> String {
        let value = String(format: "%.2f", Double(max(cents, 0)) / 100)
        if AppDefaults.store.string(forKey: "appLanguage") == "en" {
            return value
        }
        return value.replacingOccurrences(of: ".", with: ",")
    }
}
