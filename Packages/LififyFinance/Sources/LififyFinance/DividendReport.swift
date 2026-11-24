import Foundation
import LififyCore

/// The dividends of one position.
public struct DividendPosition: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let totalCents: Int
    public let lastYearCents: Int
    public let forecastCents: Int

    /// Creates a position's dividends.
    public init(id: String, name: String, totalCents: Int, lastYearCents: Int, forecastCents: Int) {
        self.id = id
        self.name = name
        self.totalCents = totalCents
        self.lastYearCents = lastYearCents
        self.forecastCents = forecastCents
    }
}

/// A sum of dividends in one month or year.
public struct DividendBucket: Identifiable, Equatable {
    /// `yyyy-MM` for a month, `yyyy` for a year.
    public let id: String
    public let date: Date
    public let cents: Int
}

/// Received dividends and the forecast of the next twelve months.
public struct DividendReport: Equatable {
    public var positions: [DividendPosition] = []
    public var months: [DividendBucket] = []
    public var years: [DividendBucket] = []
    public var forecastMonths: [DividendBucket] = []

    /// Creates a report.
    public init(
        positions: [DividendPosition] = [],
        months: [DividendBucket] = [],
        years: [DividendBucket] = [],
        forecastMonths: [DividendBucket] = []
    ) {
        self.positions = positions
        self.months = months
        self.years = years
        self.forecastMonths = forecastMonths
    }

    /// All received dividends.
    public var totalCents: Int { positions.reduce(0) { $0 + $1.totalCents } }
    /// The expected dividends of the next twelve months.
    public var forecastCents: Int { forecastMonths.reduce(0) { $0 + $1.cents } }

    /// The positions that still pay, so sold funds do not crowd the list.
    public var payingPositions: [DividendPosition] { positions.filter { $0.forecastCents > 0 } }
}

/// Builds the dividend overview from the existing income bookings.
@MainActor
public enum DividendReportBuilder {
    /// One received dividend, matched to its position when possible.
    private struct Payment {
        let date: Date
        let cents: Int
        let key: String
        let name: String
        let holding: PortfolioHolding?
    }

    /// Builds the report.
    ///
    /// The forecast repeats each payment of the last twelve months one year later. It uses the
    /// dividend per share of that payment and the shares held then, including future savings plans.
    ///
    /// - Parameters:
    ///   - entries: All bookings.
    ///   - holdings: The open depot positions.
    ///   - now: The current time.
    /// - Returns: Received dividends by position, month, and year, with the forecast.
    public static func make(
        entries: [LedgerEntry],
        holdings: [PortfolioHolding],
        now: Date = FinanceClock.now
    ) -> DividendReport {
        let payments = entries
            .filter { BookingClassification.category(of: $0, accounts: [], viewedAccountID: nil) == .dividend }
            .map { payment(for: $0, holdings: holdings) }
        let calendar = Calendar.current
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let recent = payments.filter { $0.date > yearAgo && $0.date <= now }
        let projected = recent.compactMap { projection(of: $0, holdings: holdings, calendar: calendar) }
        return DividendReport(
            positions: positions(payments, recent: recent, projected: projected),
            months: buckets(payments.map { ($0.date, $0.cents) }, format: "yyyy-MM", calendar: calendar).reversed(),
            years: buckets(payments.map { ($0.date, $0.cents) }, format: "yyyy", calendar: calendar).reversed(),
            forecastMonths: buckets(projected.map { ($0.date, $0.cents) }, format: "yyyy-MM", calendar: calendar)
        )
    }

    /// Matches a booking to a position by ISIN, then by name.
    private static func payment(for entry: LedgerEntry, holdings: [PortfolioHolding]) -> Payment {
        let text = normalized("\(entry.title) \(entry.notes)")
        let match = holdings.first { !$0.symbol.isEmpty && text.contains(normalized($0.symbol)) }
            ?? holdings.first { !$0.name.isEmpty && text.contains(normalized($0.name)) }
        let name = match?.name ?? entry.title
        return Payment(
            date: entry.date,
            cents: abs(entry.amountCents),
            key: match?.id.uuidString ?? normalized(entry.title),
            name: name,
            holding: match
        )
    }

    /// Repeats a payment one year later for the shares held then.
    private static func projection(
        of payment: Payment,
        holdings: [PortfolioHolding],
        calendar: Calendar
    ) -> (key: String, date: Date, cents: Int)? {
        guard let holding = payment.holding,
              let next = calendar.date(byAdding: .year, value: 1, to: payment.date)
        else { return nil }
        let then = HoldingMaintenance.quantity(of: holding, through: payment.date, holdings: holdings)
        guard then > 0.0000005 else { return nil }
        let future = HoldingMaintenance.quantity(of: holding, through: next, holdings: holdings)
        let cents = Int((Double(payment.cents) / then * future).rounded())
        return cents > 0 ? (payment.key, next, cents) : nil
    }

    /// Sums the payments per position, largest first.
    private static func positions(
        _ payments: [Payment],
        recent: [Payment],
        projected: [(key: String, date: Date, cents: Int)]
    ) -> [DividendPosition] {
        Dictionary(grouping: payments, by: \.key).map { key, rows in
            DividendPosition(
                id: key,
                name: rows.first?.name ?? key,
                totalCents: rows.reduce(0) { $0 + $1.cents },
                lastYearCents: recent.filter { $0.key == key }.reduce(0) { $0 + $1.cents },
                forecastCents: projected.filter { $0.key == key }.reduce(0) { $0 + $1.cents }
            )
        }
        .sorted { $0.totalCents != $1.totalCents ? $0.totalCents > $1.totalCents : $0.name < $1.name }
    }

    /// Sums amounts per calendar month or year, oldest first.
    private static func buckets(_ rows: [(date: Date, cents: Int)], format: String, calendar: Calendar) -> [DividendBucket] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return Dictionary(grouping: rows) { formatter.string(from: $0.date) }
            .map { key, values in
                DividendBucket(id: key, date: values.map(\.date).min() ?? .distantPast, cents: values.reduce(0) { $0 + $1.cents })
            }
            .sorted { $0.id < $1.id }
    }

    /// Reduces a text for comparison.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { $0.isLetter || $0.isNumber }
    }
}
