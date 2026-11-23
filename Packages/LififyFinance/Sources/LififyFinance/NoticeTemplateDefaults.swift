import Foundation
import LififyCore

/// The known notice layouts of Sparkasse and Trade Republic. Each one reads its own amount and title.
public enum NoticeFormat: String, Codable, CaseIterable, Sendable {
    case sparkasseDebit
    case sparkasseCredit
    case tradeBuy
    case tradeSale
    case savingsPlan
    case dividend
    case cardPayment
    case cancelledOrder

    public var bank: BankNoticeBank {
        switch self {
        case .sparkasseDebit, .sparkasseCredit: .sparkasse
        default: .tradeRepublic
        }
    }

    public var name: String {
        switch self {
        case .sparkasseDebit: L("Umsatzwecker: Abbuchung", "Balance alert: debit")
        case .sparkasseCredit: L("Umsatzwecker: Gutschrift", "Balance alert: credit")
        case .tradeBuy: L("Kauf ausgeführt", "Buy executed")
        case .tradeSale: L("Verkauf ausgeführt", "Sale executed")
        case .savingsPlan: L("Sparplan ausgeführt", "Savings plan executed")
        case .dividend: L("Dividende erhalten", "Dividend received")
        case .cardPayment: L("Kartenzahlung", "Card payment")
        case .cancelledOrder: L("Order storniert", "Order cancelled")
        }
    }

    /// Made-up values in the real layout. No account number or balance of a real person belongs here.
    public var example: String {
        switch self {
        case .sparkasseDebit: "Konto 1234567890:\nBeispiel.: -19,99 EUR\nNeuer Saldo: 1.000,00 EUR"
        case .sparkasseCredit: "Konto 1234567890:\nBEISPIEL: 27,32 EUR\nNeuer Saldo: 1.000,00 EUR"
        case .tradeBuy: "Deine Kauf Order von 2 × Beispiel AG wurde für 283,24 € ausgeführt."
        case .tradeSale: "Deine Verkaufen Order von 200 × Beispiel AG wurde für 90,00 € ausgeführt."
        case .savingsPlan: "Dein Beispiel ETF Sparplan von 45,00 € wurde ausgeführt"
        case .dividend: "Beispiel AG hat heute eine Dividende von 0,27 $ pro Aktie ausgeschüttet. Du hast 0,01 € erhalten."
        case .cardPayment: "15,90 € bei Beispiel ausgegeben"
        case .cancelledOrder: "Deine Limit Kauf Order von 3 × Beispiel AG wurde storniert."
        }
    }

    public var action: NoticeTemplateAction {
        switch self {
        case .sparkasseDebit, .cardPayment: .expense
        case .sparkasseCredit, .dividend: .income
        case .tradeBuy, .savingsPlan: .depotBuy
        case .tradeSale: .depotSale
        case .cancelledOrder: .ignore
        }
    }

