import Foundation
import SwiftData

struct Birthday: Equatable {
    var year: Int
    var month: Int
    var day: Int
}

/// Whether a stored birthday pays 500 coins on a given day. No stored data is read or written.
enum BirthdayBonus {
    static let coins = 500

    /// A 29 February birthday is observed on 28 February when that year has no 29 February.
    static func observed(birth: Birthday, in year: Int, calendar: Calendar) -> Date? {
        if let exact = exactDay(year: year, month: birth.month, day: birth.day, calendar: calendar) {
            return exact
        }
        guard birth.month == 2, birth.day == 29 else { return nil }
        return exactDay(year: year, month: 2, day: 28, calendar: calendar)
    }

    static func isBirthday(_ birth: Birthday, on day: Date, calendar: Calendar = .current) -> Bool {
        isDue(birth: birth, on: day, awardedYear: nil, calendar: calendar)
    }

    /// True only on the observed birthday, not before the actual date of birth, and once per year.
    static func isDue(birth: Birthday, on day: Date, awardedYear: Int?, calendar: Calendar = .current) -> Bool {
        guard let born = exactDay(year: birth.year, month: birth.month, day: birth.day, calendar: calendar) else {
            return false
        }
        let today = calendar.startOfDay(for: day)
        guard today >= born else { return false }
        let year = calendar.component(.year, from: today)
        guard awardedYear != year else { return false }
        guard let observed = observed(birth: birth, in: year, calendar: calendar) else { return false }
        return calendar.isDate(observed, inSameDayAs: today)
    }

    /// A real calendar day. A lenient calendar that rolls 29 February into March does not count.
    private static func exactDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func referenceID(year: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", year)) ?? UUID()
    }
}

enum UserProfile {
    static let birthKey = "userBirthDate"
    static let awardedYearKey = "lifify.birthdayAwardedYear"

    static func birth(defaults: UserDefaults = .standard) -> Birthday? {
        parse(defaults.string(forKey: birthKey) ?? "")
    }

    static func birthDate(calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Date? {
        guard let birth = birth(defaults: defaults) else { return nil }
        return calendar.date(from: DateComponents(year: birth.year, month: birth.month, day: birth.day))
    }

    static func suggestedDate(calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: Date()) - 25
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
    }

    static func setBirthDate(_ date: Date, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        let today = calendar.startOfDay(for: Date())
        let chosen = min(calendar.startOfDay(for: date), today)
        let parts = calendar.dateComponents([.year, .month, .day], from: chosen)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        defaults.set(raw(Birthday(year: year, month: month, day: day)), forKey: birthKey)
    }

    static func birthRaw(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: birthKey) ?? ""
    }

    static func awardedYear(defaults: UserDefaults = .standard) -> Int? {
        let year = defaults.integer(forKey: awardedYearKey)
        return year > 0 ? year : nil
    }

    static func awardedYearRaw(defaults: UserDefaults = .standard) -> String {
        guard let year = awardedYear(defaults: defaults) else { return "" }
        return String(year)
    }

    static func setAwardedYear(_ year: Int, defaults: UserDefaults = .standard) {
        defaults.set(year, forKey: awardedYearKey)
    }

    static func restore(birthRaw: String, awardedYearRaw: String, defaults: UserDefaults = .standard) {
        if let birth = parse(birthRaw) {
            defaults.set(raw(birth), forKey: birthKey)
        } else {
            defaults.removeObject(forKey: birthKey)
        }
        if let year = Int(awardedYearRaw), year > 0 {
            defaults.set(year, forKey: awardedYearKey)
        } else {
            defaults.removeObject(forKey: awardedYearKey)
        }
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: birthKey)
        defaults.removeObject(forKey: awardedYearKey)
    }

    private static func parse(_ raw: String) -> Birthday? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 0,
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }
        return Birthday(year: year, month: month, day: day)
    }

    private static func raw(_ birth: Birthday) -> String {
        String(format: "%04d-%02d-%02d", birth.year, birth.month, birth.day)
    }
}

@MainActor
enum BirthdayBonusService {
    static func settle(context: ModelContext, now: Date = AppClock.now, calendar: Calendar = .current) {
        guard let birth = UserProfile.birth() else { return }
        guard BirthdayBonus.isDue(birth: birth, on: now, awardedYear: UserProfile.awardedYear(), calendar: calendar) else { return }
        let year = calendar.component(.year, from: now)
        let reference = BirthdayBonus.referenceID(year: year)
        let existing = (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []
        if existing.contains(where: { $0.referenceID == reference }) {
            UserProfile.setAwardedYear(year)
            return
        }
        context.insert(CoinTransaction(
            date: now,
            title: L("Geburtstag", "Birthday"),
            amount: BirthdayBonus.coins,
            referenceID: reference
        ))
        UserProfile.setAwardedYear(year)
        try? context.save()
    }
}
