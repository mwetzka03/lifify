import Foundation
import SwiftData

/// One buy, sale, gift, or opening of a holding. `position` keeps the stored order.
@Model
final class StoredHoldingLot {
    var lotID: UUID
    var holdingID: UUID
    var position: Int
    var date: Date
    var quantity: Double
    var unitPriceCents: Int
    var amountCents: Int
    var isSale: Bool
    var isSavingsPlan: Bool
    var ledgerEntryID: UUID?
    var source: String

    init(_ lot: HoldingLot, holdingID: UUID, position: Int) {
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

    var lot: HoldingLot {
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

@Model
final class StoredSavingsPlan {
    var planID: UUID
    var position: Int
    var isin: String
    var name: String
    var amountCents: Int
    var cadenceRaw: String
    var checkingAccountID: UUID
    var portfolioAccountID: UUID
    var holdingID: UUID?
    var lastExecution: Date
    var historyThrough: Date
    var active: Bool
    var fixedCostID: UUID?

    init(_ plan: SavingsPlanRecord, position: Int) {
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

    var plan: SavingsPlanRecord {
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
final class StoredClosedPosition {
    var position: Int
    var isin: String
    var name: String
    var lotsData: Data

    init(_ record: ClosedPositionRecord, position: Int) {
        self.position = position
        isin = record.isin
        name = record.name
        lotsData = (try? JSONEncoder().encode(record.lots)) ?? Data("[]".utf8)
    }

    var record: ClosedPositionRecord {
        ClosedPositionRecord(
            isin: isin,
            name: name,
            lots: (try? JSONDecoder().decode([HoldingLot].self, from: lotsData)) ?? []
        )
    }
}

/// Market symbol, previous close, and first purchase date of one holding.
@Model
final class StoredHoldingMarket {
    @Attribute(.unique) var holdingID: UUID
    var symbol: String?
    var previousCloseCents: Int?
    var purchaseDate: Date?

    init(holdingID: UUID, symbol: String? = nil, previousCloseCents: Int? = nil, purchaseDate: Date? = nil) {
        self.holdingID = holdingID
        self.symbol = symbol
        self.previousCloseCents = previousCloseCents
        self.purchaseDate = purchaseDate
    }
}

@Model
final class StoredPortfolioLink {
    @Attribute(.unique) var checkingID: UUID
    var portfolioID: UUID

    init(checkingID: UUID, portfolioID: UUID) {
        self.checkingID = checkingID
        self.portfolioID = portfolioID
    }
}
