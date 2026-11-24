import Foundation
import LififyChallenges
import LififyCore
import SwiftData

/// The daily step goal and its challenge, which checks itself off from Apple Health.
///
/// The challenge exists while a goal is set and Apple Health is on. It has the usual streak and
/// freezes. A day counts once Apple Health reports at least the goal; the app reads the steps when
/// it comes to the front, so a reached goal is booked then, also for past days.
@MainActor
public enum StepChallenge {
    public static let challengeMark = "health:steps"
    public static let goalKey = "lifify.stepGoal"
    public static let rewardCoins = 20
    /// Suggested in setup and settings.
    public static let suggestedGoal = 8_000

    /// The daily goal, or 0 when none is set.
    public static var goal: Int {
        max(AppDefaults.store.integer(forKey: goalKey), 0)
    }

    /// The challenge's title for a goal.
    public static func title(for goal: Int) -> String {
        L("\(goal.formatted()) Schritte", "\(goal.formatted()) steps")
    }

    /// Creates, renames, archives, or revives the challenge to match the goal.
    ///
    /// - Parameter context: The database context.
    /// - Returns: The active challenge, or `nil` without a goal or Apple Health.
    @discardableResult
    public static func sync(context: ModelContext) -> ChallengeItem? {
        let stored = ((try? context.fetch(FetchDescriptor<ChallengeItem>())) ?? []).first { $0.externalIdentifier == challengeMark }
        guard goal > 0, AppleHealthSync.isEnabled else {
            if let stored, !stored.isArchived {
                stored.isArchived = true
                try? context.save()
            }
            return nil
        }
        guard let stored else { return create(context: context) }
        let wanted = title(for: goal)
        if stored.isArchived || stored.title != wanted {
            stored.isArchived = false
            stored.title = wanted
            try? context.save()
        }
        return stored
    }

    /// Books every day since the challenge began whose steps reached the goal.
    ///
    /// - Parameters:
    ///   - days: The daily steps from Apple Health.
    ///   - context: The database context.
    ///   - now: The current time.
    /// - Returns: The number of newly booked days.
    @discardableResult
    public static func settle(days: [HealthDayValue], context: ModelContext, now: Date = AppClock.now) -> Int {
        guard let challenge = sync(context: context) else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: challenge.startDate ?? challenge.createdAt)
        let today = calendar.startOfDay(for: now)
        let reached = days
            .filter { $0.value >= Double(goal) }
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 >= start && $0 <= today }
            .sorted()
        var booked = 0
        for day in reached {
            let completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
            let events = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
            if ChallengeService.markCompletedIfNeeded(challenge: challenge, date: day, completions: completions, events: events, context: context) {
                booked += 1
            }
        }
        return booked
    }

    /// The evening note: how far the day's steps are from the goal.
    ///
    /// - Parameters:
    ///   - steps: The steps read last, or `nil` when unknown.
    ///   - readAt: When they were read.
    /// - Returns: Title and text, or `nil` without a goal.
    public static func note(steps: Int?, readAt: Date?) -> CalorieNudge.Note? {
        guard goal > 0 else { return nil }
        guard let steps, let readAt else {
            return CalorieNudge.Note(
                title: L("Schrittziel", "Step goal"),
                body: L("Heute sind \(goal.formatted()) Schritte das Ziel. Öffne Lifify, damit sie zählen.",
                        "Today's goal is \(goal.formatted()) steps. Open Lifify so they count.")
            )
        }
        let time = readAt.formatted(date: .omitted, time: .shortened)
        guard steps < goal else {
            return CalorieNudge.Note(
                title: L("Schrittziel erreicht", "Step goal reached"),
                body: L("\(steps.formatted()) Schritte (Stand \(time)). Stark!", "\(steps.formatted()) steps (as of \(time)). Strong!")
            )
        }
        return CalorieNudge.Note(
            title: L("Noch ein paar Schritte", "A few more steps"),
            body: L("\(steps.formatted()) von \(goal.formatted()) Schritten (Stand \(time)). Noch \((goal - steps).formatted()) bis zum Ziel.",
                    "\(steps.formatted()) of \(goal.formatted()) steps (as of \(time)). \((goal - steps).formatted()) to go.")
        )
    }

    /// Makes the challenge with its streak and icon.
    private static func create(context: ModelContext) -> ChallengeItem {
        let challenge = ChallengeItem(
            title: title(for: goal),
            details: L(
                "Ein Tag zählt, wenn Apple Health mindestens das Schrittziel meldet. Lifify liest die Schritte beim Öffnen und bucht auch vergangene Tage nach.",
                "A day counts when Apple Health reports at least the step goal. Lifify reads the steps when it opens and also books past days."
            ),
            category: .other,
            recurrence: .daily,
            startDate: Calendar.current.startOfDay(for: AppClock.now),
            rewardCoins: rewardCoins,
            externalIdentifier: challengeMark
        )
        context.insert(challenge)
        try? context.save()
        StreakSettings.setEnabled(true, for: challenge.id)
        IconPreferenceStore.set("figure.walk", for: challenge.id)
        return challenge
    }
}
