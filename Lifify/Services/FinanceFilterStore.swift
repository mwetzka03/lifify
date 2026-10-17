import Combine
import Foundation

@MainActor
final class FinanceFilterStore: ObservableObject {
    @Published var accountID: UUID? {
        didSet {
            if accountID != nil { showsDepot = false }
        }
    }
    @Published var periodID: String?
    @Published var showsDepot = false {
        didSet {
            if showsDepot, accountID != nil { accountID = nil }
        }
    }

    func selectAllAccounts() {
        showsDepot = false
        accountID = nil
    }

    func selectDepot() {
        accountID = nil
        showsDepot = true
    }

    func select(account id: UUID) {
        showsDepot = false
        accountID = id
    }

    func period(in periods: [ForecastPeriod]) -> ForecastPeriod? {
        if let periodID, let match = periods.first(where: { $0.id == periodID }) {
            return match
        }
        return periods.first { $0.contains(.now) } ?? periods.last
    }

    func account(in accounts: [Account]) -> Account? {
        guard let accountID else { return nil }
        return accounts.first { $0.id == accountID }
    }

    func shiftPeriod(in periods: [ForecastPeriod], by delta: Int) {
        guard let current = period(in: periods),
              let index = periods.firstIndex(of: current) else { return }
        let next = index + delta
        guard periods.indices.contains(next) else { return }
        periodID = periods[next].id
    }

    func jumpToToday(in periods: [ForecastPeriod]) {
        periodID = periods.first { $0.contains(.now) }?.id
    }
}

enum FinancePeriods {
    @MainActor
    static func all(entries: [LedgerEntry], forecasts: [IncomeForecast]) -> [ForecastPeriod] {
        let earliest = entries.map(\.date).min() ?? .now
        let latest = Calendar.current.date(byAdding: .month, value: 18, to: .now) ?? .now
        return FinanceService.forecastPeriods(
            primary: primaryForecast(in: forecasts),
            earliest: earliest,
            latest: latest
        )
    }

    static func primaryForecast(in forecasts: [IncomeForecast]) -> IncomeForecast? {
        guard let id = UserDefaults.standard.string(forKey: "primaryIncomeForecastID").flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return forecasts.first { $0.id == id }
    }

    static func includes(
        _ entry: LedgerEntry,
        period: ForecastPeriod?,
        account: Account?,
        depotIDs: Set<UUID> = []
    ) -> Bool {
        if let period, !period.contains(entry.date) { return false }
        if account == nil, !depotIDs.isEmpty {
            return entry.fromAccountID.map { depotIDs.contains($0) } == true
                || entry.toAccountID.map { depotIDs.contains($0) } == true
        }
        guard let account else { return true }
        return entry.accountID == account.id
            || entry.fromAccountID == account.id
            || entry.toAccountID == account.id
    }
}

enum TradeAccountPreference {
    static let storageKey = "defaultTradeCheckingAccountID"

    static func accountID() -> UUID? {
        UserDefaults.standard.string(forKey: storageKey).flatMap(UUID.init(uuidString:))
    }
}

enum TradeFeePreference {
    static let storageKey = "defaultTradeFeeCents"
    static let defaultCents = 100

    static func editString(cents: Int) -> String {
        let value = String(format: "%.2f", Double(max(cents, 0)) / 100)
        if UserDefaults.standard.string(forKey: "appLanguage") == "en" {
            return value
        }
        return value.replacingOccurrences(of: ".", with: ",")
    }
}
