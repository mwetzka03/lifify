import Foundation
import LififyCore
import Observation
import SwiftData

/// A choice in one of the depot's segmented controls, stored by its raw value.
public protocol PortfolioOption: RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    /// The text shown in the control.
    var label: String { get }
}

/// Default behavior of depot options.
public extension PortfolioOption {
    /// The raw value identifies the option.
    var id: String { rawValue }
}

/// Which gain the depot shows.
public enum PortfolioBasis: String, PortfolioOption {
    case today
    case purchase

    /// The text shown in the control.
    public var label: String {
        switch self {
        case .today: L("Heute", "Today")
        case .purchase: L("Seit Kauf", "Since purchase")
        }
    }
}

/// How the depot orders its positions.
public enum PortfolioSort: String, PortfolioOption {
    case value
    case purchase
    case name

    /// The text shown in the control.
    public var label: String {
        switch self {
        case .value: L("Wert", "Value")
        case .purchase: L("Kauf", "Purchase")
        case .name: "A–Z"
        }
    }
}

/// Whether gains appear in percent or euros.
public enum PortfolioUnit: String, PortfolioOption {
    case percent
    case eur

    /// The text shown in the control.
    public var label: String {
        switch self {
        case .percent: "%"
        case .eur: "€"
        }
    }
}

/// Day and purchase gains of one position or a sum of positions.
public struct HoldingPerformance {
    public var value = 0
    public var dayCents: Int?
    public var dayBase = 0
    public var purchaseCents = 0
    public var purchaseBase = 0

    /// Creates a performance from its parts. The default is an empty sum.
    public init(value: Int = 0, dayCents: Int? = nil, dayBase: Int = 0, purchaseCents: Int = 0, purchaseBase: Int = 0) {
        self.value = value
        self.dayCents = dayCents
        self.dayBase = dayBase
        self.purchaseCents = purchaseCents
        self.purchaseBase = purchaseBase
    }

    /// The day gain as a ratio, when a previous close exists.
    public var dayPercent: Double? {
        guard dayCents != nil, dayBase > 0 else { return nil }
        return Double(dayCents ?? 0) / Double(dayBase)
    }

    /// The gain since purchase as a ratio.
    public var purchasePercent: Double? {
        guard purchaseBase > 0 else { return nil }
        return Double(purchaseCents) / Double(purchaseBase)
    }

    /// Adds another performance. The day gain stays empty only when both are empty.
    public func adding(_ other: HoldingPerformance) -> HoldingPerformance {
        HoldingPerformance(
            value: value + other.value,
            dayCents: dayCents == nil && other.dayCents == nil ? nil : (dayCents ?? 0) + (other.dayCents ?? 0),
            dayBase: dayBase + other.dayBase,
            purchaseCents: purchaseCents + other.purchaseCents,
            purchaseBase: purchaseBase + other.purchaseBase
        )
    }

    /// Formats the gain for the selected basis and unit.
    ///
    /// - Parameters:
    ///   - basis: The raw value of a ``PortfolioBasis``.
    ///   - unit: The raw value of a ``PortfolioUnit``.
    /// - Returns: The text and the signed cents that decide its color.
    public func selected(basis: String, unit: String) -> (text: String, cents: Int) {
        let useEuro = unit == PortfolioUnit.eur.rawValue
        guard basis != PortfolioBasis.purchase.rawValue else {
            if useEuro { return (signedMoney(purchaseCents), purchaseCents) }
            guard let percent = purchasePercent else { return (signedMoney(purchaseCents), purchaseCents) }
            return (signedPercent(percent), purchaseCents)
        }
        guard let cents = dayCents else {
            return (L("Kein Vortageskurs", "No previous close"), 0)
        }
        if useEuro { return (signedMoney(cents), cents) }
        guard let percent = dayPercent else {
            return (L("Kein Vortageskurs", "No previous close"), cents)
        }
        return (signedPercent(percent), cents)
    }

    /// Formats cents with a plus sign for gains.
    private func signedMoney(_ cents: Int) -> String {
        cents > 0 ? "+\(Money.string(cents: cents))" : Money.string(cents: cents)
    }

    /// Formats a ratio as a signed percentage with two decimals.
    private func signedPercent(_ ratio: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = formatter.plusSign
        return formatter.string(from: NSNumber(value: ratio)) ?? "0 %"
    }
}

/// Calculates the current performance of one position from its stored prices.
@MainActor
public func holdingPerformance(_ holding: PortfolioHolding) -> HoldingPerformance {
    let value = Int((holding.quantity * Double(holding.currentPriceCents)).rounded())
    let purchaseValue = Int((holding.quantity * Double(holding.purchasePriceCents)).rounded())
    var performance = HoldingPerformance(
        value: value,
        purchaseCents: value - purchaseValue,
        purchaseBase: purchaseValue
    )
    if let previous = PreviousCloseStore.cents(for: holding.id), previous > 0 {
        let base = Int((holding.quantity * Double(previous)).rounded())
        performance.dayCents = value - base
        performance.dayBase = base
    }
    return performance
}

/// One open position with everything its row shows.
public struct PortfolioRow: Identifiable {
    public let holding: PortfolioHolding
    public let quantity: Double
    public let valueCents: Int
    public let shownPriceCents: Int
    public let performance: HoldingPerformance

    /// The position's identifier.
    public var id: UUID { holding.id }
}

/// The calculated content of a depot screen.
public struct PortfolioSnapshot {
    public var rows: [PortfolioRow] = []
    public var totals = HoldingPerformance()
    public var marketValueCents = 0
    /// Whether the shown value contains the return scenario.
    public var usesScenario = false
}

