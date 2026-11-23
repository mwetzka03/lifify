import Foundation
import LififyCore
import SwiftData

/// The stored form of a planned transfer.
@Model
public final class StoredTransferForecast {
    @Attribute(.unique) public var forecastID: UUID
    public var position: Int
    public var name: String
    public var amountCents: Int
    public var fromAccountID: UUID?
    public var toAccountID: UUID?
    public var cadenceRaw: String
    public var firstDate: Date
    public var endDate: Date?
    public var dueRuleRaw: String
    public var dayOfMonth: Int
    public var active: Bool

    /// Stores a transfer with its list position.
    public init(_ record: TransferForecastRecord, position: Int) {
        forecastID = record.id
        self.position = position
        name = record.name
        amountCents = record.amountCents
        fromAccountID = record.fromAccountID
        toAccountID = record.toAccountID
        cadenceRaw = record.cadenceRaw
        firstDate = record.firstDate
        endDate = record.endDate
        dueRuleRaw = record.dueRuleRaw
        dayOfMonth = record.dayOfMonth
        active = record.active
    }

    public var record: TransferForecastRecord {
        var record = TransferForecastRecord(
            id: forecastID,
            name: name,
            amountCents: amountCents,
            fromAccountID: fromAccountID,
            toAccountID: toAccountID,
            firstDate: firstDate,
            endDate: endDate,
            dayOfMonth: dayOfMonth,
            active: active
        )
        record.cadenceRaw = cadenceRaw
        record.dueRuleRaw = dueRuleRaw
        return record
    }
}

/// A Shortcuts template. The template's own rules decide how its fields are read.
@Model
public final class StoredNoticeTemplate {
    public var position: Int
    public var payload: Data

    public init(payload: Data, position: Int) {
        self.payload = payload
        self.position = position
    }
}
