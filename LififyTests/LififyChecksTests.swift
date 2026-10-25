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
    func testDeveloperMode() {
        assertPassed(.developer)
    }

    @MainActor
    func testTopicsCoverChallengesTrainingAndCalendar() {
        let results = LififyChecks.run()
        for topic in [LififyCheckTopic.challenge, .calendar, .training, .streak, .multiplier] {
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
