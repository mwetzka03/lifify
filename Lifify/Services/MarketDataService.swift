import Foundation
import SwiftData

struct StockSuggestion: Identifiable, Hashable {
    let symbol: String
    let name: String
    let exchange: String

    var id: String { symbol }
}

enum MarketSymbolStore {
    static func symbol(for holdingID: UUID) -> String? {
        UserDefaults.standard.string(forKey: "market.symbol.\(holdingID.uuidString)")
    }

    static func set(_ symbol: String, for holdingID: UUID) {
        UserDefaults.standard.set(symbol, forKey: "market.symbol.\(holdingID.uuidString)")
    }

    static func remove(for holdingID: UUID) {
        UserDefaults.standard.removeObject(forKey: "market.symbol.\(holdingID.uuidString)")
    }
}

struct MarketQuote {
    let priceCents: Int
    let previousCloseCents: Int?
}

@MainActor
enum HistoricalPriceStore {
    private static let key = "lifify.historicalPrices"

    static func cents(for holdingID: UUID, dayKey: String) -> Int? {
        all()[holdingID.uuidString]?[dayKey]
    }

    static func nearestCents(for holdingID: UUID, onOrBefore dayKey: String) -> Int? {
        guard let prices = all()[holdingID.uuidString] else { return nil }
        return prices.filter { $0.key <= dayKey }.max { $0.key < $1.key }?.value
    }

    static func replace(_ prices: [String: Int], holdingID: UUID) {
        var map = all()
        if prices.isEmpty {
            map.removeValue(forKey: holdingID.uuidString)
        } else {
            map[holdingID.uuidString] = prices
        }
        save(map)
    }

    static func remove(for holdingID: UUID) {
        var map = all()
        map.removeValue(forKey: holdingID.uuidString)
        save(map)
    }

    private static func all() -> [String: [String: Int]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return [:] }
        return decoded
    }

    private static func save(_ map: [String: [String: Int]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum PreviousCloseStore {
    static func cents(for holdingID: UUID) -> Int? {
        let key = "market.previous.\(holdingID.uuidString)"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    static func set(_ cents: Int, for holdingID: UUID) {
        UserDefaults.standard.set(cents, forKey: "market.previous.\(holdingID.uuidString)")
    }

    static func remove(for holdingID: UUID) {
        UserDefaults.standard.removeObject(forKey: "market.previous.\(holdingID.uuidString)")
    }
}

enum HoldingPurchaseDateStore {
    static func date(for holdingID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: key(for: holdingID)) as? Date
    }

    static func set(_ date: Date, for holdingID: UUID) {
        UserDefaults.standard.set(date, forKey: key(for: holdingID))
    }

    static func remove(for holdingID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: holdingID))
    }

    private static func key(for holdingID: UUID) -> String {
        "holding.purchased.\(holdingID.uuidString)"
    }
}

@MainActor
enum MarketDataService {
    static func refresh(holdings: [PortfolioHolding], context: ModelContext) async {
        var changed = false
        var fxRates: [String: [String: Double]] = [:]
        for holding in holdings where isValidISIN(holding.symbol) {
            let loaded: (history: [String: Int], priceCents: Int, previousCloseCents: Int?, fxRates: [String: [String: Double]])?
            if let history = try? await history(for: holding, fxRates: fxRates) {
                loaded = history
            } else if let quote = try? await currentQuote(for: holding) {
                loaded = (history: [:], priceCents: quote.priceCents, previousCloseCents: quote.previousCloseCents, fxRates: fxRates)
            } else {
                loaded = nil
            }
            guard let loaded else { continue }
            fxRates = loaded.fxRates
            if !loaded.history.isEmpty {
                HistoricalPriceStore.replace(loaded.history, holdingID: holding.id)
            }
            holding.currentPriceCents = loaded.priceCents
            if let previous = loaded.previousCloseCents {
                PreviousCloseStore.set(previous, for: holding.id)
            }
            holding.updatedAt = .now
            changed = true
        }
        if changed { try? context.save() }
    }

    static func currentPriceCents(for isin: String) async throws -> Int {
        try await quote(for: isin).priceCents
    }

    static func quote(for isin: String) async throws -> MarketQuote {
        let matches = try await suggestions(for: isin)
        guard let match = preferred(matches) else { throw MarketDataError.instrumentNotFound }
        return try await quote(for: match)
    }

    static func quote(for suggestion: StockSuggestion) async throws -> MarketQuote {
        try await quote(forMarketSymbol: suggestion.symbol)
    }

