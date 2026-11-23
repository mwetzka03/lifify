import Foundation

/// One depot position for the look-through analysis.
public struct LookThroughPosition: Equatable, Sendable {
    public var name: String
    public var isin: String
    public var valueCents: Int
    /// The fund's holdings, or `nil` for a single stock or a fund without data.
    public var constituents: [FundConstituent]?
    public var leverage: Double

    /// Creates a position.
    public init(name: String, isin: String, valueCents: Int, constituents: [FundConstituent]? = nil, leverage: Double = 1) {
        self.name = name
        self.isin = isin
        self.valueCents = valueCents
        self.constituents = constituents
        self.leverage = leverage
    }
}

/// One company's share of the whole depot.
public struct LookThroughLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let cents: Int
    /// The share of the depot, where 1 is 100 %.
    public let fraction: Double
    public let isOther: Bool
}

/// The depot broken down into its single companies.
public struct LookThroughResult: Equatable, Sendable {
    public var lines: [LookThroughLine] = []
    public var totalFraction = 0.0
    public var hasLeverage = false
    /// Funds shown as one line because their holdings are unknown.
    public var uncoveredFunds: [String] = []
}

/// Breaks ETFs into their holdings and merges the same company across all positions.
public enum DepotLookThrough {
    /// Lines below this share of the depot are combined into Other.
    public static let minimumFraction = 0.001

    /// A company while its parts are being added up.
    private struct Group {
        var label: String
        var cents: Double
    }

    /// Calculates the look-through.
    ///
    /// A fund contributes value × leverage × weight to each holding. With leverage the sum can
    /// exceed 100 %. Weights missing from a fund's list stay in Other, so nothing is lost.
    ///
    /// - Parameters:
    ///   - positions: The depot positions.
    ///   - otherTitle: The label of the combined line.
    ///   - funds: The ISINs treated as funds even without data.
    /// - Returns: The lines, largest first, with Other last.
    public static func analyze(
        _ positions: [LookThroughPosition],
        otherTitle: String,
        funds: Set<String> = []
    ) -> LookThroughResult {
        let total = positions.reduce(0) { $0 + $1.valueCents }
        guard total > 0 else { return LookThroughResult() }
        var merger = CompanyMerger()
        var unassigned = 0.0
        for position in positions {
            guard let constituents = position.constituents else {
                merger.add(name: position.name, isin: position.isin, ticker: "", cents: Double(position.valueCents))
                continue
            }
            let value = Double(position.valueCents) * position.leverage
            for item in constituents {
                merger.add(name: item.name, isin: item.isin, ticker: item.ticker, cents: value * item.weight)
            }
            unassigned += value * max(0, 1 - constituents.reduce(0) { $0 + $1.weight })
        }
        var result = lines(merger.groups, unassigned: unassigned, total: Double(total), otherTitle: otherTitle)
        result.hasLeverage = positions.contains { $0.constituents != nil && $0.leverage > 1 }
        result.uncoveredFunds = positions.filter { $0.constituents == nil && funds.contains($0.isin) }.map(\.name)
        return result
    }

    /// Splits the groups into single lines and the combined line.
    private static func lines(_ groups: [Group], unassigned: Double, total: Double, otherTitle: String) -> LookThroughResult {
        let large = groups.filter { $0.cents / total >= minimumFraction }.sorted { $0.cents > $1.cents }
        let small = groups.filter { $0.cents / total < minimumFraction }.reduce(0) { $0 + $1.cents } + unassigned
        var rows = large.map {
            LookThroughLine(id: $0.label, label: $0.label, cents: Int($0.cents.rounded()), fraction: $0.cents / total, isOther: false)
        }
        if small >= 0.5 {
            rows.append(LookThroughLine(id: "other", label: otherTitle, cents: Int(small.rounded()), fraction: small / total, isOther: true))
        }
        return LookThroughResult(lines: rows, totalFraction: rows.reduce(0) { $0 + $1.fraction })
    }

    /// Merges securities by ISIN, then ticker, then normalized company name.
    private struct CompanyMerger {
        private(set) var groups: [Group] = []
        private var index: [String: Int] = [:]

        /// Adds an amount to its company.
        mutating func add(name: String, isin: String, ticker: String, cents: Double) {
            let keys = [
                isin.isEmpty ? nil : "isin:\(isin.uppercased())",
                ticker.isEmpty ? nil : "ticker:\(ticker.uppercased())",
                companyKey(name).isEmpty ? nil : "name:\(companyKey(name))"
            ].compactMap { $0 }
            let position: Int
            if let known = keys.compactMap({ index[$0] }).first {
                position = known
            } else {
                groups.append(Group(label: name, cents: 0))
                position = groups.count - 1
            }
            groups[position].cents += cents
            keys.forEach { index[$0] = position }
        }

        /// Reduces a name to its company, so share classes such as Alphabet A and C merge.
        private func companyKey(_ name: String) -> String {
            let suffixes: Set<String> = [
                "A", "B", "C", "CL", "CLASS", "INC", "CORP", "CORPORATION", "CO", "COMPANY", "LTD", "LIMITED",
                "PLC", "AG", "SE", "SA", "NV", "ADR", "REG", "REGISTERED", "SHARES", "ORD", "PREF", "THE"
            ]
            var words = name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                .uppercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            while words.count > 1, let last = words.last, suffixes.contains(last) {
                words.removeLast()
            }
            return words.joined(separator: " ")
        }
    }
}
