import Foundation
import LififyCore
import SwiftData

/// The banks with built-in notice handling.
public enum BankNoticeBank: String, Equatable {
    case sparkasse
    case tradeRepublic

    public var fallbackTitle: String {
        switch self {
        case .sparkasse: "Sparkasse"
        case .tradeRepublic: "Trade Republic"
        }
    }
}

/// Whether a notice is money in or out.
public enum BankNoticeDirection: Equatable {
    case `in`
    case out
}

/// The values read from a bank notice.
public struct ParsedNotice: Equatable {
    public var amountCents: Int
    public var title: String
    public var direction: BankNoticeDirection

    public init(amountCents: Int, title: String, direction: BankNoticeDirection) {
        self.amountCents = amountCents
        self.title = title
        self.direction = direction
    }
}

/// A stored booking, reduced to what duplicate detection needs.
public struct BookedNotice: Equatable {
    public var accountID: UUID
    public var amountCents: Int
    public var direction: BankNoticeDirection
    public var date: Date
    public var title: String?

    public init(accountID: UUID, amountCents: Int, direction: BankNoticeDirection, date: Date, title: String? = nil) {
        self.accountID = accountID
        self.amountCents = amountCents
        self.direction = direction
        self.date = date
        self.title = title
    }
}

/// What a notice will book.
public enum BankNoticePlan: Equatable {
    case book(accountID: UUID, title: String, amountCents: Int, kind: LedgerKind)
    case bookNoted(accountID: UUID, title: String, amountCents: Int, kind: LedgerKind, notes: String)
    case bookTransfer(fromAccountID: UUID, toAccountID: UUID, title: String, amountCents: Int)
    case duplicate
    case ignored
    case unreadable
    case missingAccount
}

/// Texts for notice results.
public enum BankNoticeCopy {
    public static var booked: String { L("Gebucht", "Booked") }

    /// The short confirmation of a booked notice, like "12,50 € gebucht: REWE".
    public static func booked(_ entry: LedgerEntry) -> String {
        L("\(Money.string(cents: abs(entry.amountCents))) gebucht: \(entry.title)", "\(Money.string(cents: abs(entry.amountCents))) booked: \(entry.title)")
    }
    public static var duplicate: String { L("Schon gebucht", "Already booked") }
    public static var ignored: String { L("Nicht gebucht", "Not booked") }
    public static var unreadable: String { L("Die Mitteilung ließ sich nicht lesen.", "The notice could not be read.") }
    public static var missingSparkasse: String {
        L("Das Sparkassen-Girokonto fehlt.", "The Sparkasse checking account is missing.")
    }
    public static var missingTradeRepublic: String {
        L("Das Trade-Republic-Konto fehlt.", "The Trade Republic account is missing.")
    }
    public static var unavailable: String { L("Lifify ist noch nicht bereit.", "Lifify is not ready yet.") }
    public static var shortcutTitle: String { L("Bankmitteilung buchen", "Record bank notice") }
}

/// Turns the text of a bank notice into a booking plan.
@MainActor
public enum BankNotice {
    /// Wallet and bank notices for one payment usually arrive within a few hours.
    public static let duplicateWindow: TimeInterval = 6 * 60 * 60
    /// Own-account transfers are matched across the same window as the bank import.
    public static let transferWindowDays = 3
    public static let transferWindow: TimeInterval = TimeInterval(transferWindowDays) * 24 * 60 * 60