    static func suggestions(for isin: String) async throws -> [StockSuggestion] {
        let normalizedISIN = isin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard isValidISIN(normalizedISIN) else { throw MarketDataError.invalidISIN }

        let urls = ["https://query1.finance.yahoo.com/v1/finance/search", "https://query2.finance.yahoo.com/v1/finance/search"].compactMap { host -> URL? in
            var components = URLComponents(string: host)
            components?.queryItems = [
                URLQueryItem(name: "q", value: normalizedISIN),
                URLQueryItem(name: "quotesCount", value: "8"),
                URLQueryItem(name: "newsCount", value: "0")
            ]
            return components?.url
        }
        let search: YahooSearchResponse = try await requestFirst(urls)
        let mapped: [(suggestion: StockSuggestion, listed: Bool)] = search.quotes.compactMap { quote in
            guard ["EQUITY", "ETF", "MUTUALFUND"].contains(quote.quoteType ?? ""),
                  let symbol = quote.symbol,
                  !symbol.isEmpty
            else { return nil }
            return (
                StockSuggestion(
                    symbol: symbol,
                    name: quote.longname ?? quote.shortname ?? symbol,
                    exchange: quote.exchDisp ?? quote.exchange ?? ""
                ),
                quote.isYahooFinance != false
            )
        }
        let listed = mapped.filter(\.listed).map(\.suggestion)
        return listed.isEmpty ? mapped.map(\.suggestion) : listed
    }

    /// Prefer a German listing. Lang & Schwarz has no public price API, so Xetra,
    /// Frankfurt, gettex and Tradegate on Yahoo are the practical source.
    private static func preferred(_ matches: [StockSuggestion]) -> StockSuggestion? {
        matches.sorted { lhs, rhs in
            let left = listingScore(lhs)
            let right = listingScore(rhs)
            if left != right { return left > right }
            return lhs.symbol < rhs.symbol
        }.first
    }

    private static func listingScore(_ item: StockSuggestion) -> Int {
        let symbol = item.symbol.uppercased()
        let exchange = item.exchange.uppercased()
        var score = 0
        if symbol.hasSuffix(".DE") { score += 80 }
        if symbol.hasSuffix(".F") || symbol.hasSuffix(".SG") || symbol.hasSuffix(".MU")
            || symbol.hasSuffix(".DU") || symbol.hasSuffix(".HM") || symbol.hasSuffix(".BE") {
            score += 40
        }
        let german = ["XETRA", "GER", "FRANKFURT", "GETTEX", "TRADEGATE", "STUTTGART", "LANG", "LSX"]
        if german.contains(where: { exchange.contains($0) || symbol.contains($0) }) { score += 30 }
        return score
    }

    static func currentPriceCents(for suggestion: StockSuggestion) async throws -> Int {
        try await quote(for: suggestion).priceCents
    }

    private static func quote(forMarketSymbol symbol: String) async throws -> MarketQuote {
        let quote = try await chart(symbol: symbol)
        guard let price = quote.price, price > 0 else { throw MarketDataError.priceUnavailable }
        let priceCents = try await euroCents(for: price, sourceCurrency: quote.currency ?? "EUR")
        let previousCents: Int?
        if let previous = quote.previousClose, previous > 0 {
            previousCents = try await euroCents(for: previous, sourceCurrency: quote.currency ?? "EUR")
        } else {
            previousCents = nil
        }
        return MarketQuote(priceCents: priceCents, previousCloseCents: previousCents)
    }

    private static func euroCents(for price: Double, sourceCurrency: String) async throws -> Int {
        let currency = sourceCurrency.uppercased()
        let euroPrice: Double
        if currency == "EUR" {
            euroPrice = price
        } else {
            let baseCurrency: String
            let basePrice: Double
            if sourceCurrency == "GBp" || currency == "GBX" {
                baseCurrency = "GBP"
                basePrice = price / 100
            } else {
                baseCurrency = currency
                basePrice = price
            }
            let conversion = try await chart(symbol: "\(baseCurrency)EUR=X")
            guard let rate = conversion.price, rate > 0 else {
                throw MarketDataError.currencyConversionUnavailable
            }
            euroPrice = basePrice * rate
        }
        return Int((euroPrice * 100).rounded())
    }

