import Foundation
import LififyCore
import SwiftData

public struct SaleEconomics: Equatable {
    public var quantity: Double
    public var costCents: Int
    public var proceedsCents: Int
    public var differenceCents: Int

    public init(quantity: Double, costCents: Int, proceedsCents: Int, differenceCents: Int) {
        self.quantity = quantity
        self.costCents = costCents
        self.proceedsCents = proceedsCents
        self.differenceCents = differenceCents
    }
}

public struct HoldingLot: Codable, Identifiable, Hashable {
    public var id: UUID
    public var date: Date
    public var quantity: Double
    public var unitPriceCents: Int
    public var amountCents: Int
    public var isSale: Bool
    public var isSavingsPlan: Bool
    public var ledgerEntryID: UUID?
    /// cashback, gift, or opening. Empty means a normal purchase.
    public var source: String = ""

    public init(
        id: UUID = UUID(),
        date: Date,
        quantity: Double,
        unitPriceCents: Int,
        amountCents: Int,
        isSale: Bool,
        isSavingsPlan: Bool,
        ledgerEntryID: UUID? = nil,
        source: String = ""
    ) {
        self.id = id
        self.date = date
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.amountCents = amountCents
        self.isSale = isSale
        self.isSavingsPlan = isSavingsPlan
        self.ledgerEntryID = ledgerEntryID
        self.source = source
    }

    public enum CodingKeys: String, CodingKey {
        case id, date, quantity, unitPriceCents, amountCents, isSale, isSavingsPlan, ledgerEntryID, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        quantity = try container.decode(Double.self, forKey: .quantity)
        unitPriceCents = try container.decode(Int.self, forKey: .unitPriceCents)
        amountCents = try container.decode(Int.self, forKey: .amountCents)
        isSale = try container.decode(Bool.self, forKey: .isSale)
        isSavingsPlan = try container.decode(Bool.self, forKey: .isSavingsPlan)
        ledgerEntryID = try container.decodeIfPresent(UUID.self, forKey: .ledgerEntryID)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unitPriceCents, forKey: .unitPriceCents)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(isSale, forKey: .isSale)
        try container.encode(isSavingsPlan, forKey: .isSavingsPlan)
        try container.encodeIfPresent(ledgerEntryID, forKey: .ledgerEntryID)
        if !source.isEmpty { try container.encode(source, forKey: .source) }
    }
}

@MainActor
public enum HoldingLotStore {
    private static var cached: [String: [HoldingLot]]?
    public private(set) static var cacheRevision = 0

    public static func clearCache() {
        cached = nil
        cacheRevision &+= 1
    }

    public static func lots(for holdingID: UUID) -> [HoldingLot] {
        snapshot()[holdingID.uuidString] ?? []
    }

    public static func allByHolding() -> [UUID: [HoldingLot]] {
        Dictionary(uniqueKeysWithValues: snapshot().compactMap { key, lots in
            UUID(uuidString: key).map { ($0, lots) }
        })
    }

    public static func add(_ lot: HoldingLot, holdingID: UUID) {
        replace(lots(for: holdingID) + [lot], holdingID: holdingID)
    }

    public static func replace(_ lots: [HoldingLot], holdingID: UUID) {
        var map = snapshot()
        if lots.isEmpty {
            map.removeValue(forKey: holdingID.uuidString)
        } else {
            map[holdingID.uuidString] = lots
        }
        if let context = LififyDatabase.sideContext {
            let descriptor = FetchDescriptor<StoredHoldingLot>(predicate: #Predicate { $0.holdingID == holdingID })
            ((try? context.fetch(descriptor)) ?? []).forEach(context.delete)
            for (position, lot) in lots.enumerated() {
                context.insert(StoredHoldingLot(lot, holdingID: holdingID, position: position))
            }
            LififyDatabase.saveSide()
        }
        cached = map
        cacheRevision += 1
    }

    public static func remove(lotID: UUID, holdingID: UUID) {
        var rows = lots(for: holdingID)
        rows.removeAll { $0.id == lotID }
        replace(rows, holdingID: holdingID)
    }

    public static func removeAll(for holdingID: UUID) {
        replace([], holdingID: holdingID)
    }

    public static func reset() {
        LififyDatabase.deleteAll(StoredHoldingLot.self)
        cached = [:]
        cacheRevision += 1
    }

    private static func snapshot() -> [String: [HoldingLot]] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredHoldingLot>(sortBy: [SortDescriptor(\.position)]))
        let decoded = Dictionary(grouping: rows, by: \.holdingID.uuidString).mapValues { $0.map(\.lot) }
        cached = decoded
        return decoded
    }
}

