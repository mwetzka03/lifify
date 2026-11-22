import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Backup completeness")
    @MainActor
    struct BackupCompletenessTests {

        private var financeValues: [String] {
            Array(BackupDefaults.financeKeys)
        }

        private var challengeValues: [String] {
            Array(BackupDefaults.challengeKeys)
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
                seed(financeValues, store.defaults)
                let finance = values(financeValues, store.defaults)
                let data = try export(store, scope: .finance)

                financeValues.forEach { store.defaults.removeObject(forKey: $0) }
                let pin = UUID()
                ChallengePinStore.pin(pin)
                try BackupService.restore(data: data, into: store.context)

                #expect(values(financeValues, store.defaults) == finance)
                #expect(ChallengePinStore.ids() == [pin])
            }
        }

        @Test func challengeBackupCarriesOnlyChallengeValues() async throws {
            try await withTestStore { store in
                let pin = UUID(), group = UUID(), challenge = UUID()
                ChallengePinStore.pin(pin)
                ChallengeGroupPinStore.pin(group)
                EventOffer.set(false, for: challenge)
                let data = try export(store, scope: .challenges)

                ChallengePinStore.unpin(pin)
                ChallengeGroupPinStore.unpin(group)
                EventOffer.set(true, for: challenge)
                store.defaults.set(Data("newer".utf8), forKey: TradeFeePreference.storageKey)
                try BackupService.restore(data: data, into: store.context)

                #expect(ChallengePinStore.ids() == [pin])
                #expect(ChallengeGroupPinStore.ids() == [group])
                #expect(!EventOffer.isEnabled(for: challenge))
                #expect(store.defaults.data(forKey: TradeFeePreference.storageKey) == Data("newer".utf8))
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

        private func healthBackup(_ store: TestStore) throws -> Data {
            let snapshot = try WorkoutStore(fileURL: WorkoutStore.defaultFileURL()).exportSnapshotData()
            return try BackupService.exportData(
                accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                scope: .training,
                workoutSnapshot: snapshot
            )
        }

        private func meal(_ title: String, kind: MealKind = .balanced, photo: String? = nil) -> MealRecord {
            MealRecord(dayKey: NutritionPlan.dayKey(.now), title: title, source: .manual, status: .draft, photoName: photo, kind: kind)
        }

        @Test func healthBackupCarriesTrainingAndMealsWithoutPhotos() async throws {
            try await withTestStore { store in
                let workouts = WorkoutStore(fileURL: WorkoutStore.defaultFileURL())
                let plan = WorkoutPlan(name: "Push")
                workouts.save(plan: plan)
                let saved = meal("Reis", photo: "abc.jpg")
                MealLog.upsert(saved)
                let data = try healthBackup(store)
                #expect(BackupService.restoredMessage([.training]).contains(L("Gesundheit", "Health")))
                let text = String(decoding: data, as: UTF8.self)
                #expect(text.contains("mealLog"))
                #expect(!text.contains("mealPhoto"))

                MealLog.reset()
                WorkoutStore.clearStored()
                try BackupService.restore(data: data, into: store.context)

                #expect(MealLog.all().map(\.id) == [saved.id])
                #expect(WorkoutStore(fileURL: WorkoutStore.defaultFileURL()).plans.map(\.id) == [plan.id])
            }
        }

        @Test func trainingFileWithoutMealsLeavesMealsAlone() async throws {
            try await withTestStore { store in
                let data = try healthBackup(store)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let backup = try decoder.decode(LififyBackup.self, from: data)
                let older = LififyBackup(version: backup.version, exportedAt: backup.exportedAt, records: backup.records.filter { $0.type != "mealLog" })
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let kept = meal("Bleibt")
                MealLog.upsert(kept)
                try BackupService.restore(data: encoder.encode(older), into: store.context)
                #expect(MealLog.all().map(\.id) == [kept.id])
            }
        }

        @Test func healthRestoreKeepsTheWalletInStepWithMeals() async throws {
            try await withTestStore { store in
                let data = try healthBackup(store)
                MealLog.upsert(meal("Burger", kind: .fastFood))
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == -MealScore.fastFoodPrice)
                try BackupService.restore(data: data, into: store.context)
                #expect(MealLog.all().isEmpty)
                try #expect(store.wallet() == 0)
            }
        }

        @Test func restoredFastFoodIsChargedOnce() async throws {
            try await withTestStore { store in
                MealLog.upsert(meal("Burger", kind: .fastFood))
                NutritionLedger.settle(context: store.context, sessions: [])
                let data = try healthBackup(store)
                try store.all(RewardPurchase.self).forEach(store.context.delete)
                try store.all(CoinTransaction.self).forEach(store.context.delete)
                try store.context.save()
                try BackupService.restore(data: data, into: store.context)
                try #expect(store.wallet() == -MealScore.fastFoodPrice)
                try #expect(store.all(RewardPurchase.self).count == 1)
            }
        }

        @Test func healthDeleteRemovesMealsPhotosAndCharges() async throws {
            try await withTestStore { store in
                let workouts = WorkoutStore(fileURL: WorkoutStore.defaultFileURL())
                workouts.save(plan: WorkoutPlan(name: "Push"))
                let id = UUID()
                let photo = try #require(MealPhotoStore.save(Data("jpg".utf8), id: id))
                MealLog.upsert(MealRecord(id: id, dayKey: NutritionPlan.dayKey(.now), title: "Burger", source: .photo, status: .draft, photoName: photo, kind: .fastFood))
                store.context.insert(CoinTransaction(title: "Start", amount: 40))
                try store.context.save()
                NutritionLedger.settle(context: store.context, sessions: [])
                try #expect(store.wallet() == 40 - MealScore.fastFoodPrice)

                try BackupService.deleteHealthData(from: store.context)

                #expect(MealLog.all().isEmpty)
                #expect(MealPhotoStore.load(photo) == nil)
                try #expect(store.wallet() == 40)
                try #expect(store.all(RewardPurchase.self).isEmpty)
                #expect(WorkoutStore(fileURL: WorkoutStore.defaultFileURL()).plans.isEmpty)
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