    static func isValidISIN(_ value: String) -> Bool {
        let value = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard value.count == 12 else { return false }
        let scalars = Array(value.unicodeScalars)
        let isASCIILetter: (UnicodeScalar) -> Bool = { (65...90).contains($0.value) }
        let isASCIIDigit: (UnicodeScalar) -> Bool = { (48...57).contains($0.value) }
        guard scalars.allSatisfy({ isASCIILetter($0) || isASCIIDigit($0) }),
              scalars.prefix(2).allSatisfy(isASCIILetter),
              scalars.last.map(isASCIIDigit) == true
        else {
            return false
        }

        var digits: [Int] = []
        for scalar in scalars {
            if isASCIIDigit(scalar) {
                digits.append(Int(scalar.value - 48))
            } else {
                let number = Int(scalar.value - 55)
                digits.append(number / 10)
                digits.append(number % 10)
            }
        }
        let checksum = digits.reversed().enumerated().reduce(0) { total, item in
            let (index, digit) = item
            let value = index.isMultiple(of: 2) ? digit : digit * 2
            return total + value / 10 + value % 10
        }
        return checksum.isMultiple(of: 10)
    }

    private static func currentQuote(for holding: PortfolioHolding) async throws -> MarketQuote {
        if let stored = MarketSymbolStore.symbol(for: holding.id) {
            if let quote = try? await quote(forMarketSymbol: stored) {
                return quote
            }
            MarketSymbolStore.remove(for: holding.id)
        }
        let matches = try await suggestions(for: holding.symbol)
        guard let match = preferred(matches) else { throw MarketDataError.instrumentNotFound }
        let quote = try await quote(for: match)
        MarketSymbolStore.set(match.symbol, for: holding.id)
        return quote
    }

    private static func history(
        for holding: PortfolioHolding,
        fxRates: [String: [String: Double]]
    ) async throws -> (history: [String: Int], priceCents: Int, previousCloseCents: Int?, fxRates: [String: [String: Double]]) {
        let series = try await series(for: holding)
        let converted = try await euroHistory(series, fxRates: fxRates)
        return (converted.history, converted.priceCents, converted.previousCloseCents, converted.fxRates)
    }

    private static func series(for holding: PortfolioHolding) async throws -> YahooSeries {
        if let stored = MarketSymbolStore.symbol(for: holding.id) {
            if let series = try? await chartSeries(symbol: stored, range: "5y") {
                return series
            }
            MarketSymbolStore.remove(for: holding.id)
        }
        let matches = try await suggestions(for: holding.symbol)
        guard let match = preferred(matches) else { throw MarketDataError.instrumentNotFound }
        let series = try await chartSeries(symbol: match.symbol, range: "5y")
        MarketSymbolStore.set(match.symbol, for: holding.id)
        return series
    }

    private static func euroHistory(
        _ series: YahooSeries,
        fxRates: [String: [String: Double]]
    ) async throws -> (history: [String: Int], priceCents: Int, previousCloseCents: Int?, fxRates: [String: [String: Double]]) {
        let currency = series.currency ?? "EUR"
        let loadedRates = await fxDayRates(currency: currency, cache: fxRates)
        let rates = loadedRates.rates
        var history: [String: Int] = [:]
        for point in series.points {
            let key = point.date.dayKey
            guard let cents = euroCents(price: point.price, currency: currency, dayKey: key, rates: rates) else { continue }
            history[key] = cents
        }
        let latestPrice = series.marketPrice ?? series.points.last?.price
        guard let latestPrice, latestPrice > 0 else { throw MarketDataError.priceUnavailable }
        let todayKey = Date.now.dayKey
        let latestCents = euroCents(price: latestPrice, currency: currency, dayKey: todayKey, rates: rates)
            ?? (try? await euroCents(for: latestPrice, sourceCurrency: currency))
        guard let latestCents else { throw MarketDataError.currencyConversionUnavailable }
        let previousPrice = series.previousClose ?? series.points.dropLast().last?.price
        let previousCents = previousPrice.flatMap { euroCents(price: $0, currency: currency, dayKey: todayKey, rates: rates) }
        return (history, latestCents, previousCents, loadedRates.cache)
    }

    private static func euroCents(price: Double, currency: String, dayKey: String, rates: [String: Double]) -> Int? {
        guard price > 0 else { return nil }
        let code = currency.uppercased()
        let (base, value): (String, Double)
        if currency == "GBp" || code == "GBX" {
            base = "GBP"
            value = price / 100
        } else {
            base = code
            value = price
        }
        if base == "EUR" {
            return Int((value * 100).rounded())
        }
        guard let rate = rates[dayKey] ?? rates.filter({ $0.key <= dayKey }).max(by: { $0.key < $1.key })?.value, rate > 0 else {
            return nil
        }
        return Int((value * rate * 100).rounded())
    }

