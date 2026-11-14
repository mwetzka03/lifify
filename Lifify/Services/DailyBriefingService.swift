import Foundation
import SwiftData

/// Builds the next daily pushes from the current challenges, events, and forecasts.
@MainActor
enum DailyBriefingService {
    static func refresh(context: ModelContext) async {
        guard LififyNotifications.briefingEnabled else {
            await LififyNotifications.cancelBriefings()
            return
        }
        guard await LififyNotifications.requestAccess() else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var items: [(id: String, title: String, body: String, date: Date)] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard LififyNotifications.dayEnabled(weekday) else { continue }
            let clock = LififyNotifications.clock(for: weekday)
            guard let fire = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day),
                  fire > Date()
            else { continue }
            let stamp = dayStamp(day, calendar: calendar)
            items.append((
                id: "lifify.briefing.\(stamp)",
                title: L("Tagesbriefing", "Daily briefing"),
                body: body(for: day, context: context, calendar: calendar),
                date: fire
            ))
        }
        await LififyNotifications.replaceBriefings(items)
    }

    /// Evening nudges, clock-time nudges, streak warnings, and the birthday note.
    /// These follow the real clock, so a developer day does not move Notification Center.
    static func scheduleFollowUps(context: ModelContext) async {
        guard await LififyNotifications.requestAccess() else { return }
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        var plans: [ChallengeNudgeDay] = []
        var streaks: [ChallengeNudgeRequest] = []
        for day in days {
            var items: [ChallengeNudgeItem] = []
            for challenge in challenges where !challenge.isArchived {
                if challenge.category != .abstinence {
                    let due = ChallengeService.isDue(challenge, on: day)
                    let done = ChallengeService.isCompleted(challenge, on: day, completions: completions)
                    if due && !done {
                        let linked = ChallengeTimeStore.linkedEvents(for: challenge.id, in: events)
                        items.append(ChallengeNudgeItem(
                            id: challenge.id,
                            title: challenge.title,
                            clocks: ChallengeNudgePlan.clocks(from: linked.map(\.startDate), calendar: calendar)
                        ))
                    }
                }
                let status = ChallengeService.status(
                    for: challenge,
                    endingOn: day,
                    completions: completions,
                    events: events
                )
                if let warning = ChallengeNudgePlan.streakWarning(
                    id: challenge.id,
                    title: challenge.title,
                    streak: status.count,
                    atRisk: status.needsFreezeWarning,
                    recurrence: challenge.recurrence,
                    on: day,
                    now: now,
                    calendar: calendar
                ) {
                    streaks.append(warning)
                }
            }
            if !items.isEmpty {
                plans.append(ChallengeNudgeDay(day: day, items: items))
            }
        }
        let nudges = ChallengeNudgePlan.requests(days: plans, now: now, calendar: calendar) + streaks
        await LififyNotifications.replace(
            prefix: ChallengeNudgePlan.nudgePrefix,
            items: nudges.map { ($0.id, $0.title, $0.body, $0.fire) },
            followsDeviceTimeZone: true
        )
        var birthday: [(id: String, title: String, body: String, date: Date)] = []
        if let birth = UserProfile.birth(),
           let fire = BirthdayCheer.nextFire(
               birth: birth,
               awardedYear: UserProfile.awardedYear(),
               now: now,
               calendar: calendar
           ) {
            let year = calendar.component(.year, from: fire)
            birthday.append((
                "\(ChallengeNudgePlan.birthdayPrefix)\(year)",
                BirthdayCheer.title(),
                BirthdayCheer.body(),
                fire
            ))
        }
        await LififyNotifications.replace(
            prefix: ChallengeNudgePlan.birthdayPrefix,
            items: birthday,
            followsDeviceTimeZone: true
        )
    }

    static func scheduleAbstinence(context: ModelContext) async {
        guard await LififyNotifications.requestAccess() else { return }
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let now = Date()
        for challenge in challenges where challenge.category == .abstinence && !challenge.isArchived {
            let start = challenge.startDate ?? challenge.createdAt
            let awarded = AbstinenceSettings.awarded(for: challenge.id)
            for milestone in AbstinenceMilestone.allCases where !awarded.contains(milestone.rawValue) {
                let due = milestone.due(from: start)
                let id = "\(challenge.id.uuidString)|\(milestone.rawValue)|\(start.timeIntervalSince1970)"
                guard due > now else { continue }
                let coins = AbstinenceRules.bonusCoins(
                    base: challenge.rewardCoins,
                    multiplier: AbstinenceSettings.multiplier(
                        for: AbstinenceSettings.difficulty(for: challenge.id),
                        milestone: milestone
                    )
                )
                LififyNotifications.schedule(
                    id: id,
                    title: AbstinenceCheer.title(for: milestone),
                    body: AbstinenceCheer.body(challenge: challenge.title, milestone: milestone, coins: coins),
                    at: due
                )
            }
        }
    }

    private static func body(for day: Date, context: ModelContext, calendar: Calendar) -> String {
        let storedEvents = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        let events = storedEvents
            .filter { !$0.isReminderSuggestion && calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
            .map { DailyBriefingLine(title: $0.title, detail: AppDate.time($0.startDate)) }
        let challenges = ((try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? [])
            .filter { !$0.isArchived && $0.category != .abstinence && ChallengeService.isDue($0, on: day) }
            .prefix(6)
            .map { DailyBriefingLine(title: $0.title, detail: "+\($0.rewardCoins)") }
        let rewardItems = (try? context.fetch(FetchDescriptor<RewardItem>())) ?? []
        let rewards = storedEvents.compactMap { event -> DailyBriefingLine? in
            guard !event.isReminderSuggestion,
                  let rewardID = event.linkedRewardID,
                  let reward = rewardItems.first(where: { $0.id == rewardID }),
                  let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: event.startDate)).day,
                  days >= 0, days <= 14
            else { return nil }
            return DailyBriefingLine(title: reward.title, detail: "\(reward.price) · \(days)d")
        }.prefix(3)
        let forecasts = (try? context.fetch(FetchDescriptor<IncomeForecast>())) ?? []
        let salary = nextSalary(in: forecasts, after: day, calendar: calendar).map(AppDate.numeric)
        let costs = ((try? context.fetch(FetchDescriptor<FixedCost>())) ?? [])
            .filter { $0.isActive && occurs($0, on: day, calendar: calendar) }
            .prefix(4)
            .map { DailyBriefingLine(title: $0.name, detail: Money.string(cents: $0.amountCents)) }
        return DailyBriefing.text(
            events: events,
            challenges: Array(challenges),
            rewards: Array(rewards),
            salary: salary,
            expenses: Array(costs)
        )
    }

    private static func nextSalary(in forecasts: [IncomeForecast], after day: Date, calendar: Calendar) -> Date? {
        guard let limit = calendar.date(byAdding: .year, value: 1, to: day) else { return nil }
        let active = forecasts.filter(\.isActive)
        let primaryID = UserDefaults.standard.string(forKey: "primaryIncomeForecastID").flatMap(UUID.init(uuidString:))
        let chosen = active.first { $0.id == primaryID } ?? active.first
        guard let chosen else { return nil }
        return CalendarService.nextOccurrences(
            firstDate: chosen.firstPaymentDate,
            cadence: chosen.cadence,
            rule: chosen.dueRule,
            day: chosen.dayOfMonth,
            endDate: chosen.endPaymentDate,
            through: limit
        ).first { calendar.startOfDay(for: $0) >= calendar.startOfDay(for: day) }
    }

    private static func occurs(_ cost: FixedCost, on day: Date, calendar: Calendar) -> Bool {
        guard let limit = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return false }
        return CalendarService.nextOccurrences(
            firstDate: cost.firstChargeDate,
            cadence: cost.cadence,
            rule: cost.dueRule,
            day: cost.dayOfMonth,
            endDate: cost.endChargeDate,
            through: limit
        ).contains { calendar.isDate($0, inSameDayAs: day) }
    }

    private static func dayStamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

}
