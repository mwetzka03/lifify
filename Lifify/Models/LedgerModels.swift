import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var isLiquid: Bool
    var isMain: Bool
    var iban: String
    var parentAccountID: UUID?
    var createdAt: Date

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .checking }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind = .checking,
        isLiquid: Bool = true,
        isMain: Bool = false,
        iban: String = "",
        parentAccountID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.isLiquid = isLiquid
        self.isMain = isMain
        self.iban = iban
        self.parentAccountID = parentAccountID
        self.createdAt = createdAt
    }
}

@Model
final class LedgerEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var notes: String
    var amountCents: Int
    var kindRaw: String
    var accountID: UUID?
    var fromAccountID: UUID?
    var toAccountID: UUID?
    var fixedCostID: UUID?
    var variableBudgetID: UUID?
    var shoppingItemID: UUID?
    var importFingerprint: String?
    var createdAt: Date

    var kind: LedgerKind {
        get { LedgerKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        notes: String = "",
        amountCents: Int,
        kind: LedgerKind,
        accountID: UUID? = nil,
        fromAccountID: UUID? = nil,
        toAccountID: UUID? = nil,
        fixedCostID: UUID? = nil,
        variableBudgetID: UUID? = nil,
        shoppingItemID: UUID? = nil,
        importFingerprint: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.notes = notes
        self.amountCents = amountCents
        self.kindRaw = kind.rawValue
        self.accountID = accountID
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.fixedCostID = fixedCostID
        self.variableBudgetID = variableBudgetID
        self.shoppingItemID = shoppingItemID
        self.importFingerprint = importFingerprint
        self.createdAt = createdAt
    }
}

@Model
final class TransactionSplit {
    @Attribute(.unique) var id: UUID
    var transactionID: UUID
    var targetID: UUID
    var kindRaw: String
    var periodKey: String
    var amountCents: Int

    var kind: SplitKind {
        get { SplitKind(rawValue: kindRaw) ?? .variableBudget }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        transactionID: UUID,
        targetID: UUID,
        kind: SplitKind,
        periodKey: String,
        amountCents: Int
    ) {
        self.id = id
        self.transactionID = transactionID
        self.targetID = targetID
        self.kindRaw = kind.rawValue
        self.periodKey = periodKey
        self.amountCents = amountCents
    }
}
