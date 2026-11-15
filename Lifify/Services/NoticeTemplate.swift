import Foundation

enum NoticeTemplateAction: String, Codable, CaseIterable, Equatable, Hashable {
    case expense
    case income
    case refund
    case interest
    case dividend
    case cashback
    case portfolioGift
    case transferIn
    case transferOut
    case portfolioBuy
    case portfolioSale
    case savingsPlan

    var label: String {
        switch self {
        case .expense: BookingCategory.expense.label
        case .income: BookingCategory.income.label
        case .refund: BookingCategory.refund.label
        case .interest: BookingCategory.interest.label
        case .dividend: BookingCategory.dividend.label
        case .cashback: BookingCategory.cashback.label
        case .portfolioGift: BookingCategory.portfolioGift.label
        case .transferIn: L("Umbuchung auf dieses Konto", "Transfer onto this account")
        case .transferOut: L("Umbuchung von diesem Konto", "Transfer from this account")
        case .portfolioBuy: BookingCategory.portfolioBuy.label
        case .portfolioSale: BookingCategory.portfolioSale.label
        case .savingsPlan: BookingCategory.savingsPlan.label
        }
    }

    var category: BookingCategory {
        switch self {
        case .expense: .expense
        case .income: .income
        case .refund: .refund
        case .interest: .interest
        case .dividend: .dividend
        case .cashback: .cashback
        case .portfolioGift: .portfolioGift
        case .transferIn, .transferOut: .transfer
        case .portfolioBuy: .portfolioBuy
        case .portfolioSale: .portfolioSale
        case .savingsPlan: .savingsPlan
        }
    }

    var direction: BankNoticeDirection {
        switch self {
        case .expense, .transferOut, .portfolioBuy, .savingsPlan: .out
        case .income, .refund, .interest, .dividend, .cashback, .portfolioGift, .transferIn, .portfolioSale: .in
        }
    }

    var needsCheckingCounterparty: Bool {
        self == .transferIn || self == .transferOut
    }

    var needsPortfolioCounterparty: Bool {
        self == .portfolioBuy || self == .portfolioSale || self == .savingsPlan
    }

    var needsCounterparty: Bool {
        needsCheckingCounterparty || needsPortfolioCounterparty
    }
}

enum NoticePatternToken: Equatable {
    case text(String)
    case amount
    case name
}

struct NoticePattern: Equatable {
    var tokens: [NoticePatternToken]

    var isUsable: Bool {
        tokens.contains { if case .amount = $0 { return true } else { return false } }
            && tokens.contains { token in
                if case .text(let text) = token {
                    return text.contains(where: \.isLetter)
                }
                return false
            }
    }

    var literalLength: Int {
        tokens.reduce(0) { total, token in
            if case .text(let text) = token {
                return total + text.count
            }
            return total
        }
    }

