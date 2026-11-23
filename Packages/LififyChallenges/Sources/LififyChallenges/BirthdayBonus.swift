import Foundation
import LififyCore
import SwiftData

/// A birthday as a plain calendar date.
public struct Birthday: Equatable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// Whether a stored birthday pays 500 coins on a given day. No stored data is read or written.
public enum BirthdayBonus {
    public static let coins = 500

    /// A 29 February birthday is observed on 28 February when that year has no 29 February.
    public static func observed(birth: Birthday, in year: Int, calendar: Calendar) -> Date? {
        if let exact = exactDay(year: year, month: birth.month, day: birth.day, calendar: calendar) {
            return exact
        }
        guard birth.month == 2, birth.day == 29 else { return nil }
        return exactDay(year: year, month: 2, day: 28, calendar: calendar)
    }

    /// Says whether the day is the birthday.
    public static func isBirthday(_ birth: Birthday, on day: Date, calendar: Calendar = .current) -> Bool {
        isDue(birth: birth, on: day, awardedYear: nil, calendar: calendar)
    }

    /// True only on the observed birthday, not before the actual date of birth, and once per year.
    public static func isDue(birth: Birthday, on day: Date, awardedYear: Int?, calendar: Calendar = .current) -> Bool {
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

    /// A stable reference that keeps one bonus per year.
    public static func referenceID(year: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", year)) ?? UUID()
    }
}

/// The stored birthday and the last year it paid a bonus.
public enum UserProfile {
    public static let birthKey = "userBirthDate"
    public static let awardedYearKey = "lifify.birthdayAwardedYear"

    /// Returns the stored birthday.
    public static func birth(defaults: UserDefaults = AppDefaults.store) -> Birthday? {
        parse(defaults.string(forKey: birthKey) ?? "")
    }

    /// Returns the birthday as a date.
    public static func birthDate(calendar: Calendar = .current, defaults: UserDefaults = AppDefaults.store) -> Date? {
        guard let birth = birth(defaults: defaults) else { return nil }
        return calendar.date(from: DateComponents(year: birth.year, month: birth.month, day: birth.day))
    }

    /// Suggests a starting date for the birthday picker.
    public static func suggestedDate(calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: Date()) - 25
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
    }

    /// Stores the birthday. A future date is limited to today.
    public static func setBirthDate(_ date: Date, calendar: Calendar = .current, defaults: UserDefaults = AppDefaults.store) {
        let today = calendar.startOfDay(for: Date())
        let chosen = min(calendar.startOfDay(for: date), today)
        let parts = calendar.dateComponents([.year, .month, .day], from: chosen)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        defaults.set(raw(Birthday(year: year, month: month, day: day)), forKey: birthKey)
    }

    /// Returns the stored text.
    public static func birthRaw(defaults: UserDefaults = AppDefaults.store) -> String {
        defaults.string(forKey: birthKey) ?? ""
    }

    /// Returns the last paid year.
    public static func awardedYear(defaults: UserDefaults = AppDefaults.store) -> Int? {
        let year = defaults.integer(forKey: awardedYearKey)
        return year > 0 ? year : nil
    }

    /// Returns the last paid year as text.
    public static func awardedYearRaw(defaults: UserDefaults = AppDefaults.store) -> String {
        guard let year = awardedYear(defaults: defaults) else { return "" }
        return String(year)
    }

    /// Stores the last paid year.
    public static func setAwardedYear(_ year: Int, defaults: UserDefaults = AppDefaults.store) {
        defaults.set(year, forKey: awardedYearKey)
    }

    /// Puts the last awarded birthday year back, or clears it.
    public static func restoreAwardedYear(_ year: Int?, defaults: UserDefaults = AppDefaults.store) {
        if let year {
            defaults.set(year, forKey: awardedYearKey)
        } else {
            defaults.removeObject(forKey: awardedYearKey)
        }
    }

    /// Restores both values from a backup.
    public static func restore(birthRaw: String, awardedYearRaw: String, defaults: UserDefaults = AppDefaults.store) {
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

    /// Removes both values.
    public static func reset(defaults: UserDefaults = AppDefaults.store) {
        defaults.removeObject(forKey: birthKey)
        defaults.removeObject(forKey: awardedYearKey)
    }

    /// Parses a stored birthday.
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

    /// Formats a birthday for storage.
    private static func raw(_ birth: Birthday) -> String {
        String(format: "%04d-%02d-%02d", birth.year, birth.month, birth.day)
    }
}

/// Pays the yearly birthday bonus.
@MainActor
public enum BirthdayBonusService {
    /// Pays the bonus once when it is due and announces it.
    public static func settle(context: ModelContext, now: Date = AppClock.now, calendar: Calendar = .current) {
        guard let birth = UserProfile.birth() else { return }
        guard BirthdayBonus.isDue(birth: birth, on: now, awardedYear: UserProfile.awardedYear(), calendar: calendar) else { return }
        let year = calendar.component(.year, from: now)
        let reference = BirthdayBonus.referenceID(year: year)
        let existing = (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []
        if existing.contains(where: { $0.referenceID == reference }) {
            UserProfile.setAwardedYear(year)
            return
        }
        SimulatedDayLedger.record(.birthday(
            previousYear: UserProfile.awardedYear(),
            notificationID: "\(ChallengeNudgePlan.birthdayPrefix)\(year)"
        ))
        SimulatedDayLedger.book(CoinTransaction(
            date: now,
            title: L("Geburtstag", "Birthday"),
            amount: BirthdayBonus.coins,
            referenceID: reference
        ), in: context)
        UserProfile.setAwardedYear(year)
        try? context.save()
        Task {
            await LififyNotifications.announceBonus(
                id: "\(ChallengeNudgePlan.birthdayPrefix)\(year)",
                title: BirthdayCheer.title(),
                body: BirthdayCheer.body(),
                due: now
            )
        }
    }
}
