import Foundation

/// Returns the text in the language chosen in the app.
public func L(_ german: String, _ english: String) -> String {
    AppDefaults.store.string(forKey: "appLanguage") == "en" ? english : german
}

/// Formats and parses amounts stored as whole cents.
public enum Money {
    /// Formats cents as a euro amount.
    public static func string(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(Double(cents) / 100)"
    }

    /// Formats cents with a plus sign for positive amounts.
    public static func signed(cents: Int) -> String {
        cents > 0 ? "+\(string(cents: cents))" : string(cents: cents)
    }

    /// Parses a typed amount. The last comma or dot is the decimal separator.
    ///
    /// - Parameter text: The input, with or without a euro sign.
    /// - Returns: The amount in cents, or `nil` when it is not a number.
    public static func cents(from text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
        let comma = cleaned.lastIndex(of: ",")
        let dot = cleaned.lastIndex(of: ".")
        let decimalSeparator: String.Index?
        if let comma, let dot {
            decimalSeparator = max(comma, dot)
        } else {
            decimalSeparator = comma ?? dot
        }
        let normalized: String
        if let decimalSeparator {
            let whole = cleaned[..<decimalSeparator].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            let fraction = cleaned[cleaned.index(after: decimalSeparator)...]
            normalized = "\(whole).\(fraction)"
        } else {
            normalized = cleaned
        }
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}

/// Formats dates in the app's language.
public enum AppDate {
    public static var isGerman: Bool {
        AppDefaults.store.string(forKey: "appLanguage") != "en"
    }

    public static var locale: Locale {
        Locale(identifier: isGerman ? "de_DE" : "en_US")
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// Formats a date with a custom pattern.
    public static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// The full numeric date.
    public static func numeric(_ date: Date) -> String {
        string(date, format: isGerman ? "dd.MM.yyyy" : "MMM d, yyyy")
    }

    /// The day of the month.
    public static func day(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    /// The date without a year.
    public static func numericShort(_ date: Date) -> String {
        string(date, format: isGerman ? "dd.MM." : "MMM d")
    }

    /// The full weekday name.
    public static func weekdayWide(_ date: Date) -> String {
        string(date, format: "EEEE")
    }

    /// The short weekday name.
    public static func weekdayShort(_ date: Date) -> String {
        string(date, format: "EEE")
    }

    /// The weekday with the date.
    public static func weekdayAndNumeric(_ date: Date) -> String {
        isGerman ? "\(weekdayWide(date)), \(numeric(date))" : string(date, format: "EEEE, MMM d, yyyy")
    }

    /// The month and year.
    public static func monthYear(_ date: Date) -> String {
        string(date, format: "MMMM yyyy")
    }

    /// The day and month.
    public static func dayMonth(_ date: Date) -> String {
        isGerman ? numericShort(date) : string(date, format: "MMM d")
    }

    /// A date range.
    public static func range(from start: Date, to end: Date) -> String {
        "\(numeric(start)) – \(numeric(end))"
    }

    /// The time in 24-hour format.
    public static func time(_ date: Date) -> String {
        string(date, format: "HH:mm")
    }

    public static var veryShortWeekdaysMondayFirst: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...]) + [symbols[0]]
    }
}

/// Date helpers for storage keys.
extension Date {
    public var monthKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: self)
    }

    public var dayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
