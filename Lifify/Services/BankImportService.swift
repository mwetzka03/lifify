import CryptoKit
import Foundation

struct ImportedTransaction: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let notes: String
    let amountCents: Int
    let iban: String
    let fingerprint: String
}

enum BankImportError: LocalizedError {
    case unreadableFile
    case unsupportedCSV
    case invalidXML

    var errorDescription: String? {
        switch self {
        case .unreadableFile: L("Datei konnte nicht gelesen werden.", "The file could not be read.")
        case .unsupportedCSV: L("CSV-Spalten wurden nicht erkannt.", "CSV columns were not recognized.")
        case .invalidXML: L("CAMT-XML ist ungültig.", "The CAMT XML is invalid.")
        }
    }
}

enum BankImportService {
    static func parse(data: Data, fileExtension: String) throws -> [ImportedTransaction] {
        if fileExtension.lowercased() == "xml" || data.firstNonWhitespace == UInt8(ascii: "<") {
            return try parseCAMT(data: data)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BankImportError.unreadableFile
        }
        return try parseCSV(text)
    }

    static func parseCSV(_ text: String) throws -> [ImportedTransaction] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return [] }
        let delimiter: Character = headerLine.filter { $0 == ";" }.count >= headerLine.filter { $0 == "," }.count ? ";" : ","
        let headers = csvFields(headerLine, delimiter: delimiter).map(normalizeHeader)
        guard
            let dateIndex = index(of: ["buchungstag", "datum", "date", "bookingdate"], in: headers),
            let amountIndex = index(of: ["betrag", "amount", "umsatz"], in: headers)
        else { throw BankImportError.unsupportedCSV }
        let titleIndex = index(of: ["verwendungszweck", "buchungstext", "beschreibung", "purpose", "description", "name"], in: headers)
        let ibanIndex = index(of: ["iban", "gegenkontoiban", "counterpartyiban"], in: headers)

        return lines.dropFirst().compactMap { line in
            let fields = csvFields(line, delimiter: delimiter)
            guard fields.indices.contains(dateIndex), fields.indices.contains(amountIndex),
                  let date = parseDate(fields[dateIndex]),
                  let amount = Money.cents(from: fields[amountIndex]) else { return nil }
            let title = titleIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? L("Importierte Buchung", "Imported transaction")
            let iban = ibanIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            return imported(date: date, title: title, notes: iban, amount: amount, iban: iban)
        }
    }

    static func parseCAMT(data: Data) throws -> [ImportedTransaction] {
        let delegate = CAMTParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw BankImportError.invalidXML }
        return delegate.rows
    }

    private static func imported(
        date: Date,
        title: String,
        notes: String,
        amount: Int,
        iban: String
    ) -> ImportedTransaction {
        let source = "\(date.dayKey)|\(amount)|\(title)|\(iban)"
        let fingerprint = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return ImportedTransaction(
            date: date,
            title: title.isEmpty ? L("Importierte Buchung", "Imported transaction") : title,
            notes: notes,
            amountCents: amount,
            iban: iban,
            fingerprint: fingerprint
        )
    }

    fileprivate static func parseDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy", "yyyyMMdd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func csvFields(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == delimiter, !quoted {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .filter(\.isLetter)
    }

    private static func index(of candidates: [String], in headers: [String]) -> Int? {
        headers.firstIndex { header in candidates.contains(header) }
    }
}

private final class CAMTParserDelegate: NSObject, XMLParserDelegate {
    var rows: [ImportedTransaction] = []
    private var path: [String] = []
    private var text = ""
    private var inEntry = false
    private var amountText = ""
    private var creditDebit = ""
    private var dateText = ""
    private var title = ""
    private var iban = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.components(separatedBy: ":").last ?? elementName
        path.append(name)
        text = ""
        if name == "Ntry" {
            inEntry = true
            amountText = ""
            creditDebit = ""
            dateText = ""
            title = ""
            iban = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.components(separatedBy: ":").last ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inEntry else {
            _ = path.popLast()
            return
        }
        if name == "Amt", amountText.isEmpty { amountText = value }
        if name == "CdtDbtInd" { creditDebit = value }
        if name == "Dt", path.contains("BookgDt") { dateText = value }
        if ["Ustrd", "AddtlNtryInf", "Nm"].contains(name), !value.isEmpty {
            title = title.isEmpty ? value : "\(title) · \(value)"
        }
        if name == "IBAN", !value.isEmpty { iban = value }
        if name == "Ntry" {
            if let date = BankImportService.parseDate(dateText), let unsigned = Money.cents(from: amountText) {
                let amount = creditDebit.uppercased().contains("DBIT") ? -abs(unsigned) : abs(unsigned)
                let source = "\(date.dayKey)|\(amount)|\(title)|\(iban)"
                let fingerprint = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
                rows.append(ImportedTransaction(
                    date: date,
                    title: title.isEmpty ? L("CAMT-Buchung", "CAMT transaction") : title,
                    notes: iban,
                    amountCents: amount,
                    iban: iban,
                    fingerprint: fingerprint
                ))
            }
            inEntry = false
        }
        _ = path.popLast()
        text = ""
    }
}

private extension Data {
    var firstNonWhitespace: UInt8? {
        first { ![9, 10, 13, 32].contains($0) }
    }
}
