import Foundation
import SwiftData

struct HoldingLot: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var quantity: Double
    var unitPriceCents: Int
    var amountCents: Int
    var isSale: Bool
    var isSavingsPlan: Bool
    var ledgerEntryID: UUID?

    init(
        id: UUID = UUID(),
        date: Date,
        quantity: Double,
        unitPriceCents: Int,
        amountCents: Int,
        isSale: Bool,
        isSavingsPlan: Bool,
        ledgerEntryID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.amountCents = amountCents
        self.isSale = isSale
        self.isSavingsPlan = isSavingsPlan
        self.ledgerEntryID = ledgerEntryID
    }

    enum CodingKeys: String, CodingKey {
        case id, date, quantity, unitPriceCents, amountCents, isSale, isSavingsPlan, ledgerEntryID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        quantity = try container.decode(Double.self, forKey: .quantity)
        unitPriceCents = try container.decode(Int.self, forKey: .unitPriceCents)
        amountCents = try container.decode(Int.self, forKey: .amountCents)
        isSale = try container.decode(Bool.self, forKey: .isSale)
        isSavingsPlan = try container.decode(Bool.self, forKey: .isSavingsPlan)
        ledgerEntryID = try container.decodeIfPresent(UUID.self, forKey: .ledgerEntryID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unitPriceCents, forKey: .unitPriceCents)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(isSale, forKey: .isSale)
        try container.encode(isSavingsPlan, forKey: .isSavingsPlan)
        try container.encodeIfPresent(ledgerEntryID, forKey: .ledgerEntryID)
    }
}

@MainActor
enum HoldingLotStore {
    private static let key = "lifify.holdingLots"

    static func lots(for holdingID: UUID) -> [HoldingLot] {
        all()[holdingID.uuidString] ?? []
    }

    static func add(_ lot: HoldingLot, holdingID: UUID) {
        var map = all()
        var rows = map[holdingID.uuidString] ?? []
        rows.append(lot)
        map[holdingID.uuidString] = rows
        save(map)
    }

    static func replace(_ lots: [HoldingLot], holdingID: UUID) {
        var map = all()
        if lots.isEmpty {
            map.removeValue(forKey: holdingID.uuidString)
        } else {
            map[holdingID.uuidString] = lots
        }
        save(map)
    }

    static func remove(lotID: UUID, holdingID: UUID) {
        var rows = lots(for: holdingID)
        rows.removeAll { $0.id == lotID }
        replace(rows, holdingID: holdingID)
    }

    static func removeAll(for holdingID: UUID) {
        var map = all()
        map.removeValue(forKey: holdingID.uuidString)
        save(map)
    }

    private static func all() -> [String: [HoldingLot]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [HoldingLot]].self, from: data) else { return [:] }
        return decoded
    }

    private static func save(_ map: [String: [HoldingLot]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct SavingsPlanRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var isin: String
    var name: String
    var amountCents: Int
    var cadenceRaw: String
    var checkingAccountID: UUID
    var portfolioAccountID: UUID
    var holdingID: UUID?
    var lastExecution: Date
    var historyThrough: Date
    var active: Bool
    var fixedCostID: UUID? = nil

    var cadence: Cadence { Cadence(rawValue: cadenceRaw) ?? .monthly }

    var monthlyCostCents: Int {
        switch cadence {
        case .weekly: return amountCents * 4
        case .biweekly: return amountCents * 2
        case .monthly: return amountCents
        case .yearly: return Int((Double(amountCents) / 12).rounded())
        }
    }

    @MainActor
    func nextExecution(after date: Date = .now) -> Date? {
        guard active else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastExecution)) ?? today
        let start = max(today, afterLast)
        let month = cadence == .yearly ? calendar.component(.month, from: lastExecution) : nil
        return CalendarService.nextSavingsPlanDate(cadence: cadence, onOrAfter: start, yearlyMonth: month)
    }
}

@MainActor
enum SavingsPlanStore {
    private static let key = "lifify.savingsPlans"