    /// Says whether the text has this format.
    public func matches(_ text: String) -> Bool {
        if self == .cancelledOrder {
            return Self.groups(#"(?i)\bOrder von\b.*\bwurde storniert\b"#, in: Self.flat(text)) != nil
        }
        return parse(text) != nil
    }

    /// Reads amount, title, and direction from a notice.
    public func parse(_ text: String) -> ParsedNotice? {
        let flat = Self.flat(text)
        switch self {
        case .sparkasseDebit, .sparkasseCredit:
            guard let row = Self.groups(#"(?i)Konto\s+[\w-]+:\s*(.+?):\s*([+-])?\s*("# + Self.amount + #")\s*EUR\s+Neuer Saldo:"#, in: flat)
            else { return nil }
            let isDebit = row[1] == "-"
            guard isDebit == (self == .sparkasseDebit) else { return nil }
            let title = row[0].trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return Self.notice(row[2], title: title, direction: isDebit ? .out : .in)
        case .tradeBuy, .tradeSale:
            let verb = self == .tradeBuy ? "Kauf" : "Verkaufen"
            guard let row = Self.groups(#"(?i)\b"# + verb + #"\s+Order von\s+[\d.,]+\s*[×x]\s*(.+?)\s+wurde für\s+("# + Self.amount + #")\s*€\s+ausgeführt"#, in: flat)
            else { return nil }
            let prefix = self == .tradeBuy ? L("Kauf", "Buy") : L("Verkauf", "Sale")
            return Self.notice(row[1], title: "\(prefix): \(row[0])", direction: self == .tradeBuy ? .out : .in)
        case .savingsPlan:
            guard let row = Self.groups(#"(?i)\bDein\s+(.+?)\s+Sparplan von\s+("# + Self.amount + #")\s*€\s+wurde ausgeführt"#, in: flat)
            else { return nil }
            return Self.notice(row[1], title: "Sparplan: \(row[0])", direction: .out)
        case .dividend:
            guard let row = Self.groups(#"(?i)(?:Dividende erhalten\s+)?(\S.*?)\s+hat heute eine Dividende\b.*?\bDu hast\s+("# + Self.amount + #")\s*€\s+erhalten"#, in: flat)
            else { return nil }
            return Self.notice(row[1], title: "\(L("Dividende", "Dividend")): \(row[0])", direction: .in)
        case .cardPayment:
            guard let row = Self.groups(#"(?i)("# + Self.amount + #")\s*€\s+bei\s+(.+?)\s+ausgegeben"#, in: flat)
            else { return nil }
            return Self.notice(row[0], title: row[1], direction: .out)
        case .cancelledOrder:
            return nil
        }
    }

    private static let amount = #"\d{1,3}(?:\.\d{3})+,\d{2}|\d+,\d{2}"#

    /// Collapses all whitespace.
    private static func flat(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Builds a parsed notice from an amount text.
    private static func notice(_ amount: String, title: String, direction: BankNoticeDirection) -> ParsedNotice? {
        guard let cents = Money.cents(from: amount), cents > 0, !title.isEmpty else { return nil }
        return ParsedNotice(amountCents: direction == .out ? -cents : cents, title: title, direction: direction)
    }

    /// The capture groups of the first match. A group that did not take part is empty.
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<max(match.numberOfRanges, 1)).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// Puts the known layouts into the normal template list. A deleted one stays deleted.
@MainActor
public enum NoticeTemplateDefaults {
    /// Adds the built-in templates that are missing or not dismissed.
    @discardableResult
    public static func install(accounts: [NamedAccount]) -> [NoticeTemplate] {
        var templates = NoticeTemplateStore.all()
        let present = Set(templates.compactMap(\.format))
        let dismissed = LinkTable.map(.dismissedNoticeTemplates)
        var changed = false
        for format in NoticeFormat.allCases where !present.contains(format) && dismissed[format.rawValue] == nil {
            guard let accountID = BankNoticeAccounts.resolve(format.bank, in: accounts) else { continue }
            templates.append(NoticeTemplate(
                accountID: accountID,
                name: format.name,
                example: format.example,
                action: format.action,
                format: format
            ))
            changed = true
        }
        if changed { NoticeTemplateStore.save(templates) }
        return templates
    }

    /// Deletes templates and remembers dismissed built-in ones.
    public static func delete(_ ids: Set<UUID>, from templates: [NoticeTemplate]) -> [NoticeTemplate] {
        for template in templates where ids.contains(template.id) {
            if let format = template.format { dismiss(format) }
        }
        let kept = templates.filter { !ids.contains($0.id) }
        NoticeTemplateStore.save(kept)
        return kept
    }

    /// A built-in layout whose example was rewritten becomes the person's own template.
    public static func detachedIfEdited(_ template: NoticeTemplate) -> NoticeTemplate {
        guard let format = template.format, template.example != format.example else { return template }
        dismiss(format)
        var own = template
        own.format = nil
        return own
    }

    /// Remembers that a built-in template was removed.
    private static func dismiss(_ format: NoticeFormat) {
        LinkTable.set(.dismissedNoticeTemplates, key: format.rawValue, value: "true")
    }
}
