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

    static func streak(for challenge: ChallengeItem, endingOn date: Date, completions: [ChallengeCompletion]) -> Int {
        let calendar = Calendar.current
        let completedDays = Set(completions.filter { $0.challengeID == challenge.id }.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: date)
        var count = 0
        while completedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func multiplier(streak: Int) -> Double {
        min(1 + Double(streak / 5) * 0.5, 5)
    }

    static func toggleCompletion(
        challenge: ChallengeItem,
        date: Date,
        completions: [ChallengeCompletion],
        transactions: [CoinTransaction],
        context: ModelContext
    ) {
        guard !challenge.isReadOnly else { return }
        let isNowCompleted: Bool
        if let completion = completions.first(where: {
            $0.challengeID == challenge.id && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            transactions.filter { $0.referenceID == completion.id }.forEach { context.delete($0) }
            context.delete(completion)
            isNowCompleted = false
        } else {
            let currentStreak = streak(for: challenge, endingOn: Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date, completions: completions)
            let earned = Int((Double(challenge.rewardCoins) * multiplier(streak: currentStreak + 1)).rounded())
            let completion = ChallengeCompletion(challengeID: challenge.id, date: date, earnedCoins: earned)
            context.insert(completion)
            context.insert(CoinTransaction(title: challenge.title, amount: earned, referenceID: completion.id))
            isNowCompleted = true
        }
        try? context.save()
        if let externalIdentifier = challenge.externalIdentifier {
            Task {
                await EventKitSyncService.setReminderCompletion(
                    externalIdentifier: externalIdentifier,
                    isCompleted: isNowCompleted
                )
            }
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
