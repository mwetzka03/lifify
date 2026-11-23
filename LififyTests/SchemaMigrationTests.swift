import Foundation
import LififyChallenges
import LififyCore
import SwiftData
import Testing
@testable import Lifify

/// Finds the test bundle that carries the stored fixture.
private final class FixtureBundleMarker {}

extension LififyRuleTests {
    /// A real store written by 0.5.5 must open in this version without losing data.
    @Suite("Schema migration")
    @MainActor
    struct SchemaMigrationTests {
        /// The fixed identifiers used when the fixture was written.
        private func id(_ number: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        }

        /// Copies the fixture to where the app keeps its store.
        private func installFixture() throws -> URL {
            let source = try #require(Bundle(for: FixtureBundleMarker.self).url(forResource: "store-0.5.5", withExtension: "store"))
            try FileManager.default.createDirectory(at: AppFiles.supportDirectory, withIntermediateDirectories: true)
            let target = AppFiles.supportDirectory.appendingPathComponent("default.store")
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }

        @Test func storeFromVersion055KeepsAllData() async throws {
            try await withTestStore { _ in
                // The container must outlive its context.
                let container = try StoreRecoveryService.makeContainer(url: installFixture())
                let context = container.mainContext
                try #expect(context.fetch(FetchDescriptor<Account>()).map(\.id) == [id(1)])
                let entry = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first)
                #expect(entry.amountCents == 80_000)
                let holding = try #require(try context.fetch(FetchDescriptor<PortfolioHolding>()).first)
                #expect(holding.quantity == 2.5)
                try #expect(context.fetchCount(FetchDescriptor<ChallengeGroup>()) == 2)
                try #expect(context.fetch(FetchDescriptor<ChallengeCompletion>()).map(\.id) == [id(30)])
                try #expect(context.fetch(FetchDescriptor<CoinTransaction>()).map(\.amount) == [7])
                let event = try #require(try context.fetch(FetchDescriptor<ChallengeCalendarEvent>()).first)
                #expect(event.linkedChallengeID == id(20))
                #expect(event.linkedChallengeGroupID == id(10))
                #expect(event.externalIdentifier == "ios-1")
            }
        }

        @Test func everyGroupMembershipSurvivesTheColumnRemoval() async throws {
            try await withTestStore { _ in
                // The container must outlive its context.
                let container = try StoreRecoveryService.makeContainer(url: installFixture())
                let context = container.mainContext
                let challenges = try context.fetch(FetchDescriptor<ChallengeItem>())
                let groups = Dictionary(uniqueKeysWithValues: challenges.map { ($0.id, $0.groupIDs) })
                #expect(groups[id(20)] == [id(10), id(11)])
                #expect(groups[id(21)] == [id(11)])
                #expect(groups[id(22)] == [])
            }
        }

        @Test func migratedStoreOpensAgain() async throws {
            try await withTestStore { _ in
                let url = try installFixture()
                do {
                    let first = try StoreRecoveryService.makeContainer(url: url)
                    try first.mainContext.save()
                }
                let reopened = try StoreRecoveryService.makeContainer(url: url)
                try #expect(reopened.mainContext.fetchCount(FetchDescriptor<ChallengeItem>()) == 3)
            }
        }
    }
}
