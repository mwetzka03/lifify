import Foundation
import SwiftData

enum ChallengeCalendarViewMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: L("Tag", "Day")
        case .week: L("Woche", "Week")
        case .month: L("Monat", "Month")
        }
    }
}

enum ChallengeRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case irregular
    case daily
    case weekly
    case monthly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: L("Einmalig", "Once")
        case .irregular: L("Unregelmäßig", "Irregular")
        case .daily: L("Täglich", "Daily")
        case .weekly: L("Wöchentlich", "Weekly")
        case .monthly: L("Monatlich", "Monthly")
        }
    }
}
enum ChallengeCategory: String, Codable, CaseIterable, Identifiable {
    case health
    case habit
    case sport
    case todo
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .health: L("Gesundheit", "Health")
        case .habit: L("Gewohnheit", "Habit")
        case .sport: L("Sport", "Sport")
        case .todo: L("Aufgabe", "To-do")
        case .other: L("Sonstiges", "Other")
        }
    }
}
@Model
final class ChallengeCalendarEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var colorHex: String
    var icon: String
    var linkedChallengeID: UUID?
    var linkedChallengeGroupID: UUID?
    var linkedRewardID: UUID?
    var externalIdentifier: String?
    var isReadOnly: Bool

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        colorHex: String = "#4F7CAC",
        icon: String = "calendar",
        linkedChallengeID: UUID? = nil,
        linkedChallengeGroupID: UUID? = nil,
        linkedRewardID: UUID? = nil,
        externalIdentifier: String? = nil,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.icon = icon
        self.linkedChallengeID = linkedChallengeID
        self.linkedChallengeGroupID = linkedChallengeGroupID
        self.linkedRewardID = linkedRewardID
        self.externalIdentifier = externalIdentifier
        self.isReadOnly = isReadOnly
    }
}
@Model
final class ChallengeItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var categoryRaw: String
    var recurrenceRaw: String
    var startDate: Date?
    var endDate: Date?
    var weeklyDays: String
    var rewardCoins: Int
    var streakTarget: Int
    var groupID: UUID?
    var isArchived: Bool
    var externalIdentifier: String?
    var isReadOnly: Bool
    var createdAt: Date

    var category: ChallengeCategory {
        get { ChallengeCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var recurrence: ChallengeRecurrence {
        get { ChallengeRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    var weekdaySet: Set<Int> {
        get { Set(weeklyDays.split(separator: ",").compactMap { Int($0) }) }
        set { weeklyDays = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        category: ChallengeCategory = .habit,
        recurrence: ChallengeRecurrence = .none,
        startDate: Date? = .now,
        endDate: Date? = nil,
        weeklyDays: Set<Int> = [],
        rewardCoins: Int = 10,
        streakTarget: Int = 0,
        groupID: UUID? = nil,
        isArchived: Bool = false,
        externalIdentifier: String? = nil,
        isReadOnly: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.categoryRaw = category.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.weeklyDays = weeklyDays.sorted().map(String.init).joined(separator: ",")
        self.rewardCoins = rewardCoins
        self.streakTarget = streakTarget
        self.groupID = groupID
        self.isArchived = isArchived
        self.externalIdentifier = externalIdentifier
        self.isReadOnly = isReadOnly
        self.createdAt = createdAt
    }
}
@Model
final class ChallengeCompletion {
    @Attribute(.unique) var id: UUID
    var challengeID: UUID
    var date: Date
    var earnedCoins: Int

    init(id: UUID = UUID(), challengeID: UUID, date: Date, earnedCoins: Int) {
        self.id = id
        self.challengeID = challengeID
        self.date = date
        self.earnedCoins = earnedCoins
    }
}
@Model
final class ChallengeGroup {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var startDate: Date?
    var colorHex: String

    init(id: UUID = UUID(), title: String, details: String = "", startDate: Date? = nil, colorHex: String = "#7B61A8") {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate
        self.colorHex = colorHex
    }
}

@Model
final class CoinTransaction {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var amount: Int
    var referenceID: UUID?

    init(id: UUID = UUID(), date: Date = .now, title: String, amount: Int, referenceID: UUID? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.referenceID = referenceID
    }
}

@Model
final class RewardItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var price: Int
    var icon: String
    var colorHex: String
    var urlString: String
    var bucketListItemID: UUID?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        price: Int,
        icon: String = "gift",
        colorHex: String = "#C78335",
        urlString: String = "",
        bucketListItemID: UUID? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.price = price
        self.icon = icon
        self.colorHex = colorHex
        self.urlString = urlString
        self.bucketListItemID = bucketListItemID
        self.isActive = isActive
    }
}

@Model
final class RewardPurchase {
    @Attribute(.unique) var id: UUID
    var rewardID: UUID
    var title: String
    var price: Int
    var date: Date

    init(id: UUID = UUID(), rewardID: UUID, title: String, price: Int, date: Date = .now) {
        self.id = id
        self.rewardID = rewardID
        self.title = title
        self.price = price
        self.date = date
    }
}

@Model
final class BucketListItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var targetYear: Int
    var isCompleted: Bool
    var linkedRewardID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        targetYear: Int = Calendar.current.component(.year, from: .now),
        isCompleted: Bool = false,
        linkedRewardID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.targetYear = targetYear
        self.isCompleted = isCompleted
        self.linkedRewardID = linkedRewardID
    }
}
// End of challenge models.
