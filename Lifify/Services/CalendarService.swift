import Foundation

enum CalendarService {
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return value
    }

    static func dueDate(year: Int, month: Int, day: Int, rule: DueRule) -> Date {
        let range = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month))!)!
        switch rule {
        case .calendarDay:
            return calendar.date(from: DateComponents(year: year, month: month, day: min(max(day, 1), range.count)))!
        case .firstBusinessDay:
            var date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            while !isBankingDay(date) { date = calendar.date(byAdding: .day, value: 1, to: date)! }
            return date
        case .lastBusinessDay:
            var date = calendar.date(from: DateComponents(year: year, month: month, day: range.count))!
            while !isBankingDay(date) { date = calendar.date(byAdding: .day, value: -1, to: date)! }
            return date
        }
    }

    static func isBankingDay(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year else { return true }
        let fixed = [
            (1, 1), (5, 1), (10, 3), (11, 1), (12, 25), (12, 26)
        ]
        if fixed.contains(where: { $0.0 == components.month && $0.1 == components.day }) { return false }
        let easter = easterSunday(year: year)
        let movableOffsets = [-2, 1, 39, 50, 60]
        return !movableOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: easter) }
            .contains { calendar.isDate($0, inSameDayAs: date) }
    }

    static func periodKey(for date: Date, pool: BudgetPool) -> String {
        if pool.periodMode == .calendarYear {
            return String(calendar.component(.year, from: date))
        }
        let day = calendar.component(.day, from: date)
        var startComponents = calendar.dateComponents([.year, .month], from: date)
        if day < pool.salaryStartDay, let previous = calendar.date(byAdding: .month, value: -1, to: date) {
            startComponents = calendar.dateComponents([.year, .month], from: previous)
        }
        let monthSeed = calendar.date(from: startComponents)!
        let maxDay = calendar.range(of: .day, in: .month, for: monthSeed)!.count
        startComponents.day = min(pool.salaryStartDay, maxDay)
        let start = calendar.date(from: startComponents)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)!
        let end = calendar.date(byAdding: .day, value: -1, to: nextMonth)!
        return "\(start.dayKey):\(end.dayKey)"
    }

    static func nextOccurrences(
        firstDate: Date,
        cadence: Cadence,
        rule: DueRule,
        day: Int,
        endDate: Date?,
        through limit: Date
    ) -> [Date] {
        var result: [Date] = []
        var cursor = firstDate
        while cursor <= limit, endDate.map({ cursor <= $0 }) ?? true {
            if cadence == .monthly || cadence == .yearly {
                let parts = calendar.dateComponents([.year, .month], from: cursor)
                result.append(dueDate(year: parts.year!, month: parts.month!, day: day, rule: rule))
            } else {
                result.append(cursor)
            }
            let component: Calendar.Component = cadence == .yearly ? .year : (cadence == .monthly ? .month : .day)
            let value = cadence == .biweekly ? 14 : (cadence == .weekly ? 7 : 1)
            guard let next = calendar.date(byAdding: component, value: value, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func easterSunday(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
