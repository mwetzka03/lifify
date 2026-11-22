import Foundation
import LififyChallenges
import LififyCore
import SwiftData

@Model
public final class StoredMeal {
    @Attribute(.unique) public var mealID: UUID
    public var dayKey: String
    public var title: String
    public var note: String
    public var correction: String
    public var createdAt: Date
    public var sourceRaw: String
    public var statusRaw: String
    public var photoName: String?
    public var nutrientsData: Data
    public var kindRaw: String
    public var chargeID: UUID?

    public init(_ meal: MealRecord) {
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

    public func update(from meal: MealRecord) {
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

    public var meal: MealRecord {
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
