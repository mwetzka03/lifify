import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Persistence")
    @MainActor
    struct PersistenceTests {
        private func storeURL() throws -> URL {
            try FileManager.default.createDirectory(at: AppFiles.supportDirectory, withIntermediateDirectories: true)
            return AppFiles.supportDirectory.appendingPathComponent("default.store")
        }

        private func archives() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: AppFiles.supportDirectory.path)) ?? [])
                .filter { $0.hasPrefix("LififyStoreArchive") }
        }

        private func writeV2Store(at url: URL, accountID: UUID) throws {
            let schema = Schema(LififySchemaV2.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            container.mainContext.insert(Account(id: accountID, name: "Giro", isMain: true))
            container.mainContext.insert(LififySchemaV3.ChallengeItem(title: "Lesen"))
            try container.mainContext.save()
        }

        @Test func storeFromVersionTwoOpensWithItsData() async throws {
            try await withTestStore { _ in
                let url = try storeURL()
                let id = UUID()
                try writeV2Store(at: url, accountID: id)
                let migrated = try StoreRecoveryService.makeContainer(url: url)
                try #expect(migrated.mainContext.fetch(FetchDescriptor<Account>()).map(\.id) == [id])
                try #expect(migrated.mainContext.fetchCount(FetchDescriptor<ChallengeItem>()) == 1)
                migrated.mainContext.insert(DataMigrationRecord(area: "test"))
                try migrated.mainContext.save()
                let reopened = try StoreRecoveryService.makeContainer(url: url)
                try #expect(reopened.mainContext.fetchCount(FetchDescriptor<DataMigrationRecord>()) == 1)
            }
        }

        @Test func finishedAppKeepsItsStoreOnANewGeneration() async throws {
            try await withTestStore { store in
                let url = try storeURL()
                try Data("data".utf8).write(to: url)
                store.defaults.set(true, forKey: "hasCompletedOnboarding")
                StoreRecoveryService.prepareCompatibleStore()
                #expect(FileManager.default.fileExists(atPath: url.path))
                #expect(archives().isEmpty)
                #expect(store.defaults.bool(forKey: "hasCompletedOnboarding"))
            }
        }

        @Test func unfinishedSetupStartsOver() async throws {
            try await withTestStore { store in
                let url = try storeURL()
                try Data("partial".utf8).write(to: url)
                store.defaults.set(true, forKey: "onboardingInProgress")
                StoreRecoveryService.prepareCompatibleStore()
                #expect(!FileManager.default.fileExists(atPath: url.path))
                #expect(archives().count == 1)
                #expect(!store.defaults.bool(forKey: "onboardingInProgress"))
            }
        }

        @Test func brokenStoreOfAFinishedAppIsReportedAndKept() async throws {
            try await withTestStore { store in
                let url = try storeURL()
                let broken = Data(repeating: 7, count: 8_192)
                try broken.write(to: url)
                store.defaults.set(true, forKey: "hasCompletedOnboarding")
                store.defaults.set(3, forKey: "lififyStoreGeneration")
                guard case .failure = StoreRecoveryService.openContainer(url: url) else {
                    Issue.record("A broken store must not open")
                    return
                }
                #expect(try Data(contentsOf: url) == broken)
                #expect(archives().isEmpty)
                #expect(store.defaults.bool(forKey: "hasCompletedOnboarding"))
            }
        }

        @Test func wrongBackupLeavesTheBrokenStoreInPlace() async throws {
            try await withTestStore { store in
                let url = try storeURL()
                let broken = Data(repeating: 7, count: 8_192)
                try broken.write(to: url)
                let partial = try BackupService.exportData(
                    accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .finance
                )
                #expect(throws: StoreRecoveryError.self) {
                    try StoreRecoveryService.recover(from: partial, url: url)
                }
                #expect(try Data(contentsOf: url) == broken)
                #expect(archives().isEmpty)
            }
        }

        @Test func fullBackupRecoversABrokenStoreAndKeepsItInTheArchive() async throws {
            try await withTestStore { store in
                let account = Account(name: "Giro", isMain: true)
                store.context.insert(account)
                try store.context.save()
                let backup = try BackupService.exportData(
                    accounts: store.all(), entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .all
                )
                let url = try storeURL()
                try Data(repeating: 7, count: 8_192).write(to: url)
                let recovered = try StoreRecoveryService.recover(from: backup, url: url)
                try #expect(recovered.mainContext.fetch(FetchDescriptor<Account>()).map(\.id) == [account.id])
                #expect(archives().count == 1)
            }
        }
    }
}
