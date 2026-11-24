import ActivityKit
import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData
import WidgetKit

/// Builds the data the widgets show and books the check-offs made in them.
@MainActor
enum WidgetPublisher {
    /// Books waiting check-offs, writes a new snapshot, and reloads the widgets.
    static func refresh(context: ModelContext, plans: [WorkoutPlan]) {
        guard let folder = WidgetStore.directory else { return }
        applyPending(context: context, folder: folder)
        WidgetStore.write(snapshot(context: context, plans: plans), in: folder)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Books the widget's check-offs with the app's rules.
    ///
    /// - Parameters:
    ///   - context: The database context.
    ///   - folder: The shared folder.
    static func applyPending(context: ModelContext, folder: URL?) {
        let queue = WidgetStore.pending(in: folder)
        guard !queue.isEmpty else { return }
        for item in queue {
            _ = SiriActions.checkOff(id: item.challengeID, context: context, now: item.date)
        }
        WidgetStore.clear(queue, in: folder)
    }

    /// Builds the snapshot. Amounts stay out while the Finance lock hides them from widgets.
    ///
    /// - Parameters:
    ///   - context: The database context.
    ///   - plans: The training plans.
    ///   - now: The current time.
    /// - Returns: The data for all widgets.
    static func snapshot(context: ModelContext, plans: [WorkoutPlan], now: Date = .now) -> WidgetSnapshot {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let events = ((try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? [])
            .filter { !$0.isReminderSuggestion && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        return WidgetSnapshot(
            generatedAt: now,
            isGerman: AppDefaults.store.string(forKey: "appLanguage") != "en",
            paletteRaw: AppDefaults.store.string(forKey: AppPalette.storageKey) ?? AppPalette.green.rawValue,
            finance: FinanceLockSettings.widgetsMayShowAmounts ? finance(context: context, now: now) : nil,
            hasFinanceLock: FinanceLockSettings.isEnabled,
            challengesByDay: [
                now.dayKey: challenges(context: context, on: now),
                tomorrow.dayKey: challenges(context: context, on: tomorrow)
            ],
            nextSlot: events.first { Calendar.current.isDate($0.startDate, inSameDayAs: now) }
                .map { WidgetAppointment(title: $0.title, date: $0.startDate) },
            nextTraining: nextTraining(events: events, plans: plans),
            coins: ChallengeService.walletBalance(transactions: (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []),
            longestStreak: longestStreak(context: context, now: now)
        )
    }

    /// The budget and depot amounts.
    private static func finance(context: ModelContext, now: Date) -> WidgetFinance {
        let budget = HomeBudget.current(context: context, now: now)
        let holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        let performance = holdings.reduce(HoldingPerformance()) { $0.adding(holdingPerformance($1)) }
        return WidgetFinance(
            remainingCents: budget.remaining,
            plannedCents: budget.planned,
            dailyCents: budget.dailyAllowance(now: now),
            depotCents: HoldingMaintenance.marketValue(of: holdings, through: now),
            depotChangeCents: performance.dayCents
        )
    }

    /// The open challenges of a day. Abstinence runs by itself and is left out.
    private static func challenges(context: ModelContext, on day: Date) -> [WidgetChallenge] {
        SiriActions.openChallenges(context: context, now: day)
            .filter { $0.category != .abstinence }
            .map { challenge in
                WidgetChallenge(
                    id: challenge.id,
                    title: challenge.title,
                    canCheckOff: SiriActions.canCheckOff(challenge),
                    planID: WorkoutLinkStore.planIDs(forChallenge: challenge.id).first
                )
            }
    }

    /// The next calendar slot with a linked plan.
    private static func nextTraining(events: [ChallengeCalendarEvent], plans: [WorkoutPlan]) -> WidgetAppointment? {
        for event in events {
            let linked = TrainingAgenda.planIDs(for: event)
            if let plan = plans.first(where: { linked.contains($0.id) }) {
                return WidgetAppointment(title: plan.name, date: event.startDate, planID: plan.id)
            }
        }
        return nil
    }

    /// The longest streak that is running.
    private static func longestStreak(context: ModelContext, now: Date) -> Int {
        let challenges = (try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []
        let completions = ChallengeCompletionIndex((try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? [])
        let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        return challenges
            .filter { !$0.isArchived && StreakSettings.isEnabled(for: $0.id) }
            .map { ChallengeService.status(for: $0, endingOn: now, completions: completions.completions(for: $0.id), events: events).count }
            .max() ?? 0
    }
}

/// Shows the running training on the Lock Screen and in the Dynamic Island.
@MainActor
final class WorkoutActivityController {
    private typealias WorkoutActivity = Activity<WorkoutActivityAttributes>
    private var activityID: String?

    /// Starts the Live Activity, when the person allows them.
    func start(planName: String, startedAt: Date, state: WorkoutActivityAttributes.ContentState) {
        guard activityID == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityID = (try? WorkoutActivity.request(
            attributes: WorkoutActivityAttributes(planName: planName, startedAt: startedAt),
            content: ActivityContent(state: state, staleDate: nil)
        ))?.id
    }

    /// Updates exercise, set, and rest.
    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activityID else { return }
        Task.detached { await Self.push(state, to: activityID) }
    }

    /// Ends the Live Activity.
    func end() {
        guard let activityID else { return }
        self.activityID = nil
        Task.detached { await Self.finish(activityID) }
    }

    /// Sends a new state to the running activity.
    private nonisolated static func push(_ state: WorkoutActivityAttributes.ContentState, to id: String) async {
        guard let activity = WorkoutActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Removes the activity from the screen.
    private nonisolated static func finish(_ id: String) async {
        guard let activity = WorkoutActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
