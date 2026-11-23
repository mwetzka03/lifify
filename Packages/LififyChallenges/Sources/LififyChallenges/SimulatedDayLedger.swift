import Foundation
import LififyCore
import SwiftData

/// One change made while developer mode simulates another day.
public enum SimulatedEffect: Codable, Equatable, Sendable {
    case transaction(UUID)
    case completion(UUID)
    case purchase(id: UUID, rewardID: UUID, rewardWasActive: Bool)
    case milestone(challengeID: UUID, raw: String, noticeID: String)
    case freeze(challengeID: UUID)
    case birthday(previousYear: Int?, notificationID: String)
    case exception(challengeID: UUID, id: UUID)
}

/// Records what a simulated day changes and removes it again on the real day,
/// so testing in developer mode never alters the real wallet.
@MainActor
public enum SimulatedDayLedger {
    /// Whether developer mode currently shows a day other than the real one.
    public static var isActive: Bool {
        AppClock.isDeveloperMode && !Calendar.current.isDate(AppClock.now, inSameDayAs: Date())
    }

    /// Remembers an effect while a day is simulated. Does nothing on the real day.
    public static func record(_ effect: SimulatedEffect) {
        guard isActive, let data = try? JSONEncoder().encode(effect) else { return }
        LinkTable.set(.simulatedEffects, key: UUID().uuidString, value: String(decoding: data, as: UTF8.self))
    }

    /// Inserts a coin booking and marks it when a day is simulated.
    public static func book(_ transaction: CoinTransaction, in context: ModelContext) {
        context.insert(transaction)
        record(.transaction(transaction.id))
    }

    /// Inserts a completion and marks it when a day is simulated.
    public static func insert(_ completion: ChallengeCompletion, in context: ModelContext) {
        context.insert(completion)
        record(.completion(completion.id))
    }

    /// The effects recorded so far.
    public static func effects() -> [SimulatedEffect] {
        LinkTable.map(.simulatedEffects).values.compactMap {
            try? JSONDecoder().decode(SimulatedEffect.self, from: Data($0.utf8))
        }
    }

    /// Removes all recorded effects once the app is back on the real day.
    ///
    /// - Parameter context: The database context holding the recorded rows.
    public static func rollbackIfOnRealDay(context: ModelContext) {
        guard !isActive else { return }
        let recorded = effects()
        guard !recorded.isEmpty else { return }
        let rows = Rows(context: context)
        recorded.forEach { undo($0, rows: rows, context: context) }
        try? context.save()
        LinkTable.replace(.simulatedEffects, with: [:])
    }

    /// The stored rows an undo can touch, read once per rollback.
    private struct Rows {
        let transactions: [CoinTransaction]
        let completions: [ChallengeCompletion]
        let purchases: [RewardPurchase]
        let rewards: [RewardItem]

        /// Reads the rows from the store.
        init(context: ModelContext) {
            transactions = (try? context.fetch(FetchDescriptor<CoinTransaction>())) ?? []
            completions = (try? context.fetch(FetchDescriptor<ChallengeCompletion>())) ?? []
            purchases = (try? context.fetch(FetchDescriptor<RewardPurchase>())) ?? []
            rewards = (try? context.fetch(FetchDescriptor<RewardItem>())) ?? []
        }
    }

    /// Reverses one effect. A row the person already removed is simply skipped.
    private static func undo(_ effect: SimulatedEffect, rows: Rows, context: ModelContext) {
        switch effect {
        case .transaction(let id):
            rows.transactions.first { $0.id == id }.map(context.delete)
        case .completion(let id):
            rows.completions.first { $0.id == id }.map(context.delete)
        case .purchase(let id, let rewardID, let wasActive):
            rows.purchases.first { $0.id == id }.map(context.delete)
            if wasActive { rows.rewards.first { $0.id == rewardID }?.isActive = true }
        case .milestone(let challengeID, let raw, let noticeID):
            undoMilestone(challengeID: challengeID, raw: raw, noticeID: noticeID)
        case .freeze(let challengeID):
            StreakSettings.removePurchasedFreeze(for: challengeID)
        case .birthday(let previousYear, let notificationID):
            UserProfile.restoreAwardedYear(previousYear)
            cancelNotification(notificationID)
        case .exception(let challengeID, let id):
            AbstinenceSettings.removeException(id, for: challengeID)
        }
    }

    /// Makes a bonus payable again and removes its notice.
    private static func undoMilestone(challengeID: UUID, raw: String, noticeID: String) {
        var awarded = AbstinenceSettings.awarded(for: challengeID)
        awarded.remove(raw)
        AbstinenceSettings.setAwarded(awarded, for: challengeID)
        AbstinenceSettings.dismissNotice(noticeID)
        cancelNotification(noticeID)
    }

    /// Cancels a notification announced for a simulated day.
    private static func cancelNotification(_ id: String) {
        Task { await LififyNotifications.cancel(idPrefix: id, keeping: []) }
    }
}
