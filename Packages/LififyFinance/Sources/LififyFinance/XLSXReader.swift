import Compression
import Foundation

/// Reads the first sheet of an Excel file without a third-party library.
///
/// An `.xlsx` file is a ZIP archive of XML files. Only what fund holdings files use is supported.
public enum XLSXReader {
    /// The reasons a file cannot be read.
    public enum Failure: Error {
        case notAnArchive
        case missingSheet
    }

    /// Returns the rows of the first sheet, each as cells by zero-based column.
    ///
    /// - Parameter data: The file.
    /// - Returns: The rows from top to bottom.
    /// - Throws: ``Failure`` when the file is no readable workbook.
    public static func rows(in data: Data) throws -> [[Int: String]] {
        let files = try ZipArchive(data)
        let strings = files.file("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        guard let name = files.names.filter({ $0.hasPrefix("xl/worksheets/sheet") }).sorted().first,
              let sheet = files.file(name)
        else { throw Failure.missingSheet }
        return SheetParser.parse(sheet, strings: strings)
    }

    /// Returns the zero-based column of a cell reference such as `C12`.
    static func column(of reference: String) -> Int {
        var value = 0
        for scalar in reference.unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            value = value * 26 + Int(scalar.value) - 64
        }
        return max(value - 1, 0)
    }
}

/// The files of a ZIP archive, read through its central directory.
private struct ZipArchive {
    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]

    /// The names of all files.
    var names: [String] { Array(entries.keys) }

    /// Reads the directory of the archive.
    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard let end = endOfDirectory() else { throw XLSXReader.Failure.notAnArchive }
        var cursor = int32(end + 16)
        for _ in 0..<int16(end + 10) {
            guard cursor + 46 <= bytes.count, int32(cursor) == 0x0201_4B50 else { throw XLSXReader.Failure.notAnArchive }
            let nameLength = int16(cursor + 28)
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(
                method: UInt16(int16(cursor + 10)),
                compressedSize: int32(cursor + 20),
                size: int32(cursor + 24),
                headerOffset: int32(cursor + 42)
            )
            cursor += 46 + nameLength + int16(cursor + 30) + int16(cursor + 32)
        }
    }

    /// Returns one unpacked file.
    func file(_ name: String) -> Data? {
        guard let entry = entries[name], entry.headerOffset + 30 <= bytes.count else { return nil }
        let start = entry.headerOffset + 30 + int16(entry.headerOffset + 26) + int16(entry.headerOffset + 28)
        guard start + entry.compressedSize <= bytes.count else { return nil }
        let packed = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0: return Data(packed)
        case 8: return inflate(packed, size: entry.size)
        default: return nil
        }
    }

    /// Finds the end-of-directory record, searching backward.
    private func endOfDirectory() -> Int? {
        guard bytes.count >= 22 else { return nil }
        var index = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while index >= lowest {
            if int32(index) == 0x0605_4B50 { return index }
            index -= 1
        }
        return nil
    }

    /// Unpacks raw deflate data.
    private func inflate(_ packed: [UInt8], size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(&output, size, packed, packed.count, nil, COMPRESSION_ZLIB)
        return written == size ? Data(output) : nil
    }

    /// Reads a little-endian 16-bit value.
    private func int16(_ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    /// Reads a little-endian 32-bit value.
    private func int32(_ offset: Int) -> Int {
        int16(offset) | int16(offset + 2) << 16
    }
}

/// Reads the workbook's shared text table.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var readsText = false

    /// Returns all shared strings.
    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        // Some providers write prefixed element names such as `x:row`.
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    /// Starts a string or a text run.
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "si" { current = "" }
        if name == "t" { readsText = true }
    }

    /// Collects text.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readsText { current += string }
    }

    /// Finishes a text run or a string.
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { readsText = false }
        if name == "si" { strings.append(current) }
    }
}

/// Reads the cells of a worksheet.
private final class SheetParser: NSObject, XMLParserDelegate {
    private let strings: [String]
    private var rows: [[Int: String]] = []
    private var row: [Int: String] = [:]
    private var column = 0
    private var type = ""
    private var value = ""
    private var readsValue = false

    /// Creates a parser with the shared strings.
    private init(strings: [String]) {
        self.strings = strings
    }

    /// Returns all rows.
    static func parse(_ data: Data, strings: [String]) -> [[Int: String]] {
        let delegate = SheetParser(strings: strings)
        let parser = XMLParser(data: data)
        // Some providers write prefixed element names such as `x:row`.
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    /// Starts a row, cell, or value.
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            row = [:]
        case "c":
            column = XLSXReader.column(of: attributes["r"] ?? "A")
            type = attributes["t"] ?? ""
            value = ""
        case "v", "t":
            readsValue = true
        default:
            break
        }
    }

    /// Collects a value.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readsValue { value += string }
    }

    /// Finishes a value, cell, or row.
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            readsValue = false
        case "c":
            if type == "s", let index = Int(value), strings.indices.contains(index) {
                row[column] = strings[index]
            } else if !value.isEmpty {
                row[column] = value
            }
        case "row":
            rows.append(row)
        default:
            break
        }
    }
}
