import Foundation
import LififyCore

/// The forecast interest on the cash account that belongs to the depot, such as Trade Republic.
///
/// It is a switch in Settings, Finance, Portfolio, off by default, with a yearly rate that starts
/// at 2.5 %. Booked interest stays as it is; this only adds the expected payments after today.
@MainActor
public enum CashInterest {
    public nonisolated static let enabledKey = "lifify.cashInterestEnabled"
    public nonisolated static let rateKey = "lifify.cashInterestRate"
    /// The rate used until the person sets one.
    public nonisolated static let standardPercent = 2.5

    /// Whether the forecast counts interest.
    public static var isEnabled: Bool {
        AppDefaults.store.bool(forKey: enabledKey)
    }

    /// The yearly rate in percent.
    public static var annualPercent: Double {
        let stored = AppDefaults.store.double(forKey: rateKey)
        return stored > 0 ? stored : standardPercent
    }

    /// The account that earns the interest: the checking account for trades, else Trade Republic.
    public static func accountID(in accounts: [Account]) -> UUID? {
        if let chosen = TradeAccountPreference.accountID(), accounts.contains(where: { $0.id == chosen }) {
            return chosen
        }
        return accounts.first { $0.kind == .checking && $0.name.localizedCaseInsensitiveContains("trade republic") }?.id
    }

    /// The month ends from today's month through a day, each with the payout on the next first.
    ///
    /// - Parameters:
    ///   - now: The current time.
    ///   - end: The last payout day needed.
    ///   - calendar: The calendar of the days.
    /// - Returns: Pairs of month end and payout day, payouts after now only.
    public static func payouts(after now: Date, through end: Date, calendar: Calendar = .current) -> [(monthEnd: Date, payout: Date)] {
        var result: [(Date, Date)] = []
        var month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        while true {
            guard let next = calendar.date(byAdding: .month, value: 1, to: month),
                  let monthEnd = calendar.date(byAdding: .day, value: -1, to: next) else { break }
            if next > end { break }
            if next > now { result.append((monthEnd, next)) }
            month = next
        }
        return result
    }

    /// One month's interest on a balance, never negative.
    public static func monthlyCents(on balance: Int, percent: Double) -> Int {
        guard balance > 0, percent > 0 else { return 0 }
        return Int((Double(balance) * percent / 100 / 12).rounded())
    }
}
