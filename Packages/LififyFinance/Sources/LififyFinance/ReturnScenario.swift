import Foundation
import LififyCore

/// What an ETF's scenario return is based on.
public enum ReturnBasis: String, Codable, Sendable {
    case tenYears
    case fiveYears
    case standard

    /// The label shown in the settings.
    public var label: String {
        switch self {
        case .tenYears: L("10 J.", "10 yrs")
        case .fiveYears: L("5 J.", "5 yrs")
        case .standard: L("Standard", "Default")
        }
    }
}

/// The yearly return of one instrument with its basis.
public struct ScenarioRate: Codable, Equatable, Sendable {
    public var annual: Double
    public var basis: ReturnBasis
    /// Whether the market data calls this instrument an ETF.
    public var isETF: Bool

    /// Creates a rate.
    public init(annual: Double, basis: ReturnBasis, isETF: Bool) {
        self.annual = annual
        self.basis = basis
        self.isETF = isETF
    }
}

/// A person's correction of the automatic ETF detection.
public enum ETFOverride: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case etf
    case other

    /// The stored value.
    public var id: String { rawValue }

    /// The label shown in the settings.
    public var label: String {
        switch self {
        case .automatic: L("Automatisch", "Automatic")
        case .etf: "ETF"
        case .other: L("Kein ETF", "Not an ETF")
        }
    }
}

/// The optional forecast in which ETFs grow by their own historic return.
@MainActor
public enum ReturnScenario {
    public static let enabledKey = "lifify.returnScenario"
    /// The return of an ETF with less than five years of prices.
    public nonisolated static let standardAnnual = 0.03
    private static var currentPeriodEnd: Date?

    /// Whether the scenario is on. It is off by default.
    public static var isEnabled: Bool {
        AppDefaults.store.bool(forKey: enabledKey)
    }

    /// Changes whenever a result of the scenario can change.
    public static var revision: Int {
        var hasher = Hasher()
        hasher.combine(isEnabled)
        hasher.combine(LinkTable.map(.etfReturn))
        hasher.combine(LinkTable.map(.etfOverride))
        hasher.combine(currentPeriodEnd)
        return hasher.finalize()
    }

    /// Remembers where the running period ends. Growth starts only after it.
    public static func noteCurrentPeriod(in periods: [ForecastPeriod], now: Date = FinanceClock.now) {
        currentPeriodEnd = periods.first { $0.contains(now) }?.end
    }

    /// Says whether a day belongs to a future forecast period.
    public static func applies(on day: Date, now: Date = FinanceClock.now) -> Bool {
        guard isEnabled else { return false }
        let calendar = Calendar.current
        let end = currentPeriodEnd ?? calendar.dateInterval(of: .month, for: now)?.end.addingTimeInterval(-1) ?? now
        return calendar.startOfDay(for: day) > calendar.startOfDay(for: end)
    }

    /// Returns the stored rate of an ISIN.
    public static func storedRate(for isin: String) -> ScenarioRate? {
        LinkTable.decoded(.etfReturn, as: ScenarioRate.self)[key(isin)]
    }

    /// Stores the rate of an ISIN.
    public static func store(_ rate: ScenarioRate, for isin: String) {
        guard let data = try? JSONEncoder().encode(rate) else { return }
        LinkTable.set(.etfReturn, key: key(isin), value: String(decoding: data, as: UTF8.self))
    }

    /// Returns the person's correction for an ISIN.
    public static func override(for isin: String) -> ETFOverride {
        LinkTable.map(.etfOverride)[key(isin)].flatMap(ETFOverride.init(rawValue:)) ?? .automatic
    }

    /// Stores the person's correction for an ISIN.
    public static func setOverride(_ value: ETFOverride, for isin: String) {
        LinkTable.set(.etfOverride, key: key(isin), value: value == .automatic ? nil : value.rawValue)
    }

    /// Says whether a position counts as an ETF.
    public static func isETF(_ holding: PortfolioHolding) -> Bool {
        switch override(for: holding.symbol) {
        case .etf: true
        case .other: false
        case .automatic: storedRate(for: holding.symbol)?.isETF ?? false
        }
    }

    /// The yearly return of a position, or `nil` when it does not grow in the scenario.
    public static func annualReturn(for holding: PortfolioHolding) -> Double? {
        guard isEnabled, isETF(holding) else { return nil }
        return storedRate(for: holding.symbol)?.annual ?? standardAnnual
    }

    /// Compounds monthly over the whole months between two days.
    ///
    /// - Parameters:
    ///   - annual: The yearly return.
    ///   - start: The first day.
    ///   - end: The last day.
    /// - Returns: The growth factor, at least 1 month apart or else 1.
    public nonisolated static func growth(annual: Double, from start: Date, to end: Date) -> Double {
        let months = Calendar.current.dateComponents([.month], from: start, to: end).month ?? 0
        guard months > 0, annual > -1 else { return 1 }
        return pow(1 + annual, Double(months) / 12)
    }

    /// Calculates the return from monthly prices: ten years, else five, else the standard.
    ///
    /// - Parameters:
    ///   - points: Monthly prices in ascending order.
    ///   - now: The current time.
    /// - Returns: The yearly return and its basis.
    public nonisolated static func historicReturn(points: [(date: Date, price: Double)], now: Date) -> (annual: Double, basis: ReturnBasis) {
        for (years, basis) in [(10, ReturnBasis.tenYears), (5, .fiveYears)] {
            if let annual = cagr(points: points, years: years, now: now) { return (annual, basis) }
        }
        return (standardAnnual, .standard)
    }

    /// The yearly growth since a price about the given number of years ago.
    private nonisolated static func cagr(points: [(date: Date, price: Double)], years: Int, now: Date) -> Double? {
        guard let target = Calendar.current.date(byAdding: .year, value: -years, to: now),
              let last = points.last, last.price > 0,
              let start = points.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }),
              abs(start.date.timeIntervalSince(target)) <= 45 * 86_400,
              start.price > 0
        else { return nil }
        let span = last.date.timeIntervalSince(start.date) / (365.25 * 86_400)
        guard span > 0 else { return nil }
        return pow(last.price / start.price, 1 / span) - 1
    }

    /// Normalizes an ISIN for storage.
    private static func key(_ isin: String) -> String {
        isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
