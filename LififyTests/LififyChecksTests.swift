import XCTest
@testable import Lifify

final class LififyChecksTests: XCTestCase {
    @MainActor
    func testStreakAndLinkSuite() {
        let failed = LififyChecks.run().filter { !$0.passed }
        XCTAssertTrue(
            failed.isEmpty,
            failed.map { "\($0.name): \($0.detail ?? "")" }.joined(separator: "\n")
        )
    }
}
