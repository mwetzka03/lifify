import Foundation
import LififyCore
import LififyFinance
import Testing
@testable import Lifify

/// Finds the test bundle that carries the sample file.
private final class HoldingsBundleMarker {}

extension LififyRuleTests {
    /// Fund files are read, and ETFs are broken down into single companies.
    @Suite("Depot look-through")
    @MainActor
    struct DepotLookThroughTests {
        @Test func readsAnExcelHoldingsFile() throws {
            let url = try #require(Bundle(for: HoldingsBundleMarker.self).url(forResource: "holdings-sample", withExtension: "xlsx"))
            let items = try FundCompositionParser.parse(Data(contentsOf: url), fileExtension: "xlsx")
            #expect(items.count == 4)
            #expect(items[0] == FundConstituent(name: "APPLE INC", isin: "US0378331005", weight: 0.5))
            #expect(items.last?.name == "Kleinwert")
        }

        @Test func readsAnISharesHoldingsFile() throws {
            let url = try #require(Bundle(for: HoldingsBundleMarker.self).url(forResource: "ishares-holdings-sample", withExtension: "csv"))
            let items = try FundCompositionParser.parse(Data(contentsOf: url), fileExtension: "csv")
            #expect(items.count == 9)
            #expect(items[0].name == "THALES SA")
            #expect(items[0].ticker == "HO")
            #expect(abs(items[0].weight - 0.0595) < 0.000001)
        }

        @Test func readsGermanPercentsFromCSV() throws {
            let csv = "Alle Fondspositionen\n\nPosition;Bezeichnung der Position;Ticker;ISIN;% des Fondsvolumens\n1;Ionq Inc;IONQ US;US46222L1089;6,03%\n2;Synopsys Inc;SNPS US;US8716071076;5,60%\n"
            let items = try FundCompositionParser.parse(Data(csv.utf8), fileExtension: "csv")
            #expect(items.map(\.ticker) == ["IONQ US", "SNPS US"])
            #expect(abs(items[0].weight - 0.0603) < 0.000001)
        }

        @Test func percentsWithoutASignAreRecognized() throws {
            let csv = "Name,ISIN,Gewichtung (%)\nApple,US0378331005,60.5\nMicrosoft,US5949181045,39.5\n"
            let items = try FundCompositionParser.parse(Data(csv.utf8), fileExtension: "csv")
            #expect(abs(items[0].weight - 0.605) < 0.000001)
        }

        @Test func aFileWithoutATableFails() {
            #expect(throws: (any Error).self) {
                try FundCompositionParser.parse(Data("nur Text\nohne Tabelle".utf8), fileExtension: "csv")
            }
        }

        @Test func picksTheOwnFileOrAFundOnTheSameIndex() {
            #expect(FundSource.resolve(isin: "IE00BGV5VN51", name: "Xtrackers Artificial Intelligence & Big Data") == .xtrackers(isin: "IE00BGV5VN51"))
            #expect(FundSource.resolve(isin: "IE00B4L5Y983", name: "iShares Core MSCI World") == .xtrackers(isin: "IE00BJ0KDQ92"))
            #expect(FundSource.resolve(isin: "X", name: "Xtrackers MSCI World ex USA") == .xtrackers(isin: "X"))
            #expect(FundSource.resolve(isin: "X", name: "iShares MSCI USA") == .xtrackers(isin: "IE00BJ0KDR00"))
            #expect(FundSource.resolve(isin: "X", name: "Amundi MSCI Emerging Markets") == .xtrackers(isin: "IE00BTJRMP35"))
            #expect(FundSource.resolve(isin: "X", name: "Amundi MSCI USA Daily 2x Leveraged") == .xtrackers(isin: "IE00BJ0KDR00"))
            #expect(FundSource.resolve(isin: "X", name: "MSCI World Consumer Staples") == .xtrackers(isin: "IE00BM67HN09"))
            #expect(FundSource.resolve(isin: "X", name: "VanEck Quantum Computing") == .vanEck(slug: "quantum-computing-etf"))
            #expect(FundSource.resolve(isin: "X", name: "VanEck Rare Earth and Strategic Metals") == .vanEck(slug: "rare-earth-etf"))
            #expect(FundSource.resolve(isin: "X", name: "VanEck Space Innovators") == .vanEck(slug: "space-etf"))
            #expect(FundSource.resolve(isin: "X", name: "iShares MSCI World Small Cap") == nil)
            #expect(FundSource.resolve(isin: "X", name: "iShares Space Technologies") == nil)
            #expect(FundSource.leverage(name: "Amundi MSCI USA Daily 2x Leveraged") == 2)
        }

