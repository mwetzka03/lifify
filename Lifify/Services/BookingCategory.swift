import SwiftUI

enum BookingCategory: String, CaseIterable, Identifiable {
    case income
    case interest
    case dividend
    case expense
    case portfolioBuy
    case portfolioSale
    case savingsPlan
    case transfer
    case adjustment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .income: L("Einnahme", "Income")
        case .interest: L("Zinsen", "Interest")
        case .dividend: L("Dividende", "Dividend")
        case .expense: L("Ausgabe", "Expense")
        case .portfolioBuy: L("Depotkauf", "Portfolio buy")
        case .portfolioSale: L("Depotverkauf", "Portfolio sale")
        case .savingsPlan: L("Sparplan", "Savings plan")
        case .transfer: L("Umbuchung", "Transfer")
        case .adjustment: L("Saldo-Korrektur", "Balance adjustment")
        }
    }

    var systemImage: String {
        switch self {
        case .income: "banknote"
        case .interest: "percent"
        case .dividend: "chart.pie"
        case .expense: "cart"
        case .portfolioBuy: "chart.line.uptrend.xyaxis"
        case .portfolioSale: "chart.line.downtrend.xyaxis"
        case .savingsPlan: "repeat.circle"
        case .transfer: "arrow.left.arrow.right"
        case .adjustment: "equal.circle"
        }
    }

    var usesTwoAccounts: Bool {
        switch self {
        case .portfolioBuy, .portfolioSale, .savingsPlan, .transfer: true
        case .income, .interest, .dividend, .expense, .adjustment: false
        }
    }

    var storedKind: LedgerKind {
        switch self {
        case .income, .interest, .dividend: .income
        case .expense: .expense
        case .adjustment: .adjustment
        case .portfolioBuy, .portfolioSale, .savingsPlan, .transfer: .transfer
        }
    }
}

enum BookingScope {
    case combined
    case account
    case depot
}

struct BookingPaint {
    var iconColor: Color
    var amountColor: Color
    var differenceCents: Int?
}

enum BookingClassification {
    static func category(
        of entry: LedgerEntry,
        accounts: [Account],
        viewedAccountID: UUID?
    ) -> BookingCategory {
        if entry.kind == .adjustment { return .adjustment }
        if isSavingsPlan(entry) { return .savingsPlan }
        let portfolios = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        if isPortfolioSale(entry, portfolios: portfolios) { return .portfolioSale }
        if isPortfolioBuy(entry, portfolios: portfolios) { return .portfolioBuy }
        if isDividend(entry) { return .dividend }
        if isInterest(entry) { return .interest }
        switch entry.kind {
        case .income:
            return .income
        case .expense:
            return .expense
        case .transfer:
            guard let viewedAccountID else { return .transfer }
            if entry.fromAccountID == viewedAccountID { return .expense }
            if entry.toAccountID == viewedAccountID { return .income }
            return .transfer
        case .adjustment:
            return .adjustment
        }
    }

    static func signedAmount(
        of entry: LedgerEntry,
        category: BookingCategory,
        viewedAccountID: UUID?
    ) -> Int {
        let amount = abs(entry.amountCents)
        switch category {
        case .expense:
            return -amount
        case .income, .interest, .dividend:
            return amount
        case .adjustment:
            return entry.amountCents
        case .portfolioBuy, .savingsPlan:
            if let viewedAccountID {
                if entry.fromAccountID == viewedAccountID { return -amount }
                if entry.toAccountID == viewedAccountID { return amount }
            }
            return -amount
        case .portfolioSale:
            if let viewedAccountID {
                if entry.toAccountID == viewedAccountID { return amount }
                if entry.fromAccountID == viewedAccountID { return -amount }
            }
            return amount
        case .transfer:
            guard let viewedAccountID else { return amount }
            if entry.fromAccountID == viewedAccountID { return -amount }
            if entry.toAccountID == viewedAccountID { return amount }
            return amount
        }
    }

    static func amountColor(category: BookingCategory, signed: Int) -> Color {
        paint(category: category, signed: signed, scope: .combined).amountColor
    }

    static func paint(
        category: BookingCategory,
        signed: Int,
        scope: BookingScope,
        differenceCents: Int? = nil
    ) -> BookingPaint {
        switch category {
        case .portfolioBuy, .savingsPlan:
            let color: Color
            switch scope {
            case .account: color = .red
            case .depot: color = .green
            case .combined: color = .primary
            }
            return BookingPaint(iconColor: color, amountColor: color, differenceCents: nil)
        case .portfolioSale:
            let color: Color
            switch scope {
            case .account: color = .green
            case .depot: color = .red
            case .combined: color = .primary
            }
            return BookingPaint(iconColor: color, amountColor: color, differenceCents: differenceCents)
        case .income, .interest, .dividend:
            return BookingPaint(iconColor: .primary, amountColor: signedColor(signed), differenceCents: nil)
        case .expense:
            return BookingPaint(iconColor: .primary, amountColor: signed < 0 ? .red : .primary, differenceCents: nil)
        case .transfer, .adjustment:
            return BookingPaint(iconColor: .primary, amountColor: .primary, differenceCents: nil)
        }
    }

