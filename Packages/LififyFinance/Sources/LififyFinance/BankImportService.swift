import CryptoKit
import LififyCore
import Foundation

/// One row read from a bank file.
public struct ImportedTransaction: Identifiable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let notes: String
    public let amountCents: Int
    public let iban: String
    public let senderIBAN: String
    public let recipientIBAN: String
    public let fingerprint: String
    public let legacyFingerprint: String?
    public let trade: ImportedSecurityTrade?
    /// Saldo printed in the rightmost statement column after this row.
    public let statementBalanceCents: Int?

    public init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        notes: String,
        amountCents: Int,
        iban: String,
        senderIBAN: String,
        recipientIBAN: String,
        fingerprint: String,
        legacyFingerprint: String? = nil,
        trade: ImportedSecurityTrade? = nil,
        statementBalanceCents: Int? = nil
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
        self.trade = trade
        self.statementBalanceCents = statementBalanceCents
    }
}

/// A security trade read from a statement.
public struct ImportedSecurityTrade: Hashable {
    public var isin: String
    public var name: String
    public var quantity: Double
    public var isSale: Bool
    public var isSavingsPlan: Bool = false

    public init(isin: String, name: String, quantity: Double, isSale: Bool, isSavingsPlan: Bool = false) {
        self.isin = isin
        self.name = name
        self.quantity = quantity
        self.isSale = isSale
        self.isSavingsPlan = isSavingsPlan
    }
}

/// The content of a Trade Republic statement.
public struct TradeRepublicStatement {
    public var iban: String
    public var openingBalanceCents: Int
    public var closingBalanceCents: Int
    public var rows: [ImportedTransaction]

    public init(iban: String, openingBalanceCents: Int, closingBalanceCents: Int, rows: [ImportedTransaction]) {
        self.iban = iban
        self.openingBalanceCents = openingBalanceCents
        self.closingBalanceCents = closingBalanceCents
        self.rows = rows
    }
}

/// A parsed bank file.
public struct BankImportDocument {
    public var rows: [ImportedTransaction]
    public var tradeRepublic: TradeRepublicStatement?

    public init(rows: [ImportedTransaction], tradeRepublic: TradeRepublicStatement? = nil) {
        self.rows = rows
        self.tradeRepublic = tradeRepublic
    }
}

/// The account an import goes to.
public enum BankImportDestination: Hashable {
    case separateChecking
    case account(UUID)
}

/// The reasons a bank file cannot be read.
public enum BankImportError: LocalizedError {
    case unreadableFile
    case unsupportedCSV
    case unsupportedPDF
    case pdfUseTradeRepublicImport
    case invalidXML
    case missingAccount

    public var errorDescription: String? {
        switch self {
        case .unreadableFile: L("Datei konnte nicht gelesen werden.", "The file could not be read.")
        case .unsupportedCSV: L("CSV-Spalten wurden nicht erkannt.", "CSV columns were not recognized.")
        case .unsupportedPDF: L("Dieses PDF ist kein Kontoauszug.", "This PDF is not a bank statement.")
        case .pdfUseTradeRepublicImport: L(
            "PDF-Dateien gehören in den separaten Trade-Republic-Import.",
            "PDF files belong in the separate Trade Republic import."
        )
        case .invalidXML: L("CAMT-XML ist ungültig.", "The CAMT XML is invalid.")
        case .missingAccount: L("Das gewählte Konto wurde nicht gefunden.", "The selected account was not found.")
        }
    }
}

/// Reads CSV, CAMT, and Trade Republic files.
public enum BankImportService {
    /// Parses a file by its extension.
    @MainActor
    public static func parseDocument(data: Data, fileExtension: String) throws -> BankImportDocument {
        let extensionName = fileExtension.lowercased()
        if extensionName == "pdf" || data.starts(with: Data("%PDF".utf8)) {
            throw BankImportError.pdfUseTradeRepublicImport
        }
        if extensionName == "xml" || data.firstNonWhitespace == UInt8(ascii: "<") {
            return BankImportDocument(rows: try parseCAMT(data: data), tradeRepublic: nil)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BankImportError.unreadableFile
        }
        return BankImportDocument(rows: try parseCSV(text), tradeRepublic: nil)
    }

    /// Parses a Trade Republic PDF statement.
    @MainActor
    public static func parseTradeRepublic(data: Data) throws -> BankImportDocument {
        let statement = try TradeRepublicImporter.parse(data: data)
        return BankImportDocument(rows: statement.rows, tradeRepublic: statement)
    }

