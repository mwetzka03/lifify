import Foundation
import SwiftData

@MainActor
enum ChallengeService {
    static func isDue(_ challenge: ChallengeItem, on date: Date) -> Bool {
        guard !challenge.isArchived else { return false }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if let start = challenge.startDate, day < calendar.startOfDay(for: start) { return false }
        if let end = challenge.endDate, day > calendar.startOfDay(for: end) { return false }
        let interval = max(
            ReminderLinkStore.metadata(for: challenge.externalIdentifier)?.interval ?? 1,
            1
        )

        switch challenge.recurrence {
        case .none:
            guard let start = challenge.startDate else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        case .irregular:
            return true
        case .daily:
            guard let start = challenge.startDate else { return true }
            let distance = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: start),
                to: day
            ).day ?? 0
            return distance.isMultiple(of: interval)
        case .weekly:
            guard challenge.weekdaySet.contains(calendar.component(.weekday, from: day)) else {
                return false
            }
            guard let start = challenge.startDate,
                  let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
                  let selectedWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start
            else {
                return true
            }
            let weeks = (calendar.dateComponents([.day], from: startWeek, to: selectedWeek).day ?? 0) / 7
            return weeks.isMultiple(of: interval)
        case .monthly:
            guard let start = challenge.startDate else { return false }
            guard calendar.component(.day, from: start) == calendar.component(.day, from: day) else {
                return false
            }
            let components = calendar.dateComponents(
                [.year, .month],
                from: calendar.startOfDay(for: start),
                to: day
            )
            let months = (components.year ?? 0) * 12 + (components.month ?? 0)
            return months.isMultiple(of: interval)
        case .yearly:
            guard let start = challenge.startDate,
                  calendar.component(.month, from: start) == calendar.component(.month, from: day),
                  calendar.component(.day, from: start) == calendar.component(.day, from: day)
            else {
                return false
            }
            let years = calendar.dateComponents(
                [.year],
                from: calendar.startOfDay(for: start),
                to: day
            ).year ?? 0
            return years.isMultiple(of: interval)
        }
    }

    static func isCompleted(_ challenge: ChallengeItem, on date: Date, completions: [ChallengeCompletion]) -> Bool {
        completions.contains { $0.challengeID == challenge.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    struct StreakStatus: Equatable {
        var count: Int
        var required: Int
        var done: Int
        var freezeKeys: [String]
        var needsFreezeWarning: Bool
    }

    /// The streak follows the challenge frequency. Three dates in a week need three
    /// completions on any days of that week. Once a month needs one day in that month.
    /// A missed quota resets the streak when the period ends, unless a freeze covers it.
    static func status(
        for challenge: ChallengeItem,
        endingOn date: Date,
        completions: [ChallengeCompletion],
        events: [ChallengeCalendarEvent],
        streakState: StreakSettings.State? = nil,
        usesStoredState: Bool = true
    ) -> StreakStatus {
        let state = usesStoredState
            ? (StreakSettings.isEnabled(for: challenge.id) ? StreakSettings.state(for: challenge.id) : nil)
            : streakState
        guard let state, state.enabled else {
            return StreakStatus(count: 0, required: 0, done: 0, freezeKeys: [], needsFreezeWarning: false)
        }
        let calendar = Calendar.current
        let enabledDay = calendar.startOfDay(for: state.enabledAt)
        let completedDays = Set(completions.filter { $0.challengeID == challenge.id }.map { calendar.startOfDay(for: $0.date) })
        guard let kind = periodKind(for: challenge.recurrence) else {
            let count = completedDays.filter { $0 >= enabledDay }.count
            return StreakStatus(count: count, required: 0, done: count, freezeKeys: [], needsFreezeWarning: false)
        }

        let rangeStart = calendar.startOfDay(for: challenge.startDate ?? state.enabledAt)
        let rangeEnd = challenge.endDate.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) ?? $0 }
        let horizon = min(date, rangeEnd?.addingTimeInterval(-1) ?? date)
        let origin = max(rangeStart, enabledDay)
        guard horizon >= origin else {
            return StreakStatus(count: 0, required: 0, done: 0, freezeKeys: [], needsFreezeWarning: false)
        }

        let schedule = scheduleEvents(for: challenge, events: events)
        let interval = max(ReminderLinkStore.metadata(for: challenge.externalIdentifier)?.interval ?? 1, 1)
        var streak = 0
        var freezesLeft = 2 + max(state.purchased, 0)
        var used: [String] = []
        var currentRequired = 0
        var currentDone = 0

        for period in periods(from: origin, through: horizon, kind: kind, calendar: calendar) {
            if let rangeEnd, period.start >= rangeEnd { continue }
            let required = quota(
                challenge: challenge,
                period: period,
                kind: kind,
                schedule: schedule,
                interval: interval,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                calendar: calendar
            )
            let windowEnd = rangeEnd.map { min(period.end, $0) } ?? period.end
            let done = completedDays.filter { $0 >= max(period.start, rangeStart) && $0 < windowEnd }.count
            let isOpen = period.start <= date && date < period.end
            if required <= 0 {
                if isOpen {
                    currentRequired = 0
                    currentDone = done
                }
                streak += done
                continue
            }
            if isOpen {
                currentRequired = required
                currentDone = done
                streak += done
                continue
            }
            if done >= required {
                streak += done
            } else if freezesLeft > 0 {
                freezesLeft -= 1
                used.append(period.key)
                streak += done
            } else {
                streak = 0
            }
        }

        let warning = currentRequired > 0 && currentDone < currentRequired && freezesLeft == 0 && streak > 0
        return StreakStatus(
            count: streak,
            required: currentRequired,
            done: currentDone,
            freezeKeys: used,
            needsFreezeWarning: warning
        )
    }

    static func projectedCoins(
        challenge: ChallengeItem,
        on date: Date,
        completions: [ChallengeCompletion],
        events: [ChallengeCalendarEvent]
    ) -> Int {
        let base = max(challenge.rewardCoins, 0)
        guard StreakSettings.isEnabled(for: challenge.id) else { return base }
        let already = completions.contains {
            $0.challengeID == challenge.id && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        let basis = already
            ? completions
            : completions + [ChallengeCompletion(challengeID: challenge.id, date: date, earnedCoins: 0)]
        let count = status(for: challenge, endingOn: date, completions: basis, events: events).count
        return Int((Double(base) * StreakSettings.multiplier(forStreak: count)).rounded())
    }

    static func freezeBalance(
        for challenge: ChallengeItem,
        completions: [ChallengeCompletion],
        events: [ChallengeCalendarEvent],
        on date: Date = .now
    ) -> Int {
        guard let state = StreakSettings.state(for: challenge.id), state.enabled else { return 0 }
        let used = status(for: challenge, endingOn: date, completions: completions, events: events).freezeKeys.count
        return max(0, 2 + state.purchased - used)
    }

    static func commitFreezes(
        for challenges: [ChallengeItem],
        completions: [ChallengeCompletion],
        events: [ChallengeCalendarEvent],
        on date: Date = .now
    ) {
        for challenge in challenges where StreakSettings.isEnabled(for: challenge.id) && !challenge.isArchived {
            let keys = status(for: challenge, endingOn: date, completions: completions, events: events).freezeKeys
            StreakSettings.setUsedPeriodKeys(keys, for: challenge.id)
        }
    }

    static func purchaseFreeze(
        challenge: ChallengeItem,
        transactions: [CoinTransaction],
        context: ModelContext
    ) -> Bool {
        guard StreakSettings.isEnabled(for: challenge.id) else { return false }
        let price = StreakSettings.price(for: challenge)
        guard walletBalance(transactions: transactions) >= price else { return false }
        context.insert(CoinTransaction(
            title: "\(L("Streak-Freeze", "Streak freeze")): \(challenge.title)",
            amount: -price,
            referenceID: challenge.id
        ))
        StreakSettings.addPurchasedFreeze(for: challenge.id)
        try? context.save()
        return true
    }

    static func toggleCompletion(
        challenge: ChallengeItem,
        date: Date,
        completions: [ChallengeCompletion],
        transactions: [CoinTransaction],
        events: [ChallengeCalendarEvent] = [],
        context: ModelContext
    ) {
        guard !challenge.isReadOnly else { return }
        let isNowCompleted: Bool
        let tracked: [ChallengeCompletion]
        if let completion = completions.first(where: {
            $0.challengeID == challenge.id && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            transactions.filter { $0.referenceID == completion.id }.forEach { context.delete($0) }
            context.delete(completion)
            tracked = completions.filter { $0.id != completion.id }
            isNowCompleted = false
        } else {
            let earned = projectedCoins(challenge: challenge, on: date, completions: completions, events: events)
            let completion = ChallengeCompletion(challengeID: challenge.id, date: date, earnedCoins: earned)
            context.insert(completion)
            context.insert(CoinTransaction(title: challenge.title, amount: earned, referenceID: completion.id))
            tracked = completions + [completion]
            isNowCompleted = true
        }
        try? context.save()
        commitFreezes(for: [challenge], completions: tracked, events: events, on: date)
        if let externalIdentifier = challenge.externalIdentifier {
            Task {
                await EventKitSyncService.setReminderCompletion(
                    externalIdentifier: externalIdentifier,
                    isCompleted: isNowCompleted
                )
            }
        }
    }

    /// Marks a challenge done for that day and awards coins once. Does nothing when it is already done.
    @discardableResult
    static func markCompletedIfNeeded(
        challenge: ChallengeItem,
        date: Date,
        completions: [ChallengeCompletion],
        events: [ChallengeCalendarEvent] = [],
        context: ModelContext
    ) -> Bool {
        guard !challenge.isArchived else { return false }
        guard !isCompleted(challenge, on: date, completions: completions) else { return false }
        let earned = projectedCoins(challenge: challenge, on: date, completions: completions, events: events)
        let completion = ChallengeCompletion(challengeID: challenge.id, date: date, earnedCoins: earned)
        context.insert(completion)
        context.insert(CoinTransaction(title: challenge.title, amount: earned, referenceID: completion.id))
        try? context.save()
        commitFreezes(for: [challenge], completions: completions + [completion], events: events, on: date)
        if let externalIdentifier = challenge.externalIdentifier {
            Task {
                await EventKitSyncService.setReminderCompletion(
                    externalIdentifier: externalIdentifier,
                    isCompleted: true
                )
            }
        }
        return true
    }

    private struct StreakPeriod {
        let key: String
        let start: Date
        let end: Date
    }

    private enum PeriodKind {
        case day, week, month, year
    }

    private struct EventSchedule {
        var usesCalendar: Bool
        var events: [ChallengeCalendarEvent]
    }

    private static func periodKind(for recurrence: ChallengeRecurrence) -> PeriodKind? {
        switch recurrence {
        case .daily: return .day
        case .weekly: return .week
        case .monthly: return .month
        case .yearly: return .year
        case .none, .irregular: return nil
        }
    }

    private static func scheduleEvents(for challenge: ChallengeItem, events: [ChallengeCalendarEvent]) -> EventSchedule {
        let own = events.filter { !$0.isReminderSuggestion && $0.linkedChallengeID == challenge.id }
        if !own.isEmpty { return EventSchedule(usesCalendar: true, events: own) }
        if let groupID = challenge.groupID {
            let grouped = events.filter {
                !$0.isReminderSuggestion && $0.linkedChallengeGroupID == groupID && $0.linkedChallengeID == nil
            }
            if !grouped.isEmpty { return EventSchedule(usesCalendar: true, events: grouped) }
        }
        return EventSchedule(usesCalendar: false, events: [])
    }

    private static func periods(from origin: Date, through horizon: Date, kind: PeriodKind, calendar: Calendar) -> [StreakPeriod] {
        var start = periodStart(origin, kind: kind, calendar: calendar)
        let last = periodStart(horizon, kind: kind, calendar: calendar)
        var result: [StreakPeriod] = []
        var guardCount = 0
        while start <= last && guardCount < 4000 {
            let end = periodEnd(start, kind: kind, calendar: calendar)
            result.append(StreakPeriod(key: periodKey(start, kind: kind, calendar: calendar), start: start, end: end))
            guard end > start else { break }
            start = end
            guardCount += 1
        }
        return result
    }

    private static func quota(
        challenge: ChallengeItem,
        period: StreakPeriod,
        kind: PeriodKind,
        schedule: EventSchedule,
        interval: Int,
        rangeStart: Date,
        rangeEnd: Date?,
        calendar: Calendar
    ) -> Int {
        let clippedEnd = rangeEnd.map { min(period.end, $0) } ?? period.end
        guard period.start < clippedEnd else { return 0 }
        if schedule.usesCalendar {
            return schedule.events.filter { event in
                event.startDate >= period.start && event.startDate < clippedEnd
            }.count
        }
        switch kind {
        case .day:
            guard period.start >= rangeStart, period.start < clippedEnd else { return 0 }
            let distance = calendar.dateComponents([.day], from: rangeStart, to: period.start).day ?? 0
            return distance >= 0 && distance.isMultiple(of: interval) ? 1 : 0
        case .week:
            guard weekIsScheduled(period.start, rangeStart: rangeStart, interval: interval, calendar: calendar) else { return 0 }
            if challenge.weekdaySet.isEmpty {
                return period.start < clippedEnd && period.end > rangeStart ? 1 : 0
            }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: period.start) }.filter { day in
                day >= rangeStart && day < clippedEnd && challenge.weekdaySet.contains(calendar.component(.weekday, from: day))
            }.count
        case .month:
            guard monthIsScheduled(period.start, rangeStart: rangeStart, interval: interval, calendar: calendar) else { return 0 }
            return period.end > rangeStart && period.start < clippedEnd ? 1 : 0
        case .year:
            guard yearIsScheduled(period.start, rangeStart: rangeStart, interval: interval, calendar: calendar) else { return 0 }
            return period.end > rangeStart && period.start < clippedEnd ? 1 : 0
        }
    }

    private static func weekIsScheduled(_ weekStart: Date, rangeStart: Date, interval: Int, calendar: Calendar) -> Bool {
        let origin = periodStart(rangeStart, kind: .week, calendar: calendar)
        let days = calendar.dateComponents([.day], from: origin, to: weekStart).day ?? 0
        let weeks = days / 7
        return weeks >= 0 && weeks.isMultiple(of: interval)
    }

    private static func monthIsScheduled(_ monthStart: Date, rangeStart: Date, interval: Int, calendar: Calendar) -> Bool {
        let start = calendar.dateComponents([.year, .month], from: rangeStart)
        let month = calendar.dateComponents([.year, .month], from: monthStart)
        let delta = ((month.year ?? 0) - (start.year ?? 0)) * 12 + ((month.month ?? 0) - (start.month ?? 0))
        return delta >= 0 && delta.isMultiple(of: interval)
    }

    private static func yearIsScheduled(_ yearStart: Date, rangeStart: Date, interval: Int, calendar: Calendar) -> Bool {
        let delta = calendar.component(.year, from: yearStart) - calendar.component(.year, from: rangeStart)
        return delta >= 0 && delta.isMultiple(of: interval)
    }

    private static func periodStart(_ date: Date, kind: PeriodKind, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        switch kind {
        case .day:
            return day
        case .week:
            let weekday = calendar.component(.weekday, from: day)
            let shift = weekday == 1 ? -6 : 2 - weekday
            return calendar.date(byAdding: .day, value: shift, to: day) ?? day
        case .month:
            let components = calendar.dateComponents([.year, .month], from: day)
            return calendar.date(from: components) ?? day
        case .year:
            let components = calendar.dateComponents([.year], from: day)
            return calendar.date(from: components) ?? day
        }
    }

    private static func periodEnd(_ start: Date, kind: PeriodKind, calendar: Calendar) -> Date {
        switch kind {
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .year:
            return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }

    private static func periodKey(_ start: Date, kind: PeriodKind, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        switch kind {
        case .day, .week:
            return "\(kind == .day ? "d" : "w"):\(String(format: "%04d-%02d-%02d", year, month, day))"
        case .month:
            return String(format: "m:%04d-%02d", year, month)
        case .year:
            return String(format: "y:%04d", year)
        }
    }

    static func walletBalance(transactions: [CoinTransaction]) -> Int {
        transactions.reduce(0) { $0 + $1.amount }
    }

    static func purchase(
        reward: RewardItem,
        transactions: [CoinTransaction],
        context: ModelContext
    ) -> Bool {
        guard walletBalance(transactions: transactions) >= reward.price else { return false }
        let purchase = RewardPurchase(rewardID: reward.id, title: reward.title, price: reward.price)
        context.insert(purchase)
        context.insert(CoinTransaction(title: reward.title, amount: -reward.price, referenceID: purchase.id))
        if !RewardPolicyStore.allowsMultiplePurchases(for: reward.id) {
            reward.isActive = false
        }
        try? context.save()
        return true
    }

    static func days(for mode: ChallengeCalendarViewMode, around selectedDate: Date) -> [Date] {
        let calendar = Calendar.current
        switch mode {
        case .day:
            return [calendar.startOfDay(for: selectedDate)]
        case .week:
            let weekday = calendar.component(.weekday, from: selectedDate)
            let daysFromMonday = weekday == 1 ? 6 : weekday - 2
            let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: selectedDate))!
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            let first = calendar.date(from: components)!
            let range = calendar.range(of: .day, in: .month, for: first)!
            return range.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: first)
            }
        }
    }
}
