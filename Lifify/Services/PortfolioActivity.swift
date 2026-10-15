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

    init(
        id: UUID = UUID(),
        date: Date,
        quantity: Double,
        unitPriceCents: Int,
        amountCents: Int,
        isSale: Bool,
        isSavingsPlan: Bool
    ) {
        self.id = id
        self.date = date
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.amountCents = amountCents
        self.isSale = isSale
        self.isSavingsPlan = isSavingsPlan
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

    var cadence: Cadence { Cadence(rawValue: cadenceRaw) ?? .monthly }

    @MainActor
    func nextExecution(after date: Date = .now) -> Date? {
        var cursor = lastExecution
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        for _ in 0..<36 {
            guard let next = SavingsPlanBuilder.date(after: cursor, cadence: cadence) else { return nil }
            if calendar.startOfDay(for: next) >= today { return next }
            cursor = next
        }
        return nil
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

    static func save(_ plans: [SavingsPlanRecord]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
            let holding = holdings.first {
                $0.accountID == portfolioID && $0.symbol.uppercased() == isin
            }
            return SavingsPlanRecord(
                id: UUID(),
                isin: isin,
                name: trade.name,
                amountCents: amount,
                cadenceRaw: cadence.rawValue,
                checkingAccountID: checkingID,
                portfolioAccountID: portfolioID,
                holdingID: holding?.id,
                lastExecution: last.date,
                historyThrough: statementEnd,
                active: active
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func date(after date: Date, cadence: Cadence) -> Date? {
        let calendar = Calendar.current
        switch cadence {
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date)
        }
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
            for _ in 0..<8 {
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
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: quantity,
                unitPriceCents: price,
                amountCents: -plan.amountCents,
                isSale: false,
                isSavingsPlan: true
            ),
            holdingID: target.id
        )
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
        return target.id
    }

    private static func quantityText(_ quantity: Double) -> String {
        var text = String(format: "%.6f", quantity)
        while text.contains("."), text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