    /// Reads amount, direction, and title from a notice.
    public static func parse(_ text: String, fallbackTitle: String) -> ParsedNotice? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = firstAmount(in: trimmed) else { return nil }
        guard let direction = direction(in: trimmed, sign: amount.sign) else { return nil }
        let cents = abs(amount.cents)
        guard cents > 0 else { return nil }
        let title = merchant(in: trimmed)
            ?? shortTitle(from: trimmed, removing: amount.range, direction: direction, fallback: fallbackTitle)
        return ParsedNotice(
            amountCents: direction == .out ? -cents : cents,
            title: title,
            direction: direction
        )
    }

    /// Decides what a notice books on an account.
    public static func plan(
        text: String,
        bank: BankNoticeBank,
        accounts: [NamedAccount],
        existing: [BookedNotice],
        now: Date,
        templates: [NoticeTemplate] = []
    ) -> BankNoticePlan {
        guard let accountID = BankNoticeAccounts.resolve(bank, in: accounts) else { return .missingAccount }
        let template = NoticeTemplateStore.matching(text: text, accountID: accountID, in: templates)
        if template?.action == .ignore { return .ignored }
        let read = template?.format?.parse(text) ?? parse(text, fallbackTitle: bank.fallbackTitle)
        guard let notice = read else { return .unreadable }
        if let template {
            return planTemplate(
                template,
                notice: notice,
                accountID: accountID,
                accounts: accounts,
                existing: existing,
                now: now
            )
        }
        if bank == .tradeRepublic, notice.direction == .in, isTransferReceived(text) {
            return planTransfer(
                notice: notice,
                toAccountID: accountID,
                accounts: accounts,
                existing: existing,
                now: now
            )
        }
        if isDuplicate(notice, accountID: accountID, existing: existing, now: now) { return .duplicate }
        return .book(
            accountID: accountID,
            title: notice.title,
            amountCents: notice.amountCents,
            kind: notice.direction == .out ? .expense : .income
        )
    }

    /// Plans a booking from a matching template.
    private static func planTemplate(
        _ template: NoticeTemplate,
        notice: ParsedNotice,
        accountID: UUID,
        accounts: [NamedAccount],
        existing: [BookedNotice],
        now: Date
    ) -> BankNoticePlan {
        switch template.action {
        case .expense:
            let booked = ParsedNotice(amountCents: -abs(notice.amountCents), title: notice.title, direction: .out)
            if isDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
            return .book(accountID: accountID, title: notice.title, amountCents: booked.amountCents, kind: .expense)
        case .income:
            let booked = ParsedNotice(amountCents: abs(notice.amountCents), title: notice.title, direction: .in)
            if template.format == .dividend {
                if isSameTitledDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
                return .bookNoted(
                    accountID: accountID,
                    title: notice.title,
                    amountCents: booked.amountCents,
                    kind: .income,
                    notes: "Typ: Ertrag"
                )
            }
            if isDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
            return .book(accountID: accountID, title: notice.title, amountCents: booked.amountCents, kind: .income)
        case .depotBuy:
            let booked = ParsedNotice(amountCents: -abs(notice.amountCents), title: notice.title, direction: .out)
            if isSameTitledDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
            guard let depot = depotID(for: accountID, in: accounts) else {
                return .book(accountID: accountID, title: notice.title, amountCents: booked.amountCents, kind: .expense)
            }
            return .bookTransfer(fromAccountID: accountID, toAccountID: depot, title: notice.title, amountCents: abs(notice.amountCents))
        case .depotSale:
            let booked = ParsedNotice(amountCents: abs(notice.amountCents), title: notice.title, direction: .in)
            if isSameTitledDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
            guard let depot = depotID(for: accountID, in: accounts) else {
                return .book(accountID: accountID, title: notice.title, amountCents: booked.amountCents, kind: .income)
            }
            return .bookTransfer(fromAccountID: depot, toAccountID: accountID, title: notice.title, amountCents: abs(notice.amountCents))
        case .ignore:
            return .ignored
        case .transferIn:
            return planTransfer(
                notice: ParsedNotice(amountCents: abs(notice.amountCents), title: notice.title, direction: .in),
                toAccountID: accountID,
                fromAccountID: template.counterpartyAccountID,
                accounts: accounts,
                existing: existing,
                now: now
            )
        case .transferOut:
            let other = template.counterpartyAccountID
                ?? accounts.first(where: { $0.kind == .checking && $0.id != accountID })?.id
            guard let other else {
                let booked = ParsedNotice(amountCents: -abs(notice.amountCents), title: notice.title, direction: .out)
                if isDuplicate(booked, accountID: accountID, existing: existing, now: now) { return .duplicate }
                return .book(accountID: accountID, title: notice.title, amountCents: booked.amountCents, kind: .expense)
            }
            let cash = abs(notice.amountCents)
            if existing.contains(where: { entry in
                entry.accountID == accountID
                    && entry.direction == .out
                    && abs(entry.amountCents) == cash
                    && abs(entry.date.timeIntervalSince(now)) <= transferWindow
            }) {
                return .duplicate
            }
            return .bookTransfer(
                fromAccountID: accountID,
                toAccountID: other,
                title: L("Umbuchung", "Transfer"),
                amountCents: cash
            )
        }
    }

    /// Finds the depot linked to an account.
    private static func depotID(for accountID: UUID, in accounts: [NamedAccount]) -> UUID? {
        if let linked = PortfolioLinkStore.portfolioID(for: accountID),
           accounts.contains(where: { $0.id == linked }) {
            return linked
        }
        return accounts.first { $0.kind == .portfolio }?.id
    }

    /// Two stocks can pay or cost the same amount on one day. A known title tells them apart.
    private static func isSameTitledDuplicate(
        _ notice: ParsedNotice,
        accountID: UUID,
        existing: [BookedNotice],
        now: Date
    ) -> Bool {
        existing.contains { entry in
            entry.accountID == accountID
                && entry.direction == notice.direction
                && abs(entry.amountCents) == abs(notice.amountCents)
                && abs(entry.date.timeIntervalSince(now)) <= duplicateWindow
                && (entry.title == nil || entry.title == notice.title)
        }
    }

    /// Says whether the notice is already booked.
    public static func isDuplicate(
        _ notice: ParsedNotice,
        accountID: UUID,
        existing: [BookedNotice],
        now: Date
    ) -> Bool {
        existing.contains { entry in
            entry.accountID == accountID
                && entry.direction == notice.direction
                && abs(entry.amountCents) == abs(notice.amountCents)
                && abs(entry.date.timeIntervalSince(now)) <= duplicateWindow
        }
    }

    /// Reduces a booking for duplicate detection.
    public static func booked(_ entry: LedgerEntry) -> BookedNotice? {
        guard entry.kind == .income || entry.kind == .expense else { return nil }
        return records(entry).first
    }

    /// Lists the records of a booking, one per affected account.
    public static func records(_ entry: LedgerEntry) -> [BookedNotice] {
        if entry.kind == .income || entry.kind == .expense, let accountID = entry.accountID {
            return [
                BookedNotice(
                    accountID: accountID,
                    amountCents: entry.amountCents,
                    direction: entry.kind == .income ? .in : .out,
                    date: entry.date,
                    title: entry.title
                )
            ]
        }
        guard entry.kind == .transfer else { return [] }
        var rows: [BookedNotice] = []
        let cash = abs(entry.amountCents)
        if let from = entry.fromAccountID {
            rows.append(BookedNotice(accountID: from, amountCents: -cash, direction: .out, date: entry.date, title: entry.title))
        }
        if let to = entry.toAccountID {
            rows.append(BookedNotice(accountID: to, amountCents: cash, direction: .in, date: entry.date, title: entry.title))
        }
        return rows
    }

    /// An amount found in a text.
    private struct AmountHit {
        var cents: Int
        var sign: BankNoticeDirection?
        var range: Range<String.Index>
    }

    /// Finds the first amount in a text.
    private static func firstAmount(in text: String) -> AmountHit? {
        let pattern = #"(?i)([+-])?\s*(€|eur|euro)?\s*(\d{1,3}(?:\.\d{3})+(?:,\d{2})|\d{1,3}(?:,\d{3})+(?:\.\d{2})|\d+(?:[.,]\d{2}))(?:\s*(€|eur|euro))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var signedOnly: AmountHit?
        for match in matches {
            guard let numberRange = Range(match.range(at: 3), in: text),
                  let whole = Range(match.range, in: text),
                  let cents = Money.cents(from: String(text[numberRange]))
            else { continue }
            let sign = directionSign(match, in: text)
            let currency = !match.range(at: 2).locationIsNotFound || !match.range(at: 4).locationIsNotFound
            let hit = AmountHit(cents: cents, sign: sign, range: whole)
            if currency { return hit }
            if sign != nil, signedOnly == nil { signedOnly = hit }
        }
        return signedOnly
    }

    /// Reads the direction from the amount's sign.
    private static func directionSign(_ match: NSTextCheckingResult, in text: String) -> BankNoticeDirection? {
        guard match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[range] == "-" ? .out : .in
    }

    /// Reads the direction from sign or wording.
    private static func direction(in text: String, sign: BankNoticeDirection?) -> BankNoticeDirection? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let outgoing = containsWord(outWords, in: folded)
        let incoming = containsWord(inWords, in: folded)
        if let sign {
            return sign
        }
        if outgoing, !incoming { return .out }
        if incoming, !outgoing { return .in }
        return nil
    }

    private static let outWords = [
        "abbuchung", "lastschrift", "kartenzahlung", "ausgegeben", "ausgabe", "bezahlt", "paid", "payment",
        "sent", "kauf", "buy", "withdrawal", "auszahlung", "spent", "debit", "belastung"
    ]
    private static let inWords = [
        "gutschrift", "eingang", "erhalten", "received", "einzahlung", "dividende", "dividend",
        "verkauf", "sell", "credit", "gutgeschrieben", "incoming", "erstattung", "refund"
    ]

    /// Says whether one of the words occurs.
    private static func containsWord(_ words: [String], in text: String) -> Bool {
        words.contains { word in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        }
    }

    /// Says whether the text reports a received transfer.
    private static func isTransferReceived(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if folded.contains("uberweisung erhalten") { return true }
        if folded.contains("received a transfer") || folded.contains("transfer received") { return true }
        return folded.contains("uberweisung") && folded.contains("erhalten")
    }

    /// Plans a transfer between two own accounts.
    private static func planTransfer(
        notice: ParsedNotice,
        toAccountID: UUID,
        fromAccountID: UUID? = nil,
        accounts: [NamedAccount],
        existing: [BookedNotice],
        now: Date
    ) -> BankNoticePlan {
        let main = fromAccountID.flatMap { id in accounts.first { $0.id == id } }
            ?? accounts.first { $0.kind == .checking && $0.isMain }
        guard let main, main.id != toAccountID else {
            if isDuplicate(notice, accountID: toAccountID, existing: existing, now: now) { return .duplicate }
            return .book(
                accountID: toAccountID,
                title: notice.title,
                amountCents: notice.amountCents,
                kind: .income
            )
        }
        let cash = abs(notice.amountCents)
        if existing.contains(where: { entry in
            entry.accountID == toAccountID
                && entry.direction == .in
                && abs(entry.amountCents) == cash
                && abs(entry.date.timeIntervalSince(now)) <= transferWindow
        }) {
            return .duplicate
        }
        return .bookTransfer(
            fromAccountID: main.id,
            toAccountID: toAccountID,
            title: L("Umbuchung", "Transfer"),
            amountCents: cash
        )
    }

    /// Reads the merchant from a card payment.
    private static func merchant(in text: String) -> String? {
        let pattern = #"(?i)(?:bei|at)\s+(.+?)\s+(?:ausgegeben|spent)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let name = String(text[range]).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        return name.isEmpty ? nil : name
    }

    /// Builds a short title from a notice.
    private static func shortTitle(
        from text: String,
        removing amount: Range<String.Index>,
        direction: BankNoticeDirection,
        fallback: String
    ) -> String {
        var copy = text
        copy.removeSubrange(amount)
        let words = direction == .out ? outWords : inWords
        let folded = copy.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if let word = words.first(where: { folded.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", options: .regularExpression) != nil }),
           let range = copy.range(of: word, options: .caseInsensitive) {
            copy.removeSubrange(range)
        }
        let collapsed = copy.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        if trimmed.isEmpty { return fallback }
        if trimmed.count <= 40 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 40)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespaces)
    }
}

