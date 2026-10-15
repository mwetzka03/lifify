import Foundation
import PDFKit

@MainActor
enum TradeRepublicImporter {
    static func parse(data: Data) throws -> TradeRepublicStatement {
        for pages in PDFContentText.candidateWordPages(in: data) {
            let placed = pages.map { page in
                page.map { PlacedWord(text: $0.text, minX: $0.minX, maxX: $0.maxX, midY: $0.midY) }
            }
            if let statement = columnStatement(from: placed), !statement.rows.isEmpty {
                return statement
            }
        }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw BankImportError.unreadableFile
        }
        guard let statement = columnStatement(in: document), !statement.rows.isEmpty else {
            throw BankImportError.unsupportedPDF
        }
        return statement
    }

    private static func columnStatement(in document: PDFDocument) -> TradeRepublicStatement? {
        var pages: [[PlacedWord]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append(textLines(on: page).flatMap(\.words))
        }
        return columnStatement(from: pages)
    }

    /// Reads only the Umsatzübersicht. The booking amount is Zahlungseingang or Zahlungsausgang.
    /// The Saldo column is the running balance and is never used as the trade value.
    private static func columnStatement(from pages: [[PlacedWord]]) -> TradeRepublicStatement? {
        var rows: [ImportedTransaction] = []
        var inTable = false
        var opening: Int?
        var openingAnchor: CGFloat?
        var running = 0
        var seeded = false
        var headerText = ""
        for page in pages {
            let lines = groupedLines(page)
            var pending: [TextLine] = []
            var stopped = false
            for line in lines {
                let joined = line.text
                if !inTable {
                    headerText += joined + "\n"
                }
                if !inTable, isOverviewTitle(joined) || line.words.contains(where: { isOverviewTitle($0.text) }) {
                    inTable = true
                    running = opening ?? 0
                    seeded = true
                    continue
                }
                if !inTable {
                    if containsMarker("Anfangssaldo", in: joined), let word = line.words.first(where: { containsMarker("Anfangssaldo", in: $0.text) }) {
                        openingAnchor = word.minX
                    }
                    if containsMarker("Cashkonto", in: joined), let anchor = openingAnchor {
                        let amounts = line.words.compactMap { word -> (CGFloat, Int)? in
                            guard let cents = amountCents(word.text) else { return nil }
                            return (word.minX, cents)
                        }
                        if let nearest = amounts.min(by: { abs($0.0 - anchor) < abs($1.0 - anchor) }) {
                            opening = nearest.1
                        }
                    }
                    continue
                }
                if isSectionEnd(joined) || line.words.contains(where: { isSectionEnd($0.text) }) {
                    stopped = true
                    break
                }
                if containsMarker("Zahlungsausgang", in: joined), containsMarker("Saldo", in: joined), containsMarker("Datum", in: joined) {
                    continue
                }
                pending.append(line)
            }
            if inTable {
                if !seeded {
                    running = opening ?? 0
                    seeded = true
                }
                rows.append(contentsOf: anchorTransactions(in: pending, running: &running))
            }
            if stopped { break }
        }
        guard inTable, !rows.isEmpty else { return nil }
        return TradeRepublicStatement(
            iban: accountIBAN(in: headerText),
            openingBalanceCents: opening ?? 0,
            closingBalanceCents: running,
            rows: rows
        )
    }

    /// PDFKit reads the page by vertical position, so a gap-based line cluster mixes the next row
    /// into this one. Each booking is therefore anchored on its type word. Amounts share that line.
    /// The date and the description sit a few points above and below it. The rightmost amount is the
    /// saldo and is never the booked value.
    private static func anchorTransactions(
        in lines: [TextLine],
        running: inout Int
    ) -> [ImportedTransaction] {
        let words = lines.flatMap(\.words)
        let anchorIndexes = words.indices.filter { index in
            let word = words[index]
            return canonicalType(word.text) != nil && word.minX > 80 && word.minX < 150
        }.sorted { words[$0].midY > words[$1].midY }
        var parsed: [ImportedTransaction] = []
        for offset in anchorIndexes.indices {
            let anchor = words[anchorIndexes[offset]]
            guard let type = canonicalType(anchor.text) else { continue }
            let above = bandLimit(from: anchor.midY, toward: offset > 0 ? words[anchorIndexes[offset - 1]].midY : nil)
            let below = bandLimit(from: anchor.midY, toward: offset + 1 < anchorIndexes.count ? words[anchorIndexes[offset + 1]].midY : nil)
            let band = words.enumerated().compactMap { item -> PlacedWord? in
                guard item.offset != anchorIndexes[offset] else { return nil }
                guard item.element.midY < anchor.midY + above, item.element.midY > anchor.midY - below else { return nil }
                return item.element
            }
            let amounts = band.compactMap { word -> (x: CGFloat, cents: Int)? in
                guard abs(word.midY - anchor.midY) <= 5, let cents = amountCents(word.text) else { return nil }
                return (word.minX, cents)
            }.sorted { $0.x < $1.x }
            guard amounts.count >= 2 else { continue }
            let cash = amounts[amounts.count - 2]
            let saldo = amounts[amounts.count - 1].cents
            let dateText = band
                .filter { $0.minX < 95 && amountCents($0.text) == nil && canonicalType($0.text) == nil }
                .sorted { lhs, rhs in
                    if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
                    return lhs.minX < rhs.minX
                }
                .map(\.text)
                .joined(separator: " ")
            guard let date = date(in: dateText) else { continue }
            let rawDescription = band
                .filter { word in
                    word.minX >= 140 && word.minX < cash.x - 4 && amountCents(word.text) == nil && canonicalType(word.text) == nil
                }
                .sorted { lhs, rhs in
                    if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
                    return lhs.minX < rhs.minX
                }
                .map(\.text)
                .joined(separator: " ")
            let delta = saldo - running
            let signed = abs(abs(delta) - cash.cents) <= 1 ? delta : (cash.x < 405 ? cash.cents : -cash.cents)
            running = saldo
            parsed.append(importedRow(
                date: date,
                type: type,
                description: rawDescription,
                signed: signed,
                balance: saldo
            ))
        }
        return parsed
    }

    private static func bandLimit(from anchor: CGFloat, toward neighbor: CGFloat?) -> CGFloat {
        guard let neighbor else { return 18 }
        return min(18, max(6, abs(neighbor - anchor) / 2 - 0.4))
    }

    private static func importedRow(
        date: Date,
        type: String,
        description rawDescription: String,
        signed: Int,
        balance: Int
    ) -> ImportedTransaction {
        let titleText = displayTitle(rawDescription)
        let trade = securityTrade(type: type, description: rawDescription, inflow: signed > 0 ? signed : nil)
        let title = eventTitle(trade: trade, fallback: titleText, type: type)
        let counterparty = iban(in: rawDescription)
        let unitPrice = trade.map { Int((Double(abs(signed)) / $0.quantity).rounded()) }
        let details = [
            "\(L("Typ", "Type")): \(type)",
            trade.map { "ISIN: \($0.isin)" },
            trade.map { "\(L("Stück", "Quantity")): \(quantityText($0.quantity))" },
            unitPrice.map { "\(L("Kurs", "Price")): \(Money.string(cents: $0))" }
        ].compactMap { $0 }.joined(separator: "\n")
        return BankImportService.imported(
            date: date,
            title: title,
            amount: signed,
            senderIBAN: signed >= 0 ? counterparty : "",
            recipientIBAN: signed < 0 ? counterparty : "",
            legacyIBAN: "",
            legacyTitle: title,
            details: details,
            trade: trade,
            statementBalanceCents: balance
        )
    }

    private static func eventTitle(trade: ImportedSecurityTrade?, fallback: String, type: String) -> String {
        guard let trade else { return fallback.isEmpty ? type : fallback }
        if trade.isSavingsPlan { return "\(L("Sparplan", "Savings plan")): \(trade.name)" }
        let action = trade.isSale ? L("Verkauf", "Sale") : L("Kauf", "Purchase")
        return "\(action): \(trade.name)"
    }

    private static func date(in text: String) -> Date? {
        let pattern = #"(\d{1,2})\.?\s+((?:Jan(?:uar)?|Feb(?:ruar)?|Mär(?:z)?|Maerz|Mar(?:z)?|Mrz|Apr(?:il)?|Mai|Juni?|Juli?|Aug(?:ust)?|Sept(?:ember)?|Sep|Okt(?:ober)?|Nov(?:ember)?|Dez(?:ember)?)\.?)\s+(20\d{2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              match.numberOfRanges > 3,
              let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let yearRange = Range(match.range(at: 3), in: text),
              let day = Int(text[dayRange]),
              let month = monthNumber(String(text[monthRange])),
              let year = Int(text[yearRange])
        else { return nil }
        return statementDate(day: day, month: month, year: year)
    }

    nonisolated private static func containsMarker(_ marker: String, in text: String) -> Bool {
        text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    nonisolated private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    nonisolated private static func isOverviewTitle(_ text: String) -> Bool {
        let value = folded(text)
        return value.contains("umsatz") && value.contains("bersicht") && !value.contains("konto")
    }

    private static func canonicalType(_ text: String) -> String? {
        let value = folded(text)
        return statementTypes.first { folded($0) == value }
    }

    nonisolated private static func isSectionEnd(_ text: String) -> Bool {
        let value = folded(text)
        if value.contains("treuhandkonten") { return true }
        if value.contains("barmittel") && value.contains("bersicht") { return true }
        if value.contains("transaktions") && value.contains("bersicht") { return true }
        return value.contains("hinweise zum")
    }

    private static func groupedLines(_ words: [PlacedWord]) -> [TextLine] {
        let sorted = words.sorted { lhs, rhs in
            if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
            return lhs.minX < rhs.minX
        }
        var groups: [[PlacedWord]] = []
        for word in sorted {
            if var last = groups.last, let sample = last.first, abs(sample.midY - word.midY) <= 2 {
                last.append(word)
                groups[groups.count - 1] = last
            } else {
                groups.append([word])
            }
        }
        return groups.map { group in
            let ordered = group.sorted { $0.minX < $1.minX }
            let midY = ordered.map(\.midY).reduce(0, +) / CGFloat(max(ordered.count, 1))
            return TextLine(midY: midY, words: ordered)
        }
    }

    private static func textLines(on page: PDFPage) -> [TextLine] {
        guard let raw = page.string, !raw.isEmpty else { return [] }
        let ns = raw as NSString
        var glyphs: [Glyph] = []
        var index = 0
        while index < ns.length {
            let range = NSRange(location: index, length: 1)
            let character = ns.substring(with: range)
            let bounds = page.characterBounds(at: index)
            index += range.length
            guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0.05, bounds.height > 0.05 else { continue }
            glyphs.append(Glyph(text: character, minX: bounds.minX, maxX: bounds.maxX, midY: bounds.midY))
        }
        let sorted = glyphs.sorted { lhs, rhs in
            if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
            return lhs.minX < rhs.minX
        }
        var glyphLines: [[Glyph]] = []
        for glyph in sorted {
            if var last = glyphLines.last, let sample = last.first, abs(sample.midY - glyph.midY) <= 2 {
                last.append(glyph)
                glyphLines[glyphLines.count - 1] = last
            } else {
                glyphLines.append([glyph])
            }
        }
        return glyphLines.compactMap { lineGlyphs in
            let ordered = lineGlyphs.sorted { $0.minX < $1.minX }
            let words = words(from: ordered)
            guard !words.isEmpty else { return nil }
            let midY = ordered.map(\.midY).reduce(0, +) / CGFloat(ordered.count)
            return TextLine(midY: midY, words: words)
        }
    }

    private static func words(from glyphs: [Glyph]) -> [PlacedWord] {
        var words: [PlacedWord] = []
        var buffer = ""
        var minX: CGFloat = 0
        var maxX: CGFloat = 0
        var midY: CGFloat = 0
        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                words.append(PlacedWord(text: text, minX: minX, maxX: maxX, midY: midY))
            }
            buffer = ""
        }
        for glyph in glyphs {
            if buffer.isEmpty {
                buffer = glyph.text
                minX = glyph.minX
                maxX = glyph.maxX
                midY = glyph.midY
                continue
            }
            let gap = glyph.minX - maxX
            if gap <= 3.2 {
                buffer += glyph.text
                maxX = max(maxX, glyph.maxX)
                minX = min(minX, glyph.minX)
            } else {
                flush()
                buffer = glyph.text
                minX = glyph.minX
                maxX = glyph.maxX
                midY = glyph.midY
            }
        }
        flush()
        return words
    }

    private static func accountIBAN(in header: String) -> String {
        let source = header.replacingOccurrences(of: "\u{00a0}", with: " ").uppercased()
        guard let match = firstMatch(#"IBAN\s+([A-Z]{2}[0-9]{2}[A-Z0-9]{11,30})"#, in: source) else { return "" }
        let candidate = match.replacingOccurrences(of: " ", with: "")
        return isIBAN(candidate) ? candidate : ""
    }

    private static func displayTitle(_ text: String) -> String {
        var title = text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let cutoffs = ["exchange rate", ", quantity", " quantity:"]
        for cutoff in cutoffs {
            if let range = title.range(of: cutoff, options: .caseInsensitive) {
                title = String(title[..<range.lowerBound])
            }
        }
        return title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-")))
    }

    private static func amountCents(_ token: String) -> Int? {
        let trimmed = token
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let isSavings = lower.contains("savings plan") || lower.contains("sparplan")
        var isSale = lower.contains("sell trade") || lower.contains("verkauf")
        let isBuy = lower.contains("buy trade") || isSavings
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
        return ImportedSecurityTrade(
            isin: isin,
            name: name.isEmpty ? isin : name,
            quantity: quantity,
            isSale: isSale,
            isSavingsPlan: isSavings && !isSale
        )
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

    private struct Glyph {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midY: CGFloat
    }

    private struct PlacedWord {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midY: CGFloat
    }

    private struct TextLine {
        var midY: CGFloat
        var words: [PlacedWord]
        var text: String { words.map(\.text).joined(separator: " ") }
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
