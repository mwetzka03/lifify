import Foundation
import SwiftData
import Testing
@testable import Lifify

/// Parent of every rule suite. The services keep static caches, so these tests run one at a time.
@Suite("Lifify rules", .serialized)
struct LififyRuleTests {}

/// An in-memory database and a private UserDefaults suite. Nothing reaches real user data.
@MainActor
struct TestStore {
    let defaults: UserDefaults
    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    func all<T: PersistentModel>(_ type: T.Type = T.self) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    func wallet() throws -> Int {
        ChallengeService.walletBalance(transactions: try all(CoinTransaction.self))
    }
}

@MainActor
func withTestStore<T>(_ body: @MainActor (TestStore) async throws -> T) async throws -> T {
    let suite = "lifify.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let schema = Schema(LififySchemaV2.models)
    let configuration = ModelConfiguration(suite, schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    AppDefaults.use(defaults)
    defer {
        AppDefaults.use(nil)
        defaults.removePersistentDomain(forName: suite)
    }
    return try await body(TestStore(defaults: defaults, container: container))
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func days(_ count: Int, after start: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: count, to: start)!
}
