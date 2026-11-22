import Foundation
import SwiftData

/// Moves data out of UserDefaults once, area by area.
/// The rows and the finished marker are saved together. Old keys go only after that save.
/// A failed or interrupted move leaves the old keys and runs again on the next launch.
@MainActor
enum LegacyDataMigration {
    static func run() {
        guard let context = LififyDatabase.sideContext else { return }
        migrateDepot(context)
        AppDefaults.clearCaches()
    }

    static func isFinished(_ area: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<DataMigrationRecord>(predicate: #Predicate { $0.area == area })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// `insert` returns false when stored data cannot be read. Then nothing changes.
    static func move(
        area: String,
        context: ModelContext,
        oldKeys: () -> [String],
        insert: () throws -> Bool
    ) {
        let defaults = AppDefaults.store
        if isFinished(area, context: context) {
            oldKeys().forEach { defaults.removeObject(forKey: $0) }
            return
        }
        do {
            guard try insert() else {
                context.rollback()
                return
            }
            context.insert(DataMigrationRecord(area: area))
            try context.save()
            oldKeys().forEach { defaults.removeObject(forKey: $0) }
        } catch {
            context.rollback()
        }
    }

    /// Missing data is fine. Data that exists and cannot be decoded stops the move.
    static func decoded<T: Decodable>(_ type: T.Type, key: String, empty: T) -> T? {
        guard let data = AppDefaults.store.data(forKey: key) else {
            return AppDefaults.store.object(forKey: key) == nil ? empty : nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func keys(prefix: String) -> [String] {
        AppDefaults.store.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
    }

    private static func migrateDepot(_ context: ModelContext) {
        let lotKey = "lifify.holdingLots"
        let planKey = "lifify.savingsPlans"
        let closedKey = "lifify.closedPositions"
        let symbolPrefix = "market.symbol."
        let closePrefix = "market.previous."
        let datePrefix = "holding.purchased."
        let linkPrefix = "lifify.portfolioLink."
        move(area: "depot", context: context, oldKeys: {
            [lotKey, planKey, closedKey]
                + keys(prefix: symbolPrefix) + keys(prefix: closePrefix) + keys(prefix: datePrefix) + keys(prefix: linkPrefix)
        }, insert: {
            guard let lots = decoded([String: [HoldingLot]].self, key: lotKey, empty: [:]),
                  let plans = decoded([SavingsPlanRecord].self, key: planKey, empty: []),
                  let closed = decoded([ClosedPositionRecord].self, key: closedKey, empty: [])
            else { return false }
            for (rawID, rows) in lots {
                guard let holdingID = UUID(uuidString: rawID) else { return false }
                for (position, lot) in rows.enumerated() {
                    context.insert(StoredHoldingLot(lot, holdingID: holdingID, position: position))
                }
            }
            for (position, plan) in plans.enumerated() {
                context.insert(StoredSavingsPlan(plan, position: position))
            }
            for (position, record) in closed.enumerated() {
                context.insert(StoredClosedPosition(record, position: position))
            }
            let defaults = AppDefaults.store
            var market: [UUID: StoredHoldingMarket] = [:]
            func row(_ key: String, _ prefix: String) -> StoredHoldingMarket? {
                guard let id = UUID(uuidString: String(key.dropFirst(prefix.count))) else { return nil }
                if let existing = market[id] { return existing }
                let created = StoredHoldingMarket(holdingID: id)
                market[id] = created
                context.insert(created)
                return created
            }
            for key in keys(prefix: symbolPrefix) { row(key, symbolPrefix)?.symbol = defaults.string(forKey: key) }
            for key in keys(prefix: closePrefix) { row(key, closePrefix)?.previousCloseCents = defaults.integer(forKey: key) }
            for key in keys(prefix: datePrefix) { row(key, datePrefix)?.purchaseDate = defaults.object(forKey: key) as? Date }
            for key in keys(prefix: linkPrefix) {
                guard let checkingID = UUID(uuidString: String(key.dropFirst(linkPrefix.count))),
                      let portfolioID = defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
                else { continue }
                context.insert(StoredPortfolioLink(checkingID: checkingID, portfolioID: portfolioID))
            }
            return true
        })
    }
}
