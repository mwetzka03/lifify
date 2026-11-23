import Foundation
import LififyCore

/// One security inside a fund.
public struct FundConstituent: Codable, Equatable, Sendable {
    public var name: String
    public var isin: String
    public var ticker: String
    /// The share of the fund, where 1 is 100 %.
    public var weight: Double

    /// Creates a constituent.
    public init(name: String, isin: String = "", ticker: String = "", weight: Double) {
        self.name = name
        self.isin = isin
        self.ticker = ticker
        self.weight = weight
    }
}

/// The holdings of a fund at one date.
public struct FundComposition: Codable, Equatable, Sendable {
    public var constituents: [FundConstituent]
    public var fetchedAt: Date
    public var isManual: Bool

    /// Creates a composition.
    public init(constituents: [FundConstituent], fetchedAt: Date, isManual: Bool = false) {
        self.constituents = constituents
        self.fetchedAt = fetchedAt
        self.isManual = isManual
    }
}

/// Finds the holdings table in an Excel or CSV file from any fund provider.
public enum FundCompositionParser {
    /// The reasons a holdings file cannot be used.
    public enum Failure: Error {
        case noHoldingsTable
    }

    /// The columns of the holdings table.
    private struct Columns {
        let header: Int
        let name: Int
        let weight: Int
        let isin: Int?
        let ticker: Int?
    }

    /// Reads a holdings file by its type.
    ///
    /// - Parameters:
    ///   - data: The file.
    ///   - fileExtension: `xlsx` or `csv`.
    /// - Returns: The constituents, largest first.
    /// - Throws: An error when no holdings table is found.
    public static func parse(_ data: Data, fileExtension: String) throws -> [FundConstituent] {
        let rows = fileExtension.lowercased() == "xlsx"
            ? try XLSXReader.rows(in: data)
            : csvRows(String(decoding: data, as: UTF8.self))
        return try parse(rows: rows)
    }

    /// Finds the header row and reads the constituents.
    public static func parse(rows: [[Int: String]]) throws -> [FundConstituent] {
        guard let columns = findColumns(in: rows) else { throw Failure.noHoldingsTable }
        let body = rows.dropFirst(columns.header + 1)
        let parsed = body.compactMap { row -> (FundConstituent, Bool)? in
            guard let name = row[columns.name]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let text = row[columns.weight],
                  let weight = number(text), weight > 0
            else { return nil }
            let item = FundConstituent(
                name: name,
                isin: columns.isin.flatMap { row[$0] }?.trimmingCharacters(in: .whitespaces).uppercased() ?? "",
                ticker: columns.ticker.flatMap { row[$0] }?.trimmingCharacters(in: .whitespaces) ?? "",
                weight: weight
            )
            return (item, text.contains("%"))
        }
        guard !parsed.isEmpty else { throw Failure.noHoldingsTable }
        let total = parsed.reduce(0) { $0 + $1.0.weight }
        let inPercent = parsed.contains(where: \.1) || total > 1.5
        return parsed
            .map { pair in
                var item = pair.0
                if inPercent { item.weight /= 100 }
                return item
            }
            .sorted { $0.weight > $1.weight }
    }

    /// Finds the first row that names both a security and its weight.
    private static func findColumns(in rows: [[Int: String]]) -> Columns? {
        for (index, row) in rows.enumerated() {
            let labels = row.mapValues { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            let weight = column(in: labels) { $0.contains("weight") || $0.contains("gewicht") || $0.contains("% des") || $0.contains("% of") }
            let name = column(in: labels) { $0 == "name" || $0.contains("bezeichnung") || $0 == "emittent" || $0 == "holding" }
            guard let weight, let name else { continue }
            return Columns(
                header: index,
                name: name,
                weight: weight,
                isin: column(in: labels) { $0 == "isin" },
                ticker: column(in: labels) { $0.contains("ticker") || $0 == "symbol" }
            )
        }
        return nil
    }

    /// Returns the leftmost column whose label fits.
    private static func column(in labels: [Int: String], where matches: (String) -> Bool) -> Int? {
        labels.filter { matches($0.value) }.keys.min()
    }

    /// Parses `6,03%`, `1.234,5`, or `0.0609`.
    private static func number(_ text: String) -> Double? {
        var cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(cleaned)
    }

    /// Splits CSV text, choosing the delimiter each line uses most.
    private static func csvRows(_ text: String) -> [[Int: String]] {
        text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .map { line in
                let delimiter: Character = line.filter { $0 == ";" }.count >= line.filter { $0 == "," }.count ? ";" : ","
                let cells = csvFields(line, delimiter: delimiter)
                return Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($0.offset, $0.element) })
            }
    }

    /// Splits one line and respects quotes.
    private static func csvFields(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == delimiter, !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}

/// Where the holdings of a fund come from.
public enum FundSource: Equatable, Sendable {
    case xtrackers(isin: String)
    case vanEck(slug: String)

    /// The file name of the cached composition.
    public var cacheKey: String {
        switch self {
        case .xtrackers(let isin): "xtrackers-\(isin)"
        case .vanEck(let slug): "vaneck-\(slug)"
        }
    }

