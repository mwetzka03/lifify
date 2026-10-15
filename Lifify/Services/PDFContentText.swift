import Compression
import CoreGraphics
import Foundation

/// Positioned text from a PDF content stream.
///
/// Trade Republic statements are written by OpenPDF with an Identity-H subset font.
/// PDFKit often returns no `characterBounds` for that font, so the page looks empty and the
/// statement is rejected. Core Graphics still reports each `Tj` with its `Tm` position, and the
/// ToUnicode map turns those bytes back into the Umsatzübersicht columns.
enum PDFContentText {
    struct Word {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midY: CGFloat
    }

    /// Every reader that found text, Core Graphics first. The caller keeps the first set that
    /// yields Umsatzübersicht rows.
    static func candidateWordPages(in data: Data) -> [[[Word]]] {
        guard data.starts(with: Data("%PDF".utf8)) else { return [] }
        var sets: [[[Word]]] = []
        if let pages = coreGraphicsWordPages(in: data), containsStatementTitle(pages) {
            sets.append(pages)
        }
        if let pages = contentStreamWordPages(in: data), containsStatementTitle(pages) {
            sets.append(pages)
        }
        return sets
    }

    private static func contentStreamWordPages(in data: Data) -> [[Word]]? {
        let reader = PDFContentReader(data: data)
        guard reader.open(), !reader.pages.isEmpty else { return nil }
        let pages = reader.pages.map { reader.words(on: $0) }
        guard pages.contains(where: { !$0.isEmpty }) else { return nil }
        return pages
    }

    private static func containsStatementTitle(_ pages: [[Word]]) -> Bool {
        pages.contains { page in
            page.contains { word in
                let folded = word.text.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "de_DE")
                )
                return folded.contains("umsatz") && folded.contains("bersicht") && !folded.contains("konto")
            }
        }
    }

    private static func coreGraphicsWordPages(in data: Data) -> [[Word]]? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0 else { return nil }
        let table = CGPDFOperatorTableCreate()
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "BT", trBeginText)
        CGPDFOperatorTableSetCallback(table, "Tm", trSetMatrix)
        CGPDFOperatorTableSetCallback(table, "Td", trMoveText)
        CGPDFOperatorTableSetCallback(table, "TD", trMoveText)
        CGPDFOperatorTableSetCallback(table, "Tf", trSetFont)
        CGPDFOperatorTableSetCallback(table, "Tj", trShowText)
        var pages: [[Word]] = []
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else {
                pages.append([])
                continue
            }
            let content = CGPDFContentStreamCreateWithPage(page)
            let collector = PDFTextCollector()
            collector.content = content
            let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(collector).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            CGPDFContentStreamRelease(content)
            pages.append(collector.words)
        }
        guard pages.contains(where: { !$0.isEmpty }) else { return nil }
        return pages
    }
}

private final class PDFTextCollector {
    var content: CGPDFContentStreamRef?
    var maps: [String: PDFCMap] = [:]
    var fontName = ""
    var fontSize: CGFloat = 6
    var a: CGFloat = 1
    var b: CGFloat = 0
    var c: CGFloat = 0
    var d: CGFloat = 1
    var e: CGFloat = 0
    var f: CGFloat = 0
    var words: [PDFContentText.Word] = []

    func resetText() {
        a = 1
        b = 0
        c = 0
        d = 1
        e = 0
        f = 0
    }

    func loadFont(_ name: String) {
        fontName = name
        guard maps[name] == nil, let content else { return }
        let object = CGPDFContentStreamGetResource(content, "Font", name)
        var dictionary: CGPDFDictionaryRef?
        guard withUnsafeMutablePointer(to: &dictionary, { pointer in
            CGPDFObjectGetValue(object, .dictionary, UnsafeMutableRawPointer(pointer))
        }), let dictionary else { return }
        var encodingPointer: UnsafePointer<CChar>?
        CGPDFDictionaryGetName(dictionary, "Encoding", &encodingPointer)
        let encoding = encodingPointer.map { String(cString: $0) } ?? ""
        var stream: CGPDFStreamRef?
        if !CGPDFDictionaryGetStream(dictionary, "ToUnicode", &stream) {
            var descendants: CGPDFArrayRef?
            var descendant: CGPDFDictionaryRef?
            if CGPDFDictionaryGetArray(dictionary, "DescendantFonts", &descendants),
               let descendants,
               CGPDFArrayGetDictionary(descendants, 0, &descendant),
               let descendant {
                CGPDFDictionaryGetStream(descendant, "ToUnicode", &stream)
            }
        }
        var map = PDFCMap(width: encoding == "Identity-H" || encoding == "Identity-V" ? 2 : 1, characters: [:])
        if let stream {
            var format = CGPDFDataFormat.raw
            if let copied = CGPDFStreamCopyData(stream, &format) {
                let parsed = PDFContentReader.cmap(from: copied as Data)
                if parsed.width > 0 { map.width = parsed.width }
                if !parsed.characters.isEmpty { map.characters = parsed.characters }
            }
        }
        maps[name] = map
    }

