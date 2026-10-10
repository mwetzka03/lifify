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
