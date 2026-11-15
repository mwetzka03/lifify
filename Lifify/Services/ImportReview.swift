import Foundation

struct ImportTransferChoice: Identifiable {
    var id: UUID { entryID }
    var entryID: UUID
    var signedAmountCents: Int
    var date: Date
    var title: String
    var notes: String
    var checkingAccountID: UUID
    var otherAccountID: UUID
    var otherAccountName: String
    var iban: String
    var matchedEntryID: UUID
    var matchedTitle: String
    var matchedDate: Date
    var matchedAmountCents: Int
    var accept = false
}

struct ImportSimilarChoice: Identifiable {
    var id: UUID
    var fingerprint: String
    var date: Date
    var title: String
    var notes: String
    var signedAmountCents: Int
    var accountID: UUID
    var existingTitle: String
    var existingDate: Date
    var existingAmountCents: Int
    var include = false
    var isExtra = false
}

struct ImportReview: Identifiable {
    let id: UUID
    var transfers: [ImportTransferChoice]
    var similar: [ImportSimilarChoice]
    var accountID: UUID?
    var currentCents: Int?

    init(
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

    var isEmpty: Bool { transfers.isEmpty && similar.isEmpty }
}