    func show(_ data: Data) {
        guard let map = maps[fontName] ?? maps.values.first else { return }
        let text = PDFContentReader.decode(data, map: map).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let width = CGFloat(text.count) * CGFloat(fontSize) * 0.5
        words.append(PDFContentText.Word(text: text, minX: e, maxX: e + width, midY: f))
    }
}

private func trCollector(_ info: UnsafeMutableRawPointer?) -> PDFTextCollector? {
    guard let info else { return nil }
    return Unmanaged<PDFTextCollector>.fromOpaque(info).takeUnretainedValue()
}

private func trBeginText(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    trCollector(info)?.resetText()
}

private func trSetMatrix(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    guard let collector = trCollector(info) else { return }
    var values: [CGPDFReal] = []
    for _ in 0..<6 {
        var number: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &number) else { return }
        values.append(number)
    }
    collector.f = values[0]
    collector.e = values[1]
    collector.d = values[2]
    collector.c = values[3]
    collector.b = values[4]
    collector.a = values[5]
}

private func trMoveText(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    guard let collector = trCollector(info) else { return }
    var y: CGPDFReal = 0
    var x: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
    collector.e += x * collector.a + y * collector.c
    collector.f += x * collector.b + y * collector.d
}

private func trSetFont(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    guard let collector = trCollector(info) else { return }
    var size: CGPDFReal = 0
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name else { return }
    collector.fontSize = size
    collector.loadFont(String(cString: name))
}

private func trShowText(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    guard let collector = trCollector(info) else { return }
    var string: CGPDFStringRef?
    guard CGPDFScannerPopString(scanner, &string), let string, let pointer = CGPDFStringGetBytePtr(string) else { return }
    collector.show(Data(bytes: pointer, count: CGPDFStringGetLength(string)))
}

private struct PDFCMap {
    var width: Int
    var characters: [Int: String]
}

private enum PDFValue {
    case null
    case number(Double)
    case name(String)
    case data(Data)
    case array([PDFValue])
    case dict([String: PDFValue])
    case reference(Int)
    case stream([String: PDFValue], Data)

    var name: String? {
        if case .name(let value) = self { return value }
        return nil
    }

    var dictionary: [String: PDFValue]? {
        if case .dict(let value) = self { return value }
        return nil
    }
}

private struct PDFScanner {
    var bytes: [UInt8]
    var index: Int