public struct SavingsPlanRecord: Codable, Identifiable, Hashable {
    public var id: UUID
    public var isin: String
    public var name: String
    public var amountCents: Int
    public var cadenceRaw: String
    public var checkingAccountID: UUID
    public var portfolioAccountID: UUID
    public var holdingID: UUID?
    public var lastExecution: Date
    public var historyThrough: Date
    public var active: Bool
    public var fixedCostID: UUID? = nil

    public var cadence: Cadence { Cadence(rawValue: cadenceRaw) ?? .monthly }

    public var monthlyCostCents: Int {
        switch cadence {
        case .weekly: return amountCents * 4
        case .biweekly: return amountCents * 2
        case .monthly: return amountCents
        case .yearly: return Int((Double(amountCents) / 12).rounded())
        }
    }

    @MainActor
    public func nextExecution(after date: Date = .now) -> Date? {
        guard active else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastExecution)) ?? today
        let start = max(today, afterLast)
        let month = cadence == .yearly ? calendar.component(.month, from: lastExecution) : nil
        return CalendarService.nextSavingsPlanDate(cadence: cadence, onOrAfter: start, yearlyMonth: month)
    }

    public init(id: UUID, isin: String, name: String, amountCents: Int, cadenceRaw: String, checkingAccountID: UUID, portfolioAccountID: UUID, holdingID: UUID? = nil, lastExecution: Date, historyThrough: Date, active: Bool, fixedCostID: UUID? = nil) {
        self.id = id
        self.isin = isin
        self.name = name
        self.amountCents = amountCents
        self.cadenceRaw = cadenceRaw
        self.checkingAccountID = checkingAccountID
        self.portfolioAccountID = portfolioAccountID
        self.holdingID = holdingID
        self.lastExecution = lastExecution
        self.historyThrough = historyThrough
        self.active = active
        self.fixedCostID = fixedCostID
    }
}

@MainActor
public enum SavingsPlanStore {
    private static var cached: [SavingsPlanRecord]?
    public private(set) static var cacheRevision = 0

    public static func clearCache() {
        cached = nil
        cacheRevision &+= 1
    }

    public static func all() -> [SavingsPlanRecord] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredSavingsPlan>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.map(\.plan)
        cached = decoded
        return decoded
    }

    public static func replace(_ plans: [SavingsPlanRecord], portfolioID: UUID) {
        var kept = all().filter { $0.portfolioAccountID != portfolioID }
        kept.append(contentsOf: plans)
        save(kept)
    }

    public static func removeAll(portfolioID: UUID) {
        save(all().filter { $0.portfolioAccountID != portfolioID })
    }

    public static func upsert(_ plan: SavingsPlanRecord) {
        var plans = all()
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        save(plans)
    }

    public static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    public static func reset() {
        LififyDatabase.deleteAll(StoredSavingsPlan.self)
        cached = []
        cacheRevision += 1
    }

    public static func save(_ plans: [SavingsPlanRecord]) {
        guard plans != all() else { return }
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredSavingsPlan>())) ?? []).forEach(context.delete)
            for (position, plan) in plans.enumerated() {
                context.insert(StoredSavingsPlan(plan, position: position))
            }
            LififyDatabase.saveSide()
        }
        cached = plans
        cacheRevision += 1
    }
}

