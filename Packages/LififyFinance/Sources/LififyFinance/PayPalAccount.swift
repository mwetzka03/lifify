import Foundation
import LififyCore
import SwiftData

/// The PayPal account: payments from the PayPal export and PayPal e-mails land here, and the
/// matching direct debits of a checking account become transfers to it.
@MainActor
public enum PayPalAccount {
    /// The account's name, which also finds it again.
    public nonisolated static let name = "PayPal"
    /// How many days after a PayPal payment its direct debit may reach the checking account.
    public nonisolated static let debitWindowDays = 3

    /// The PayPal account, if one exists.
    public static func find(in accounts: [Account]) -> Account? {
        accounts.first { $0.kind == .checking && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The PayPal account, created on first use.
    @discardableResult
    public static func ensure(context: ModelContext) -> Account {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if let existing = find(in: accounts) { return existing }
        let account = Account(name: name, kind: .checking, isLiquid: true)
        context.insert(account)
        try? context.save()
        return account
    }

    /// Turns checking-account debits to PayPal into transfers to the PayPal account, once the
    /// payment they fund is there.
    ///
    /// A debit pairs with a PayPal payment of the same amount that happened up to three days before
    /// it. The debit's fixed cost, variable cost, splits, pool, and refund links move to the payment
    /// when the payment has none, so nothing counts twice and no choice is lost. Debits without a
    /// payment stay expenses.
    ///
    /// - Parameter context: The database context.
    /// - Returns: How many debits became transfers.
    @discardableResult
    public static func pairDebits(context: ModelContext) -> Int {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let payPal = find(in: accounts) else { return 0 }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var used = Set(LinkTable.map(.payPalPairing).values)
        let payments = entries.filter { $0.accountID == payPal.id && $0.kind == .expense }
        let debits = entries
            .filter { $0.kind == .expense && $0.accountID != nil && $0.accountID != payPal.id && PayPalBookings.isPayPal(title: $0.title, notes: $0.notes) }
            .sorted { $0.date < $1.date }
        var count = 0
        for debit in debits {
            guard let payment = payment(for: debit, in: payments, used: used) else { continue }
            moveChoices(from: debit, to: payment, context: context)
            debit.kind = .transfer
            debit.fromAccountID = debit.accountID
            debit.toAccountID = payPal.id
            debit.accountID = nil
            debit.amountCents = abs(debit.amountCents)
            LinkTable.set(.payPalPairing, key: debit.id.uuidString, value: payment.id.uuidString)
            used.insert(payment.id.uuidString)
            count += 1
        }
        if count > 0 { try? context.save() }
        return count
    }

    /// The unpaired PayPal payment a debit funds: same amount, at most three days earlier, the closest.
    private static func payment(for debit: LedgerEntry, in payments: [LedgerEntry], used: Set<String>) -> LedgerEntry? {
        let calendar = Calendar.current
        let debitDay = calendar.startOfDay(for: debit.date)
        return payments
            .filter { payment in
                guard !used.contains(payment.id.uuidString), abs(payment.amountCents) == abs(debit.amountCents) else { return false }
                let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: payment.date), to: debitDay).day ?? -1
                return (0...debitWindowDays).contains(gap)
            }
            .min { abs($0.date.timeIntervalSince(debit.date)) < abs($1.date.timeIntervalSince(debit.date)) }
    }

    /// Hands the person's choices on a debit to the payment, unless the payment has its own.
    private static func moveChoices(from debit: LedgerEntry, to payment: LedgerEntry, context: ModelContext) {
        let paymentFree = payment.fixedCostID == nil && payment.variableBudgetID == nil && payment.shoppingItemID == nil
        if paymentFree {
            payment.fixedCostID = debit.fixedCostID
            payment.variableBudgetID = debit.variableBudgetID
            payment.shoppingItemID = debit.shoppingItemID
        }
        debit.fixedCostID = nil
        debit.variableBudgetID = nil
        debit.shoppingItemID = nil
        let id = debit.id
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>(predicate: #Predicate { $0.transactionID == id }))) ?? []
        let paymentHasSplits = !(((try? context.fetch(FetchDescriptor<TransactionSplit>())) ?? []).filter { $0.transactionID == payment.id }.isEmpty)
        for split in splits {
            if paymentHasSplits { context.delete(split) } else { split.transactionID = payment.id }
        }
        // Refund links and a picked icon follow the payment, which is now the real expense.
        ImportCarryOver.renameLinks([debit.id.uuidString: payment.id.uuidString])
    }
}

/// Reads PayPal's activity export ("Aktivitäten herunterladen", CSV).
///
/// Only completed euro payments and refunds become rows. Top-ups from and payouts to a bank are left
/// out, because the bank account already has them as direct debits and credits.
public enum PayPalCSV {
    /// The rows of a PayPal export, or `nil` when the file is not one.
    public static func parse(_ text: String) -> [ImportedTransaction]? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first?.replacingOccurrences(of: "\u{FEFF}", with: "") else { return nil }
        let delimiter: Character = headerLine.filter { $0 == ";" }.count > headerLine.filter { $0 == "," }.count ? ";" : ","
        let headers = BankImportService.csvFields(headerLine, delimiter: delimiter).map(BankImportService.normalizeHeader)
        guard let code = BankImportService.index(of: ["transaktionscode", "transactionid"], in: headers),
              let date = BankImportService.index(of: ["datum", "date"], in: headers),
              let amount = BankImportService.index(of: ["netto", "net", "brutto", "gross"], in: headers)
        else { return nil }
        let columns = Columns(
            date: date, amount: amount, code: code,
            name: BankImportService.index(of: ["name"], in: headers),
            type: BankImportService.index(of: ["typ", "type", "beschreibung", "description"], in: headers),
            status: BankImportService.index(of: ["status"], in: headers),
            currency: BankImportService.index(of: ["waehrung", "wahrung", "currency"], in: headers)
        )
        return lines.dropFirst().compactMap { row(BankImportService.csvFields($0, delimiter: delimiter), columns: columns) }
    }