    var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    mutating func skip() {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12 {
                index += 1
                continue
            }
            if byte == 37 {
                while index < bytes.count && bytes[index] != 10 && bytes[index] != 13 {
                    index += 1
                }
                continue
            }
            return
        }
    }

    mutating func parseNumber() -> Double? {
        let rollback = index
        skip()
        guard index < bytes.count else {
            index = rollback
            return nil
        }
        let start = index
        if bytes[index] == 43 || bytes[index] == 45 { index += 1 }
        var sawDigit = false
        var sawDot = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 48 && byte <= 57 {
                sawDigit = true
                index += 1
                continue
            }
            if byte == 46 && !sawDot {
                sawDot = true
                index += 1
                continue
            }
            break
        }
        guard sawDigit, let text = String(bytes: bytes[start..<index], encoding: .ascii), let value = Double(text) else {
            index = rollback
            return nil
        }
        return value
    }

    mutating func consume(_ word: String) -> Bool {
        let rollback = index
        skip()
        let encoded = Array(word.utf8)
        guard index + encoded.count <= bytes.count else {
            index = rollback
            return false
        }
        for offset in encoded.indices where bytes[index + offset] != encoded[offset] {
            index = rollback
            return false
        }
        let end = index + encoded.count
        if end < bytes.count && !isDelimiter(bytes[end]) {
            index = rollback
            return false
        }
        index = end
        return true
    }

    mutating func parseValue() -> PDFValue? {
        skip()
        guard let byte = peek else { return nil }
        if byte == 60 {
            if index + 1 < bytes.count && bytes[index + 1] == 60 {
                index += 2
                return parseDictionary()
            }
            return .data(parseHex())
        }
        if byte == 91 {
            index += 1
            return parseArray()
        }
        if byte == 40 {
            return .data(parseLiteral())
        }
        if byte == 47 {
            return .name(parseName())
        }
        if byte == 116 && consume("true") { return .number(1) }
        if byte == 102 && consume("false") { return .number(0) }
        if byte == 110 && consume("null") { return .null }
        guard let number = parseNumber() else { return nil }
        let saved = index
        if parseNumber() != nil && consume("R") {
            return .reference(Int(number))
        }
        index = saved
        return .number(number)
    }

    private mutating func parseDictionary() -> PDFValue {
        var items: [String: PDFValue] = [:]
        while index < bytes.count {
            skip()
            if index + 1 < bytes.count && bytes[index] == 62 && bytes[index + 1] == 62 {
                index += 2
                return .dict(items)
            }
            guard case .name(let key) = parseValue(), let value = parseValue() else {
                return .dict(items)
            }
            items[key] = value
        }
        return .dict(items)
    }

    private mutating func parseArray() -> PDFValue {
        var items: [PDFValue] = []
        while index < bytes.count {
            skip()
            if peek == 93 {
                index += 1
                return .array(items)
            }
            guard let value = parseValue() else { return .array(items) }
            items.append(value)
        }
        return .array(items)
    }

    mutating func parseName() -> String {
        index += 1
        var units: [UInt8] = []
        while index < bytes.count && !isDelimiter(bytes[index]) {
            if bytes[index] == 35, index + 2 < bytes.count, let decoded = hexByte(bytes[index + 1], bytes[index + 2]) {
                units.append(decoded)
                index += 3
                continue
            }
            units.append(bytes[index])
            index += 1
        }
        return String(bytes: units, encoding: .isoLatin1) ?? ""
    }

    mutating func parseLiteral() -> Data {
        index += 1
        var buffer: [UInt8] = []
        var depth = 1
        while index < bytes.count && depth > 0 {
            let byte = bytes[index]
            if byte == 92 {
                index += 1
                guard index < bytes.count else { break }
                let escaped = bytes[index]
                let mapped: [UInt8: UInt8] = [110: 10, 114: 13, 116: 9, 98: 8, 102: 12, 40: 40, 41: 41, 92: 92]
                if let value = mapped[escaped] {
                    buffer.append(value)
                    index += 1
                    continue
                }
                if escaped >= 48 && escaped <= 55 {
                    var octal = Int(escaped - 48)
                    index += 1
                    for _ in 0..<2 {
                        guard index < bytes.count, bytes[index] >= 48, bytes[index] <= 55 else { break }
                        octal = octal * 8 + Int(bytes[index] - 48)
                        index += 1
                    }
                    buffer.append(UInt8(octal & 255))
                    continue
                }
                if escaped == 10 || escaped == 13 {
                    if escaped == 13, index + 1 < bytes.count, bytes[index + 1] == 10 {
                        index += 2
                    } else {
                        index += 1
                    }
                    continue
                }
                buffer.append(escaped)
                index += 1
                continue
            }
            if byte == 40 {
                depth += 1
                buffer.append(byte)
                index += 1
                continue
            }
            if byte == 41 {
                depth -= 1
                if depth == 0 {
                    index += 1
                    break
                }
                buffer.append(byte)
                index += 1
                continue
            }
            buffer.append(byte)
            index += 1
        }
        return Data(buffer)
    }

    mutating func parseHex() -> Data {
        index += 1
        var hex: [UInt8] = []
        while index < bytes.count && bytes[index] != 62 {
            let byte = bytes[index]
            if byte != 32 && byte != 9 && byte != 10 && byte != 13 {
                hex.append(byte)
            }
            index += 1
        }
        if peek == 62 { index += 1 }
        if hex.count % 2 == 1 { hex.append(48) }
        var data: [UInt8] = []
        var cursor = 0
        while cursor + 1 < hex.count {
            if let value = hexByte(hex[cursor], hex[cursor + 1]) {
                data.append(value)
            }
            cursor += 2
        }
        return Data(data)
    }

    func isDelimiter(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
            || byte == 40 || byte == 41 || byte == 60 || byte == 62
            || byte == 91 || byte == 93 || byte == 123 || byte == 125
            || byte == 47 || byte == 37
    }

    private func hexByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
        guard let first = hexValue(high), let second = hexValue(low) else { return nil }
        return first * 16 + second
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        if byte >= 48 && byte <= 57 { return byte - 48 }
        if byte >= 65 && byte <= 70 { return byte - 55 }
        if byte >= 97 && byte <= 102 { return byte - 87 }
        return nil
    }
}