        @Test func addsDirectSharesAndFundShares() {
            let result = DepotLookThrough.analyze([
                LookThroughPosition(name: "Apple", isin: "US0378331005", valueCents: 50_000),
                LookThroughPosition(name: "World", isin: "F", valueCents: 50_000, constituents: [
                    FundConstituent(name: "APPLE INC", isin: "US0378331005", weight: 0.2),
                    FundConstituent(name: "MICROSOFT", isin: "US5949181045", weight: 0.8)
                ])
            ], otherTitle: "Sonstige")
            #expect(result.lines.map(\.cents) == [60_000, 40_000])
            #expect(result.lines[0].label == "Apple")
            #expect(abs(result.lines[0].fraction - 0.6) < 0.000001)
        }

        @Test func shareClassesMergeIntoOneCompany() {
            let result = DepotLookThrough.analyze([
                LookThroughPosition(name: "World", isin: "F", valueCents: 100_000, constituents: [
                    FundConstituent(name: "ALPHABET INC CLASS A", isin: "US02079K3059", weight: 0.6),
                    FundConstituent(name: "Alphabet Inc Class C", isin: "US02079K1079", weight: 0.4)
                ])
            ], otherTitle: "Sonstige")
            #expect(result.lines.count == 1)
            #expect(result.lines[0].cents == 100_000)
        }

        @Test func entriesBelowTheLimitBecomeOneOtherLine() {
            let result = DepotLookThrough.analyze([
                LookThroughPosition(name: "World", isin: "F", valueCents: 1_000_000, constituents: [
                    FundConstituent(name: "Gross", isin: "A1", weight: 0.998),
                    FundConstituent(name: "Grenze", isin: "A2", weight: 0.001),
                    FundConstituent(name: "Klein", isin: "A3", weight: 0.0005),
                    FundConstituent(name: "Winzig", isin: "A4", weight: 0.0005)
                ])
            ], otherTitle: "Sonstige")
            #expect(result.lines.map(\.label) == ["Gross", "Grenze", "Sonstige"])
            #expect(result.lines.last?.isOther == true)
            #expect(result.lines.last?.cents == 1_000)
        }

        @Test func leverageCanExceedTheWholeDepot() {
            let result = DepotLookThrough.analyze([
                LookThroughPosition(name: "USA 2x", isin: "F", valueCents: 10_000, constituents: [
                    FundConstituent(name: "Apple", isin: "A1", weight: 1)
                ], leverage: 2)
            ], otherTitle: "Sonstige")
            #expect(result.hasLeverage)
            #expect(abs(result.totalFraction - 2) < 0.000001)
        }

        @Test func aFundWithoutDataStaysVisibleAsOneLine() {
            let result = DepotLookThrough.analyze([
                LookThroughPosition(name: "Small Cap", isin: "F", valueCents: 10_000)
            ], otherTitle: "Sonstige", funds: ["F"])
            #expect(result.lines.map(\.label) == ["Small Cap"])
            #expect(result.uncoveredFunds == ["Small Cap"])
        }

        @Test func aManualImportWinsAndStoredDataAges() async throws {
            try await withTestStore { _ in
                let source = FundSource.xtrackers(isin: "IE00BJ0KDQ92")
                let now = date(2026, 3, 18)
                #expect(FundCompositionStore.needsRefresh(source, now: now))
                FundCompositionStore.store(FundComposition(constituents: [FundConstituent(name: "Geladen", weight: 1)], fetchedAt: now), for: source)
                #expect(!FundCompositionStore.needsRefresh(source, now: days(6, after: now)))
                #expect(FundCompositionStore.needsRefresh(source, now: days(7, after: now)))
                #expect(FundCompositionStore.composition(isin: "IE00B4L5Y983", name: "iShares Core MSCI World")?.constituents.first?.name == "Geladen")
                FundCompositionStore.storeManual(FundComposition(constituents: [FundConstituent(name: "Manuell", weight: 1)], fetchedAt: now, isManual: true), isin: "IE00B4L5Y983")
                #expect(FundCompositionStore.composition(isin: "IE00B4L5Y983", name: "iShares Core MSCI World")?.constituents.first?.name == "Manuell")
                FundCompositionStore.removeManual(isin: "IE00B4L5Y983")
                #expect(FundCompositionStore.composition(isin: "IE00B4L5Y983", name: "iShares Core MSCI World")?.constituents.first?.name == "Geladen")
            }
        }
    }
}
