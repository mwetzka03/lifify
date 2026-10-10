import Foundation
import SwiftData

@MainActor
enum MarketDataService {
    static func refresh(holdings: [PortfolioHolding], context: ModelContext) async {
        var changed = false
        for holding in holdings where isValidISIN(holding.symbol) {
            guard let cents = try? await currentPriceCents(for: holding.symbol) else {
                continue
            }
            holding.currentPriceCents = cents
            holding.updatedAt = .now
            changed = true
        }
        if changed { try? context.save() }
    }

    static func currentPriceCents(for isin: String) async throws -> Int {
        let normalizedISIN = isin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard isValidISIN(normalizedISIN) else { throw MarketDataError.invalidISIN }

        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: normalizedISIN),
            URLQueryItem(name: "quotesCount", value: "8"),
            URLQueryItem(name: "newsCount", value: "0")
        ]
        let search: YahooSearchResponse = try await request(components.url!)
        let eligibleQuotes = search.quotes.filter {
            ["EQUITY", "ETF", "MUTUALFUND"].contains($0.quoteType ?? "")
                && $0.isYahooFinance == true
        }
        guard eligibleQuotes.count == 1, let symbol = eligibleQuotes[0].symbol else {
            throw MarketDataError.instrumentNotFound
        }

        let quote = try await chart(symbol: symbol)
        guard let price = quote.price, price > 0 else { throw MarketDataError.priceUnavailable }
        let sourceCurrency = quote.currency ?? "EUR"
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

    private static func chart(symbol: String) async throws -> YahooChartQuote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d")!
        let response: YahooChartResponse = try await request(url)
        guard let meta = response.chart.result?.first?.meta else {
            throw MarketDataError.priceUnavailable
        }
        return YahooChartQuote(price: meta.regularMarketPrice, currency: meta.currency)
    }

    private static func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 Lifify/0.1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
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
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooChartResult]?
}

private struct YahooChartResult: Decodable {
    let meta: YahooChartMeta
}

private struct YahooChartMeta: Decodable {
    let regularMarketPrice: Double?
    let currency: String?
}

private struct YahooChartQuote {
    let price: Double?
    let currency: String?
}

private enum MarketDataError: Error {
    case invalidISIN
    case instrumentNotFound
    case priceUnavailable
    case currencyConversionUnavailable
    case requestFailed
}