/// Finds the account of a bank.
public enum BankNoticeAccounts {
    /// Returns the bank's checking account.
    public static func resolve(_ bank: BankNoticeBank, in accounts: [NamedAccount]) -> UUID? {
        let checking = accounts.filter { $0.kind == .checking }
        switch bank {
        case .sparkasse:
            if let named = checking.first(where: { $0.name.range(of: "sparkasse", options: .caseInsensitive) != nil }) {
                return named.id
            }
            return checking.first(where: \.isMain)?.id
        case .tradeRepublic:
            return checking.first(where: { $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame })?.id
        }
    }
}

/// Reads the `lifify://notice` link.
public enum BankNoticeURL {
    /// Decodes bank and text from the link.
    public static func decode(_ url: URL) -> (bank: BankNoticeBank, text: String)? {
        guard url.scheme?.lowercased() == "lifify", url.host?.lowercased() == "notice" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let account = items.first { $0.name == "account" }?.value?.lowercased()
        let text = items.first { $0.name == "text" }?.value ?? ""
        let bank: BankNoticeBank?
        switch account {
        case "sparkasse": bank = .sparkasse
        case "traderepublic", "trade-republic", "tr": bank = .tradeRepublic
        default: bank = nil
        }
        guard let bank else { return nil }
        return (bank, text)
    }
}

