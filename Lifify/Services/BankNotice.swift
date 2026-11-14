import Foundation
import SwiftData

enum BankNoticeBank: String, Equatable {
    case sparkasse
    case tradeRepublic

    var fallbackTitle: String {
        switch self {
        case .sparkasse: "Sparkasse"
        case .tradeRepublic: "Trade Republic"
        }
    }
}

enum BankNoticeDirection: Equatable {
    case `in`
    case out
}

struct ParsedNotice: Equatable {
    var amountCents: Int
    var title: String
    var direction: BankNoticeDirection
}

struct BookedNotice: Equatable {
    var accountID: UUID
    var amountCents: Int
    var direction: BankNoticeDirection
    var date: Date
}

enum BankNoticePlan: Equatable {
    case book(accountID: UUID, title: String, amountCents: Int, kind: LedgerKind)
    case duplicate
    case unreadable
    case missingAccount
}

enum BankNoticeCopy {
    static var booked: String { L("Gebucht", "Booked") }
    static var duplicate: String { L("Schon gebucht", "Already booked") }
    static var unreadable: String { L("Die Mitteilung ließ sich nicht lesen.", "The notice could not be read.") }
    static var missingSparkasse: String {
        L("Das Sparkassen-Girokonto fehlt.", "The Sparkasse checking account is missing.")
    }
    static var missingTradeRepublic: String {
        L("Das Trade-Republic-Konto fehlt.", "The Trade Republic account is missing.")
    }
    static var unavailable: String { L("Lifify ist noch nicht bereit.", "Lifify is not ready yet.") }
    static var shortcutTitle: String { L("Bankmitteilung buchen", "Record bank notice") }
}

enum BankNotice {
    /// Wallet and bank notices for one payment usually arrive within a few hours.
    static let duplicateWindow: TimeInterval = 6 * 60 * 60

    static func parse(_ text: String, fallbackTitle: String) -> ParsedNotice? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = firstAmount(in: trimmed) else { return nil }
        guard let direction = direction(in: trimmed, sign: amount.sign) else { return nil }
        let cents = abs(amount.cents)
        guard cents > 0 else { return nil }
        let title = shortTitle(from: trimmed, removing: amount.range, direction: direction, fallback: fallbackTitle)
        return ParsedNotice(
            amountCents: direction == .out ? -cents : cents,
            title: title,
            direction: direction
        )
    }

    static func plan(
        text: String,
        bank: BankNoticeBank,
        accounts: [NamedAccount],
        existing: [BookedNotice],
        now: Date
    ) -> BankNoticePlan {
        guard let notice = parse(text, fallbackTitle: bank.fallbackTitle) else { return .unreadable }
        guard let accountID = BankNoticeAccounts.resolve(bank, in: accounts) else { return .missingAccount }
        if isDuplicate(notice, accountID: accountID, existing: existing, now: now) { return .duplicate }
        return .book(
            accountID: accountID,
            title: notice.title,
            amountCents: notice.amountCents,
            kind: notice.direction == .out ? .expense : .income
        )
    }

    static func isDuplicate(
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

    static func booked(_ entry: LedgerEntry) -> BookedNotice? {
        guard let accountID = entry.accountID else { return nil }
        guard entry.kind == .income || entry.kind == .expense else { return nil }
        return BookedNotice(
            accountID: accountID,
            amountCents: entry.amountCents,
            direction: entry.kind == .income ? .in : .out,
            date: entry.date
        )
    }

    private struct AmountHit {
        var cents: Int
        var sign: BankNoticeDirection?
        var range: Range<String.Index>
    }

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

    private static func directionSign(_ match: NSTextCheckingResult, in text: String) -> BankNoticeDirection? {
        guard match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[range] == "-" ? .out : .in
    }

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
        "abbuchung", "lastschrift", "kartenzahlung", "ausgabe", "bezahlt", "paid", "payment",
        "sent", "kauf", "buy", "withdrawal", "auszahlung", "spent", "debit", "belastung"
    ]
    private static let inWords = [
        "gutschrift", "eingang", "erhalten", "received", "einzahlung", "dividende", "dividend",
        "verkauf", "sell", "credit", "gutgeschrieben", "incoming", "erstattung", "refund"
    ]

    private static func containsWord(_ words: [String], in text: String) -> Bool {
        words.contains { word in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        }
    }

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

enum BankNoticeAccounts {
    static func resolve(_ bank: BankNoticeBank, in accounts: [NamedAccount]) -> UUID? {
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

enum BankNoticeURL {
    static func decode(_ url: URL) -> (bank: BankNoticeBank, text: String)? {
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

@MainActor
enum BankNoticeIntake {
    @discardableResult
    static func commit(
        text: String,
        bank: BankNoticeBank,
        context: ModelContext,
        now: Date = .now
    ) -> String {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let named = accounts.map { NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain) }
        let existing = entries.compactMap(BankNotice.booked)
        switch BankNotice.plan(text: text, bank: bank, accounts: named, existing: existing, now: now) {
        case .book(let accountID, let title, let amountCents, let kind):
            let entry = LedgerEntry(
                date: now,
                title: title,
                amountCents: amountCents,
                kind: kind,
                accountID: accountID
            )
            context.insert(entry)
            do {
                try context.save()
            } catch {
                context.delete(entry)
                return BankNoticeCopy.unavailable
            }
            return BankNoticeCopy.booked
        case .duplicate:
            return BankNoticeCopy.duplicate
        case .unreadable:
            return BankNoticeCopy.unreadable
        case .missingAccount:
            return bank == .sparkasse ? BankNoticeCopy.missingSparkasse : BankNoticeCopy.missingTradeRepublic
        }
    }

    @discardableResult
    static func open(_ url: URL, context: ModelContext) -> String? {
        guard let call = BankNoticeURL.decode(url) else { return nil }
        return commit(text: call.text, bank: call.bank, context: context)
    }
}

private extension NSRange {
    var locationIsNotFound: Bool { location == NSNotFound }
}
