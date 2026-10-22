import Foundation

@MainActor
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

    static func periodKeys(from startDate: Date, through endDate: Date, pool: BudgetPool) -> [String] {
        var result: [String] = []
        var cursor = startDate
        let component: Calendar.Component = pool.periodMode == .calendarYear ? .year : .month
        while cursor <= endDate {
            let key = periodKey(for: cursor, pool: pool)
            if result.last != key { result.append(key) }
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        let finalKey = periodKey(for: endDate, pool: pool)
        if result.last != finalKey { result.append(finalKey) }
        return result
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
        var iterations = 0
        while cursor <= limit, endDate.map({ cursor <= $0 }) ?? true, iterations < 2_400 {
            iterations += 1
            if cadence == .monthly || cadence == .yearly {
                let parts = calendar.dateComponents([.year, .month], from: cursor)
                guard let year = parts.year, let month = parts.month else { break }
                result.append(dueDate(year: year, month: month, day: day, rule: rule))
            } else {
                result.append(cursor)
            }
            let component: Calendar.Component = cadence == .yearly ? .year : (cadence == .monthly ? .month : .day)
            let value = cadence == .biweekly ? 14 : (cadence == .weekly ? 7 : 1)
            guard let next = calendar.date(byAdding: component, value: value, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }

    /// Trade Republic debits savings plans on the 2nd, 9th, 16th and 23rd.
    /// Weekly uses all four days, biweekly the 2nd and 16th, monthly and yearly the 2nd.
    static func chargeDays(for cadence: Cadence) -> [Int] {
        switch cadence {
        case .weekly: return [2, 9, 16, 23]
        case .biweekly: return [2, 16]
        case .monthly, .yearly: return [2]
        }
    }

    static func nextBankingDay(onOrAfter date: Date) -> Date {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<14 {
            if isBankingDay(cursor) { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return cursor }
            cursor = next
        }
        return cursor
    }

    static func savingsPlanDates(
        cadence: Cadence,
        from: Date,
        through: Date,
        endDate: Date? = nil,
        yearlyMonth: Int? = nil
    ) -> [Date] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        let cappedEnd = endDate.map { min(end, calendar.startOfDay(for: $0)) } ?? end
        guard start <= cappedEnd else { return [] }
        let days = chargeDays(for: cadence)
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        var result: [Date] = []
        var seen = Set<String>()
        while cursor <= cappedEnd {
            let parts = calendar.dateComponents([.year, .month], from: cursor)
            let month = parts.month ?? 1
            let includeMonth = cadence != .yearly || month == (yearlyMonth ?? month)
            if includeMonth, let year = parts.year {
                for day in days {
                    guard let nominal = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                    let actual = nextBankingDay(onOrAfter: nominal)
                    guard actual >= start, actual <= cappedEnd, seen.insert(actual.dayKey).inserted else { continue }
                    result.append(actual)
                }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result.sorted()
    }

    static func nextSavingsPlanDate(cadence: Cadence, onOrAfter date: Date, yearlyMonth: Int? = nil) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 2, to: date) ?? date
        return savingsPlanDates(
            cadence: cadence,
            from: date,
            through: horizon,
            yearlyMonth: yearlyMonth
        ).first
    }

    static func savingsPlanScheduleText(cadence: Cadence) -> String {
        switch cadence {
        case .weekly:
            return L(
                "Abbuchung am 2., 9., 16. und 23. Ist das kein Bankarbeitstag, gilt der nächste.",
                "Debited on the 2nd, 9th, 16th and 23rd. If that is not a banking day, the next one is used."
            )
        case .biweekly:
            return L(
                "Abbuchung am 2. und 16. Ist das kein Bankarbeitstag, gilt der nächste.",
                "Debited on the 2nd and 16th. If that is not a banking day, the next one is used."
            )
        case .monthly:
            return L(
                "Abbuchung am 2. Ist das kein Bankarbeitstag, gilt der nächste.",
                "Debited on the 2nd. If that is not a banking day, the next one is used."
            )
        case .yearly:
            return L(
                "Abbuchung einmal im Jahr am 2. Ist das kein Bankarbeitstag, gilt der nächste.",
                "Debited once a year on the 2nd. If that is not a banking day, the next one is used."
            )
        }
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
