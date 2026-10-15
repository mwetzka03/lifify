import Foundation

func L(_ german: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "appLanguage") == "en" ? english : german
}

enum Money {
    static func string(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(Double(cents) / 100)"
    }

    static func signed(cents: Int) -> String {
        cents > 0 ? "+\(string(cents: cents))" : string(cents: cents)
    }

    static func cents(from text: String) -> Int? {
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

enum AppDate {
    static var isGerman: Bool {
        UserDefaults.standard.string(forKey: "appLanguage") != "en"
    }

    static var locale: Locale {
        Locale(identifier: isGerman ? "de_DE" : "en_US")
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func numeric(_ date: Date) -> String {
        string(date, format: isGerman ? "dd.MM.yyyy" : "MMM d, yyyy")
    }

    static func day(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    static func numericShort(_ date: Date) -> String {
        string(date, format: isGerman ? "dd.MM." : "MMM d")
    }

    static func weekdayWide(_ date: Date) -> String {
        string(date, format: "EEEE")
    }

    static func weekdayShort(_ date: Date) -> String {
        string(date, format: "EEE")
    }

    static func weekdayAndNumeric(_ date: Date) -> String {
        isGerman ? "\(weekdayWide(date)), \(numeric(date))" : string(date, format: "EEEE, MMM d, yyyy")
    }

    static func monthYear(_ date: Date) -> String {
        string(date, format: "MMMM yyyy")
    }

    static func dayMonth(_ date: Date) -> String {
        isGerman ? numericShort(date) : string(date, format: "MMM d")
    }

    static func range(from start: Date, to end: Date) -> String {
        "\(numeric(start)) – \(numeric(end))"
    }

    static func time(_ date: Date) -> String {
        string(date, format: "HH:mm")
    }

    static var veryShortWeekdaysMondayFirst: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...]) + [symbols[0]]
    }
}

extension Date {
    var monthKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: self)
    }

    var dayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
