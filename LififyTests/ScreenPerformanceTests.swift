import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Lifify

extension LififyRuleTests {
    /// Measures the first open of the large screens with stress data.
    ///
    /// Skipped in normal test runs. Start it with `TEST_RUNNER_LIFIFY_MEASURE=1` in a
    /// Release build. `TEST_RUNNER_LIFIFY_MEASURE_SCREEN` limits it to one screen and
    /// `TEST_RUNNER_LIFIFY_MEASURE_SAMPLES` sets the opens per screen (default five).
    /// Each result is the median of those opens on freshly seeded data,
    /// with the slowest and fastest open beside it so noise stays visible.
    @Suite("Screen performance", .enabled(if: ProcessInfo.processInfo.environment["LIFIFY_MEASURE"] != nil))
    @MainActor
    struct ScreenPerformanceTests {
        /// The screens covered by the measurement.
        private enum Screen: String, CaseIterable {
            case dashboard, portfolio, transactions, challenges, dataManagement

            /// Builds the screen as the app shows it.
            @MainActor @ViewBuilder
            var view: some View {
                switch self {
                case .dashboard: DashboardView(isMainTab: true, path: nil)
                case .portfolio: PortfolioView()
                case .transactions: TransactionsView()
                case .challenges: ChallengesView()
                case .dataManagement: DataManagementView()
                }
            }
        }

        @Test func firstOpen() async throws {
            let environment = ProcessInfo.processInfo.environment
            let count = environment["LIFIFY_MEASURE_SAMPLES"].flatMap(Int.init) ?? 5
            let only = environment["LIFIFY_MEASURE_SCREEN"]
            for screen in Screen.allCases where only == nil || only == screen.rawValue {
                var samples: [TimeInterval] = []
                for _ in 0..<count {
                    samples.append(try await withTestStore { store in
                        try seed(store)
                        _ = try await lastStall(after: Date())
                        return try await open(screen, store: store)
                    })
                }
                let sorted = samples.sorted().map { Int($0 * 1_000) }
                print("MEASURE \(screen.rawValue) median \(sorted[count / 2]) ms, range \(sorted[0])-\(sorted[count - 1]) ms")
            }
        }

        /// Shows a screen in a real window and waits until the main thread stays free.
        ///
        /// - Parameters:
        ///   - screen: The screen to open.
        ///   - store: The seeded test store.
        /// - Returns: The seconds from opening until the last main-thread stall ended.
        private func open(_ screen: Screen, store: TestStore) async throws -> TimeInterval {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let root = NavigationStack { screen.view }
                .modelContainer(store.container)
                .environmentObject(FinanceFilterStore())
                .environmentObject(WorkoutStore(fileURL: WorkoutStore.defaultFileURL()))
            let start = Date()
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            let finished = try await lastStall(after: start)
            window.isHidden = true
            window.rootViewController = nil
            return finished.timeIntervalSince(start)
        }

        /// Waits for half a second without a stall and returns when the last stall ended.
        private func lastStall(after start: Date) async throws -> Date {
            var last = Date()
            while Date().timeIntervalSince(start) < 180 {
                let before = Date()
                try await Task.sleep(for: .milliseconds(10))
                let now = Date()
                if now.timeIntervalSince(before) > 0.05 {
                    last = now
                } else if now.timeIntervalSince(last) > 0.5 {
                    break
                }
            }
            return last
        }

        /// Seeds 5,000 bookings, 30 holdings, 1,200 lots, 365 prices each, and challenge data.
        private func seed(_ store: TestStore) throws {
            let main = Account(name: "Giro", isMain: true)
            let depot = Account(name: "Depot", kind: .portfolio, isLiquid: false)
            store.context.insert(main)
            store.context.insert(depot)
            seedBookings(store, accountID: main.id)
            seedHoldings(store, accountID: depot.id)
            seedChallenges(store)
            try store.context.save()
        }

        /// Inserts 5,000 bookings spread over the last four years.
        private func seedBookings(_ store: TestStore, accountID: UUID) {
            for index in 0..<5_000 {
                let day = Calendar.current.date(byAdding: .day, value: -(index % 1_460), to: .now)!
                let isIncome = index % 25 == 0
                store.context.insert(LedgerEntry(
                    date: day,
                    title: "Buchung \(index % 80)",
                    amountCents: isIncome ? 250_000 : 1_000 + index % 9_000,
                    kind: isIncome ? .income : .expense,
                    accountID: accountID
                ))
            }
        }

        /// Inserts 30 holdings with 40 lots and 365 daily prices each.
        private func seedHoldings(_ store: TestStore, accountID: UUID) {
            for number in 0..<30 {
                let holding = PortfolioHolding(
                    accountID: accountID, name: "Position \(number)", quantity: 40,
                    purchasePriceCents: 5_000, currentPriceCents: 6_000 + number
                )
                store.context.insert(holding)
                let lots = (0..<40).map { index in
                    HoldingLot(
                        date: Calendar.current.date(byAdding: .day, value: -30 * index, to: .now)!,
                        quantity: 1, unitPriceCents: 5_000, amountCents: 5_000,
                        isSale: false, isSavingsPlan: index % 2 == 0
                    )
                }
                HoldingLotStore.replace(lots, holdingID: holding.id)
                var prices: [String: Int] = [:]
                for offset in 0..<365 {
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
                    prices[day.dayKey] = 5_000 + offset
                }
                HistoricalPriceStore.replace(prices, holdingID: holding.id)
            }
        }

        /// Inserts 100 challenges with completions, coins, and events.
        private func seedChallenges(_ store: TestStore) {
            for number in 0..<100 {
                let challenge = ChallengeItem(
                    title: "Challenge \(number)",
                    recurrence: number % 2 == 0 ? .daily : .none,
                    startDate: Calendar.current.date(byAdding: .day, value: -120, to: .now)
                )
                store.context.insert(challenge)
                for offset in 0..<30 {
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
                    store.context.insert(ChallengeCompletion(challengeID: challenge.id, date: day, earnedCoins: 10))
                    store.context.insert(CoinTransaction(date: day, title: challenge.title, amount: 10))
                }
                let start = Calendar.current.date(byAdding: .hour, value: number, to: .now)!
                store.context.insert(ChallengeCalendarEvent(
                    title: "Termin \(number)", startDate: start, endDate: start.addingTimeInterval(3_600)
                ))
            }
        }
    }
}