@MainActor
public enum HoldingMaintenance {
    /// Einstand is the cash paid divided by the shares still held, rounded once.
    public static func averagePurchaseCents(for lots: [HoldingLot]) -> (quantity: Double, priceCents: Int)? {
        let ordered = lots.sorted { $0.date < $1.date }
        var quantity = 0.0
        var cost = 0.0
        for lot in ordered {
            if lot.isSale {
                guard quantity > 0.0000005 else { continue }
                let sold = min(lot.quantity, quantity)
                cost *= (quantity - sold) / quantity
                quantity -= sold
            } else {
                quantity += lot.quantity
                if lot.source == "gift" || lot.source == "cashback" { continue }
                let cash = abs(lot.amountCents)
                cost += cash > 0 ? Double(cash) : lot.quantity * Double(lot.unitPriceCents)
            }
        }
        guard quantity > 0.0000005 else { return nil }
        return (quantity, max(0, Int((cost / quantity).rounded())))
    }

    /// Rebuilds the holding from its lots. A position that was fully sold, or whose lots were all removed, disappears.
    @discardableResult
    public static func sync(_ holding: PortfolioHolding, context: ModelContext) -> Bool {
        let lots = HoldingLotStore.lots(for: holding.id)
        guard let position = averagePurchaseCents(for: lots) else {
            retire(holding, context: context)
            try? context.save()
            return false
        }
        holding.quantity = position.quantity
        holding.purchasePriceCents = position.priceCents
        holding.updatedAt = .now
        if let first = lots.first(where: { !$0.isSale }) {
            HoldingPurchaseDateStore.set(first.date, for: holding.id)
        }
        try? context.save()
        return true
    }

    public static func ledgerEntry(for lot: HoldingLot, holding: PortfolioHolding, context: ModelContext) -> LedgerEntry? {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        if let id = lot.ledgerEntryID, let entry = entries.first(where: { $0.id == id }) {
            return entry
        }
        let symbol = holding.symbol.uppercased()
        let calendar = Calendar.current
        return entries.first { entry in
            calendar.isDate(entry.date, inSameDayAs: lot.date)
                && abs(entry.amountCents) == abs(lot.amountCents)
                && (symbol.isEmpty
                    || entry.notes.uppercased().contains(symbol)
                    || entry.title.localizedCaseInsensitiveContains(holding.name))
        }
    }

    public static func updateLedger(previous: HoldingLot, updated: HoldingLot, holding: PortfolioHolding, context: ModelContext) {
        guard let entry = ledgerEntry(for: previous, holding: holding, context: context) else { return }
        let portfolioID = holding.accountID
        let other: UUID?
        if entry.fromAccountID == portfolioID {
            other = entry.toAccountID
        } else if entry.toAccountID == portfolioID {
            other = entry.fromAccountID
        } else {
            other = entry.accountID ?? entry.fromAccountID ?? entry.toAccountID
        }
        entry.date = updated.date
        entry.amountCents = abs(updated.amountCents)
        entry.kind = .transfer
        entry.accountID = nil
        if updated.isSale {
            entry.fromAccountID = portfolioID
            entry.toAccountID = other
            entry.title = "\(L("Verkauf", "Sale")): \(holding.name)"
        } else if updated.isSavingsPlan {
            entry.fromAccountID = other
            entry.toAccountID = portfolioID
            entry.title = "\(L("Sparplan", "Savings plan")): \(holding.name)"
        } else {
            entry.fromAccountID = other
            entry.toAccountID = portfolioID
            entry.title = "\(L("Kauf", "Purchase")): \(holding.name)"
        }
        var stored = updated
        stored.ledgerEntryID = entry.id
        var lots = HoldingLotStore.lots(for: holding.id)
        if let index = lots.firstIndex(where: { $0.id == updated.id }) {
            lots[index] = stored
            HoldingLotStore.replace(lots, holdingID: holding.id)
        }
    }

    /// Removes a closed position from the depot and keeps its lots for the sale result.
    public static func retire(_ holding: PortfolioHolding, context: ModelContext) {
        let lots = HoldingLotStore.lots(for: holding.id)
        if !lots.isEmpty {
            ClosedPositionStore.archive(isin: holding.symbol, name: holding.name, lots: lots)
        }
        HoldingLotStore.removeAll(for: holding.id)
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HistoricalPriceStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
        context.delete(holding)
    }

