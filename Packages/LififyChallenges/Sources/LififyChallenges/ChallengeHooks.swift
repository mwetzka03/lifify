import Foundation
import LififyCore
import SwiftData

/// What Challenges needs from other areas. The app connects these at launch.
@MainActor
public enum ChallengeHooks {
    /// Confirmed meals of one day, for the nutrition challenge.
    public static var confirmedMeals: (Date) -> Int = { _ in 0 }
    /// Runs after an abstinence run restarts, so its reminders follow.
    public static var abstinenceChanged: @MainActor (ModelContext) async -> Void = { _ in }
}
