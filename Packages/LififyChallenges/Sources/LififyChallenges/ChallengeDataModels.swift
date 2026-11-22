import Foundation
import LififyCore
import SwiftData

@Model
public final class StoredStreakState {
    @Attribute(.unique) public var challengeID: UUID
    public var enabled: Bool
    public var enabledAt: Date
    public var purchased: Int
    public var usedPeriodKeysData: Data

    public init(challengeID: UUID, state: StreakSettings.State) {
        self.challengeID = challengeID
        enabled = state.enabled
        enabledAt = state.enabledAt
        purchased = state.purchased
        usedPeriodKeysData = (try? JSONEncoder().encode(state.usedPeriodKeys)) ?? Data("[]".utf8)
    }

    public var state: StreakSettings.State {
        StreakSettings.State(
            enabled: enabled,
            enabledAt: enabledAt,
            purchased: purchased,
            usedPeriodKeys: (try? JSONDecoder().decode([String].self, from: usedPeriodKeysData)) ?? []
        )
    }
}

/// A workout plan linked to a challenge, or to a calendar event when `isEvent` is true.
@Model
public final class StoredWorkoutLink {
    public var planID: UUID
    public var targetID: UUID
    public var isEvent: Bool
    public var managed: Bool
    public var position: Int

    public init(planID: UUID, targetID: UUID, isEvent: Bool, managed: Bool, position: Int) {
        self.planID = planID
        self.targetID = targetID
        self.isEvent = isEvent
        self.managed = managed
        self.position = position
    }
}

