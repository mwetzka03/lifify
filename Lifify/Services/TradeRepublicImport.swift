import Foundation
import PDFKit

@MainActor
enum TradeRepublicImporter {
    static func parse(data: Data) throws -> TradeRepublicStatement {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw BankImportError.unreadableFile
        }
        if let statement = columnStatement(in: document) {
            return statement
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
        let closing = balances.opening + parsed.reduce(0) { $0 + $1.amountCents }
        return TradeRepublicStatement(
            iban: accountIBAN(in: header),
            openingBalanceCents: balances.opening,
            closingBalanceCents: closing,
            rows: parsed
        )
    }

    /// Reads only the Umsatzübersicht. The booking amount is Zahlungseingang or Zahlungsausgang.
    /// The Saldo column is the running balance and is never used as the trade value.
    private static func columnStatement(in document: PDFDocument) -> TradeRepublicStatement? {
        var rows: [ImportedTransaction] = []
        var inTable = false
        var opening: Int?
        var openingAnchor: CGFloat?
        var running = 0
        var seeded = false
        var matches = 0
        var headerText = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if !inTable {
                headerText += (page.string ?? "") + "\n"
            }
            let lines = textLines(on: page)
            var pending: [TextLine] = []
            var stopped = false
            for line in lines {
                let joined = line.text
                if !inTable, isOverviewTitle(joined) {
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
                if isSectionEnd(joined) {
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
                rows.append(contentsOf: transactions(in: pending, running: &running, matches: &matches))
            }
            if stopped { break }
        }
        guard inTable, !rows.isEmpty else { return nil }
        // A column reading that does not follow the printed balance is discarded.
        // The text parser then derives each booking from the saldo change.
        if rows.count - matches > 3 { return nil }
        return TradeRepublicStatement(
            iban: accountIBAN(in: headerText),
            openingBalanceCents: opening ?? 0,
            closingBalanceCents: running,
            rows: rows
        )
    }

    private static func transactions(
        in lines: [TextLine],
        running: inout Int,
        matches: inout Int
    ) -> [ImportedTransaction] {
        var parsed: [ImportedTransaction] = []
        for cluster in clusters(from: lines) {
            let words = cluster.flatMap(\.words)
            guard let type = words.first(where: { statementTypes.contains($0.text) && $0.minX < 170 })?.text else { continue }
            var descriptionWords: [PlacedWord] = []
            var dates: [String] = []
            var amounts: [(x: CGFloat, cents: Int)] = []
            for word in words.sorted(by: { lhs, rhs in
                if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
                return lhs.minX < rhs.minX
            }) {
                if let cents = amountCents(word.text) {
                    amounts.append((word.minX, cents))
                } else if word.minX < 110 {
                    dates.append(word.text)
                } else if !statementTypes.contains(word.text) {
                    descriptionWords.append(word)
                }
            }
            let ordered = amounts.sorted { $0.x < $1.x }
            guard ordered.count >= 2, let date = date(in: dates.joined(separator: " ")) else { continue }
            let cashX = ordered[ordered.count - 2].x
            let resolved = booking(earlier: ordered[ordered.count - 2].cents, later: ordered[ordered.count - 1].cents, previous: running)
            if resolved.matched { matches += 1 }
            running = resolved.saldo
            let rawDescription = descriptionWords
                .filter { $0.minX < cashX - 4 }
                .map(\.text)
                .joined(separator: " ")
            parsed.append(importedRow(date: date, type: type, description: rawDescription, signed: resolved.signed))
        }
        return parsed
    }

    /// The right-hand amount is the balance after the booking. The amount beside it is the cash movement.
    /// Zahlungseingang increases the balance, Zahlungsausgang decreases it. The saldo itself is never the booking.
    private static func booking(earlier: Int, later: Int, previous: Int) -> (signed: Int, saldo: Int, matched: Bool) {
        let forward = later - previous
        if abs(abs(forward) - earlier) <= 1 {
            return (forward, later, true)
        }
        let backward = earlier - previous
        if abs(abs(backward) - later) <= 1 {
            return (backward, earlier, true)
        }
        let signed = forward < 0 ? -earlier : earlier
        return (signed, previous + signed, false)
    }

    private static func importedRow(date: Date, type: String, description rawDescription: String, signed: Int) -> ImportedTransaction {
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
            trade: trade
        )
    }