    /// Parses a file and returns its rows.
    @MainActor
    public static func parse(data: Data, fileExtension: String) throws -> [ImportedTransaction] {
        try parseDocument(data: data, fileExtension: fileExtension).rows
    }

    /// Parses a bank CSV by recognizing its column headers.
    public static func parseCSV(_ text: String) throws -> [ImportedTransaction] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return [] }
        let delimiter: Character = headerLine.filter { $0 == ";" }.count >= headerLine.filter { $0 == "," }.count ? ";" : ","
        let headers = csvFields(headerLine, delimiter: delimiter).map(normalizeHeader)
        guard
            let dateIndex = index(of: ["buchungstag", "datum", "date", "bookingdate"], in: headers),
            let amountIndex = index(of: ["betrag", "amount", "umsatz"], in: headers)
        else { throw BankImportError.unsupportedCSV }
        let bookingTextIndex = index(of: ["buchungstext", "bookingtext"], in: headers)
        let purposeIndex = index(of: ["verwendungszweck", "beschreibung", "purpose", "description"], in: headers)
        let counterpartyNameIndex = index(
            of: ["beguenstigterzahlungspflichtiger", "gegenpartei", "counterparty", "name"],
            in: headers
        )
        let ownIBANIndex = index(
            of: ["auftragskonto", "eigeneskkonto", "owniban", "accountiban"],
            in: headers
        )
        let ibanIndex = index(
            of: ["kontonummeriban", "gegenkontoiban", "ibanime", "counterpartyiban", "iban"],
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
        let referenceIndex = index(
            of: ["kundenreferenzendtoend", "endtoend", "endtoendid", "referenz"],
            in: headers
        )
        let infoIndex = index(of: ["info", "umsatzstatus", "status"], in: headers)

        return lines.dropFirst().compactMap { line in
            let fields = csvFields(line, delimiter: delimiter)
            guard fields.indices.contains(dateIndex), fields.indices.contains(amountIndex),
                  let date = parseDate(fields[dateIndex]),
                  let amount = Money.cents(from: fields[amountIndex]) else { return nil }
            let info = field(at: infoIndex, from: fields)
            if isPendingBankRow(info) { return nil }
            let bookingText = field(at: bookingTextIndex, from: fields)
            let purpose = field(at: purposeIndex, from: fields)
            let reference = field(at: referenceIndex, from: fields)
            let counterpartyName = field(at: counterpartyNameIndex, from: fields)
            let title = [counterpartyName, bookingText, purpose]
                .first(where: { !$0.isEmpty }) ?? L("Importierte Buchung", "Imported transaction")
            let legacyTitle = [purpose, bookingText, counterpartyName]
                .first(where: { !$0.isEmpty }) ?? L("Importierte Buchung", "Imported transaction")
            let ownIBAN = field(at: ownIBANIndex, from: fields)
            let genericIBAN = ibanIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            var senderIBAN = senderIBANIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            var recipientIBAN = recipientIBANIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            if amount >= 0 {
                if senderIBAN.isEmpty { senderIBAN = genericIBAN }
                if recipientIBAN.isEmpty { recipientIBAN = ownIBAN }
            } else {
                if senderIBAN.isEmpty { senderIBAN = ownIBAN }
                if recipientIBAN.isEmpty { recipientIBAN = genericIBAN }
            }
            let details = [
                bookingText.isEmpty ? nil : "\(L("Buchungstext", "Booking text")): \(bookingText)",
                purpose.isEmpty ? nil : "\(L("Verwendungszweck", "Purpose")): \(purpose)",
                reference.isEmpty ? nil : "\(L("Referenz", "Reference")): \(reference)",
                counterpartyName.isEmpty ? nil : "\(L("Gegenpartei", "Counterparty")): \(counterpartyName)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            let distinct = [purpose, bookingText, reference].filter { !$0.isEmpty }.joined(separator: "|")
            return imported(
                date: date,
                title: title,
                amount: amount,
                senderIBAN: senderIBAN,
                recipientIBAN: recipientIBAN,
                legacyIBAN: genericIBAN,
                legacyTitle: legacyTitle,
                details: details,
                distinct: distinct
            )
        }
    }

    /// Parses a CAMT XML statement.
    public static func parseCAMT(data: Data) throws -> [ImportedTransaction] {
        let delegate = CAMTParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw BankImportError.invalidXML }
        return delegate.rows
    }

    /// Builds an imported row with its fingerprint.
    public static func imported(
        date: Date,
        title: String,
        amount: Int,
        senderIBAN: String,
        recipientIBAN: String,
        legacyIBAN: String,
        legacyTitle: String,
        details: String,
        trade: ImportedSecurityTrade? = nil,
        statementBalanceCents: Int? = nil,
        distinct: String = ""
    ) -> ImportedTransaction {
        let senderIBAN = validIBAN(senderIBAN) ?? ""
        let recipientIBAN = validIBAN(recipientIBAN) ?? ""
        let iban = amount >= 0 ? senderIBAN : recipientIBAN
        let notes = [details, ibanNotes(sender: senderIBAN, recipient: recipientIBAN)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let fingerprint = makeFingerprint(date: date, amount: amount, title: title, iban: iban, distinct: distinct)
        let legacyFingerprint = makeFingerprint(
            date: date,
            amount: amount,
            title: legacyTitle,
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
            legacyFingerprint: legacyFingerprint == fingerprint ? nil : legacyFingerprint,
            trade: trade,
            statementBalanceCents: statementBalanceCents
        )
    }

    /// Builds the fingerprint that recognizes a row in later imports.
    public static func makeFingerprint(date: Date, amount: Int, title: String, iban: String, distinct: String = "") -> String {
        var source = "\(date.dayKey)|\(amount)|\(title)|\(iban)"
        if !distinct.isEmpty { source += "|\(distinct)" }
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Sparkasse marks reserved card payments as vorgemerkt. They are not booked yet.
    public static func isPendingBankRow(_ info: String) -> Bool {
        let folded = info.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return folded.contains("vorgemerkt") || folded.contains("pending")
    }

    /// Extracts the purpose line used to tell similar rows apart.
    public static func purposeMark(notes: String) -> String {
        for line in notes.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let label = parts[0].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            if label.contains("verwendungszweck") || label.contains("purpose") { return parts[1] }
        }
        return ""
    }

    /// Normalizes an IBAN for comparison.
    private static func normalizeIBAN(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").uppercased()
    }

    /// Returns the IBAN when it has a valid form.
    private static func validIBAN(_ value: String) -> String? {
        let candidate = normalizeIBAN(value)
        guard (15...34).contains(candidate.count),
              candidate.prefix(2).allSatisfy(\.isLetter),
              candidate.dropFirst(2).allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            return nil
        }
        return candidate
    }

    /// Writes sender and recipient IBAN into the notes.
    public static func ibanNotes(sender: String, recipient: String) -> String {
        [
            sender.isEmpty ? nil : "\(L("Sender-IBAN", "Sender IBAN")): \(sender)",
            recipient.isEmpty ? nil : "\(L("Empfänger-IBAN", "Recipient IBAN")): \(recipient)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    /// Reads sender and recipient IBAN from the notes.
    public static func ibans(from notes: String, amountCents: Int? = nil) -> (sender: String, recipient: String) {
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

    /// Parses the date formats banks use.
    fileprivate static func parseDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats: [String]
        if value.range(of: #"^\d{2}\.\d{2}\.\d{2}$"#, options: .regularExpression) != nil {
            formats = ["dd.MM.yy"]
        } else {
            formats = ["yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy", "yyyyMMdd"]
        }
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.isLenient = false
            formatter.twoDigitStartDate = Calendar(identifier: .gregorian)
                .date(from: DateComponents(year: 2000, month: 1, day: 1))
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Reads a CSV field by index.
    private static func field(at index: Int?, from fields: [String]) -> String {
        guard let index, fields.indices.contains(index) else { return "" }
        return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a CSV line and respects quotes.
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

    /// Normalizes a column header.
    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .filter(\.isLetter)
    }

    /// Finds the column for any of the header names.
    private static func index(of candidates: [String], in headers: [String]) -> Int? {
        candidates.lazy.compactMap { headers.firstIndex(of: $0) }.first
    }
}

/// Reads transactions from CAMT XML.
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

    /// Tracks the opened element.
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

    /// Collects element text.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    /// Stores a finished value or transaction.
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
                let fingerprint = BankImportService.makeFingerprint(
                    date: date,
                    amount: amount,
                    title: title,
                    iban: iban
                )
                let legacyFingerprint = BankImportService.makeFingerprint(
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

/// Text decoding for bank files.
private extension Data {
    var firstNonWhitespace: UInt8? {
        first { ![9, 10, 13, 32].contains($0) }
    }
}
