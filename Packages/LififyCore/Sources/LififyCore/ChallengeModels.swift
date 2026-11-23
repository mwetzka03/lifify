import Foundation
import SwiftData

public enum ChallengeCalendarViewMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .day: L("Tag", "Day")
        case .week: L("Woche", "Week")
        case .month: L("Monat", "Month")
        }
    }
}

public enum ChallengeRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case irregular
    case daily
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: L("Einmalig", "Once")
        case .irregular: L("Unregelmäßig", "Irregular")
        case .daily: L("Täglich", "Daily")
        case .weekly: L("Wöchentlich", "Weekly")
        case .monthly: L("Monatlich", "Monthly")
        case .yearly: L("Jährlich", "Yearly")
        }
    }
}
public enum ChallengeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case health
    case abstinence
    case habit
    case sport
    case todo
    case other

    public var id: String { rawValue }

    /// The categories offered when creating a challenge. More can be added in settings.
    public static let offered: [ChallengeCategory] = [.sport, .abstinence, .other]

    public var label: String {
        switch self {
        case .health: L("Gesundheit", "Health")
        case .abstinence: L("Abstinenz", "Abstinence")
        case .habit: L("Gewohnheit", "Habit")
        case .sport: L("Sport", "Sport")
        case .todo: L("Aufgabe", "To-do")
        case .other: L("Sonstiges", "Other")
        }
    }
}
@Model
public final class ChallengeCalendarEvent {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var colorHex: String
    public var icon: String
    public var linkedChallengeID: UUID?
    public var linkedChallengeGroupID: UUID?
    public var linkedRewardID: UUID?
    public var externalIdentifier: String?
    public var isReadOnly: Bool

    public init(
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

public enum RecommendationCopy {
    public static var empty: String { L("Keine importierten Empfehlungen", "No imported recommendations") }
    public static var heading: String { L("Empfehlungen", "Recommendations") }
}

extension ChallengeCalendarEvent {
    public var isReminderSuggestion: Bool {
        externalIdentifier?.hasPrefix("reminder:") == true
    }
}

@Model
public final class ChallengeItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var categoryRaw: String
    public var recurrenceRaw: String
    public var startDate: Date?
    public var endDate: Date?
    public var weeklyDays: String
    public var rewardCoins: Int
    public var streakTarget: Int
    /// The one source for group membership, including the group from its event. Write through `groupIDs`.
    public var groupIDsRaw: String = ""
    public var isArchived: Bool
    public var externalIdentifier: String?
    public var isReadOnly: Bool
    public var createdAt: Date

    public var category: ChallengeCategory {
        get { ChallengeCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    public var recurrence: ChallengeRecurrence {
        get { ChallengeRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    public var weekdaySet: Set<Int> {
        get { Set(weeklyDays.split(separator: ",").compactMap { Int($0) }) }
        set { weeklyDays = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    public var groupIDs: [UUID] {
        get { ChallengeGroups.ids(primary: nil, stored: groupIDsRaw) }
        set { groupIDsRaw = ChallengeGroups.stored(newValue) }
    }

    public func belongs(to group: UUID) -> Bool {
        ChallengeGroups.contains(groupIDs, group)
    }

    public init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        category: ChallengeCategory = .other,
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
        self.groupIDsRaw = groupID?.uuidString ?? ""
        self.isArchived = isArchived
        self.externalIdentifier = externalIdentifier
        self.isReadOnly = isReadOnly
        self.createdAt = createdAt
    }
}
@Model
public final class ChallengeCompletion {
    @Attribute(.unique) public var id: UUID
    public var challengeID: UUID
    public var date: Date
    public var earnedCoins: Int

    public init(id: UUID = UUID(), challengeID: UUID, date: Date, earnedCoins: Int) {
        self.id = id
        self.challengeID = challengeID
        self.date = date
        self.earnedCoins = earnedCoins
    }
}
@Model
public final class ChallengeGroup {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var startDate: Date?
    public var colorHex: String

    public init(id: UUID = UUID(), title: String, details: String = "", startDate: Date? = nil, colorHex: String = "#7B61A8") {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate
        self.colorHex = colorHex
    }
}

@Model
public final class CoinTransaction {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var title: String
    public var amount: Int
    public var referenceID: UUID?

    public init(id: UUID = UUID(), date: Date = .now, title: String, amount: Int, referenceID: UUID? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.referenceID = referenceID
    }
}

@Model
public final class RewardItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var price: Int
    public var icon: String
    public var colorHex: String
    public var urlString: String
    public var bucketListItemID: UUID?
    public var isActive: Bool

    public init(
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
public final class RewardPurchase {
    @Attribute(.unique) public var id: UUID
    public var rewardID: UUID
    public var title: String
    public var price: Int
    public var date: Date

    public init(id: UUID = UUID(), rewardID: UUID, title: String, price: Int, date: Date = .now) {
        self.id = id
        self.rewardID = rewardID
        self.title = title
        self.price = price
        self.date = date
    }
}

@Model
public final class BucketListItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var targetYear: Int
    public var isCompleted: Bool
    public var linkedRewardID: UUID?

    public init(
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