    /// Market value of the shares held at the end of `day`. Future savings plans
    /// increase the share count at the current price. Plans without a priced holding
    /// still add their nominal euro amount.
    public static func marketValue(of holdings: [PortfolioHolding], through day: Date) -> Int {
        let held = holdings.reduce(0) { total, holding in
            total + valued(quantity(of: holding, through: day, holdings: holdings), of: holding, pricedOn: day)
        }
        return held + futureShares(through: day, holdings: holdings).unmatchedCents
    }

    public static func quantity(of holding: PortfolioHolding, through day: Date, holdings: [PortfolioHolding]) -> Double {
        let dayKey = Calendar.current.startOfDay(for: day).dayKey
        var stamp = holdings.count
        for item in holdings {
            stamp = stamp &* 31 &+ item.currentPriceCents
            stamp = stamp &* 31 &+ item.id.hashValue
        }
        let key = QuantityMemoKey(
            dayKey: dayKey,
            lotRevision: HoldingLotStore.cacheRevision,
            planRevision: SavingsPlanStore.cacheRevision,
            holdingStamp: stamp
        )
        if quantityMemoKey != key {
            quantityMemoKey = key
            quantityMemo = [:]
        }
        if let cached = quantityMemo[holding.id] { return cached }
        let value = heldQuantity(of: holding, before: dayCutoff(day))
            + (futureShares(through: day, holdings: holdings).quantity[holding.id] ?? 0)
        quantityMemo[holding.id] = value
        return value
    }

    public static func marketValue(of holding: PortfolioHolding, through day: Date, holdings: [PortfolioHolding]) -> Int {
        valued(quantity(of: holding, through: day, holdings: holdings), of: holding, pricedOn: day)
    }

    /// Cost, proceeds and difference of one sale. Fees stay inside the cash amounts.
    public static func saleEconomics(for entry: LedgerEntry, holdings: [PortfolioHolding]) -> SaleEconomics? {
        let groups = holdings.map { HoldingLotStore.lots(for: $0.id) } + ClosedPositionStore.all().map(\.lots)
        if let matched = groups.compactMap({ economics(in: $0, entry: entry, requireLedgerID: true) }).first {
            return matched
        }
        return groups.compactMap { economics(in: $0, entry: entry, requireLedgerID: false) }.first
    }

    /// Sale proceeds minus the average cost of the shares sold, after fees.
    public static func realizedGainCents(for entry: LedgerEntry, holdings: [PortfolioHolding]) -> Int? {
        saleEconomics(for: entry, holdings: holdings)?.differenceCents
    }

