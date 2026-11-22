import Foundation
import SwiftData

@Model
final class StoredStreakState {
    @Attribute(.unique) var challengeID: UUID
    var enabled: Bool
    var enabledAt: Date
    var purchased: Int
    var usedPeriodKeysData: Data

    init(challengeID: UUID, state: StreakSettings.State) {
        self.challengeID = challengeID
        enabled = state.enabled
        enabledAt = state.enabledAt
        purchased = state.purchased
        usedPeriodKeysData = (try? JSONEncoder().encode(state.usedPeriodKeys)) ?? Data("[]".utf8)
    }

    var state: StreakSettings.State {
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
final class StoredWorkoutLink {
    var planID: UUID
    var targetID: UUID
    var isEvent: Bool
    var managed: Bool
    var position: Int

    init(planID: UUID, targetID: UUID, isEvent: Bool, managed: Bool, position: Int) {
        self.planID = planID
        self.targetID = targetID
        self.isEvent = isEvent
        self.managed = managed
        self.position = position
    }
}

@Model
final class StoredMeal {
    @Attribute(.unique) var mealID: UUID
    var dayKey: String
    var title: String
    var note: String
    var correction: String
    var createdAt: Date
    var sourceRaw: String
    var statusRaw: String
    var photoName: String?
    var nutrientsData: Data
    var kindRaw: String
    var chargeID: UUID?

    init(_ meal: MealRecord) {
        mealID = meal.id
        dayKey = meal.dayKey
        title = meal.title
        note = meal.note
        correction = meal.correction
        createdAt = meal.createdAt
        sourceRaw = meal.source.rawValue
        statusRaw = meal.status.rawValue
        photoName = meal.photoName
        nutrientsData = (try? JSONEncoder().encode(meal.nutrients)) ?? Data("{}".utf8)
        kindRaw = meal.kindRaw
        chargeID = meal.chargeID
    }

    func update(from meal: MealRecord) {
        dayKey = meal.dayKey
        title = meal.title
        note = meal.note
        correction = meal.correction
        createdAt = meal.createdAt
        sourceRaw = meal.source.rawValue
        statusRaw = meal.status.rawValue
        photoName = meal.photoName
        nutrientsData = (try? JSONEncoder().encode(meal.nutrients)) ?? Data("{}".utf8)
        kindRaw = meal.kindRaw
        chargeID = meal.chargeID
    }

    var meal: MealRecord {
        var record = MealRecord(
            id: mealID,
            dayKey: dayKey,
            title: title,
            note: note,
            correction: correction,
            createdAt: createdAt,
            source: MealSource(rawValue: sourceRaw) ?? .manual,
            status: MealStatus(rawValue: statusRaw) ?? .draft,
            photoName: photoName,
            nutrients: (try? JSONDecoder().decode([String: Double].self, from: nutrientsData)) ?? [:],
            chargeID: chargeID
        )
        record.kindRaw = kindRaw
        return record
    }
}