    static func all() -> [SavingsPlanRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavingsPlanRecord].self, from: data) else { return [] }
        return decoded
    }

    static func replace(_ plans: [SavingsPlanRecord], portfolioID: UUID) {
        var kept = all().filter { $0.portfolioAccountID != portfolioID }
        kept.append(contentsOf: plans)
        save(kept)
    }

    static func removeAll(portfolioID: UUID) {
        save(all().filter { $0.portfolioAccountID != portfolioID })
    }

    static func upsert(_ plan: SavingsPlanRecord) {
        var plans = all()
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        save(plans)
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    static func save(_ plans: [SavingsPlanRecord]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
enum HoldingMaintenance {
    /// Einstand is the cash paid divided by the shares still held, rounded once.
    static func averagePurchaseCents(for lots: [HoldingLot]) -> (quantity: Double, priceCents: Int)? {
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
                cost += Double(abs(lot.amountCents))
            }
        }
        guard quantity > 0.0000005 else { return nil }
        return (quantity, max(0, Int((cost / quantity).rounded())))
    }

    /// Rebuilds the holding from its lots. A position that was fully sold, or whose lots were all removed, disappears.
    @discardableResult
    static func sync(_ holding: PortfolioHolding, context: ModelContext) -> Bool {
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

    static func ledgerEntry(for lot: HoldingLot, holding: PortfolioHolding, context: ModelContext) -> LedgerEntry? {
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

    static func updateLedger(previous: HoldingLot, updated: HoldingLot, holding: PortfolioHolding, context: ModelContext) {
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
    static func retire(_ holding: PortfolioHolding, context: ModelContext) {
        let lots = HoldingLotStore.lots(for: holding.id)
        if !lots.isEmpty {
            ClosedPositionStore.archive(isin: holding.symbol, name: holding.name, lots: lots)
        }
        HoldingLotStore.removeAll(for: holding.id)
        MarketSymbolStore.remove(for: holding.id)
        PreviousCloseStore.remove(for: holding.id)
        HoldingPurchaseDateStore.remove(for: holding.id)
        context.delete(holding)
    }

    /// Market value of the shares already held at the end of `day`. Later buys are excluded.
    static func marketValue(of holdings: [PortfolioHolding], through day: Date) -> Int {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: day)
        ) ?? day
        return holdings.reduce(0) { total, holding in
            total + marketValue(of: holding, before: cutoff)
        }
    }

    /// Sale proceeds minus the average cost of the shares sold, after fees.
    static func realizedGainCents(for entry: LedgerEntry, holdings: [PortfolioHolding]) -> Int? {
        let groups = holdings.map { HoldingLotStore.lots(for: $0.id) } + ClosedPositionStore.all().map(\.lots)
        if let matched = groups.compactMap({ gainCents(in: $0, entry: entry, requireLedgerID: true) }).first {
            return matched
        }
        return groups.compactMap { gainCents(in: $0, entry: entry, requireLedgerID: false) }.first
    }

    private static func marketValue(of holding: PortfolioHolding, before cutoff: Date) -> Int {
        let stored = HoldingLotStore.lots(for: holding.id)
        let lots = stored.filter { $0.date < cutoff }.sorted { $0.date < $1.date }
        let quantity: Double
        if stored.isEmpty {
            let purchased = HoldingPurchaseDateStore.date(for: holding.id) ?? .distantPast
            quantity = purchased < cutoff ? max(holding.quantity, 0) : 0
        } else {
            var held = 0.0
            for lot in lots {
                if lot.isSale {
                    held -= lot.quantity
                } else {
                    held += lot.quantity
                }
            }
            quantity = max(0, held)
        }
        guard quantity > 0.0000005 else { return 0 }
        return Int((quantity * Double(holding.currentPriceCents)).rounded())
    }

    private static func gainCents(in lots: [HoldingLot], entry: LedgerEntry, requireLedgerID: Bool) -> Int? {
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
                cost += Double(abs(lot.amountCents))
            }
        }
        let sale = ordered[index]
        guard quantity > 0.0000005, sale.quantity > 0.0000005 else { return nil }
        let sold = min(sale.quantity, quantity)
        let removedCost = cost * sold / quantity
        let proceeds = Double(abs(sale.amountCents)) * (sold / sale.quantity)
        return Int((proceeds - removedCost).rounded())
    }

    static func deleteLedger(_ lot: HoldingLot, holding: PortfolioHolding, context: ModelContext) {
        if let entry = ledgerEntry(for: lot, holding: holding, context: context) {
            context.delete(entry)
        }
    }
}