    private static func dayCutoff(_ day: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) ?? day
    }

    private static func heldQuantity(of holding: PortfolioHolding, before cutoff: Date) -> Double {
        let stored = HoldingLotStore.lots(for: holding.id)
        let lots = stored.filter { $0.date < cutoff }.sorted { $0.date < $1.date }
        if stored.isEmpty {
            let purchased = HoldingPurchaseDateStore.date(for: holding.id) ?? .distantPast
            return purchased < cutoff ? max(holding.quantity, 0) : 0
        }
        var held = 0.0
        for lot in lots {
            if lot.isSale {
                held -= lot.quantity
            } else {
                held += lot.quantity
            }
        }
        return max(0, held)
    }

    private static func valued(_ quantity: Double, of holding: PortfolioHolding, pricedOn day: Date) -> Int {
        guard quantity > 0.0000005 else { return 0 }
        return Int((quantity * Double(priceCents(for: holding, on: day))).rounded())
    }

    /// Historical close for that day when one is stored. Otherwise the current price.
    /// Future days always use the current price. Upcoming savings change the share count.
    private static func priceCents(for holding: PortfolioHolding, on day: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: .now)
        if dayStart > today {
            return max(holding.currentPriceCents, 0)
        }
        let key = dayStart.dayKey
        if let exact = HistoricalPriceStore.cents(for: holding.id, dayKey: key) {
            return exact
        }
        if let prior = HistoricalPriceStore.nearestCents(for: holding.id, onOrBefore: key) {
            return prior
        }
        return max(holding.currentPriceCents, 0)
    }

    private struct FutureShares {
        var quantity: [UUID: Double] = [:]
        var unmatchedCents = 0
    }

    private struct QuantityMemoKey: Equatable {
        var dayKey: String
        var lotRevision: Int
        var planRevision: Int
        var holdingStamp: Int
    }

    private static var quantityMemoKey: QuantityMemoKey?
    private static var quantityMemo: [UUID: Double] = [:]

    private struct ShareCacheKey: Equatable {
        var dayKey: String
        var planRevision: Int
        var holdingStamp: Int
    }

    private static var shareCacheKey: ShareCacheKey?
    private static var shareCache = FutureShares()

    public static func clearCache() {
        quantityMemoKey = nil
        quantityMemo = [:]
        shareCacheKey = nil
        shareCache = FutureShares()
    }

    /// Each future execution buys `amount / current price` shares. The euro value of those
    /// shares is the nominal plan amount, so it is not added a second time.
    private static func futureShares(through day: Date, holdings: [PortfolioHolding]) -> FutureShares {
        let dayKey = Calendar.current.startOfDay(for: day).dayKey
        var hasher = Hasher()
        for holding in holdings.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(holding.id)
            hasher.combine(holding.accountID)
            hasher.combine(holding.symbol)
            hasher.combine(holding.currentPriceCents)
        }
        let key = ShareCacheKey(
            dayKey: dayKey,
            planRevision: SavingsPlanStore.cacheRevision,
            holdingStamp: hasher.finalize()
        )
        if shareCacheKey == key { return shareCache }
        var result = FutureShares()
        let ordered = holdings.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var claimed = Set<UUID>()
        for plan in SavingsPlanStore.all() where plan.active {
            let executions = futureExecutionCount(plan, through: day)
            guard executions > 0 else { continue }
            guard let target = ordered.first(where: { matches($0, plan: plan) && $0.currentPriceCents > 0 }) else {
                result.unmatchedCents += executions * abs(plan.amountCents)
                continue
            }
            guard claimed.insert(plan.id).inserted else { continue }
            let shares = Double(executions) * Double(abs(plan.amountCents)) / Double(target.currentPriceCents)
            result.quantity[target.id, default: 0] += shares
        }
        shareCacheKey = key
        shareCache = result
        return result
    }

    private static func matches(_ holding: PortfolioHolding, plan: SavingsPlanRecord) -> Bool {
        if let holdingID = plan.holdingID { return holding.id == holdingID }
        return holding.accountID == plan.portfolioAccountID
            && holding.symbol.caseInsensitiveCompare(plan.isin) == .orderedSame
    }

    /// Executions after today and after the last booked execution, through `day`.
    private static func futureExecutionCount(_ plan: SavingsPlanRecord, through day: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let target = calendar.startOfDay(for: day)
        guard target > today else { return 0 }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: plan.lastExecution)) ?? tomorrow
        let from = max(tomorrow, afterLast)
        guard from <= target else { return 0 }
        let month = plan.cadence == .yearly ? calendar.component(.month, from: plan.lastExecution) : nil
        return CalendarService.savingsPlanDates(
            cadence: plan.cadence,
            from: from,
            through: target,
            yearlyMonth: month
        ).count
    }

    private static func economics(in lots: [HoldingLot], entry: LedgerEntry, requireLedgerID: Bool) -> SaleEconomics? {
        let ordered = lots.sorted { $0.date < $1.date }
        guard let index = ordered.firstIndex(where: { lot in
            guard lot.isSale else { return false }
            if lot.ledgerEntryID == entry.id { return true }
            if requireLedgerID { return false }
            return Calendar.current.isDate(lot.date, inSameDayAs: entry.date)
                && abs(lot.amountCents) == abs(entry.amountCents)
        }) else { return nil }
        var quantity = 0.0
        var cost = 0.0
        for lot in ordered[..<index] {
            if lot.isSale {
                guard quantity > 0.0000005 else { continue }
                let sold = min(lot.quantity, quantity)
                cost *= (quantity - sold) / quantity
                quantity -= sold
            } else {
                quantity += lot.quantity
                if lot.source == "gift" || lot.source == "cashback" { continue }
                let cash = abs(lot.amountCents)
                cost += cash > 0 ? Double(cash) : lot.quantity * Double(lot.unitPriceCents)
            }
        }
        let sale = ordered[index]
        guard quantity > 0.0000005, sale.quantity > 0.0000005 else { return nil }
        let sold = min(sale.quantity, quantity)
        let removedCost = cost * sold / quantity
        let proceeds = Double(abs(sale.amountCents)) * (sold / sale.quantity)
        return SaleEconomics(
            quantity: sold,
            costCents: Int(removedCost.rounded()),
            proceedsCents: Int(proceeds.rounded()),
            differenceCents: Int((proceeds - removedCost).rounded())
        )
    }

    public static func deleteLedger(_ lot: HoldingLot, holding: PortfolioHolding, context: ModelContext) {
        if let entry = ledgerEntry(for: lot, holding: holding, context: context) {
            context.delete(entry)
        }
    }
}