    /// The official download.
    public var url: URL? {
        switch self {
        case .xtrackers(let isin):
            URL(string: "https://etf.deutsche-am.com/etfdata/export/DEU/DEU/excel/product/constituent/\(isin)/")
        case .vanEck(let slug):
            URL(string: "https://www.vaneck.com/de/de/investments/\(slug)/downloads/holdings/")
        }
    }

    /// Picks the fund's own file, or a fund on the same index.
    ///
    /// Funds on one index hold the same weights. For a swap ETF only the index is meaningful,
    /// because its actual holdings are a substitute basket.
    ///
    /// - Parameters:
    ///   - isin: The fund's ISIN.
    ///   - name: The fund's name.
    /// - Returns: The source, or `nil` when only a manual import can help.
    public static func resolve(isin: String, name: String) -> FundSource? {
        let text = name.lowercased()
        if text.contains("vaneck") { return vanEckSource(text) }
        if text.contains("xtrackers"), !text.contains("2x") { return .xtrackers(isin: isin.uppercased()) }
        return indexStandIn(text).map { .xtrackers(isin: $0) }
    }

    /// The leverage factor of a fund, read from its name.
    public static func leverage(name: String) -> Double {
        let text = name.lowercased()
        if text.contains("3x") { return 3 }
        return text.contains("2x") ? 2 : 1
    }

    /// Finds the VanEck page of a fund.
    private static func vanEckSource(_ text: String) -> FundSource? {
        if text.contains("quantum") { return .vanEck(slug: "quantum-computing-etf") }
        if text.contains("rare earth") { return .vanEck(slug: "rare-earth-etf") }
        if text.contains("space") { return .vanEck(slug: "space-etf") }
        return nil
    }

    /// Finds an Xtrackers fund on the same MSCI index.
    private static func indexStandIn(_ text: String) -> String? {
        guard text.contains("msci") else { return nil }
        if text.contains("small") { return nil }
        if text.contains("ex usa") { return "IE0006WW1TQ4" }
        if text.contains("consumer staples") { return "IE00BM67HN09" }
        if text.contains("emerging") { return "IE00BTJRMP35" }
        if text.contains("usa") { return "IE00BJ0KDR00" }
        return text.contains("world") ? "IE00BJ0KDQ92" : nil
    }
}

/// Keeps fund compositions as files. They are caches, so no backup carries them.
public enum FundCompositionStore {
    /// Compositions are loaded again after this many days at the earliest.
    public static let refreshDays = 7

    /// The folder of the files.
    private static var directory: URL {
        AppFiles.supportDirectory.appendingPathComponent("FundCompositions", isDirectory: true)
    }

    /// Returns the composition of a position. A manual import wins over a download.
    public static func composition(isin: String, name: String) -> FundComposition? {
        if let manual = read("manual-\(isin.uppercased())") { return manual }
        return FundSource.resolve(isin: isin, name: name).flatMap { read($0.cacheKey) }
    }

    /// Stores a downloaded composition.
    public static func store(_ composition: FundComposition, for source: FundSource) {
        write(composition, name: source.cacheKey)
    }

    /// Stores a manually imported composition.
    public static func storeManual(_ composition: FundComposition, isin: String) {
        write(composition, name: "manual-\(isin.uppercased())")
    }

    /// Removes a manual import.
    public static func removeManual(isin: String) {
        try? FileManager.default.removeItem(at: file("manual-\(isin.uppercased())"))
    }

    /// Says whether a source needs a new download.
    public static func needsRefresh(_ source: FundSource, now: Date) -> Bool {
        guard let stored = read(source.cacheKey) else { return true }
        return now.timeIntervalSince(stored.fetchedAt) >= Double(refreshDays) * 86_400
    }

    /// Deletes all stored compositions.
    public static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Returns a file's location.
    private static func file(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    /// Reads one file.
    private static func read(_ name: String) -> FundComposition? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(FundComposition.self, from: data)
    }

    /// Writes one file.
    private static func write(_ composition: FundComposition, name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(composition) else { return }
        try? data.write(to: file(name), options: .atomic)
    }
}

/// Downloads fund holdings from the providers' official files. Only fund identifiers are sent.
public enum FundCompositionLoader {
    /// Loads the positions' compositions that are missing or older than a week.
    ///
    /// - Parameters:
    ///   - funds: ISIN and name of the positions.
    ///   - force: Whether to load even when the stored data is recent.
    ///   - now: The current time.
    /// - Returns: The number of sources that could not be loaded.
    @discardableResult
    public static func refresh(funds: [(isin: String, name: String)], force: Bool, now: Date = Date()) async -> Int {
        var sources: [FundSource] = []
        for fund in funds {
            if let source = FundSource.resolve(isin: fund.isin, name: fund.name), !sources.contains(source) {
                sources.append(source)
            }
        }
        var failed = 0
        for source in sources where force || FundCompositionStore.needsRefresh(source, now: now) {
            if let constituents = try? await download(source), !constituents.isEmpty {
                FundCompositionStore.store(FundComposition(constituents: constituents, fetchedAt: now), for: source)
            } else {
                failed += 1
            }
        }
        return failed
    }

    /// Downloads and parses one official file.
    private static func download(_ source: FundSource) async throws -> [FundConstituent] {
        guard let url = source.url else { throw URLError(.badURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 Lifify/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try FundCompositionParser.parse(data, fileExtension: "xlsx")
    }
}