private final class PDFContentReader {
    private let bytes: [UInt8]
    private var table: [Int: Entry] = [:]
    private var cache: [Int: PDFValue] = [:]
    private var streamObjects: [Int: [PDFValue]] = [:]
    private var loadingStreams: Set<Int> = []
    private(set) var pages: [[String: PDFValue]] = []

    init(data: Data) {
        bytes = [UInt8](data)
    }

    func open() -> Bool {
        let file = Data(bytes)
        guard let marker = file.range(of: Data("startxref".utf8), options: .backwards) else { return false }
        let markerEnd = file.distance(from: file.startIndex, to: marker.upperBound)
        var scanner = PDFScanner(bytes: bytes, index: markerEnd)
        guard let start = scanner.parseNumber(), start >= 0, Int(start) < bytes.count else { return false }
        guard case .stream(let dictionary, let payload) = readObject(at: Int(start), resolvingLengths: false) else { return false }
        guard dictionary["Type"]?.name == "XRef" else { return false }
        guard let root = dictionary["Root"], case .reference(let rootID) = root else { return false }
        guard indexTable(payload, dictionary: dictionary) else { return false }
        guard case .dict(let catalog) = resolve(.reference(rootID)), catalog["Type"]?.name == "Catalog" else { return false }
        guard let pages = catalog["Pages"] else { return false }
        collectPages(pages)
        return !self.pages.isEmpty
    }

    func words(on page: [String: PDFValue]) -> [PDFContentText.Word] {
        let fonts = fontMaps(on: page)
        guard !fonts.isEmpty else { return [] }
        let content = contentBytes(page["Contents"])
        guard !content.isEmpty else { return [] }
        return showText(in: content, fonts: fonts)
    }

    private enum Entry {
        case offset(Int)
        case compressed(stream: Int, index: Int)
    }

    private func indexTable(_ payload: Data, dictionary: [String: PDFValue]) -> Bool {
        let widths = integers(dictionary["W"])
        guard widths.count == 3 else { return false }
        var ranges = integers(dictionary["Index"])
        if ranges.isEmpty, let size = integer(dictionary["Size"]) {
            ranges = [0, size]
        }
        guard ranges.count >= 2 else { return false }
        let raw = [UInt8](payload)
        var cursor = 0
        var pair = 0
        while pair + 1 < ranges.count {
            let first = ranges[pair]
            let count = ranges[pair + 1]
            for offset in 0..<count {
                var fields: [Int] = []
                for width in widths {
                    let (value, next) = readField(raw, at: cursor, width: width)
                    guard let value, let next else { return false }
                    fields.append(value)
                    cursor = next
                }
                let type = widths[0] == 0 ? 1 : fields[0]
                let objectID = first + offset
                if type == 1 {
                    table[objectID] = .offset(fields[1])
                } else if type == 2 {
                    table[objectID] = .compressed(stream: fields[1], index: fields[2])
                }
            }
            pair += 2
        }
        return !table.isEmpty
    }

    private func readField(_ raw: [UInt8], at cursor: Int, width: Int) -> (Int?, Int?) {
        if width == 0 { return (0, cursor) }
        guard cursor + width <= raw.count else { return (nil, nil) }
        var value = 0
        for offset in 0..<width {
            value = (value << 8) | Int(raw[cursor + offset])
        }
        return (value, cursor + width)
    }

    private func load(_ id: Int) -> PDFValue {
        if let cached = cache[id] { return cached }
        switch table[id] {
        case .offset(let offset):
            let value = readObject(at: offset, resolvingLengths: true) ?? .null
            cache[id] = value
            return value
        case .compressed(let stream, let index):
            let values = objects(in: stream)
            let value = values.indices.contains(index) ? values[index] : .null
            cache[id] = value
            return value
        case nil:
            return .null
        }
    }