@MainActor
public enum SavingsPlanBuilder {
    public static func build(
        rows: [ImportedTransaction],
        checkingID: UUID,
        portfolioID: UUID,
        holdings: [PortfolioHolding]
    ) -> [SavingsPlanRecord] {
        let savings = rows.filter { $0.trade?.isSavingsPlan == true }
        let grouped = Dictionary(grouping: savings) { $0.trade?.isin.uppercased() ?? "" }
        let statementEnd = rows.map(\.date).max() ?? .now
        return grouped.compactMap { isin, items in
            guard !isin.isEmpty else { return nil }
            let sorted = items.sorted { $0.date < $1.date }
            guard let last = sorted.last, let trade = last.trade else { return nil }
            let calendar = Calendar.current
            let days = Array(Set(sorted.map { calendar.startOfDay(for: $0.date) })).sorted()
            guard let lastDay = days.last else { return nil }
            let sameDay = sorted.filter { calendar.isDate($0.date, inSameDayAs: lastDay) }
            let amount = sameDay.map { abs($0.amountCents) }.max() ?? abs(last.amountCents)
            var gaps: [Int] = []
            for pair in zip(days, days.dropFirst()) {
                let gap = calendar.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0
                if gap > 0 { gaps.append(gap) }
            }
            let cadence = cadence(for: gaps)
            let since = calendar.dateComponents([.day], from: lastDay, to: calendar.startOfDay(for: statementEnd)).day ?? 0
            let interval = intervalDays(cadence)
            let active = since <= max(Int(Double(interval) * 1.5), interval + 3)
            guard active else { return nil }
            guard let holding = holdings.first(where: {
                $0.accountID == portfolioID && $0.symbol.uppercased() == isin && $0.quantity > 0.0000005
            }) else { return nil }
            return SavingsPlanRecord(
                id: UUID(),
                isin: isin,
                name: trade.name,
                amountCents: amount,
                cadenceRaw: cadence.rawValue,
                checkingAccountID: checkingID,
                portfolioAccountID: portfolioID,
                holdingID: holding.id,
                lastExecution: last.date,
                historyThrough: statementEnd,
                active: true
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func date(after date: Date, cadence: Cadence) -> Date? {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let month = cadence == .yearly ? calendar.component(.month, from: date) : nil
        return CalendarService.nextSavingsPlanDate(cadence: cadence, onOrAfter: nextDay, yearlyMonth: month)
    }

    private static func cadence(for gaps: [Int]) -> Cadence {
        guard !gaps.isEmpty else { return .monthly }
        let median = gaps.sorted()[gaps.count / 2]
        switch median {
        case ...10: return .weekly
        case ...18: return .biweekly
        case ...45: return .monthly
        default: return .yearly
        }
    }

    private static func intervalDays(_ cadence: Cadence) -> Int {
        switch cadence {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .yearly: return 365
        }
    }
}

@MainActor
public enum SavingsPlanRunner {
    /// Advances the last execution only when a real statement row or booking already covers it.
    /// A due date without that booking stays a forecast and is not written into the ledger.
    public static func bookDue(context: ModelContext) {
        let removedSynthetic = removeSyntheticExecutions(context: context)
        var plans = SavingsPlanStore.all()
        guard plans.contains(where: \.active) || removedSynthetic else { return }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var changed = removedSynthetic
        if removedSynthetic {
            for index in plans.indices {
                let execution = calendar.startOfDay(for: plans[index].lastExecution)
                let covered = calendar.startOfDay(for: plans[index].historyThrough)
                guard execution > covered, !alreadyBooked(plans[index], on: plans[index].lastExecution, entries: entries) else { continue }
                plans[index].lastExecution = plans[index].historyThrough
            }
        }
        for index in plans.indices where plans[index].active {
            var cursor = plans[index].lastExecution
            for _ in 0..<24 {
                guard let next = SavingsPlanBuilder.date(after: cursor, cadence: plans[index].cadence) else { break }
                if calendar.startOfDay(for: next) > today { break }
                let coveredByStatement = calendar.startOfDay(for: next) <= calendar.startOfDay(for: plans[index].historyThrough)
                guard coveredByStatement || alreadyBooked(plans[index], on: next, entries: entries) else { break }
                cursor = next
                plans[index].lastExecution = next
                changed = true
            }
        }
        if changed {
            SavingsPlanStore.save(plans)
        }
    }

    /// Drops ledger rows this app previously invented when a savings-plan date passed.
    private static func removeSyntheticExecutions(context: ModelContext) -> Bool {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let synthetic = entries.filter { $0.importFingerprint?.hasPrefix("sparplan-") == true }
        guard !synthetic.isEmpty else { return false }
        let holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        for entry in synthetic {
            for holding in holdings {
                let lots = HoldingLotStore.lots(for: holding.id)
                let removed = lots.filter { $0.ledgerEntryID == entry.id }
                guard !removed.isEmpty else { continue }
                let kept = lots.filter { $0.ledgerEntryID != entry.id }
                HoldingLotStore.replace(kept, holdingID: holding.id)
                let quantity = removed.reduce(0.0) { $0 + $1.quantity }
                holding.quantity = max(0, holding.quantity - quantity)
            }
            context.delete(entry)
        }
        try? context.save()
        return true
    }

    private static func alreadyBooked(_ plan: SavingsPlanRecord, on date: Date, entries: [LedgerEntry]) -> Bool {
        let calendar = Calendar.current
        return entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
                && entry.notes.localizedCaseInsensitiveContains(plan.isin)
        }
    }
}

public struct ClosedPositionRecord: Codable, Hashable {
    public var isin: String
    public var name: String
    public var lots: [HoldingLot]

    public init(isin: String, name: String, lots: [HoldingLot]) {
        self.isin = isin
        self.name = name
        self.lots = lots
    }
}

@MainActor
public enum ClosedPositionStore {
    private static var cached: [ClosedPositionRecord]?

    public static func clearCache() {
        cached = nil
    }

    public static func all() -> [ClosedPositionRecord] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredClosedPosition>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.map(\.record)
        cached = decoded
        return decoded
    }

    public static func archive(isin: String, name: String, lots: [HoldingLot]) {
        let symbol = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty, !lots.isEmpty else { return }
        var rows = all().filter { $0.isin.uppercased() != symbol }
        rows.append(ClosedPositionRecord(isin: symbol, name: name, lots: lots))
        save(rows)
    }

    public static func remove(isin: String) {
        let symbol = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        save(all().filter { $0.isin.uppercased() != symbol })
    }

    public static func reset() {
        LififyDatabase.deleteAll(StoredClosedPosition.self)
        cached = []
    }

    private static func save(_ rows: [ClosedPositionRecord]) {
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredClosedPosition>())) ?? []).forEach(context.delete)
            for (position, record) in rows.enumerated() {
                context.insert(StoredClosedPosition(record, position: position))
            }
            LififyDatabase.saveSide()
        }
        cached = rows
    }
}

