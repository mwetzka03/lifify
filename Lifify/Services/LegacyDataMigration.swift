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
        migrateChallenges(context)
        normalizeGroupMembership(context)
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

    /// Older records may hold only the single group. Afterward `groupIDsRaw` is the one source.
    private static func normalizeGroupMembership(_ context: ModelContext) {
        move(area: "challengeGroups", context: context, oldKeys: { [] }, insert: {
            for challenge in try context.fetch(FetchDescriptor<ChallengeItem>()) {
                let ids = challenge.groupIDs
                if challenge.groupIDsRaw != ChallengeGroups.stored(ids) || challenge.groupID != ids.first {
                    challenge.groupIDs = ids
                }
            }
            return true
        })
    }

    private static func insertMap<T: Codable>(_ type: T.Type, kind: LinkKind, key: String, context: ModelContext) -> Bool {
        guard let values = decoded([String: T].self, key: key, empty: [:]) else { return false }
        for (entry, raw) in LinkTable.encoded(values) {
            context.insert(StoredLink(kind: kind, key: entry, value: raw))
        }
        return true
    }

    private static func insertList<T: Codable>(_ type: T.Type, kind: LinkKind, key: String, context: ModelContext) -> Bool {
        guard let values = decoded([T].self, key: key, empty: []) else { return false }
        if !values.isEmpty {
            for (entry, raw) in LinkTable.encoded(["all": values]) {
                context.insert(StoredLink(kind: kind, key: entry, value: raw))
            }
        }
        return true
    }

    private static func migrateChallenges(_ context: ModelContext) {
        let defaults = AppDefaults.store
        let stateKey = "lifify.streakStates"
        let durationKey = "lifify.challengeDuration"
        let actualKey = "lifify.challengeActualMinutes"
        let memberKey = "lifify.challengeTimeMembers"
        let plannedKey = "lifify.challengeTimePlanned"
        let difficultyKey = "lifify.abstinenceDifficulty"
        let awardedKey = "lifify.abstinenceAwarded"
        let relapseKey = "lifify.abstinenceRelapses"
        let noticeKey = "lifify.abstinenceNotices"
        let exceptionKey = "lifify.abstinenceExceptions"
        let rewardLinkKey = "lifify.abstinenceRewardLinks"
        let categoryKey = "lifify.customCategories"
        let pinKey = "lifify.pinnedChallenges"
        let groupPinKey = "lifify.pinnedChallengeGroups"
        let workoutChallengeKey = "lifify.workoutChallengeLinks"
        let workoutEventKey = "lifify.workoutEventLinks"
        let mealKey = "lifify.meals"
        let fastFoodKey = "lifify.fastFoodReward"
        let flags: [(LinkKind, String)] = [
            (.rewardPolicy, "reward.multiple."),
            (.reminderSync, "challenge.syncReminders."),
            (.eventOffer, "lifify.eventOffer.")
        ]
        let metadata: [(LinkKind, String)] = [
            (.reminderRecurrence, "reminder.recurrence."),
            (.eventRecurrence, "event.recurrence.")
        ]
        let iconPrefix = "icon."
        move(area: "challenges", context: context, oldKeys: {
            [stateKey, durationKey, actualKey, memberKey, plannedKey, difficultyKey, awardedKey, relapseKey, noticeKey,
             exceptionKey, rewardLinkKey, categoryKey, pinKey, groupPinKey, workoutChallengeKey, workoutEventKey, mealKey, fastFoodKey]
                + flags.flatMap { keys(prefix: $0.1) } + metadata.flatMap { keys(prefix: $0.1) } + keys(prefix: iconPrefix)
        }, insert: {
            guard let states = decoded([String: StreakSettings.State].self, key: stateKey, empty: [:]),
                  let challengeLinks = decoded([WorkoutChallengeLink].self, key: workoutChallengeKey, empty: []),
                  let eventLinks = decoded([WorkoutEventLink].self, key: workoutEventKey, empty: []),
                  let meals = decoded([MealRecord].self, key: mealKey, empty: []),
                  insertMap(Int.self, kind: .challengeDuration, key: durationKey, context: context),
                  insertMap(Int.self, kind: .challengeActual, key: actualKey, context: context),
                  insertMap([String].self, kind: .challengeMembers, key: memberKey, context: context),
                  insertMap(Int.self, kind: .challengePlanned, key: plannedKey, context: context),
                  insertMap([String].self, kind: .abstinenceAwarded, key: awardedKey, context: context),
                  insertMap([AbstinenceRelapse].self, kind: .abstinenceRelapses, key: relapseKey, context: context),
                  insertMap([AbstinenceException].self, kind: .abstinenceExceptions, key: exceptionKey, context: context),
                  insertList(AbstinenceNotice.self, kind: .abstinenceNotices, key: noticeKey, context: context),
                  insertList(CustomChallengeCategory.self, kind: .customCategories, key: categoryKey, context: context),
                  let difficulties = decoded([String: String].self, key: difficultyKey, empty: [:]),
                  let rewardLinks = decoded([String: String].self, key: rewardLinkKey, empty: [:])
            else { return false }
            for (key, state) in states {
                guard let id = UUID(uuidString: key) else { return false }
                context.insert(StoredStreakState(challengeID: id, state: state))
            }
            difficulties.forEach { context.insert(StoredLink(kind: .abstinenceDifficulty, key: $0.key, value: $0.value)) }
            rewardLinks.forEach { context.insert(StoredLink(kind: .abstinenceRewardLink, key: $0.key, value: $0.value)) }
            for (position, link) in challengeLinks.enumerated() {
                context.insert(StoredWorkoutLink(planID: link.planID, targetID: link.challengeID, isEvent: false, managed: false, position: position))
            }
            for (offset, link) in eventLinks.enumerated() {
                context.insert(StoredWorkoutLink(planID: link.planID, targetID: link.eventID, isEvent: true, managed: link.managed, position: challengeLinks.count + offset))
            }
            var uniqueMeals: [UUID: MealRecord] = [:]
            meals.forEach { uniqueMeals[$0.id] = $0 }
            uniqueMeals.values.forEach { context.insert(StoredMeal($0)) }
            for (kind, key) in [(LinkKind.pinnedChallenges, pinKey), (.pinnedGroups, groupPinKey)] {
                if let ids = defaults.stringArray(forKey: key), !ids.isEmpty {
                    context.insert(StoredLink(kind: kind, key: "all", value: ids.joined(separator: ",")))
                }
            }
            if let reward = defaults.string(forKey: fastFoodKey) {
                context.insert(StoredLink(kind: .fastFoodReward, key: "id", value: reward))
            }
            for (kind, prefix) in flags {
                for key in keys(prefix: prefix) {
                    context.insert(StoredLink(kind: kind, key: String(key.dropFirst(prefix.count)), value: defaults.bool(forKey: key) ? "true" : "false"))
                }
            }
            for (kind, prefix) in metadata {
                for key in keys(prefix: prefix) {
                    guard let data = defaults.data(forKey: key) else { return false }
                    context.insert(StoredLink(kind: kind, key: String(key.dropFirst(prefix.count)), value: String(decoding: data, as: UTF8.self)))
                }
            }
            for key in keys(prefix: iconPrefix) {
                guard let icon = defaults.string(forKey: key) else { continue }
                context.insert(StoredLink(kind: .icon, key: String(key.dropFirst(iconPrefix.count)), value: icon))
            }
            return true
        })
    }

    private static func migrateFinanceLinks(_ context: ModelContext) {
        let defaults = AppDefaults.store
        let maps: [(LinkKind, String)] = [
            (.refund, "lifify.refundLinks"),
            (.transferAssignment, "lifify.transferForecastAssignments"),
            (.forecastPeriod, "lifify.forecastPeriodLinks"),
            (.expenseGroup, "lifify.expenseGroupAssignments"),
            (.incomeSecondary, "secondaryIncomeMappings"),
            (.incomeEntry, "incomeEntryAssignments")
        ]
        let sets: [(LinkKind, String)] = [
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
                values.forEach { context.insert(StoredLink(kind: kind, key: $0.key, value: $0.value)) }
            }
            for (kind, key) in sets {
                guard defaults.object(forKey: key) != nil else { continue }
                guard let values = defaults.stringArray(forKey: key) else { return false }
                Set(values).forEach { context.insert(StoredLink(kind: kind, key: $0, value: "")) }
            }
            if let forecast = defaults.string(forKey: "primaryIncomeForecastID") {
                context.insert(StoredLink(kind: .incomePrimary, key: "forecastID", value: forecast))
                if let iban = defaults.string(forKey: "primaryIncomeIBAN") {
                    context.insert(StoredLink(kind: .incomePrimary, key: "iban", value: iban))
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
                context.insert(StoredLink(kind: .budgetAccounts, key: budget, value: ids.map(\.uuidString).joined(separator: ",")))
            }
            for key in keys(prefix: cursorPrefix) {
                context.insert(StoredLink(kind: .bankCursor, key: String(key.dropFirst(cursorPrefix.count)), value: String(defaults.double(forKey: key))))
            }
            for key in keys(prefix: currentPrefix) {
                context.insert(StoredLink(kind: .bankCurrent, key: String(key.dropFirst(currentPrefix.count)), value: String(defaults.integer(forKey: key))))
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