    static func displayedAmount(_ signed: Int, category: BookingCategory, scope: BookingScope) -> Int {
        guard scope == .depot else { return signed }
        switch category {
        case .portfolioBuy, .savingsPlan:
            return abs(signed)
        case .portfolioSale:
            return -abs(signed)
        case .income, .interest, .dividend, .expense, .transfer, .adjustment:
            return signed
        }
    }

    static func differenceColor(_ cents: Int) -> Color {
        signedColor(cents)
    }

    private static func signedColor(_ cents: Int) -> Color {
        if cents > 0 { return .green }
        if cents < 0 { return .red }
        return .primary
    }

    static func isSavingsPlan(_ entry: LedgerEntry) -> Bool {
        guard entry.kind == .transfer else { return false }
        if entry.title.hasPrefix("Sparplan:") || entry.title.hasPrefix("Savings plan:") { return true }
        let notes = folded(entry.notes)
        return notes.contains("typ: sparplan") || notes.contains("type: savings plan")
    }

    static func preparedTitle(_ raw: String, for category: BookingCategory) -> String {
        let stripped = stripPrefixes(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        switch category {
        case .savingsPlan:
            return "Sparplan: \(stripped)"
        case .portfolioBuy:
            return "Kauf: \(stripped)"
        case .portfolioSale:
            return "Verkauf: \(stripped)"
        case .income, .interest, .dividend, .expense, .transfer, .adjustment:
            return stripped
        }
    }

    static func preparedNotes(_ notes: String, for category: BookingCategory) -> String {
        switch category {
        case .interest:
            return replacingType(notes, with: "Zinsen")
        case .dividend:
            return replacingType(notes, with: "Ertrag")
        case .savingsPlan:
            return replacingType(notes, with: "Sparplan")
        case .income, .expense, .transfer, .portfolioBuy, .portfolioSale, .adjustment:
            return removingTypeValues(notes, values: ["zinsen", "ertrag", "sparplan", "interest", "dividend"])
        }
    }

    private static func isPortfolioBuy(_ entry: LedgerEntry, portfolios: Set<UUID>) -> Bool {
        guard entry.kind == .transfer, !isSavingsPlan(entry) else { return false }
        if let to = entry.toAccountID, portfolios.contains(to) {
            if let from = entry.fromAccountID, portfolios.contains(from) { return false }
            return true
        }
        return hasPrefix(entry.title, ["Kauf:", "Purchase:", "Buy:"])
    }

    private static func isPortfolioSale(_ entry: LedgerEntry, portfolios: Set<UUID>) -> Bool {
        guard entry.kind == .transfer, !isSavingsPlan(entry) else { return false }
        if let from = entry.fromAccountID, portfolios.contains(from) {
            if let to = entry.toAccountID, portfolios.contains(to) { return false }
            return true
        }
        return hasPrefix(entry.title, ["Verkauf:", "Sale:", "Sell:"])
    }

    private static func isDividend(_ entry: LedgerEntry) -> Bool {
        guard entry.kind == .income else { return false }
        let notes = folded(entry.notes)
        return notes.contains("typ: ertrag")
            || notes.contains("type: ertrag")
            || notes.contains("type: dividend")
    }

    private static func isInterest(_ entry: LedgerEntry) -> Bool {
        guard entry.kind == .income else { return false }
        let notes = folded(entry.notes)
        return notes.contains("typ: zinsen")
            || notes.contains("type: zinsen")
            || notes.contains("type: interest")
    }

    private static func hasPrefix(_ title: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { title.hasPrefix($0) }
    }

    private static func stripPrefixes(_ title: String) -> String {
        let prefixes = [
            "Sparplan: ", "Savings plan: ",
            "Kauf: ", "Purchase: ", "Buy: ",
            "Verkauf: ", "Sale: ", "Sell: "
        ]
        for prefix in prefixes where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    private static func replacingType(_ notes: String, with value: String) -> String {
        var lines = notes.components(separatedBy: .newlines).filter { !isTypeLine($0) }
        lines.insert("Typ: \(value)", at: 0)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingTypeValues(_ notes: String, values: [String]) -> String {
        notes.components(separatedBy: .newlines)
            .filter { line in
                guard isTypeLine(line) else { return true }
                return !values.contains(typeValue(line))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTypeLine(_ line: String) -> Bool {
        let label = line.split(separator: ":", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return label == "typ" || label == "type"
    }

    private static func typeValue(_ line: String) -> String {
        let value = line.split(separator: ":", maxSplits: 1).dropFirst().first ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