    private func resolve(_ value: PDFValue) -> PDFValue {
        if case .reference(let id) = value { return load(id) }
        return value
    }

    private func objects(in streamID: Int) -> [PDFValue] {
        if let existing = streamObjects[streamID] { return existing }
        if loadingStreams.contains(streamID) { return [] }
        loadingStreams.insert(streamID)
        defer { loadingStreams.remove(streamID) }
        guard case .stream(let dictionary, let payload) = load(streamID),
              let first = integer(dictionary["First"]),
              let count = integer(dictionary["N"]),
              first >= 0, count > 0, first <= payload.count
        else { return [] }
        let header = String(decoding: payload.prefix(first), as: UTF8.self)
        let numbers = header.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard numbers.count >= count * 2 else { return [] }
        let raw = [UInt8](payload)
        var values: [PDFValue] = []
        var ids: [Int] = []
        for pair in 0..<count {
            let objectID = numbers[pair * 2]
            let offset = numbers[pair * 2 + 1]
            let start = first + offset
            guard start >= 0, start <= raw.count else { return [] }
            var scanner = PDFScanner(bytes: raw, index: start)
            values.append(scanner.parseValue() ?? .null)
            ids.append(objectID)
        }
        streamObjects[streamID] = values
        for (objectID, value) in zip(ids, values) {
            cache[objectID] = value
        }
        return values
    }

    private func readObject(at offset: Int, resolvingLengths: Bool) -> PDFValue? {
        guard offset >= 0, offset < bytes.count else { return nil }
        var scanner = PDFScanner(bytes: bytes, index: offset)
        guard scanner.parseNumber() != nil, scanner.parseNumber() != nil, scanner.consume("obj"),
              let value = scanner.parseValue()
        else { return nil }
        guard scanner.consume("stream"), case .dict(let dictionary) = value else { return value }
        if scanner.peek == 13 { scanner.index += 1 }
        if scanner.peek == 10 { scanner.index += 1 }
        guard let length = streamLength(dictionary, resolving: resolvingLengths),
              length >= 0, scanner.index + length <= bytes.count
        else { return nil }
        let slice = Data(bytes[scanner.index..<(scanner.index + length)])
        guard let decoded = Self.decoded(slice, filters: filterNames(dictionary)) else { return nil }
        return .stream(dictionary, decoded)
    }

    private func streamLength(_ dictionary: [String: PDFValue], resolving: Bool) -> Int? {
        if let direct = integer(dictionary["Length"]) { return direct }
        guard resolving, case .reference(let id) = dictionary["Length"] else { return nil }
        return integer(load(id))
    }

    private func collectPages(_ value: PDFValue) {
        guard case .dict(let node) = resolve(value) else { return }
        if node["Type"]?.name == "Page" {
            pages.append(node)
            return
        }
        if node["Type"]?.name == "Pages", case .some(.array(let kids)) = node["Kids"] {
            kids.forEach(collectPages)
        }
    }

    private func contentBytes(_ value: PDFValue?) -> Data {
        guard let value else { return Data() }
        switch resolve(value) {
        case .stream(_, let data):
            return data
        case .array(let items):
            var all = Data()
            for item in items {
                all.append(contentBytes(item))
                all.append(0x0A)
            }
            return all
        default:
            return Data()
        }
    }

    private func fontMaps(on page: [String: PDFValue]) -> [String: PDFCMap] {
        guard case .dict(let resources) = resolve(page["Resources"] ?? .null),
              case .dict(let fonts) = resolve(resources["Font"] ?? .null)
        else { return [:] }
        var maps: [String: PDFCMap] = [:]
        for (name, value) in fonts {
            guard case .dict(let font) = resolve(value) else { continue }
            let encoding = font["Encoding"]?.name ?? ""
            var map = PDFCMap(width: encoding == "Identity-H" || encoding == "Identity-V" ? 2 : 1, characters: [:])
            if case .stream(_, let data) = resolve(font["ToUnicode"] ?? .null) {
                let parsed = Self.cmap(from: data)
                if parsed.width > 0 { map.width = parsed.width }
                map.characters = parsed.characters
            }
            maps[name] = map
        }
        return maps
    }

