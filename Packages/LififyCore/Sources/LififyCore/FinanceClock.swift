import Foundation

/// The current time for finance calculations. Reference tests fix it, so results stay comparable.
public enum FinanceClock {
    nonisolated(unsafe) private static var fixed: Date?

    /// The fixed test time, or the real time.
    public static var now: Date { fixed ?? Date() }

    /// Fixes the time, or returns to the real clock when passed `nil`.
    public static func fix(_ date: Date?) {
        fixed = date
    }
}
