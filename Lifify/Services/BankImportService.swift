import CryptoKit
import Foundation

struct ImportedTransaction: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let notes: String
    let amountCents: Int
    let iban: String
    let senderIBAN: String
    let recipientIBAN: String
    let fingerprint: String
    let legacyFingerprint: String?

    init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        notes: String,
        amountCents: Int,
        iban: String,
        senderIBAN: String,
        recipientIBAN: String,
        fingerprint: String,
        legacyFingerprint: String? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.notes = notes
        self.amountCents = amountCents
        self.iban = iban
        self.senderIBAN = senderIBAN
        self.recipientIBAN = recipientIBAN
        self.fingerprint = fingerprint
        self.legacyFingerprint = legacyFingerprint
    }
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
        let ibanIndex = index(
            of: ["gegenkontoiban", "ibanime", "counterpartyiban", "iban"],
            in: headers
        )
        let senderIBANIndex = index(
            of: [
                "absenderiban", "ibanabsender", "auftraggeberiban", "ibanauftraggeber",
                "senderiban", "ibansender", "debtoriban", "ibandebtor", "voniban"
            ],
            in: headers
        )
        let recipientIBANIndex = index(
            of: [
                "empfaengeriban", "ibanempfaenger", "recipientiban", "ibanrecipient",
                "creditoriban", "ibancreditor", "beguenstigteriban", "ibanbeguenstigter", "nachiban"
            ],
            in: headers
        )

        return lines.dropFirst().compactMap { line in
            let fields = csvFields(line, delimiter: delimiter)
            guard fields.indices.contains(dateIndex), fields.indices.contains(amountIndex),
                  let date = parseDate(fields[dateIndex]),
                  let amount = Money.cents(from: fields[amountIndex]) else { return nil }
            let title = titleIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? L("Importierte Buchung", "Imported transaction")
            let genericIBAN = ibanIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            var senderIBAN = senderIBANIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            var recipientIBAN = recipientIBANIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            if amount > 0, senderIBAN.isEmpty { senderIBAN = genericIBAN }
            if amount < 0, recipientIBAN.isEmpty { recipientIBAN = genericIBAN }
            return imported(
                date: date,
                title: title,
                amount: amount,
                senderIBAN: senderIBAN,
                recipientIBAN: recipientIBAN,
                legacyIBAN: genericIBAN
            )
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
        amount: Int,
        senderIBAN: String,
        recipientIBAN: String,
        legacyIBAN: String
    ) -> ImportedTransaction {
        let senderIBAN = normalizeIBAN(senderIBAN)
        let recipientIBAN = normalizeIBAN(recipientIBAN)
        let iban = amount >= 0 ? senderIBAN : recipientIBAN
        let notes = ibanNotes(sender: senderIBAN, recipient: recipientIBAN)
        let fingerprint = fingerprint(date: date, amount: amount, title: title, iban: iban)
        let legacyFingerprint = fingerprint(
            date: date,
            amount: amount,
            title: title,
            iban: legacyIBAN
        )
        return ImportedTransaction(
            date: date,
            title: title.isEmpty ? L("Importierte Buchung", "Imported transaction") : title,
            notes: notes,
            amountCents: amount,
            iban: iban,
            senderIBAN: senderIBAN,
            recipientIBAN: recipientIBAN,
            fingerprint: fingerprint,
            legacyFingerprint: legacyFingerprint == fingerprint ? nil : legacyFingerprint
        )
    }

    fileprivate static func fingerprint(date: Date, amount: Int, title: String, iban: String) -> String {
        let source = "\(date.dayKey)|\(amount)|\(title)|\(iban)"
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizeIBAN(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").uppercased()
    }

    fileprivate static func ibanNotes(sender: String, recipient: String) -> String {
        [
            sender.isEmpty ? nil : "\(L("Sender-IBAN", "Sender IBAN")): \(sender)",
            recipient.isEmpty ? nil : "\(L("Empfänger-IBAN", "Recipient IBAN")): \(recipient)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    static func ibans(from notes: String, amountCents: Int? = nil) -> (sender: String, recipient: String) {
        var sender = ""
        var recipient = ""
        for line in notes.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let label = parts[0].lowercased()
            let value = normalizeIBAN(parts[1])
            if label.contains("sender") { sender = value }
            if label.contains("empfänger") || label.contains("recipient") { recipient = value }
        }
        if sender.isEmpty, recipient.isEmpty, let amountCents {
            let candidate = normalizeIBAN(notes)
            if (15...34).contains(candidate.count),
               candidate.prefix(2).allSatisfy(\.isLetter),
               candidate.dropFirst(2).allSatisfy({ $0.isLetter || $0.isNumber }) {
                if amountCents >= 0 {
                    sender = candidate
                } else {
                    recipient = candidate
                }
            }
        }
        return (sender, recipient)
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
        candidates.lazy.compactMap { headers.firstIndex(of: $0) }.first
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
    private var senderIBAN = ""
    private var recipientIBAN = ""
    private var genericIBAN = ""
    private var legacyIBAN = ""

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
            senderIBAN = ""
            recipientIBAN = ""
            genericIBAN = ""
            legacyIBAN = ""
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
        if name == "IBAN", !value.isEmpty {
            legacyIBAN = value
            if path.contains("DbtrAcct") {
                senderIBAN = value
            } else if path.contains("CdtrAcct") {
                recipientIBAN = value
            } else {
                genericIBAN = value
            }
        }
        if name == "Ntry" {
            if let date = BankImportService.parseDate(dateText), let unsigned = Money.cents(from: amountText) {
                let amount = creditDebit.uppercased().contains("DBIT") ? -abs(unsigned) : abs(unsigned)
                if amount > 0, senderIBAN.isEmpty { senderIBAN = genericIBAN }
                if amount < 0, recipientIBAN.isEmpty { recipientIBAN = genericIBAN }
                senderIBAN = senderIBAN.replacingOccurrences(of: " ", with: "").uppercased()
                recipientIBAN = recipientIBAN.replacingOccurrences(of: " ", with: "").uppercased()
                let iban = amount >= 0 ? senderIBAN : recipientIBAN
                let fingerprint = BankImportService.fingerprint(
                    date: date,
                    amount: amount,
                    title: title,
                    iban: iban
                )
                let legacyFingerprint = BankImportService.fingerprint(
                    date: date,
                    amount: amount,
                    title: title,
                    iban: legacyIBAN
                )
                rows.append(ImportedTransaction(
                    date: date,
                    title: title.isEmpty ? L("CAMT-Buchung", "CAMT transaction") : title,
                    notes: BankImportService.ibanNotes(sender: senderIBAN, recipient: recipientIBAN),
                    amountCents: amount,
                    iban: iban,
                    senderIBAN: senderIBAN,
                    recipientIBAN: recipientIBAN,
                    fingerprint: fingerprint,
                    legacyFingerprint: legacyFingerprint == fingerprint ? nil : legacyFingerprint
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