    private static func eventTitle(trade: ImportedSecurityTrade?, fallback: String, type: String) -> String {
        guard let trade else { return fallback.isEmpty ? type : fallback }
        if trade.isSavingsPlan { return "\(L("Sparplan", "Savings plan")): \(trade.name)" }
        let action = trade.isSale ? L("Verkauf", "Sale") : L("Kauf", "Purchase")
        return "\(action): \(trade.name)"
    }

    private static func clusters(from lines: [TextLine]) -> [[TextLine]] {
        var clusters: [[TextLine]] = []
        var current: [TextLine] = []
        var previous: CGFloat?
        for line in lines {
            if let previous, previous - line.midY > 12, !current.isEmpty {
                clusters.append(current)
                current = []
            }
            current.append(line)
            previous = line.midY
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
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

    nonisolated private static func isSectionEnd(_ text: String) -> Bool {
        let value = folded(text)
        if value.contains("treuhandkonten") { return true }
        if value.contains("barmittel") && value.contains("bersicht") { return true }
        if value.contains("transaktions") && value.contains("bersicht") { return true }
        return value.contains("hinweise zum")
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
            if gap <= 2.2 {
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
        let markers = ["Transaktionsübersicht", "Barmittelübersicht", "Treuhandkonten", "Hinweise"]
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
        let typeIndexes = tokens.indices.filter { statementTypes.contains(tokens[$0]) }
        var rows: [ImportedTransaction] = []
        var balance = openingBalanceCents
        var carriedDate = firstDate(in: tokens)
        for offset in typeIndexes.indices {
            let typeAt = typeIndexes[offset]
            let previous = offset > 0 ? typeIndexes[offset - 1] + 1 : 0
            if let found = lastDate(in: Array(tokens[previous..<typeAt])) {
                carriedDate = found
            }
            let next = offset + 1 < typeIndexes.count ? typeIndexes[offset + 1] : tokens.count
            let chunk = Array(tokens[(typeAt + 1)..<next])
            let amountIndexes = chunk.indices.filter { amountCents(chunk[$0]) != nil }
            guard amountIndexes.count >= 2, let components = carriedDate else { continue }
            let cashIndex = amountIndexes[amountIndexes.count - 2]
            guard let cash = amountCents(chunk[cashIndex]),
                  let saldo = amountCents(chunk[amountIndexes[amountIndexes.count - 1]])
            else { continue }
            let rawDescription = chunk[..<cashIndex].joined(separator: " ")
            let resolved = booking(earlier: cash, later: saldo, previous: balance)
            balance = resolved.saldo
            guard let date = statementDate(day: components.day, month: components.month, year: components.year) else { continue }
            rows.append(importedRow(date: date, type: tokens[typeAt], description: rawDescription, signed: resolved.signed))
        }
        return rows
    }

    private static func firstDate(in tokens: [String]) -> (day: Int, month: Int, year: Int)? {
        var index = 0
        while index < tokens.count {
            if let components = dateComponents(at: index, in: tokens) { return components }
            index += 1
        }
        return nil
    }

    private static func lastDate(in tokens: [String]) -> (day: Int, month: Int, year: Int)? {
        var found: (day: Int, month: Int, year: Int)?
        var index = 0
        while index < tokens.count {
            if let components = dateComponents(at: index, in: tokens) {
                found = components
                index += 3
            } else {
                index += 1
            }
        }
        return found
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

    private static func loosen(_ text: String) -> String {
        var spaced = text.replacingOccurrences(
            of: #"([A-Za-zÄÖÜäöü])-\s+([A-Za-zÄÖÜäöü])"#,
            with: "$1$2",
            options: .regularExpression
        )
        for type in statementTypes.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: type))(?![\\p{L}\\p{N}])"
            spaced = spaced.replacingOccurrences(of: pattern, with: " \(type) ", options: .regularExpression)
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
