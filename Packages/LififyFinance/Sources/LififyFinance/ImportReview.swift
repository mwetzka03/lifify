import Foundation
import LififyCore

/// A question about a row that resembles a stored booking.
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

/// All open questions of an import.
public struct ImportReview: Identifiable {
    public let id: UUID
    public var similar: [ImportSimilarChoice]
    public var accountID: UUID?
    public var currentCents: Int?

    public init(
        id: UUID = UUID(),
        similar: [ImportSimilarChoice] = [],
        accountID: UUID? = nil,
        currentCents: Int? = nil
    ) {
        self.id = id
        self.similar = similar
        self.accountID = accountID
        self.currentCents = currentCents
    }

    public var isEmpty: Bool { similar.isEmpty }
}