    var display: String {
        tokens.map { token in
            switch token {
            case .text(let text): text
            case .amount: L("[Betrag]", "[Amount]")
            case .name: L("[Name]", "[Name]")
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    func matches(_ text: String) -> Bool {
        guard isUsable, let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let folded = NoticePattern.folded(text)
        let ns = folded as NSString
        return regex.firstMatch(in: folded, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private var regexPattern: String {
        let amount = #"[+-]?\s*(?:€|eur|euro)?\s*(?:\d{1,3}(?:\.\d{3})+(?:,\d{2})|\d{1,3}(?:,\d{3})+(?:\.\d{2})|\d+(?:[.,]\d{2}))(?:\s*(?:€|eur|euro))?"#
        var parts: [String] = []
        for token in tokens {
            switch token {
            case .text(let text):
                let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
                guard !words.isEmpty else { continue }
                parts.append(
                    words
                        .map { NSRegularExpression.escapedPattern(for: NoticePattern.folded(String($0))) }
                        .joined(separator: "\\s+")
                )
            case .amount:
                parts.append(amount)
            case .name:
                parts.append(".+?")
            }
        }
        return "(?i)" + parts.joined(separator: "[\\s\\S]*?")
    }

    static func from(example: String) -> NoticePattern {
        let trimmed = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NoticePattern(tokens: []) }
        var work = trimmed
        if let amount = BankNotice.amount(in: work) {
            work.replaceSubrange(amount.range, with: amountSentinel)
        }
        work = generalizeNames(in: work)
        return NoticePattern(tokens: tokenize(work))
    }

    private static let amountSentinel = "<<<AMOUNT>>>"
    private static let nameSentinel = "<<<NAME>>>"

    private static func generalizeNames(in text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .map { raw -> String in
                let word = String(raw)
                if word == amountSentinel || word == nameSentinel { return word }
                let folded = folded(word.trimmingCharacters(in: .punctuationCharacters))
                if folded.isEmpty { return word }
                if keptWords.contains(folded) { return word }
                return nameSentinel
            }
            .reduce(into: [String]()) { result, word in
                if word == nameSentinel, result.last == nameSentinel { return }
                result.append(word)
            }
            .joined(separator: " ")
    }

    private static func tokenize(_ text: String) -> [NoticePatternToken] {
        var tokens: [NoticePatternToken] = []
        var remaining = text[...]
        while !remaining.isEmpty {
            if remaining.hasPrefix(amountSentinel) {
                tokens.append(.amount)
                remaining = remaining.dropFirst(amountSentinel.count)
                continue
            }
            if remaining.hasPrefix(nameSentinel) {
                tokens.append(.name)
                remaining = remaining.dropFirst(nameSentinel.count)
                continue
            }
            var buffer = ""
            while !remaining.isEmpty,
                  !remaining.hasPrefix(amountSentinel),
                  !remaining.hasPrefix(nameSentinel) {
                buffer.append(remaining.removeFirst())
            }
            let collapsed = buffer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !collapsed.isEmpty {
                tokens.append(.text(collapsed))
            }
        }
        return tokens
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    private static let keptWords: Set<String> = [
        "abbuchung", "lastschrift", "kartenzahlung", "ausgegeben", "ausgabe", "bezahlt", "paid", "payment",
        "sent", "kauf", "buy", "withdrawal", "auszahlung", "spent", "debit", "belastung",
        "gutschrift", "eingang", "erhalten", "received", "einzahlung", "dividende", "dividend",
        "verkauf", "sell", "credit", "gutgeschrieben", "incoming", "erstattung", "refund",
        "uberweisung", "echtzeit", "paypal", "visa", "kontowecker",
        "zinsen", "interest", "sparplan", "saveback", "ertrag", "wertpapier", "aktie", "share", "shares",
        "coupon", "kupon", "order", "ausgefuhrt", "executed", "depot", "portfolio", "cashback",
        "du", "sie", "uns", "ich", "wir", "you", "we", "hast", "haben", "hat", "have", "has", "had",
        "bei", "at", "von", "from", "uber", "wurde", "wurden", "wird", "worden", "been", "were", "was",
        "are", "is", "dein", "deine", "deiner", "deinen", "dir", "ihnen", "die", "der", "das", "den",
        "dem", "des", "und", "or", "and", "the", "a", "an", "in", "im", "on", "fur", "fuer", "to", "of",
        "mit", "nach", "per", "eur", "euro"
    ]
}

struct NoticeTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var accountID: UUID
    var name: String
    var example: String
    var action: NoticeTemplateAction
    var counterpartyAccountID: UUID?

    init(
        id: UUID = UUID(),
        accountID: UUID,
        name: String,
        example: String,
        action: NoticeTemplateAction,
        counterpartyAccountID: UUID? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.example = example
        self.action = action
        self.counterpartyAccountID = counterpartyAccountID
        self.name = name
    }

    var pattern: NoticePattern { NoticePattern.from(example: example) }

    func matches(_ text: String) -> Bool {
        pattern.matches(text)
    }

    static func markers(in text: String) -> [String] {
        let folded = NoticePattern.folded(text)
        return markerWords.filter { word in
            folded.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                options: .regularExpression
            ) != nil
        }
    }

    static func displayPattern(from example: String) -> String {
        NoticePattern.from(example: example).display
    }

    private static let markerWords = [
        "abbuchung", "lastschrift", "kartenzahlung", "ausgegeben", "ausgabe", "bezahlt", "paid", "payment",
        "sent", "kauf", "buy", "withdrawal", "auszahlung", "spent", "debit", "belastung",
        "gutschrift", "eingang", "erhalten", "received", "einzahlung", "dividende", "dividend",
        "verkauf", "sell", "credit", "gutgeschrieben", "incoming", "erstattung", "refund",
        "uberweisung", "echtzeit", "paypal", "visa", "kontowecker",
        "zinsen", "interest", "sparplan", "saveback", "ertrag"
    ]
}

enum NoticeTemplateStore {
    private static let key = "lifify.noticeTemplates"

    static func all() -> [NoticeTemplate] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([NoticeTemplate].self, from: data)
        else { return [] }
        return rows
    }

    static func save(_ templates: [NoticeTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func matching(text: String, accountID: UUID, in templates: [NoticeTemplate]) -> NoticeTemplate? {
        templates
            .filter { $0.accountID == accountID && $0.matches(text) }
            .max { lhs, rhs in
                if lhs.pattern.literalLength != rhs.pattern.literalLength {
                    return lhs.pattern.literalLength < rhs.pattern.literalLength
                }
                return NoticeTemplate.markers(in: lhs.example).count < NoticeTemplate.markers(in: rhs.example).count
            }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
