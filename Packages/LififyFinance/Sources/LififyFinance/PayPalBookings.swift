import Foundation
import LififyCore
import SwiftData

/// Recognizes bank bookings that went through PayPal and names them after the real payee.
///
/// Every PayPal debit carries PayPal's own IBAN and name; the shop or person only appears in the
/// reference, as in "1054…/PP.2481.PP/. Netflix.com, Ihr Einkauf bei Netflix.com".
@MainActor
public enum PayPalBookings {
    /// The suffix that marks a renamed PayPal booking.
    public static let marker = " (PayPal)"

    /// Says whether a booking's title or counterparty is PayPal.
    public static func isPayPal(title: String, notes: String) -> Bool {
        let text = (title + " " + counterparty(in: notes)).lowercased()
        return text.contains("paypal")
    }

    /// The real payee from the reference, or `nil` when PayPal does not name one.
    ///
    /// - Parameter notes: The booking's notes with its "Verwendungszweck" line.
    /// - Returns: The shop or person, such as "Netflix.com".
    public static func payee(in notes: String) -> String? {
        let purpose = BankImportService.purposeMark(notes: notes)
        if let range = purpose.range(of: "Ihr Einkauf bei", options: .caseInsensitive) {
            let name = clean(String(purpose[range.upperBound...]))
            // "Ihr Einkauf bei" with nothing after it means PayPal names no payee at all.
            return name.isEmpty ? nil : name
        }
        // References without that phrase carry the name between "/. " and the comma.
        if let start = purpose.range(of: "/. ") {
            let rest = String(purpose[start.upperBound...])
            let name = clean(rest.components(separatedBy: ",").first ?? "")
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// The title a PayPal booking gets: the payee with a PayPal mark, or just "PayPal".
    ///
    /// - Parameters:
    ///   - title: The title from the bank.
    ///   - notes: The booking's notes.
    /// - Returns: A new title for a PayPal booking, or the title unchanged for any other booking.
    public static func title(for title: String, notes: String) -> String {
        guard isPayPal(title: title, notes: notes), !title.hasSuffix(marker) else { return title }
        return payee(in: notes).map { $0 + marker } ?? "PayPal"
    }

    /// Renames the PayPal bookings that still carry PayPal's own name.
    ///
    /// A title the person changed by hand no longer mentions PayPal, so it is left alone.
    ///
    /// - Parameter entries: The bookings to look at.
    /// - Returns: How many bookings were renamed.
    @discardableResult
    public static func rename(_ entries: [LedgerEntry]) -> Int {
        var count = 0
        for entry in entries where entry.title.lowercased().contains("paypal") && !entry.title.hasSuffix(marker) && entry.title != "PayPal" {
            let renamed = title(for: entry.title, notes: entry.notes)
            guard renamed != entry.title else { continue }
            entry.title = renamed
            count += 1
        }
        return count
    }

    /// The "Gegenpartei" line of the notes.
    private static func counterparty(in notes: String) -> String {
        notes.components(separatedBy: .newlines)
            .first { $0.lowercased().hasPrefix("gegenpartei:") || $0.lowercased().hasPrefix("counterparty:") }
            ?? ""
    }

    /// Trims spaces and trailing punctuation.
    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.")))
    }
}

/// Bookings from bank notices, which a later bank import fills in instead of booking twice.
///
/// The import overwrites the notice booking in place, so its ID, and with it every assignment,
/// split, pool, and refund link, stays.
@MainActor
public enum NoticeBookings {
    /// Marks a booking as coming from a notice.
    public static func mark(_ id: UUID) {
        LinkTable.set(.noticeBooking, key: id.uuidString, value: "1")
    }

    /// Says whether a booking came from a notice and still waits for its import.
    public static func isNotice(_ id: UUID) -> Bool {
        LinkTable.map(.noticeBooking)[id.uuidString] != nil
    }

    /// The notice booking an import row stands for: same account, same amount and direction, same
    /// day, and the same name or IBAN.
    ///
    /// - Parameters:
    ///   - row: The imported row.
    ///   - accountID: The account the row is booked on.
    ///   - entries: All bookings.
    /// - Returns: The waiting notice booking, if one fits.
    public static func match(_ row: ImportedTransaction, accountID: UUID, in entries: [LedgerEntry]) -> LedgerEntry? {
        let calendar = Calendar.current
        let names = rowNames(row)
        return entries.first { entry in
            isNotice(entry.id)
                && entry.importFingerprint == nil
                && entry.accountID == accountID
                && entry.amountCents == row.amountCents
                && calendar.isDate(entry.date, inSameDayAs: row.date)
                && sameParty(entry, names: names, row: row)
        }
    }

    /// Fills a notice booking with the import row and ends its waiting.
    public static func fill(_ entry: LedgerEntry, with row: ImportedTransaction) {
        entry.title = PayPalBookings.title(for: row.title, notes: row.notes)
        entry.notes = row.notes
        entry.date = row.date
        entry.importFingerprint = row.fingerprint
        LinkTable.set(.noticeBooking, key: entry.id.uuidString, value: nil)
    }

    /// The comparable names of a row: its title, its PayPal payee, and its counterparty.
    private static func rowNames(_ row: ImportedTransaction) -> [String] {
        [row.title, PayPalBookings.payee(in: row.notes) ?? ""]
            .map(SubscriptionDetector.payeeKey)
            .filter { $0.count >= 3 }
    }

    /// Says whether the notice names the same party as the row, by name or by IBAN in its text.
    private static func sameParty(_ entry: LedgerEntry, names: [String], row: ImportedTransaction) -> Bool {
        let own = SubscriptionDetector.payeeKey(entry.title)
        if own.count >= 3, names.contains(where: { $0.contains(own) || own.contains($0) }) { return true }
        let iban = (row.amountCents < 0 ? row.recipientIBAN : row.senderIBAN).uppercased().filter { !$0.isWhitespace }
        return !iban.isEmpty && (entry.title + " " + entry.notes).uppercased().filter { !$0.isWhitespace }.contains(iban)
    }
}