    /// Says whether a PayPal line moves money to or from a bank instead of paying someone.
    public static func isBankMovement(type: String) -> Bool {
        let folded = type.lowercased()
        return folded.contains("bank") || folded.contains("währungsumrechnung") || folded.contains("currency conversion")
            || folded.contains("autorisierung") || folded.contains("authorization")
    }

    /// The column positions of one export.
    private struct Columns {
        let date: Int, amount: Int, code: Int
        let name: Int?, type: Int?, status: Int?, currency: Int?
    }

    /// One payment or refund, or `nil` for a line that is not one.
    private static func row(_ fields: [String], columns: Columns) -> ImportedTransaction? {
        guard fields.indices.contains(columns.amount), fields.indices.contains(columns.date),
              let date = BankImportService.parseDate(fields[columns.date]),
              let cents = Money.cents(from: fields[columns.amount]), cents != 0
        else { return nil }
        let status = BankImportService.field(at: columns.status, from: fields).lowercased()
        guard status.isEmpty || status.contains("abgeschlossen") || status.contains("completed") else { return nil }
        let currency = BankImportService.field(at: columns.currency, from: fields).uppercased()
        guard currency.isEmpty || currency == "EUR" else { return nil }
        let type = BankImportService.field(at: columns.type, from: fields)
        guard !isBankMovement(type: type) else { return nil }
        let name = BankImportService.field(at: columns.name, from: fields)
        let code = BankImportService.field(at: columns.code, from: fields)
        let details = [
            type.isEmpty ? nil : "Typ: \(type)",
            name.isEmpty ? nil : "\(L("Gegenpartei", "Counterparty")): \(name)",
            "\(L("Transaktionscode", "Transaction ID")): \(code)"
        ].compactMap { $0 }.joined(separator: "\n")
        let title = name.isEmpty ? (type.isEmpty ? "PayPal" : type) : name
        return BankImportService.imported(
            date: date, title: title, amount: cents, senderIBAN: "", recipientIBAN: "",
            legacyIBAN: "", legacyTitle: title, details: details, distinct: code
        )
    }
}

/// Reads PayPal's payment e-mails, passed in by a Shortcuts automation.
public enum PayPalMail {
    /// Amount, direction, and payee of a PayPal e-mail, or `nil` when it names no payment.
    ///
    /// It understands lines like "Sie haben eine Zahlung über 10,99 € EUR an Netflix.com gesendet",
    /// "… an Spotify AB autorisiert", "… von Max Muster erhalten", and the English "You sent a
    /// payment of €10.99 EUR to Netflix.com".
    public static func parse(_ text: String) -> ParsedNotice? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let cents = amount(in: flat), cents > 0 else { return nil }
        let incoming = matches(flat, #"(erhalten|received|Rückzahlung|Erstattung|refund)"#)
        let payee = (incoming
            ? capture(flat, #"(?:von|from)\s+(.+?)\s+(?:erhalten|received)"#)
            : capture(flat, #"\b(?:an|to)\s+(.+?)\s+(?:gesendet|autorisiert|bezahlt|geschickt)"#)
                ?? capture(flat, #"(?:sent a payment of|Zahlung über)\s+\S+\s+(?:EUR\s+)?(?:to|an)\s+([^.\n]+)"#))
            ?? "PayPal"
        let title = payee.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,")))
        return ParsedNotice(amountCents: incoming ? cents : -cents, title: title.isEmpty ? "PayPal" : title, direction: incoming ? .in : .out)
    }

    /// The first euro amount, in German ("1.234,56") or English ("1,234.56") notation.
    private static func amount(in text: String) -> Int? {
        guard let raw = capture(text, #"(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})(?!\d)"#) else { return nil }
        let decimalComma = raw.dropLast(2).last == ","
        let digits = decimalComma
            ? raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            : raw.replacingOccurrences(of: ",", with: "")
        return Double(digits).map { Int(($0 * 100).rounded()) }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The first capture group of a pattern.
    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