/// Books notices from Shortcuts and links.
@MainActor
public enum BankNoticeIntake {
    /// Plans and books a notice.
    @discardableResult
    public static func commit(
        text: String,
        bank: BankNoticeBank,
        context: ModelContext,
        now: Date = FinanceClock.now,
        onBooked: ((LedgerEntry) -> Void)? = nil
    ) -> String {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let named = accounts.map { NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain) }
        let existing = entries.flatMap(BankNotice.records)
        NoticeTemplateDefaults.install(accounts: named)
        switch BankNotice.plan(
            text: text,
            bank: bank,
            accounts: named,
            existing: existing,
            now: now,
            templates: NoticeTemplateStore.all()
        ) {
        case .book(let accountID, let title, let amountCents, let kind):
            let entry = LedgerEntry(
                date: now,
                title: title,
                amountCents: amountCents,
                kind: kind,
                accountID: accountID
            )
            return save(entry, context: context, onBooked: onBooked)
        case .bookNoted(let accountID, let title, let amountCents, let kind, let notes):
            let entry = LedgerEntry(
                date: now,
                title: title,
                notes: notes,
                amountCents: amountCents,
                kind: kind,
                accountID: accountID
            )
            return save(entry, context: context, onBooked: onBooked)
        case .bookTransfer(let fromAccountID, let toAccountID, let title, let amountCents):
            let entry = LedgerEntry(
                date: now,
                title: title,
                amountCents: amountCents,
                kind: .transfer,
                fromAccountID: fromAccountID,
                toAccountID: toAccountID
            )
            let message = save(entry, context: context, onBooked: onBooked)
            if message == BankNoticeCopy.booked {
                BankImportApplier.relinkOwnAccounts(context: context)
            }
            return message
        case .duplicate:
            return BankNoticeCopy.duplicate
        case .ignored:
            return BankNoticeCopy.ignored
        case .unreadable:
            return BankNoticeCopy.unreadable
        case .missingAccount:
            return bank == .sparkasse ? BankNoticeCopy.missingSparkasse : BankNoticeCopy.missingTradeRepublic
        }
    }

    /// Books the notice from a link.
    @discardableResult
    public static func open(_ url: URL, context: ModelContext) -> String? {
        guard let call = BankNoticeURL.decode(url) else { return nil }
        return commit(text: call.text, bank: call.bank, context: context)
    }

    /// Saves a booking and returns the result text.
    private static func save(_ entry: LedgerEntry, context: ModelContext, onBooked: ((LedgerEntry) -> Void)?) -> String {
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            return BankNoticeCopy.unavailable
        }
        onBooked?(entry)
        return BankNoticeCopy.booked
    }
}

/// Converts ranges for regular expressions.
private extension NSRange {
    var locationIsNotFound: Bool { location == NSNotFound }
}