/// Holds the depot calculations and repeats them only when an input changed.
///
/// `@Query` works only inside views, so the views keep their queries and pass the results
/// in. The stored result is deliberately not observed: asking for it during `body` must
/// not trigger another render.
@MainActor
@Observable
public final class PortfolioScreenModel {
    /// The inputs a snapshot depends on.
    private struct Key: Equatable {
        /// The values of one position that affect the result.
        struct Position: Equatable {
            let id: UUID
            let name: String
            let quantity: Double
            let purchasePriceCents: Int
            let currentPriceCents: Int
        }

        let positions: [Position]
        let day: Date
        let today: Date
        let sort: PortfolioSort
        let lotRevision: Int
        let planRevision: Int
        let priceRevision: Int
        let marketRevision: Int
        let scenarioRevision: Int
    }

    @ObservationIgnored private var key: Key?
    @ObservationIgnored private var stored = PortfolioSnapshot()

    /// Creates an empty model.
    public init() {}

    /// Returns the depot content, reusing the last result while no input changed.
    ///
    /// - Parameters:
    ///   - holdings: The positions in scope.
    ///   - day: The day whose share counts and prices apply.
    ///   - sort: The raw value of a ``PortfolioSort``.
    /// - Returns: Sorted open positions, their totals, and the market value.
    public func snapshot(holdings: [PortfolioHolding], through day: Date, sort: String) -> PortfolioSnapshot {
        let order = PortfolioSort(rawValue: sort) ?? .value
        let current = makeKey(holdings: holdings, day: day, sort: order)
        if key == current { return stored }
        let rows = holdings.compactMap { row(for: $0, through: day, holdings: holdings) }
        stored = PortfolioSnapshot(
            rows: Self.sorted(rows, by: order),
            totals: rows.reduce(HoldingPerformance()) { $0.adding($1.performance) },
            marketValueCents: HoldingMaintenance.marketValue(of: holdings, through: day),
            usesScenario: ReturnScenario.applies(on: day) && holdings.contains { ReturnScenario.isETF($0) }
        )
        key = current
        return stored
    }

    /// Captures every input of a calculation.
    private func makeKey(holdings: [PortfolioHolding], day: Date, sort: PortfolioSort) -> Key {
        let calendar = Calendar.current
        return Key(
            positions: holdings.map {
                Key.Position(
                    id: $0.id,
                    name: $0.name,
                    quantity: $0.quantity,
                    purchasePriceCents: $0.purchasePriceCents,
                    currentPriceCents: $0.currentPriceCents
                )
            },
            day: calendar.startOfDay(for: day),
            today: calendar.startOfDay(for: FinanceClock.now),
            sort: sort,
            lotRevision: HoldingLotStore.cacheRevision,
            planRevision: SavingsPlanStore.cacheRevision,
            priceRevision: HistoricalPriceStore.cacheRevision,
            marketRevision: HoldingMarketStore.cacheRevision,
            scenarioRevision: ReturnScenario.revision
        )
    }

    /// Builds the row of a position, or `nil` when no shares are held on that day.
    private func row(for holding: PortfolioHolding, through day: Date, holdings: [PortfolioHolding]) -> PortfolioRow? {
        let quantity = HoldingMaintenance.quantity(of: holding, through: day, holdings: holdings)
        guard quantity > 0.0000005 else { return nil }
        let value = HoldingMaintenance.marketValue(of: holding, through: day, holdings: holdings)
        return PortfolioRow(
            holding: holding,
            quantity: quantity,
            valueCents: value,
            shownPriceCents: Int((Double(value) / quantity).rounded()),
            performance: holdingPerformance(holding)
        )
    }

    /// Orders rows by value, newest purchase, or name.
    private static func sorted(_ rows: [PortfolioRow], by order: PortfolioSort) -> [PortfolioRow] {
        switch order {
        case .value:
            return rows.sorted { $0.valueCents > $1.valueCents }
        case .purchase:
            return rows.sorted { lhs, rhs in
                let left = HoldingPurchaseDateStore.date(for: lhs.id) ?? .distantPast
                let right = HoldingPurchaseDateStore.date(for: rhs.id) ?? .distantPast
                if left != right { return left > right }
                return lhs.holding.name.localizedCaseInsensitiveCompare(rhs.holding.name) == .orderedAscending
            }
        case .name:
            return rows.sorted {
                $0.holding.name.localizedCaseInsensitiveCompare($1.holding.name) == .orderedAscending
            }
        }
    }
}

/// Depot helpers of the finance filter.
public extension FinanceFilterStore {
    /// The end of the selected finance period, or now when none is selected.
    func projectionDay(entries: [LedgerEntry], forecasts: [IncomeForecast], accounts: [Account]) -> Date {
        period(in: FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts))?.end ?? FinanceClock.now
    }
}

/// Removal and repair helpers for positions.
public extension HoldingMaintenance {
    /// Deletes a position with its lots and market values. Its stored price history stays.
    static func deletePosition(_ holding: PortfolioHolding, context: ModelContext) {
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
        HoldingLotStore.removeAll(for: holding.id)
        context.delete(holding)
        try? context.save()
    }

    /// Gives positions without a purchase date their last update as that date.
    static func backfillPurchaseDates(_ holdings: [PortfolioHolding]) {
        for holding in holdings where HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(holding.updatedAt, for: holding.id)
        }
    }
}
