import Foundation
import LififyCore
import LififyHealth
import SwiftData

/// Brings the step challenge, the widget, and the evening note up to date when Apple Health
/// reports new steps, also while Lifify is not on screen.
@MainActor
enum StepUpdates {
    /// The days read on each update, enough to book a day missed overnight.
    static let recentDays = 3

    /// Registers the handler and starts watching. Called at every launch, as Apple Health requires.
    static func install() {
        AppleHealthSync.onStepChange = { await handle() }
        AppleHealthSync.startStepUpdates()
    }

    /// Reads the newest steps and updates everything that shows them.
    static func handle() async {
        guard let container = LififyDatabase.container else { return }
        let context = ModelContext(container)
        await AppleHealthSync.refreshTodaySteps()
        if StepChallenge.goal > 0, let recent = await AppleHealthSync.summary(days: recentDays) {
            StepChallenge.settle(days: recent.steps, context: context)
        }
        WidgetPublisher.refreshSteps()
        await DailyBriefingService.scheduleFollowUps(context: context, sessions: WorkoutStore().sessions)
    }
}
