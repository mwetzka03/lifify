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
        migrateFinanceLinks(context)
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

    private static func migrateFinanceLinks(_ context: ModelContext) {
        let defaults = AppDefaults.store
        let maps: [(FinanceLinkKind, String)] = [
            (.refund, "lifify.refundLinks"),
            (.transferAssignment, "lifify.transferForecastAssignments"),
            (.forecastPeriod, "lifify.forecastPeriodLinks"),
            (.expenseGroup, "lifify.expenseGroupAssignments"),
            (.incomeSecondary, "secondaryIncomeMappings"),
            (.incomeEntry, "incomeEntryAssignments")
        ]
        let sets: [(FinanceLinkKind, String)] = [
            (.forecastSkip, "lifify.forecastSkips"),
            (.matchRejection, "lifify.forecastMatchRejections")
        ]
        let transferKey = "lifify.transferForecasts"
        let templateKey = "lifify.noticeTemplates"
        let budgetKey = "lifify.variableBudgetAccounts"
        let cursorPrefix = "lifify.bankImport.cursor."
        let currentPrefix = "lifify.bankImport.current."
        let primary = ["primaryIncomeIBAN", "primaryIncomeForecastID"]
        move(area: "financeLinks", context: context, oldKeys: {
            maps.map(\.1) + sets.map(\.1) + [transferKey, templateKey, budgetKey] + primary
                + keys(prefix: cursorPrefix) + keys(prefix: currentPrefix)
        }, insert: {
            for (kind, key) in maps {
                guard defaults.object(forKey: key) != nil else { continue }
                guard let values = defaults.dictionary(forKey: key) as? [String: String] else { return false }
                values.forEach { context.insert(StoredFinanceLink(kind: kind, key: $0.key, value: $0.value)) }
            }
            for (kind, key) in sets {
                guard defaults.object(forKey: key) != nil else { continue }
                guard let values = defaults.stringArray(forKey: key) else { return false }
                Set(values).forEach { context.insert(StoredFinanceLink(kind: kind, key: $0, value: "")) }
            }
            if let forecast = defaults.string(forKey: "primaryIncomeForecastID") {
                context.insert(StoredFinanceLink(kind: .incomePrimary, key: "forecastID", value: forecast))
                if let iban = defaults.string(forKey: "primaryIncomeIBAN") {
                    context.insert(StoredFinanceLink(kind: .incomePrimary, key: "iban", value: iban))
                }
            }
            guard let transfers = decoded([TransferForecastRecord].self, key: transferKey, empty: []),
                  let templates = decoded([NoticeTemplate].self, key: templateKey, empty: []),
                  let budgets = decoded([String: [UUID]].self, key: budgetKey, empty: [:])
            else { return false }
            for (position, record) in transfers.enumerated() {
                context.insert(StoredTransferForecast(record, position: position))
            }
            for (position, template) in templates.enumerated() {
                context.insert(StoredNoticeTemplate(payload: try JSONEncoder().encode(template), position: position))
            }
            for (budget, ids) in budgets where !ids.isEmpty {
                context.insert(StoredFinanceLink(kind: .budgetAccounts, key: budget, value: ids.map(\.uuidString).joined(separator: ",")))
            }
            for key in keys(prefix: cursorPrefix) {
                context.insert(StoredFinanceLink(kind: .bankCursor, key: String(key.dropFirst(cursorPrefix.count)), value: String(defaults.double(forKey: key))))
            }
            for key in keys(prefix: currentPrefix) {
                context.insert(StoredFinanceLink(kind: .bankCurrent, key: String(key.dropFirst(currentPrefix.count)), value: String(defaults.integer(forKey: key))))
            }
            return true
        })
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
