import XCTest
@testable import Lifify

final class LififyChecksTests: XCTestCase {
    @MainActor
    func testStreak() {
        assertPassed(.streak)
    }

    @MainActor
    func testMultiplier() {
        assertPassed(.multiplier)
    }

    @MainActor
    func testChallenge() {
        assertPassed(.challenge)
    }

    @MainActor
    func testCalendar() {
        assertPassed(.calendar)
    }

    @MainActor
    func testTraining() {
        assertPassed(.training)
    }

    @MainActor
    func testAbstinence() {
        assertPassed(.abstinence)
    }

    @MainActor
    func testDeveloperMode() {
        assertPassed(.developer)
    }

    @MainActor
    func testFinance() {
        assertPassed(.finance)
    }

    @MainActor
    func testScreen() {
        assertPassed(.screen)
    }

    @MainActor
    func testAccount() {
        assertPassed(.account)
    }

    @MainActor
    func testForecast() {
        assertPassed(.forecast)
    }

    @MainActor
    func testBudget() {
        assertPassed(.budget)
    }

    @MainActor
    func testPortfolio() {
        assertPassed(.portfolio)
    }

    @MainActor
    func testBankImport() {
        assertPassed(.bankImport)
    }

    @MainActor
    func testBackup() {
        assertPassed(.backup)
    }

    @MainActor
    func testShop() {
        assertPassed(.shop)
    }

    @MainActor
    func testNavigation() {
        assertPassed(.navigation)
    }

    @MainActor
    func testTopicsCoverChallengesTrainingAndCalendar() {
        let results = LififyChecks.run()
        for topic in [
            LififyCheckTopic.challenge, .calendar, .training, .streak, .multiplier, .abstinence,
            .finance, .screen, .developer, .account, .forecast, .budget, .portfolio,
            .bankImport, .backup, .shop, .navigation
        ] {
            let rows = results.filter { $0.topic == topic }
            XCTAssertTrue(rows.contains { $0.kind == .unit }, "\(topic.rawValue) unit")
            XCTAssertTrue(rows.contains { $0.kind == .integration }, "\(topic.rawValue) integration")
        }
        XCTAssertEqual(Set(results.map(\.topic)), Set(LififyCheckTopic.allCases))
    }

    @MainActor
    private func assertPassed(_ topic: LififyCheckTopic) {
        let failed = LififyChecks.run().filter { $0.topic == topic && !$0.passed }
        XCTAssertTrue(
            failed.isEmpty,
            failed.map { "\($0.name): \($0.detail ?? "")" }.joined(separator: "\n")
        )
    }
}
