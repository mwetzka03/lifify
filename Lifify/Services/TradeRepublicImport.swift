import Foundation
import PDFKit

@MainActor
enum TradeRepublicImporter {
    static func parse(data: Data) throws -> TradeRepublicStatement {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw BankImportError.unreadableFile
        }
        let pages = (0..<document.pageCount).compactMap { index -> [StatementWord]? in
            guard let page = document.page(at: index) else { return nil }
            return words(on: page)
        }
        let flattened = pages.flatMap { $0.map(\.text) }.joined(separator: " ")
        guard flattened.localizedCaseInsensitiveContains("TRADE REPUBLIC"),
              flattened.localizedCaseInsensitiveContains("UMSATZÜBERSICHT")
        else { throw BankImportError.unsupportedPDF }

        let iban = accountIBAN(in: pages.first ?? [])
        let balances = cashBalances(in: pages.first ?? [])
        let parsed = transactionRows(in: pages)
        guard !parsed.isEmpty else { throw BankImportError.unsupportedPDF }
        return TradeRepublicStatement(
            iban: iban,
            openingBalanceCents: balances.opening,
            closingBalanceCents: balances.closing,
            rows: parsed
        )
    }

    private static func words(on page: PDFPage) -> [StatementWord] {
        guard let raw = page.string, !raw.isEmpty else { return [] }
        let text = raw as NSString
        var glyphs: [(CGRect, String)] = []
        glyphs.reserveCapacity(text.length)
        for index in 0..<text.length {
            let token = text.substring(with: NSRange(location: index, length: 1))
            if token == "\n" || token == "\r" || token == "\t" { continue }
            let rect = page.characterBounds(at: index)
            if rect.isNull || rect.isInfinite || rect.width < 0.05 || rect.height < 0.05 { continue }
            glyphs.append((rect, token))
        }
        glyphs.sort { lhs, rhs in
            if abs(lhs.0.midY - rhs.0.midY) > 2.4 { return lhs.0.midY > rhs.0.midY }
            return lhs.0.minX < rhs.0.minX
        }

        var lines: [[StatementWord]] = []
        var current: [(CGRect, String)] = []
        func flushLine() {
            guard !current.isEmpty else { return }
            lines.append(words(from: current))
            current = []
        }
        for glyph in glyphs {
            if let last = current.last, abs(last.0.midY - glyph.0.midY) > 2.4 {
                flushLine()
            }
            current.append(glyph)
        }
        flushLine()
        return lines.flatMap { $0 }.filter { $0.y > 90 }
    }

    private static func words(from glyphs: [(CGRect, String)]) -> [StatementWord] {
        var words: [StatementWord] = []
        var buffer = ""
        var minX: CGFloat = 0
        var maxX: CGFloat = 0
        var y: CGFloat = 0
        func close() {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                words.append(StatementWord(x: minX, y: y, text: trimmed))
            }
            buffer = ""
        }
        for glyph in glyphs {
            let character = glyph.1
            if character == " " || character == "\u{00a0}" {
                close()
                continue
            }
            if !buffer.isEmpty, glyph.0.minX > maxX + 1.8 {
                close()
            }
            if buffer.isEmpty {
                minX = glyph.0.minX
                y = glyph.0.midY
            }
            buffer.append(character)
            maxX = glyph.0.maxX
        }
        close()
        var joined: [StatementWord] = []
        for word in words {
            if word.text == "€" || word.text == "€,", let previous = joined.popLast(), previous.text.contains(where: \.isNumber) {
                joined.append(StatementWord(x: previous.x, y: previous.y, text: previous.text + " €"))
            } else {
                joined.append(word)
            }
        }
        return joined
    }

    private static func accountIBAN(in words: [StatementWord]) -> String {
        let lines = groupedLines(words)
        for line in lines {
            if let label = line.firstIndex(where: { $0.text.caseInsensitiveCompare("IBAN") == .orderedSame }),
               line.index(after: label) < line.endIndex {
                let candidate = normalizeIBAN(line[line.index(after: label)].text)
                if isIBAN(candidate) { return candidate }
            }
        }
        return ""
    }

    private static func cashBalances(in words: [StatementWord]) -> (opening: Int, closing: Int) {
        let lines = groupedLines(words)
        guard let line = lines.first(where: { $0.contains { $0.text == "Cashkonto" } }) else { return (0, 0) }
        let amounts = line.compactMap { word -> (CGFloat, Int)? in
            guard word.text.contains("€"), let cents = Money.cents(from: word.text) else { return nil }
            return (word.x, cents)
        }.sorted { $0.0 < $1.0 }
        guard let opening = amounts.first?.1, let closing = amounts.last?.1 else { return (0, 0) }
        return (opening, closing)
    }

    private static func transactionRows(in pages: [[StatementWord]]) -> [ImportedTransaction] {
        var rows: [ImportedTransaction] = []
        var carried: StatementColumns?
        for page in pages {
            let lines = groupedLines(page)
            if lines.contains(where: { $0.contains { $0.text == "TRANSAKTIONSÜBERSICHT" } }) {
                if let columns = columns(in: lines) ?? carried {
                    rows.append(contentsOf: rows(on: lines, columns: columns))
                }
                break
            }
            if let detected = columns(in: lines) {
                carried = detected
            }
            guard let columns = carried else { continue }
            rows.append(contentsOf: rows(on: lines, columns: columns))
        }
        return rows
    }

    private static func columns(in lines: [[StatementWord]]) -> StatementColumns? {
        for line in lines {
            let labels = Dictionary(uniqueKeysWithValues: line.map { ($0.text, $0.x) })
            guard let descriptionX = labels["BESCHREIBUNG"], let balanceX = labels["SALDO"], let typeX = labels["TYP"] else { continue }
            return StatementColumns(
                headerY: line.map(\.y).max() ?? 0,
                dateX: labels["DATUM"] ?? descriptionX - 86,
                typeX: typeX,
                descriptionX: descriptionX,
                inflowX: labels["ZAHLUNGSEINGANG"] ?? descriptionX + 213,
                outflowX: labels["ZAHLUNGSAUSGANG"] ?? descriptionX + 267,
                balanceX: balanceX
            )
        }
        return nil
    }

    private static func rows(on lines: [[StatementWord]], columns: StatementColumns) -> [ImportedTransaction] {
        var content = lines.filter { ($0.map(\.y).max() ?? 0) < columns.headerY - 2 }
        if let stop = content.firstIndex(where: { line in
            line.contains {
                $0.text == "TRANSAKTIONSÜBERSICHT" || $0.text == "BARMITTELÜBERSICHT" || $0.text == "HINWEISE"
            }
        }) {
            content = Array(content.prefix(stop))
        }
        let anchors = content.enumerated().compactMap { index, line -> Int? in
            line.contains { abs($0.x - columns.typeX) < 36 && statementTypes.contains($0.text) } ? index : nil
        }
        return anchors.enumerated().compactMap { offset, index in
            let y = content[index].map(\.y).max() ?? 0
            let previous = offset > 0 ? (content[anchors[offset - 1]].map(\.y).max() ?? columns.headerY) : columns.headerY
            let next = offset + 1 < anchors.count ? (content[anchors[offset + 1]].map(\.y).max() ?? 0) : -10
            let upper = (previous + y) / 2
            let lower = offset + 1 < anchors.count ? (next + y) / 2 : y - 36
            var type = ""
            var dateWords: [String] = []
            var descriptionWords: [String] = []
            var inflow: Int?
            var outflow: Int?
            let inflowBoundary = (columns.inflowX + columns.outflowX) / 2
            let outflowBoundary = (columns.outflowX + columns.balanceX) / 2
            for line in content {
                let lineY = line.map(\.y).max() ?? 0
                guard lower < lineY, lineY <= upper + 0.4 else { continue }
                for word in line {
                    if abs(word.x - columns.typeX) < 36, statementTypes.contains(word.text) {
                        type = word.text
                    } else if word.x < (columns.dateX + columns.typeX) / 2 + 10 {
                        dateWords.append(word.text)
                    } else if word.x >= columns.descriptionX - 16, word.x < columns.inflowX - 8, !word.text.contains("€") {
                        descriptionWords.append(word.text)
                    } else if word.text.contains("€"), let cents = Money.cents(from: word.text) {
                        if word.x < inflowBoundary {
                            inflow = cents
                        } else if word.x < outflowBoundary {
                            outflow = cents
                        }
                    }
                }
            }
            guard !type.isEmpty, inflow != nil || outflow != nil, let date = statementDate(dateWords) else { return nil }
            let description = descriptionWords.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
            let amount = (inflow ?? 0) - (outflow ?? 0)
            let trade = securityTrade(type: type, description: description, inflow: inflow)
            let title = trade.map { "\($0.isSale ? L("Verkauf", "Sale") : L("Kauf", "Purchase")): \($0.name)" } ?? description
            let counterparty = iban(in: description)
            let sender = amount >= 0 ? counterparty : ""
            let recipient = amount < 0 ? counterparty : ""
            let details = [
                "\(L("Typ", "Type")): \(type)",
                trade.map { "ISIN: \($0.isin)" },
                trade.map { "\(L("Stück", "Quantity")): \(quantityText($0.quantity))" }
            ].compactMap { $0 }.joined(separator: "\n")
            return BankImportService.imported(
                date: date,
                title: title.isEmpty ? type : title,
                amount: amount,
                senderIBAN: sender,
                recipientIBAN: recipient,
                legacyIBAN: "",
                legacyTitle: title.isEmpty ? type : title,
                details: details,
                trade: trade
            )
        }
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

    private static func statementDate(_ words: [String]) -> Date? {
        var day: Int?
        var month: Int?
        var year: Int?
        for word in words {
            for token in word.split(whereSeparator: \.isWhitespace) {
                let raw = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if raw.count == 4, let value = Int(raw), (2000...2100).contains(value) {
                    year = value
                } else if let value = monthNumber(raw) {
                    month = value
                } else if let value = Int(raw), (1...31).contains(value) {
                    day = value
                }
            }
        }
        guard let day, let month, let year else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }

    private static func monthNumber(_ token: String) -> Int? {
        let folded = token.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
        return months[folded]
    }

    private static func groupedLines(_ words: [StatementWord]) -> [[StatementWord]] {
        var lines: [[StatementWord]] = []
        for word in words.sorted(by: { lhs, rhs in
            if abs(lhs.y - rhs.y) > 2.4 { return lhs.y > rhs.y }
            return lhs.x < rhs.x
        }) {
            if let last = lines.last?.first, abs(last.y - word.y) <= 2.4 {
                lines[lines.count - 1].append(word)
            } else {
                lines.append([word])
            }
        }
        return lines
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
        let candidate = normalizeIBAN(match)
        return isIBAN(candidate) ? candidate : ""
    }

    private static func normalizeIBAN(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").uppercased()
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

private struct StatementWord {
    var x: CGFloat
    var y: CGFloat
    var text: String
}

private struct StatementColumns {
    var headerY: CGFloat
    var dateX: CGFloat
    var typeX: CGFloat
    var descriptionX: CGFloat
    var inflowX: CGFloat
    var outflowX: CGFloat
    var balanceX: CGFloat
}
