import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Backup completeness")
    @MainActor
    struct BackupCompletenessTests {
        private let cursorKey = "lifify.bankImport.cursor.\(UUID().uuidString)"
        private let currentKey = "lifify.bankImport.current.\(UUID().uuidString)"
        private let offerKey = "lifify.eventOffer.\(UUID().uuidString)"

        private var financeValues: [String] {
            Array(BackupDefaults.financeKeys) + [cursorKey, currentKey]
        }

        private var challengeValues: [String] {
            Array(BackupDefaults.challengeKeys) + [offerKey]
        }

        private func export(_ store: TestStore, scope: BackupScope) throws -> Data {
            try BackupService.exportData(
                accounts: store.all(),
                entries: store.all(),
                splits: store.all(),
                fixedCosts: store.all(),
                variableBudgets: store.all(),
                pools: store.all(),
                forecasts: store.all(),
                shopping: store.all(),
                debts: store.all(),
                groups: store.all(),
                lines: store.all(),
                holdings: store.all(),
                calendarEvents: store.all(),
                challenges: store.all(),
                completions: store.all(),
                challengeGroups: store.all(),
                coinTransactions: store.all(),
                rewards: store.all(),
                purchases: store.all(),
                bucketItems: store.all(),
                scope: scope
            )
        }

        private func seed(_ keys: [String], _ defaults: UserDefaults) {
            for key in keys {
                defaults.set(Data("value of \(key)".utf8), forKey: key)
            }
        }

        private func values(_ keys: [String], _ defaults: UserDefaults) -> [String: Data] {
            Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                defaults.data(forKey: key).map { (key, $0) }
            })
        }

        @Test func entireAppSurvivesResetAndRestore() async throws {
            try await withTestStore { store in
                let keys = financeValues + challengeValues + Array(BackupDefaults.appKeys)
                seed(keys, store.defaults)
                let account = Account(name: "Giro", isMain: true)
                let challenge = ChallengeItem(title: "Lesen", startDate: date(2026, 3, 2))
                store.context.insert(account)
                store.context.insert(challenge)
                store.context.insert(LedgerEntry(date: date(2026, 3, 2), title: "Stand", amountCents: 500, kind: .adjustment, accountID: account.id))
                store.context.insert(CoinTransaction(date: date(2026, 3, 2), title: "Start", amount: 7))
                try store.context.save()
                let before = values(keys, store.defaults)
                #expect(before.count == keys.count)

                let data = try export(store, scope: .all)
                try BackupService.resetApp(from: store.context)
                keys.forEach { store.defaults.removeObject(forKey: $0) }
                try store.context.save()
                try #expect(store.all(Account.self).isEmpty)

                try BackupService.restore(data: data, into: store.context)
                try store.context.save()

                #expect(values(keys, store.defaults) == before)
                try #expect(store.all(Account.self).map(\.id) == [account.id])
                try #expect(store.all(ChallengeItem.self).map(\.id) == [challenge.id])
                try #expect(store.all(LedgerEntry.self).map(\.amountCents) == [500])
                try #expect(store.wallet() == 7)
            }
        }

        @Test func financeBackupCarriesOnlyFinanceValues() async throws {
            try await withTestStore { store in
                seed(financeValues + challengeValues, store.defaults)
                let finance = values(financeValues, store.defaults)
                let data = try export(store, scope: .finance)

                financeValues.forEach { store.defaults.removeObject(forKey: $0) }
                store.defaults.set(Data("newer".utf8), forKey: "lifify.pinnedChallenges")
                try BackupService.restore(data: data, into: store.context)

                #expect(values(financeValues, store.defaults) == finance)
                #expect(store.defaults.data(forKey: "lifify.pinnedChallenges") == Data("newer".utf8))
            }
        }

        @Test func challengeBackupCarriesOnlyChallengeValues() async throws {
            try await withTestStore { store in
                seed(financeValues + challengeValues, store.defaults)
                let challenges = values(challengeValues, store.defaults)
                let data = try export(store, scope: .challenges)

                challengeValues.forEach { store.defaults.removeObject(forKey: $0) }
                store.defaults.set(Data("newer".utf8), forKey: "lifify.forecastSkips")
                try BackupService.restore(data: data, into: store.context)

                #expect(values(challengeValues, store.defaults) == challenges)
                #expect(store.defaults.data(forKey: "lifify.forecastSkips") == Data("newer".utf8))
            }
        }

        @Test func restoreClearsValuesThatWereNotInTheBackup() async throws {
            try await withTestStore { store in
                let data = try export(store, scope: .challenges)
                ChallengePinStore.pin(UUID())
                #expect(!ChallengePinStore.ids().isEmpty)
                try BackupService.restore(data: data, into: store.context)
                #expect(ChallengePinStore.ids().isEmpty)
            }
        }

        @Test func olderBackupLeavesCurrentValuesAlone() async throws {
            try await withTestStore { store in
                let pin = UUID()
                ChallengePinStore.pin(pin)
                let exported = try export(store, scope: .challenges)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let backup = try decoder.decode(LififyBackup.self, from: exported)
                let older = LififyBackup(
                    version: backup.version,
                    exportedAt: backup.exportedAt,
                    records: backup.records.filter { $0.type != BackupDefaults.recordType }
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try BackupService.restore(data: encoder.encode(older), into: store.context)
                #expect(ChallengePinStore.ids() == [pin])
            }
        }

        @Test func cachesAndSecretsStayOut() async throws {
            try await withTestStore { store in
                for key in ["lifify.historicalPrices", "lifify.forecastSkipRevision", "lifify.developerMode", "hasCompletedOnboarding", "gemini.api.key", "lifify.tradeRepublic.sample"] {
                    store.defaults.set("private", forKey: key)
                    #expect(!BackupDefaults.belongs(key, to: .all))
                }
                let record = try #require(BackupDefaults.record(scope: .all))
                #expect(record.strings.isEmpty)
                #expect(BackupDefaults.record(scope: .training) == nil)
            }
        }

        @Test func restoreIgnoresKeysOutsideTheList() async throws {
            try await withTestStore { store in
                let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
                let record = BackupRecord(
                    type: BackupDefaults.recordType,
                    id: UUID(),
                    strings: ["hasCompletedOnboarding", value.base64EncodedString()]
                )
                BackupDefaults.restore(from: [record], scope: .all)
                #expect(store.defaults.object(forKey: "hasCompletedOnboarding") == nil)
            }
        }

        @Test func fastFoodRewardStaysSingleAfterRestore() async throws {
            try await withTestStore { store in
                NutritionLedger.settle(context: store.context, sessions: [])
                let rewardID = try #require(store.all(RewardItem.self).first?.id)
                let data = try export(store, scope: .challenges)
                try BackupService.restore(data: data, into: store.context)
                try store.context.save()
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.all(RewardItem.self).map(\.id) == [rewardID])
            }
        }
    }
}