@MainActor
enum SavingsPlanBuilder {
    static func build(
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

    static func date(after date: Date, cadence: Cadence) -> Date? {
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
enum SavingsPlanRunner {
    static func bookDue(context: ModelContext) {
        var plans = SavingsPlanStore.all()
        guard plans.contains(where: \.active) else { return }
        var entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var changed = false
        for index in plans.indices where plans[index].active {
            var cursor = plans[index].lastExecution
            for _ in 0..<24 {
                guard let next = SavingsPlanBuilder.date(after: cursor, cadence: plans[index].cadence) else { break }
                if calendar.startOfDay(for: next) > today { break }
                let coveredByStatement = calendar.startOfDay(for: next) <= calendar.startOfDay(for: plans[index].historyThrough)
                if coveredByStatement || alreadyBooked(plans[index], on: next, entries: entries) {
                    cursor = next
                    plans[index].lastExecution = next
                    changed = true
                    continue
                }
                guard let holdingID = book(plans[index], on: next, context: context, entries: &entries, holdings: &holdings) else { break }
                plans[index].holdingID = holdingID
                cursor = next
                plans[index].lastExecution = next
                changed = true
            }
        }
        if changed {
            SavingsPlanStore.save(plans)
            try? context.save()
        }
    }

    private static func alreadyBooked(_ plan: SavingsPlanRecord, on date: Date, entries: [LedgerEntry]) -> Bool {
        let calendar = Calendar.current
        return entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
                && entry.notes.localizedCaseInsensitiveContains(plan.isin)
        }
    }

    @discardableResult
    private static func book(
        _ plan: SavingsPlanRecord,
        on date: Date,
        context: ModelContext,
        entries: inout [LedgerEntry],
        holdings: inout [PortfolioHolding]
    ) -> UUID? {
        let holding = holdings.first { $0.id == plan.holdingID }
            ?? holdings.first { $0.accountID == plan.portfolioAccountID && $0.symbol.caseInsensitiveCompare(plan.isin) == .orderedSame }
        let price = holding?.currentPriceCents ?? holding?.purchasePriceCents ?? 0
        guard price > 0 else { return nil }
        let quantity = Double(plan.amountCents) / Double(price)
        guard quantity > 0 else { return nil }
        let target: PortfolioHolding
        if let holding {
            let previous = holding.quantity * Double(holding.purchasePriceCents)
            let next = holding.quantity + quantity
            holding.purchasePriceCents = Int(((previous + Double(plan.amountCents)) / next).rounded())
            holding.quantity = next
            holding.updatedAt = date
            target = holding
        } else {
            let created = PortfolioHolding(
                accountID: plan.portfolioAccountID,
                name: plan.name,
                symbol: plan.isin,
                quantity: quantity,
                purchasePriceCents: price,
                currentPriceCents: price,
                updatedAt: date
            )
            context.insert(created)
            holdings.append(created)
            target = created
        }
        let entry = LedgerEntry(
            date: date,
            title: "\(L("Sparplan", "Savings plan")): \(plan.name)",
            notes: "\(L("Typ", "Type")): Sparplan\nISIN: \(plan.isin)\n\(L("Stück", "Quantity")): \(quantityText(quantity))",
            amountCents: plan.amountCents,
            kind: .transfer,
            fromAccountID: plan.checkingAccountID,
            toAccountID: plan.portfolioAccountID,
            importFingerprint: "sparplan-\(plan.isin)-\(date.dayKey)"
        )
        context.insert(entry)
        entries.append(entry)
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: quantity,
                unitPriceCents: price,
                amountCents: -plan.amountCents,
                isSale: false,
                isSavingsPlan: true,
                ledgerEntryID: entry.id
            ),
            holdingID: target.id
        )
        return target.id
    }

    private static func quantityText(_ quantity: Double) -> String {
        var text = String(format: "%.6f", quantity)
        while text.contains("."), text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}

struct ClosedPositionRecord: Codable, Hashable {
    var isin: String
    var name: String
    var lots: [HoldingLot]
}

@MainActor
enum ClosedPositionStore {
    private static let key = "lifify.closedPositions"

    static func all() -> [ClosedPositionRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ClosedPositionRecord].self, from: data) else { return [] }
        return decoded
    }

    static func archive(isin: String, name: String, lots: [HoldingLot]) {
        let symbol = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty, !lots.isEmpty else { return }
        var rows = all().filter { $0.isin.uppercased() != symbol }
        rows.append(ClosedPositionRecord(isin: symbol, name: name, lots: lots))
        save(rows)
    }

    static func remove(isin: String) {
        let symbol = isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        save(all().filter { $0.isin.uppercased() != symbol })
    }

    private static func save(_ rows: [ClosedPositionRecord]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
enum SavingsPlanFixedCosts {
    static var namePrefix: String { "\(L("Sparplan", "Savings plan")): " }

    static func isManagedName(_ name: String) -> Bool {
        name.hasPrefix("Sparplan: ") || name.hasPrefix("Savings plan: ")
    }

    static func sync(context: ModelContext) {
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

    static func planName(inFixedCostName name: String) -> String {
        if name.hasPrefix("Sparplan: ") { return String(name.dropFirst("Sparplan: ".count)) }
        if name.hasPrefix("Savings plan: ") { return String(name.dropFirst("Savings plan: ".count)) }
        return name
    }

    static func isSavingsCost(_ cost: FixedCost) -> Bool {
        if isManagedName(cost.name) { return true }
        return SavingsPlanStore.all().contains { $0.fixedCostID == cost.id }
    }

    /// Writes a fixed-cost edit back onto the depot savings plan that owns it.
    static func adopt(_ cost: FixedCost) {
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

    static func removePlan(for cost: FixedCost) {
        guard isManagedName(cost.name) else { return }
        let title = planName(inFixedCostName: cost.name)
        let plans = SavingsPlanStore.all().filter { plan in
            if plan.fixedCostID == cost.id { return false }
            if plan.fixedCostID == nil && plan.name == title { return false }
            return true
        }
        SavingsPlanStore.save(plans)
    }

    static func monthlyCostCents(of plans: [SavingsPlanRecord]) -> Int {
        plans.filter(\.active).reduce(0) { $0 + $1.monthlyCostCents }
    }

    static func weeklyCostCents(of plans: [SavingsPlanRecord]) -> Int {
        Int((Double(monthlyCostCents(of: plans)) / 4).rounded())
    }
}
