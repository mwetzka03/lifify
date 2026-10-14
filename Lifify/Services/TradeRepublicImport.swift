import Foundation
import PDFKit

@MainActor
enum TradeRepublicImporter {
    static func parse(data: Data) throws -> TradeRepublicStatement {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw BankImportError.unreadableFile
        }
        let text = (0..<document.pageCount).compactMap { index -> String? in
            guard let page = document.page(at: index) else { return nil }
            let plain = page.string ?? ""
            let selected = page.selection(for: page.bounds(for: .mediaBox))?.string ?? ""
            let pageText = selected.count > plain.count ? selected : plain
            return pageText.isEmpty ? nil : pageText
        }.joined(separator: "\n")
        guard let overview = markerRange("Umsatzübersicht", in: text) ?? markerRange("Zahlungsausgang", in: text) else {
            throw BankImportError.unsupportedPDF
        }
        let header = String(text[..<overview.lowerBound])
        let section = String(text[overview.upperBound..<stopIndex(in: text, after: overview.upperBound)])
        let balances = cashBalances(in: header)
        let parsed = transactionRows(in: section, openingBalanceCents: balances.opening)
        guard !parsed.isEmpty else { throw BankImportError.unsupportedPDF }
        return TradeRepublicStatement(
            iban: accountIBAN(in: header),
            openingBalanceCents: balances.opening,
            closingBalanceCents: balances.closing,
            rows: parsed
        )
    }

    private static func markerRange(_ marker: String, in text: String, from: String.Index? = nil) -> Range<String.Index>? {
        let ns = text as NSString
        let start = from.map { text.utf16.distance(from: text.startIndex, to: $0) } ?? 0
        guard start <= ns.length else { return nil }
        let found = ns.range(
            of: marker,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: NSRange(location: start, length: ns.length - start)
        )
        guard found.location != NSNotFound, let range = Range(found, in: text) else { return nil }
        return range
    }

    private static func stopIndex(in text: String, after start: String.Index) -> String.Index {
        let markers = ["Transaktionsübersicht", "Barmittelübersicht", "Hinweise"]
        let indices = markers.compactMap { markerRange($0, in: text, from: start)?.lowerBound }
        return indices.min() ?? text.endIndex
    }

    private static func accountIBAN(in header: String) -> String {
        let source = header.replacingOccurrences(of: "\u{00a0}", with: " ").uppercased()
        guard let match = firstMatch(#"IBAN\s+([A-Z]{2}[0-9]{2}[A-Z0-9]{11,30})"#, in: source) else { return "" }
        let candidate = match.replacingOccurrences(of: " ", with: "")
        return isIBAN(candidate) ? candidate : ""
    }

    private static func cashBalances(in header: String) -> (opening: Int, closing: Int) {
        guard let range = markerRange("Cashkonto", in: header) else { return (0, 0) }
        let tail = String(header[range.lowerBound...].prefix(240))
        let amounts = tokenize(tail).compactMap(amountCents)
        guard let opening = amounts.first else { return (0, 0) }
        return (opening, amounts.last ?? opening)
    }

    private static func transactionRows(in section: String, openingBalanceCents: Int) -> [ImportedTransaction] {
        let tokens = tokenize(loosen(section))
        var rows: [ImportedTransaction] = []
        var balance = openingBalanceCents
        var index = 0
        while index < tokens.count {
            guard let components = dateComponents(at: index, in: tokens),
                  let typeAt = typeIndex(from: index + 3, through: index + 8, in: tokens)
            else {
                index += 1
                continue
            }
            let next = nextDateIndex(from: typeAt + 1, in: tokens)
            let chunk = Array(tokens[(typeAt + 1)..<next])
            let amountIndexes = chunk.indices.filter { amountCents(chunk[$0]) != nil }
            guard amountIndexes.count >= 2 else {
                index = max(next, index + 1)
                continue
            }
            var used = Array(amountIndexes.suffix(2))
            if amountIndexes.count >= 3 {
                let third = amountIndexes[amountIndexes.count - 3]
                let last = amountIndexes[amountIndexes.count - 1]
                let between = chunk[(third + 1)..<last]
                if between.allSatisfy({ amountCents($0) != nil }) {
                    used = Array(amountIndexes.suffix(3))
                }
            }
            let values = used.compactMap { amountCents(chunk[$0]) }
            guard values.count == used.count, let firstAmount = used.first else {
                index = max(next, index + 1)
                continue
            }
            let description = chunk[..<firstAmount]
                .joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
            let signed: Int
            let saldo: Int
            if values.count == 3 {
                signed = values[0] - values[1]
                saldo = values[2]
            } else {
                let movement = values[0]
                saldo = values[1]
                if balance + movement == saldo {
                    signed = movement
                } else if balance - movement == saldo {
                    signed = -movement
                } else {
                    signed = saldo - balance
                }
            }
            balance = balance + signed == saldo ? balance + signed : saldo
            let type = tokens[typeAt]
            let trade = securityTrade(type: type, description: description, inflow: signed > 0 ? signed : nil)
            let title = trade.map { "\($0.isSale ? L("Verkauf", "Sale") : L("Kauf", "Purchase")): \($0.name)" } ?? description
            let counterparty = iban(in: description)
            let details = [
                "\(L("Typ", "Type")): \(type)",
                trade.map { "ISIN: \($0.isin)" },
                trade.map { "\(L("Stück", "Quantity")): \(quantityText($0.quantity))" }
            ].compactMap { $0 }.joined(separator: "\n")
            guard let date = statementDate(day: components.day, month: components.month, year: components.year) else {
                index = max(next, index + 1)
                continue
            }
            rows.append(BankImportService.imported(
                date: date,
                title: title.isEmpty ? type : title,
                amount: signed,
                senderIBAN: signed >= 0 ? counterparty : "",
                recipientIBAN: signed < 0 ? counterparty : "",
                legacyIBAN: "",
                legacyTitle: title.isEmpty ? type : title,
                details: details,
                trade: trade
            ))
            index = next
        }
        return rows
    }

    private static func loosen(_ text: String) -> String {
        var spaced = text
        for type in statementTypes.sorted(by: { $0.count > $1.count }) {
            spaced = spaced.replacingOccurrences(of: type, with: " \(type) ")
        }
        let pattern = #"(\d{1,2})((?:Jan(?:uar)?|Feb(?:ruar)?|Mär(?:z)?|Maerz|Mar(?:z)?|Mrz|Apr(?:il)?|Mai|Juni?|Juli?|Aug(?:ust)?|Sept(?:ember)?|Sep|Okt(?:ober)?|Nov(?:ember)?|Dez(?:ember)?)\.?)(20\d{2})"#
        return spaced.replacingOccurrences(
            of: pattern,
            with: "$1 $2 $3",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "€", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func dateComponents(at index: Int, in tokens: [String]) -> (day: Int, month: Int, year: Int)? {
        guard index + 2 < tokens.count else { return nil }
        let dayText = tokens[index].trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let day = Int(dayText), (1...31).contains(day),
              let month = monthNumber(tokens[index + 1]),
              let year = Int(tokens[index + 2]), (2000...2100).contains(year)
        else { return nil }
        return (day, month, year)
    }

    private static func typeIndex(from start: Int, through end: Int, in tokens: [String]) -> Int? {
        guard start < tokens.count else { return nil }
        let limit = min(end, tokens.count)
        guard start < limit else { return nil }
        return (start..<limit).first { statementTypes.contains(tokens[$0]) }
    }

    private static func nextDateIndex(from start: Int, in tokens: [String]) -> Int {
        var index = start
        while index < tokens.count {
            if dateComponents(at: index, in: tokens) != nil,
               typeIndex(from: index + 3, through: index + 8, in: tokens) != nil {
                return index
            }
            index += 1
        }
        return tokens.count
    }

    private static func amountCents(_ token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "€"))
        guard trimmed.range(of: #"^\d{1,3}(\.\d{3})*,\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return Money.cents(from: trimmed)
    }

    private static func securityTrade(type: String, description: String, inflow: Int?) -> ImportedSecurityTrade? {
        guard type == "Handel" else { return nil }
        guard let isin = firstMatch(#"\b([A-Z]{2}[A-Z0-9]{10})\b"#, in: description),
              let quantityMatch = firstMatch(#"quantity:\s*([0-9]+(?:[.,][0-9]+)?)"#, in: description, options: [.caseInsensitive]),
              let quantity = Double(quantityMatch.replacingOccurrences(of: ",", with: ".")),
              quantity > 0
        else { return nil }
        let lower = description.lowercased()
        var isSale = lower.contains("sell trade") || lower.contains("verkauf")
        let isBuy = lower.contains("buy trade") || lower.contains("savings plan") || lower.contains("sparplan")
        let cancels = lower.contains("cancellation") || lower.contains("storno") || lower.contains("rückerstattung") || lower.contains("rueckerstattung")
        if cancels {
            if isSale || isBuy {
                isSale.toggle()
            } else {
                isSale = inflow != nil
            }
        } else if !isSale && !isBuy {
            isSale = inflow != nil
        }
        let name = instrumentName(description: description, isin: isin)
        return ImportedSecurityTrade(isin: isin, name: name.isEmpty ? isin : name, quantity: quantity, isSale: isSale)
    }

    private static func instrumentName(description: String, isin: String) -> String {
        guard let range = description.range(of: isin) else { return "" }
        var name = String(description[range.upperBound...])
        if let cutoff = name.range(of: ", quantity", options: .caseInsensitive) {
            name = String(name[..<cutoff.lowerBound])
        }
        return name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-,")))
    }

    private static func statementDate(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }

    private static func monthNumber(_ token: String) -> Int? {
        let folded = token
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
        return months[folded]
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func iban(in text: String) -> String {
        guard let match = firstMatch(#"\b([A-Z]{2}[0-9]{2}[A-Z0-9]{11,30})\b"#, in: text.uppercased()) else { return "" }
        let candidate = match.replacingOccurrences(of: " ", with: "")
        return isIBAN(candidate) ? candidate : ""
    }

    private static func isIBAN(_ value: String) -> Bool {
        (15...34).contains(value.count)
            && value.prefix(2).allSatisfy(\.isLetter)
            && value.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func quantityText(_ quantity: Double) -> String {
        var text = String(format: "%.6f", quantity)
        while text.contains("."), text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private static let statementTypes: Set<String> = [
        "Überweisung", "Handel", "Ertrag", "Kartentransaktion", "Zinsen", "Steuern", "Empfehlung", "Bonus"
    ]

    private static let months = [
        "jan": 1, "januar": 1,
        "feb": 2, "februar": 2,
        "mar": 3, "mrz": 3, "marz": 3,
        "apr": 4, "april": 4,
        "mai": 5,
        "jun": 6, "juni": 6,
        "jul": 7, "juli": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "okt": 10, "oktober": 10,
        "nov": 11, "november": 11,
        "dez": 12, "dezember": 12
    ]
}
