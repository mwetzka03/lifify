import Foundation
import SwiftData

@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kindRaw: String
    public var isLiquid: Bool
    public var isMain: Bool
    public var iban: String
    public var parentAccountID: UUID?
    public var createdAt: Date

    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .checking }
        set { kindRaw = newValue.rawValue }
    }

    public init(
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
public final class LedgerEntry {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var title: String
    public var notes: String
    public var amountCents: Int
    public var kindRaw: String
    public var accountID: UUID?
    public var fromAccountID: UUID?
    public var toAccountID: UUID?
    public var fixedCostID: UUID?
    public var variableBudgetID: UUID?
    public var shoppingItemID: UUID?
    public var importFingerprint: String?
    public var createdAt: Date

    public var kind: LedgerKind {
        get { LedgerKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(
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
public final class TransactionSplit {
    @Attribute(.unique) public var id: UUID
    public var transactionID: UUID
    public var targetID: UUID
    public var kindRaw: String
    public var periodKey: String
    public var amountCents: Int

    public var kind: SplitKind {
        get { SplitKind(rawValue: kindRaw) ?? .variableBudget }
        set { kindRaw = newValue.rawValue }
    }

    public init(
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