@MainActor
public enum SavingsPlanFixedCosts {
    public static var namePrefix: String { "\(L("Sparplan", "Savings plan")): " }

    public static func isManagedName(_ name: String) -> Bool {
        name.hasPrefix("Sparplan: ") || name.hasPrefix("Savings plan: ")
    }

    public static func sync(context: ModelContext) {
        var plans = SavingsPlanStore.all().filter(\.active)
        var costs = (try? context.fetch(FetchDescriptor<FixedCost>())) ?? []
        var kept: Set<UUID> = []
        for index in plans.indices {
            var plan = plans[index]
            let name = "\(namePrefix)\(plan.name)"
            let anchor = plan.lastExecution
            let existing = costs.first { $0.id == plan.fixedCostID }
                ?? costs.first { $0.accountID == plan.checkingAccountID && $0.name == name }
            let cost = existing ?? FixedCost(
                name: name,
                amountCents: plan.amountCents,
                accountID: plan.checkingAccountID,
                cadence: plan.cadence,
                firstChargeDate: anchor,
                dayOfMonth: 2,
                isActive: plan.active
            )
            if existing == nil {
                context.insert(cost)
                costs.append(cost)
            }
            cost.name = name
            cost.amountCents = plan.amountCents
            cost.accountID = plan.checkingAccountID
            cost.cadence = plan.cadence
            cost.firstChargeDate = anchor
            cost.dayOfMonth = 2
            cost.dueRule = .calendarDay
            cost.isActive = plan.active
            cost.endChargeDate = plan.active ? nil : plan.lastExecution
            plan.fixedCostID = cost.id
            plans[index] = plan
            kept.insert(cost.id)
        }
        for cost in costs where isManagedName(cost.name) && !kept.contains(cost.id) {
            context.delete(cost)
        }
        SavingsPlanStore.save(plans)
        try? context.save()
    }

