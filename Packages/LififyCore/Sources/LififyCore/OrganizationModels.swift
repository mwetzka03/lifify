import Foundation
import SwiftData

@Model
public final class ShoppingItem {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var amountCents: Int
    public var plannedDate: Date?
    public var groupName: String
    public var urlString: String
    public var notes: String
    public var isPurchased: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int = 0,
        plannedDate: Date? = nil,
        groupName: String = "",
        urlString: String = "",
        notes: String = "",
        isPurchased: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.plannedDate = plannedDate
        self.groupName = groupName
        self.urlString = urlString
        self.notes = notes
        self.isPurchased = isPurchased
        self.createdAt = createdAt
    }
}

@Model
public final class DebtEntry {
    @Attribute(.unique) public var id: UUID
    public var contactName: String
    public var title: String
    public var amountCents: Int
    public var directionRaw: String
    public var date: Date
    public var isSettled: Bool

    public var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .owedToMe }
        set { directionRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        contactName: String,
        title: String,
        amountCents: Int,
        direction: DebtDirection,
        date: Date = .now,
        isSettled: Bool = false
    ) {
        self.id = id
        self.contactName = contactName
        self.title = title
        self.amountCents = amountCents
        self.directionRaw = direction.rawValue
        self.date = date
        self.isSettled = isSettled
    }
}

@Model
public final class ExpenseGroup {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var date: Date
    public var notes: String

    public init(id: UUID = UUID(), name: String, date: Date = .now, notes: String = "") {
        self.id = id
        self.name = name
        self.date = date
        self.notes = notes
    }
}

@Model
public final class ExpenseGroupLine {
    @Attribute(.unique) public var id: UUID
    public var groupID: UUID
    public var name: String
    public var amountCents: Int
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        groupID: UUID,
        name: String,
        amountCents: Int,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.amountCents = amountCents
        self.sortOrder = sortOrder
    }
}

@Model
public final class PortfolioHolding {
    @Attribute(.unique) public var id: UUID
    public var accountID: UUID?
    public var name: String
    public var symbol: String
    public var quantity: Double
    public var purchasePriceCents: Int
    public var currentPriceCents: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        accountID: UUID? = nil,
        name: String,
        symbol: String = "",
        quantity: Double,
        purchasePriceCents: Int,
        currentPriceCents: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.symbol = symbol
        self.quantity = quantity
        self.purchasePriceCents = purchasePriceCents
        self.currentPriceCents = currentPriceCents
        self.updatedAt = updatedAt
    }
}

// Kept only so existing SwiftData stores remain readable; no article feature uses it.
@Model
public final class SavedArticle {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var urlString: String
    public var notes: String
    public var savedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String = "",
        notes: String = "",
        savedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.notes = notes
        self.savedAt = savedAt
    }
}
