import Foundation
import LififyCore
import SwiftData

/// One buy, sale, gift, or opening of a holding. `position` keeps the stored order.
@Model
public final class StoredHoldingLot {
    public var lotID: UUID
    public var holdingID: UUID
    public var position: Int
    public var date: Date
    public var quantity: Double
    public var unitPriceCents: Int
    public var amountCents: Int
    public var isSale: Bool
    public var isSavingsPlan: Bool
    public var ledgerEntryID: UUID?
    public var source: String

    /// Stores a lot with its position in the holding.
    public init(_ lot: HoldingLot, holdingID: UUID, position: Int) {
        lotID = lot.id
        self.holdingID = holdingID
        self.position = position
        date = lot.date
        quantity = lot.quantity
        unitPriceCents = lot.unitPriceCents
        amountCents = lot.amountCents
        isSale = lot.isSale
        isSavingsPlan = lot.isSavingsPlan
        ledgerEntryID = lot.ledgerEntryID
        source = lot.source
    }

    public var lot: HoldingLot {
        HoldingLot(
            id: lotID,
            date: date,
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            amountCents: amountCents,
            isSale: isSale,
            isSavingsPlan: isSavingsPlan,
            ledgerEntryID: ledgerEntryID,
            source: source
        )
    }
}

/// The stored form of a savings plan.
@Model
public final class StoredSavingsPlan {
    public var planID: UUID
    public var position: Int
    public var isin: String
    public var name: String
    public var amountCents: Int
    public var cadenceRaw: String
    public var checkingAccountID: UUID
    public var portfolioAccountID: UUID
    public var holdingID: UUID?
    public var lastExecution: Date
    public var historyThrough: Date
    public var active: Bool
    public var fixedCostID: UUID?

    /// Stores a plan with its list position.
    public init(_ plan: SavingsPlanRecord, position: Int) {
        planID = plan.id
        self.position = position
        isin = plan.isin
        name = plan.name
        amountCents = plan.amountCents
        cadenceRaw = plan.cadenceRaw
        checkingAccountID = plan.checkingAccountID
        portfolioAccountID = plan.portfolioAccountID
        holdingID = plan.holdingID
        lastExecution = plan.lastExecution
        historyThrough = plan.historyThrough
        active = plan.active
        fixedCostID = plan.fixedCostID
    }

    public var plan: SavingsPlanRecord {
        SavingsPlanRecord(
            id: planID,
            isin: isin,
            name: name,
            amountCents: amountCents,
            cadenceRaw: cadenceRaw,
            checkingAccountID: checkingAccountID,
            portfolioAccountID: portfolioAccountID,
            holdingID: holdingID,
            lastExecution: lastExecution,
            historyThrough: historyThrough,
            active: active,
            fixedCostID: fixedCostID
        )
    }
}

/// A position that was fully sold. Its lots stay together as one history.
@Model
public final class StoredClosedPosition {
    public var position: Int
    public var isin: String
    public var name: String
    public var lotsData: Data

    /// Stores a closed position with its list position.
    public init(_ record: ClosedPositionRecord, position: Int) {
        self.position = position
        isin = record.isin
        name = record.name
        lotsData = (try? JSONEncoder().encode(record.lots)) ?? Data("[]".utf8)
    }

    public var record: ClosedPositionRecord {
        ClosedPositionRecord(
            isin: isin,
            name: name,
            lots: (try? JSONDecoder().decode([HoldingLot].self, from: lotsData)) ?? []
        )
    }
}

/// Market symbol, previous close, and first purchase date of one holding.
@Model
public final class StoredHoldingMarket {
    @Attribute(.unique) public var holdingID: UUID
    public var symbol: String?
    public var previousCloseCents: Int?
    public var purchaseDate: Date?

    public init(holdingID: UUID, symbol: String? = nil, previousCloseCents: Int? = nil, purchaseDate: Date? = nil) {
        self.holdingID = holdingID
        self.symbol = symbol
        self.previousCloseCents = previousCloseCents
        self.purchaseDate = purchaseDate
    }
}

/// Links a depot account to its checking account.
@Model
public final class StoredPortfolioLink {
    @Attribute(.unique) public var checkingID: UUID
    public var portfolioID: UUID

    public init(checkingID: UUID, portfolioID: UUID) {
        self.checkingID = checkingID
        self.portfolioID = portfolioID
    }
}
