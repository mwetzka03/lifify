import Foundation
import SwiftData

@Model
final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var amountCents: Int
    var plannedDate: Date?
    var groupName: String
    var urlString: String
    var notes: String
    var isPurchased: Bool
    var createdAt: Date

    init(
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
final class DebtEntry {
    @Attribute(.unique) var id: UUID
    var contactName: String
    var title: String
    var amountCents: Int
    var directionRaw: String
    var date: Date
    var isSettled: Bool

    var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .owedToMe }
        set { directionRaw = newValue.rawValue }
    }

    init(
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
final class ExpenseGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var notes: String

    init(id: UUID = UUID(), name: String, date: Date = .now, notes: String = "") {
        self.id = id
        self.name = name
        self.date = date
        self.notes = notes
    }
}

@Model
final class ExpenseGroupLine {
    @Attribute(.unique) var id: UUID
    var groupID: UUID
    var name: String
    var amountCents: Int
    var sortOrder: Int

    init(
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
final class PortfolioHolding {
    @Attribute(.unique) var id: UUID
    var accountID: UUID?
    var name: String
    var symbol: String
    var quantity: Double
    var purchasePriceCents: Int
    var currentPriceCents: Int
    var updatedAt: Date

    init(
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
final class SavedArticle {
    @Attribute(.unique) var id: UUID
    var title: String
    var urlString: String
    var notes: String
    var savedAt: Date

    init(
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
