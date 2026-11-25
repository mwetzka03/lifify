import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import Testing

extension LififyRuleTests {
    /// The changes from the first test on the iPhone.
    @Suite("Owner feedback 0.6.0")
    struct OwnerFeedbackTests {
        @Test func brokerNamesWithoutProviderStillFindTheirFund() {
            #expect(FundSource.resolve(isin: "IE00BGV5VN51", name: "AI & Big Data USD (Acc)") == .xtrackers(isin: "IE00BGV5VN51"))
            #expect(FundSource.resolve(isin: "IE0002PG6CA6", name: "Rare Earth & Strategic Metals USD (Acc)") == .vanEck(slug: "rare-earth-etf"))
            #expect(FundSource.resolve(isin: "IE000YU9K6K2", name: "Space Innovators USD (Acc)") == .vanEck(slug: "space-etf"))
            #expect(FundSource.resolve(isin: "IE0006WW1TQ4", name: "MSCI World Ex-USA USD (Acc)") == .xtrackers(isin: "IE0006WW1TQ4"))
            #expect(FundSource.resolve(isin: "IE000A9G9R73", name: "Space Technologies USD (Acc)") == .iShares(portfolioID: "351117"))
            #expect(FundSource.resolve(isin: "IE00BF4RFH31", name: "MSCI World Small Cap USD (Acc)") == .iShares(portfolioID: "296576"))
            #expect(FundSource.iShares(portfolioID: "351117").fileExtension == "csv")
            #expect(FundSource.resolve(isin: "FR0010755611", name: "MSCI USA Daily (2x) Leveraged EUR (Acc)") == .xtrackers(isin: "IE00BJ0KDR00"))
            #expect(FundSource.leverage(name: "MSCI USA Daily (2x) Leveraged EUR (Acc)") == 2)
        }

        @Test func thePieCombinesSlicesBelowHalfAPercent() {
            let lines = [
                LookThroughLine(id: "a", label: "A", cents: 900, fraction: 0.9, isOther: false),
                LookThroughLine(id: "b", label: "B", cents: 4, fraction: 0.004, isOther: false),
                LookThroughLine(id: "c", label: "C", cents: 2, fraction: 0.002, isOther: false),
                LookThroughLine(id: "other", label: "Sonstige", cents: 1, fraction: 0.001, isOther: true)
            ]
            let pie = DepotLookThrough.chartLines(lines, otherTitle: "Sonstige")
            #expect(pie.map(\.id) == ["a", "other"])
            #expect(pie.last?.cents == 7)
            #expect(abs((pie.last?.fraction ?? 0) - 0.007) < 0.000_001)
            #expect(DepotLookThrough.chartLines(Array(lines.prefix(1)), otherTitle: "Sonstige").count == 1)
        }

        @MainActor @Test func anISINPlanNameGivesWayToARealName() {
            #expect(SavingsPlanNames.isPlaceholder("IE0007Y8Y157", isin: "IE0007Y8Y157"))
            #expect(SavingsPlanNames.isPlaceholder(" ", isin: "IE0007Y8Y157"))
            #expect(!SavingsPlanNames.isPlaceholder("VanEck Quantum Computing", isin: "IE0007Y8Y157"))
            #expect(SavingsPlanNames.keep("VanEck Quantum Computing", over: "IE0007Y8Y157", isin: "IE0007Y8Y157") == "VanEck Quantum Computing")
            #expect(SavingsPlanNames.keep("IE0007Y8Y157", over: "Quantum", isin: "IE0007Y8Y157") == "Quantum")
        }

        @Test func theCalorieNoteFollowsTheGoal() throws {
            let under = try #require(CalorieNudge.note(goal: .loseFat, target: 2_000, eaten: 1_500))
            #expect(under.body.contains("500"))
            #expect(under.title == L("Bisher gut gemacht", "Well done so far"))
            let over = try #require(CalorieNudge.note(goal: .loseFat, target: 2_000, eaten: 2_300))
            #expect(over.body.contains("300"))
            let gain = try #require(CalorieNudge.note(goal: .gainMuscle, target: 3_000, eaten: 2_200))
            #expect(gain.body.contains("800"))
            let reached = try #require(CalorieNudge.note(goal: .gainMuscle, target: 3_000, eaten: 3_100))
            #expect(reached.title == L("Ziel erreicht", "Goal reached"))
            let empty = try #require(CalorieNudge.note(goal: .loseFat, target: 2_000, eaten: 0))
            #expect(empty.body.contains("2000"))
            #expect(CalorieNudge.note(goal: .maintain, target: 2_000, eaten: 1_950)?.title == L("Im Zielbereich", "In range"))
            #expect(CalorieNudge.note(goal: .maintain, target: nil, eaten: 100) == nil)
        }

        @Test func anOwnEveningTextReplacesTheOpenReminder() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)) ?? .distantFuture
            let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)) ?? .distantFuture
            let item = ChallengeNudgeItem(id: UUID(), title: "Kalorien", clocks: [], eveningTitle: "Bisher gut gemacht", eveningBody: "500 kcal Luft")
            let requests = ChallengeNudgePlan.requests(days: [ChallengeNudgeDay(day: day, items: [item])], now: now, calendar: calendar)
            #expect(requests.count == 1)
            #expect(requests.first?.title == "Bisher gut gemacht")
            #expect(requests.first?.body == "500 kcal Luft")
        }
    }
}

extension LififyRuleTests {
    /// Each lot in a position's details shows its own gain.
    @Suite("Lot gain")
    struct LotGainTests {
        @Test func aBoughtLotGainsAgainstItsCostAndAGiftCountsFully() {
            let bought = HoldingLot(date: .now, quantity: 2, unitPriceCents: 1_000, amountCents: 2_000, isSale: false, isSavingsPlan: false)
            #expect(HoldingLotGain.cents(of: bought, priceCents: 1_100) == 200)
            #expect(HoldingLotGain.cents(of: bought, priceCents: 900) == -200)
            let cashback = HoldingLot(date: .now, quantity: 0.1, unitPriceCents: 15_000, amountCents: 1_500, isSale: false, isSavingsPlan: false, source: "cashback")
            #expect(HoldingLotGain.cents(of: cashback, priceCents: 15_100) == 1_510)
            let sale = HoldingLot(date: .now, quantity: 1, unitPriceCents: 1_000, amountCents: 1_000, isSale: true, isSavingsPlan: false)
            #expect(HoldingLotGain.cents(of: sale, priceCents: 1_100) == nil)
        }
    }
}