    public static func planName(inFixedCostName name: String) -> String {
        if name.hasPrefix("Sparplan: ") { return String(name.dropFirst("Sparplan: ".count)) }
        if name.hasPrefix("Savings plan: ") { return String(name.dropFirst("Savings plan: ".count)) }
        return name
    }

    public static func isSavingsCost(_ cost: FixedCost) -> Bool {
        if isManagedName(cost.name) { return true }
        return SavingsPlanStore.all().contains { $0.fixedCostID == cost.id }
    }

    /// Writes a fixed-cost edit back onto the depot savings plan that owns it.
    public static func adopt(_ cost: FixedCost) {
        guard isManagedName(cost.name) else { return }
        var plans = SavingsPlanStore.all()
        let title = planName(inFixedCostName: cost.name)
        guard let index = plans.firstIndex(where: { $0.fixedCostID == cost.id })
            ?? plans.firstIndex(where: { $0.fixedCostID == nil && $0.name == title })
        else { return }
        plans[index].name = title
        plans[index].amountCents = abs(cost.amountCents)
        plans[index].cadenceRaw = cost.cadence.rawValue
        if let accountID = cost.accountID {
            plans[index].checkingAccountID = accountID
        }
        plans[index].active = cost.isActive
        plans[index].fixedCostID = cost.id
        SavingsPlanStore.save(plans)
    }

    public static func removePlan(for cost: FixedCost) {
        guard isManagedName(cost.name) else { return }
        let title = planName(inFixedCostName: cost.name)
        let plans = SavingsPlanStore.all().filter { plan in
            if plan.fixedCostID == cost.id { return false }
            if plan.fixedCostID == nil && plan.name == title { return false }
            return true
        }
        SavingsPlanStore.save(plans)
    }

    public static func monthlyCostCents(of plans: [SavingsPlanRecord]) -> Int {
        plans.filter(\.active).reduce(0) { $0 + $1.monthlyCostCents }
    }

    public static func weeklyCostCents(of plans: [SavingsPlanRecord]) -> Int {
        Int((Double(monthlyCostCents(of: plans)) / 4).rounded())
    }
}
