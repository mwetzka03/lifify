import Foundation
import LififyCore

public struct ImportTransferChoice: Identifiable {
    public var id: UUID { entryID }
    public var entryID: UUID
    public var signedAmountCents: Int
    public var date: Date
    public var title: String
    public var notes: String
    public var checkingAccountID: UUID
    public var otherAccountID: UUID
    public var otherAccountName: String
    public var iban: String
    public var matchedEntryID: UUID
    public var matchedTitle: String
    public var matchedDate: Date
    public var matchedAmountCents: Int
    public var accept = false

    public init(entryID: UUID, signedAmountCents: Int, date: Date, title: String, notes: String, checkingAccountID: UUID, otherAccountID: UUID, otherAccountName: String, iban: String, matchedEntryID: UUID, matchedTitle: String, matchedDate: Date, matchedAmountCents: Int, accept: Bool = false) {
        self.entryID = entryID
        self.signedAmountCents = signedAmountCents
        self.date = date
        self.title = title
        self.notes = notes
        self.checkingAccountID = checkingAccountID
        self.otherAccountID = otherAccountID
        self.otherAccountName = otherAccountName
        self.iban = iban
        self.matchedEntryID = matchedEntryID
        self.matchedTitle = matchedTitle
        self.matchedDate = matchedDate
        self.matchedAmountCents = matchedAmountCents
        self.accept = accept
    }
}

public struct ImportSimilarChoice: Identifiable {
    public var id: UUID
    public var fingerprint: String
    public var date: Date
    public var title: String
    public var notes: String
    public var signedAmountCents: Int
    public var accountID: UUID
    public var existingTitle: String
    public var existingDate: Date
    public var existingAmountCents: Int
    public var include = false
    public var isExtra = false

    public init(id: UUID, fingerprint: String, date: Date, title: String, notes: String, signedAmountCents: Int, accountID: UUID, existingTitle: String, existingDate: Date, existingAmountCents: Int, include: Bool = false, isExtra: Bool = false) {
        self.id = id
        self.fingerprint = fingerprint
        self.date = date
        self.title = title
        self.notes = notes
        self.signedAmountCents = signedAmountCents
        self.accountID = accountID
        self.existingTitle = existingTitle
        self.existingDate = existingDate
        self.existingAmountCents = existingAmountCents
        self.include = include
        self.isExtra = isExtra
    }
}

public struct ImportReview: Identifiable {
    public let id: UUID
    public var transfers: [ImportTransferChoice]
    public var similar: [ImportSimilarChoice]
    public var accountID: UUID?
    public var currentCents: Int?

    public init(
        id: UUID = UUID(),
        transfers: [ImportTransferChoice] = [],
        similar: [ImportSimilarChoice] = [],
        accountID: UUID? = nil,
        currentCents: Int? = nil
    ) {
        self.id = id
        self.transfers = transfers
        self.similar = similar
        self.accountID = accountID
        self.currentCents = currentCents
    }

    public var isEmpty: Bool { transfers.isEmpty && similar.isEmpty }
}