    private static func fxDayRates(
        currency: String,
        cache: [String: [String: Double]]
    ) async -> (rates: [String: Double], cache: [String: [String: Double]]) {
        let code = currency.uppercased()
        let base = (currency == "GBp" || code == "GBX") ? "GBP" : code
        if base == "EUR" { return ([:], cache) }
        if let cached = cache[base] { return (cached, cache) }
        var stored = cache
        guard let series = try? await chartSeries(symbol: "\(base)EUR=X", range: "5y") else {
            stored[base] = [:]
            return ([:], stored)
        }
        var rates: [String: Double] = [:]
        for point in series.points where point.price > 0 {
            rates[point.date.dayKey] = point.price
        }
        stored[base] = rates
        return (rates, stored)
    }

    private static func chart(symbol: String) async throws -> YahooChartQuote {
        let series = try await chartSeries(symbol: symbol, range: "5d")
        return YahooChartQuote(
            price: series.marketPrice ?? series.points.last?.price,
            previousClose: series.previousClose ?? series.points.dropLast().last?.price,
            currency: series.currency
        )
    }

    private static func chartSeries(symbol: String, range: String) async throws -> YahooSeries {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "=")
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: allowed) ?? symbol
        let urls = [
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=\(range)",
            "https://query2.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=\(range)"
        ].compactMap(URL.init(string:))
        let response: YahooChartResponse = try await requestFirst(urls)
        guard let result = response.chart.result?.first else { throw MarketDataError.priceUnavailable }
        let closes = result.indicators?.quote?.first?.close ?? []
        let stamps = result.timestamp ?? []
        var points: [(date: Date, price: Double)] = []
        for (stamp, close) in zip(stamps, closes) {
            guard let close, close > 0 else { continue }
            points.append((Date(timeIntervalSince1970: TimeInterval(stamp)), close))
        }
        return YahooSeries(
            currency: result.meta.currency,
            points: points,
            marketPrice: result.meta.regularMarketPrice,
            previousClose: result.meta.previousClose ?? result.meta.chartPreviousClose
        )
    }

    private static func requestFirst<Response: Decodable>(_ urls: [URL]) async throws -> Response {
        var last: Error = MarketDataError.requestFailed
        for url in urls {
            do { return try await request(url) }
            catch { last = error }
        }
        throw last
    }

    private static func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 Lifify/0.2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MarketDataError.requestFailed
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct YahooSearchResponse: Decodable {
    let quotes: [YahooSearchQuote]
}

private struct YahooSearchQuote: Decodable {
    let symbol: String?
    let quoteType: String?
    let isYahooFinance: Bool?
    let longname: String?
    let shortname: String?
    let exchange: String?
    let exchDisp: String?
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooChartResult]?
}

private struct YahooChartResult: Decodable {
    let meta: YahooChartMeta
    let timestamp: [Int]?
    let indicators: YahooIndicators?

    private enum CodingKeys: String, CodingKey {
        case meta, timestamp, indicators
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(YahooChartMeta.self, forKey: .meta)
        if let stamps = try? container.decode([Int].self, forKey: .timestamp) {
            timestamp = stamps
        } else if let stamps = try? container.decode([Double].self, forKey: .timestamp) {
            timestamp = stamps.map { Int($0) }
        } else {
            timestamp = nil
        }
        indicators = try? container.decode(YahooIndicators.self, forKey: .indicators)
    }
}

private struct YahooIndicators: Decodable {
    let quote: [YahooIndicatorQuote]?
}

private struct YahooIndicatorQuote: Decodable {
    let close: [Double?]?
}

private struct YahooSeries {
    let currency: String?
    let points: [(date: Date, price: Double)]
    let marketPrice: Double?
    let previousClose: Double?
}

private struct YahooChartMeta: Decodable {
    let regularMarketPrice: Double?
    let previousClose: Double?
    let chartPreviousClose: Double?
    let currency: String?
}

private struct YahooChartQuote {
    let price: Double?
    let previousClose: Double?
    let currency: String?
}

private enum MarketDataError: Error {
    case invalidISIN
    case instrumentNotFound
    case priceUnavailable
    case currencyConversionUnavailable
    case requestFailed
}
