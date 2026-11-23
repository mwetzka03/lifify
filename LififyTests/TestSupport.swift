import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
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
    let calendar: RecordingCalendarGateway

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
    LififyAssembly.install()
    let suite = "lifify.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let schema = Schema(LififySchemaV3.models)
    let configuration = ModelConfiguration(suite, schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let files = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    AppDefaults.use(defaults)
    AppFiles.use(files)
    LififyDatabase.container = container
    let calendar = RecordingCalendarGateway()
    CalendarBridge.use(calendar)
    defer {
        CalendarBridge.use(nil)
        LififyDatabase.container = nil
        AppDefaults.use(nil)
        AppFiles.use(nil)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: files)
    }
    return try await body(TestStore(defaults: defaults, container: container, calendar: calendar))
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func days(_ count: Int, after start: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: count, to: start)!
}

enum RuleKind {
    case unit
    case integration
}

enum RuleTopic {
    case streak, multiplier, challenge, calendar, training, abstinence, developer, finance
    case screen, account, forecast, budget, portfolio, bankImport, backup, shop, navigation
}

/// The outcome of one worked example with its measured values.
struct RuleScenario {
    var name: String
    var passed: Bool
    var detail: String?
    var reading: String = ""
    var kind: RuleKind
    var topic: RuleTopic
}

@MainActor
func expectScenario(_ scenario: @MainActor () -> RuleScenario) async throws {
    try await withTestStore { _ in
        let result = scenario()
        #expect(result.passed, "\(result.name): \(result.detail ?? result.reading)")
    }
}