    private func showText(in data: Data, fonts: [String: PDFCMap]) -> [PDFContentText.Word] {
        let tokens = Self.contentTokens(in: [UInt8](data))
        var words: [PDFContentText.Word] = []
        var operands: [ContentToken] = []
        var textA = 1.0
        var textB = 0.0
        var textC = 0.0
        var textD = 1.0
        var textE = 0.0
        var textF = 0.0
        var fontSize = 6.0
        var fontName = fonts.keys.sorted().first ?? ""
        for token in tokens {
            switch token {
            case .number, .name, .bytes:
                operands.append(token)
            case .keyword(let operation):
                switch operation {
                case "BT":
                    textA = 1
                    textB = 0
                    textC = 0
                    textD = 1
                    textE = 0
                    textF = 0
                case "Tm":
                    let numbers = operandNumbers(operands, count: 6)
                    if numbers.count == 6 {
                        textA = numbers[0]
                        textB = numbers[1]
                        textC = numbers[2]
                        textD = numbers[3]
                        textE = numbers[4]
                        textF = numbers[5]
                    }
                case "Td", "TD":
                    let numbers = operandNumbers(operands, count: 2)
                    if numbers.count == 2 {
                        textE += numbers[0] * textA + numbers[1] * textC
                        textF += numbers[0] * textB + numbers[1] * textD
                    }
                case "Tf":
                    if case .number(let size) = operands.last { fontSize = size }
                    if let name = operands.compactMap({ token -> String? in
                        if case .name(let value) = token { return value }
                        return nil
                    }).last {
                        fontName = name
                    }
                case "Tj":
                    if let encoded = operands.compactMap({ token -> Data? in
                        if case .bytes(let value) = token { return value }
                        return nil
                    }).last {
                        let map = fonts[fontName] ?? fonts.values.first
                        if let map {
                        let text = Self.decode(encoded, map: map)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            let width = CGFloat(text.count) * CGFloat(fontSize) * 0.5
                            words.append(PDFContentText.Word(
                                text: text,
                                minX: CGFloat(textE),
                                maxX: CGFloat(textE) + width,
                                midY: CGFloat(textF)
                            ))
                        }
                        }
                    }
                default:
                    break
                }
                operands = []
            }
        }
        return words
    }

    private func operandNumbers(_ operands: [ContentToken], count: Int) -> [Double] {
        operands.suffix(count).compactMap { token in
            if case .number(let value) = token { return value }
            return nil
        }
    }

    private func integers(_ value: PDFValue?) -> [Int] {
        switch value {
        case .some(.array(let items)):
            return items.compactMap { integer($0) }
        case .some(.number(let number)):
            return [Int(number.rounded())]
        default:
            return []
        }
    }

    private func integer(_ value: PDFValue?) -> Int? {
        if case .some(.number(let number)) = value { return Int(number.rounded()) }
        return nil
    }

    private func filterNames(_ dictionary: [String: PDFValue]) -> [String] {
        switch dictionary["Filter"] {
        case .some(.name(let name)):
            return [name]
        case .some(.array(let items)):
            return items.compactMap(\.name)
        default:
            return []
        }
    }

    private static func decoded(_ data: Data, filters: [String]) -> Data? {
        if filters.isEmpty { return data }
        guard filters == ["FlateDecode"] else { return nil }
        return inflate(data)
    }

    fileprivate static func cmap(from data: Data) -> PDFCMap {
        let text = String(decoding: data, as: UTF8.self)
        var width = 0
        if let start = text.range(of: "begincodespacerange") {
            let tail = String(text[start.upperBound...])
            if let expression = try? NSRegularExpression(pattern: #"<([0-9A-Fa-f]+)>"#),
               let match = expression.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
               let range = Range(match.range(at: 1), in: tail) {
                width = tail[range].count / 2
            }
        }
        var characters: [Int: String] = [:]
        let rangePattern = #"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>"#
        if let expression = try? NSRegularExpression(pattern: rangePattern) {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard match.numberOfRanges > 3,
                      let startRange = Range(match.range(at: 1), in: text),
                      let endRange = Range(match.range(at: 2), in: text),
                      let destinationRange = Range(match.range(at: 3), in: text),
                      let start = Int(text[startRange], radix: 16),
                      let end = Int(text[endRange], radix: 16),
                      let destination = Int(text[destinationRange], radix: 16),
                      end >= start, end - start < 4096
                else { continue }
                for offset in 0...(end - start) {
                    let code = destination + offset
                    if let scalar = UnicodeScalar(code) {
                        characters[start + offset] = String(Character(scalar))
                    }
                }
            }
        }
        if let expression = try? NSRegularExpression(pattern: #"(?s)beginbfchar(.*?)endbfchar"#) {
            for block in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(block.range(at: 1), in: text) else { continue }
                let body = String(text[range])
                let pair = try? NSRegularExpression(pattern: #"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>"#)
                for match in pair?.matches(in: body, range: NSRange(body.startIndex..., in: body)) ?? [] {
                    guard match.numberOfRanges > 2,
                          let sourceRange = Range(match.range(at: 1), in: body),
                          let destinationRange = Range(match.range(at: 2), in: body),
                          let source = Int(body[sourceRange], radix: 16)
                    else { continue }
                    let hex = String(body[destinationRange])
                    var units = ""
                    var cursor = hex.startIndex
                    while cursor < hex.endIndex {
                        let next = hex.index(cursor, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
                        if let code = Int(hex[cursor..<next], radix: 16), let scalar = UnicodeScalar(code) {
                            units.append(Character(scalar))
                        }
                        cursor = next
                    }
                    if !units.isEmpty { characters[source] = units }
                }
            }
        }
        return PDFCMap(width: width, characters: characters)
    }

    fileprivate static func decode(_ data: Data, map: PDFCMap) -> String {
        let width = max(map.width, 1)
        let raw = [UInt8](data)
        var text = ""
        var index = 0
        while index + width <= raw.count {
            var code = 0
            for _ in 0..<width {
                code = (code << 8) | Int(raw[index])
                index += 1
            }
            if let character = map.characters[code] {
                text.append(character)
            }
        }
        return text
    }

    private static func contentTokens(in bytes: [UInt8]) -> [ContentToken] {
        var scanner = PDFScanner(bytes: bytes, index: 0)
        var tokens: [ContentToken] = []
        while scanner.index < bytes.count {
            scanner.skip()
            guard let byte = scanner.peek else { break }
            if byte == 40 {
                tokens.append(.bytes(scanner.parseLiteral()))
                continue
            }
            if byte == 60 && scanner.index + 1 < bytes.count && bytes[scanner.index + 1] != 60 {
                tokens.append(.bytes(scanner.parseHex()))
                continue
            }
            if byte == 47 {
                tokens.append(.name(scanner.parseName()))
                continue
            }
            if byte == 91 || byte == 93 {
                tokens.append(.keyword(byte == 91 ? "[" : "]"))
                scanner.index += 1
                continue
            }
            if let number = scanner.parseNumber() {
                tokens.append(.number(number))
                continue
            }
            let start = scanner.index
            while scanner.index < bytes.count && !scanner.isDelimiter(bytes[scanner.index]) {
                scanner.index += 1
            }
            if scanner.index == start {
                scanner.index += 1
                continue
            }
            let word = String(bytes: bytes[start..<scanner.index], encoding: .isoLatin1) ?? ""
            tokens.append(.keyword(word))
        }
        return tokens
    }

    private static func inflate(_ source: Data) -> Data? {
        guard !source.isEmpty else { return Data() }
        let scratchSize = max(compression_decode_scratch_buffer_size(COMPRESSION_ZLIB), 1)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchSize, alignment: 16)
        scratch.initializeMemory(as: UInt8.self, repeating: 0, count: scratchSize)
        defer { scratch.deallocate() }
        var capacity = max(source.count * 8, 65_536)
        while capacity <= 33_554_432 {
            var output = Data(count: capacity)
            let written: Int = output.withUnsafeMutableBytes { destination in
                source.withUnsafeBytes { input in
                    let destinationBuffer = destination.bindMemory(to: UInt8.self)
                    let sourceBuffer = input.bindMemory(to: UInt8.self)
                    guard let destinationBase = destinationBuffer.baseAddress,
                          let sourceBase = sourceBuffer.baseAddress else { return 0 }
                    return compression_decode_buffer(
                        destinationBase,
                        destinationBuffer.count,
                        sourceBase,
                        sourceBuffer.count,
                        scratch,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0, written < capacity {
                return output.prefix(written)
            }
            capacity *= 2
        }
        return nil
    }
}

private enum ContentToken {
    case number(Double)
    case name(String)
    case bytes(Data)
    case keyword(String)
}
