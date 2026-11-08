import Foundation
import SwiftData

/// Pays the daily base coins and each reached bonus once for the current run.
@MainActor
enum AbstinenceService {
    static func settle(context: ModelContext, now: Date = AppClock.now) {
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let calendar = Calendar.current
        var changed = false
        for challenge in challenges where challenge.category == .abstinence && !challenge.isArchived {
            let start = challenge.startDate ?? challenge.createdAt
            let completed = Set(
                completions
                    .filter { $0.challengeID == challenge.id }
                    .map { calendar.startOfDay(for: $0.date) }
            )
            let plan = AbstinenceRules.plan(
                start: start,
                now: now,
                completedDays: completed,
                awarded: AbstinenceSettings.awarded(for: challenge.id),
                calendar: calendar
            )
            let base = max(challenge.rewardCoins, 0)
            for day in plan.days {
                let completion = ChallengeCompletion(challengeID: challenge.id, date: day, earnedCoins: base)
                context.insert(completion)
                if base > 0 {
                    context.insert(CoinTransaction(date: day, title: challenge.title, amount: base, referenceID: completion.id))
                }
                changed = true
            }
            if !plan.milestones.isEmpty {
                let difficulty = AbstinenceSettings.difficulty(for: challenge.id)
                var awarded = AbstinenceSettings.awarded(for: challenge.id)
                for milestone in plan.milestones {
                    let coins = AbstinenceRules.bonusCoins(
                        base: base,
                        multiplier: AbstinenceSettings.multiplier(for: difficulty, milestone: milestone)
                    )
                    awarded.insert(milestone.rawValue)
                    let due = milestone.due(from: start, calendar: calendar)
                    if coins > 0 {
                        context.insert(CoinTransaction(
                            date: due,
                            title: "\(L("Bonus", "Bonus")): \(challenge.title) · \(milestone.label)",
                            amount: coins,
                            referenceID: challenge.id
                        ))
                    }
                    AbstinenceSettings.postNotice(AbstinenceNotice(
                        id: "\(challenge.id.uuidString)|\(milestone.rawValue)|\(start.timeIntervalSince1970)",
                        challengeID: challenge.id,
                        title: challenge.title,
                        milestone: milestone.rawValue,
                        coins: coins,
                        date: due
                    ))
                }
                AbstinenceSettings.setAwarded(awarded, for: challenge.id)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Starts the timer again. Coins already paid stay. Bonuses of the new run can be earned again.
    static func relapse(_ challenge: ChallengeItem, context: ModelContext, now: Date = AppClock.now) {
        guard challenge.category == .abstinence else { return }
        let start = challenge.startDate ?? challenge.createdAt
        AbstinenceSettings.recordRelapse(
            AbstinenceRelapse(id: UUID(), date: now, lasted: AbstinenceRules.elapsed(from: start, to: now)),
            for: challenge.id
        )
        challenge.startDate = now
        AbstinenceSettings.clearAwarded(for: challenge.id)
        try? context.save()
        settle(context: context, now: now)
    }
}
