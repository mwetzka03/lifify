import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LififyBackup: Codable {
    let version: Int
    let exportedAt: Date
    let records: [BackupRecord]
}

struct BackupRecord: Codable {
    let type: String
    let id: UUID
    var strings: [String] = []
    var integers: [Int] = []
    var doubles: [Double] = []
    var booleans: [Bool] = []
    var dates: [Date?] = []
    var uuids: [UUID?] = []
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    static func exportData(
        accounts: [Account],
        entries: [LedgerEntry],
        splits: [TransactionSplit],
        fixedCosts: [FixedCost],
        variableBudgets: [VariableBudget],
        pools: [BudgetPool],
        forecasts: [IncomeForecast],
        shopping: [ShoppingItem],
        debts: [DebtEntry],
        groups: [ExpenseGroup],
        lines: [ExpenseGroupLine],
        holdings: [PortfolioHolding],
        articles: [SavedArticle]
    ) throws -> Data {
        var records: [BackupRecord] = []
        records += accounts.map {
            BackupRecord(type: "account", id: $0.id, strings: [$0.name, $0.kindRaw, $0.iban], booleans: [$0.isLiquid, $0.isMain], dates: [$0.createdAt], uuids: [$0.parentAccountID])
        }
        records += entries.map {
            BackupRecord(type: "entry", id: $0.id, strings: [$0.title, $0.notes, $0.kindRaw, $0.importFingerprint ?? ""], integers: [$0.amountCents], dates: [$0.date, $0.createdAt], uuids: [$0.accountID, $0.fromAccountID, $0.toAccountID, $0.fixedCostID, $0.variableBudgetID, $0.shoppingItemID])
        }
        records += splits.map {
            BackupRecord(type: "split", id: $0.id, strings: [$0.kindRaw, $0.periodKey], integers: [$0.amountCents], uuids: [$0.transactionID, $0.targetID])
        }
        records += fixedCosts.map {
            BackupRecord(type: "fixed", id: $0.id, strings: [$0.name, $0.cadenceRaw, $0.dueRuleRaw], integers: [$0.amountCents, $0.dayOfMonth], booleans: [$0.isActive], dates: [$0.firstChargeDate, $0.endChargeDate], uuids: [$0.accountID])
        }
        records += variableBudgets.map {
            BackupRecord(type: "variable", id: $0.id, strings: [$0.name, $0.notes], integers: [$0.monthlyAmountCents], dates: [$0.createdAt], uuids: [$0.accountID])
        }
        records += pools.map {
            BackupRecord(type: "pool", id: $0.id, strings: [$0.name, $0.periodModeRaw], integers: [$0.amountCents, $0.salaryStartDay], booleans: [$0.isScalable, $0.isActive], dates: [$0.createdAt], uuids: [$0.accountID])
        }
        records += forecasts.map {
            BackupRecord(type: "forecast", id: $0.id, strings: [$0.name, $0.cadenceRaw, $0.dueRuleRaw], integers: [$0.amountCents, $0.dayOfMonth], booleans: [$0.isActive], dates: [$0.firstPaymentDate, $0.endPaymentDate], uuids: [$0.accountID])
        }
        records += shopping.map {
            BackupRecord(type: "shopping", id: $0.id, strings: [$0.name, $0.groupName, $0.urlString, $0.notes], integers: [$0.amountCents], booleans: [$0.isPurchased], dates: [$0.plannedDate, $0.createdAt])
        }
        records += debts.map {
            BackupRecord(type: "debt", id: $0.id, strings: [$0.contactName, $0.title, $0.directionRaw], integers: [$0.amountCents], booleans: [$0.isSettled], dates: [$0.date])
        }
        records += groups.map {
            BackupRecord(type: "group", id: $0.id, strings: [$0.name, $0.notes], dates: [$0.date])
        }
        records += lines.map {
            BackupRecord(type: "line", id: $0.id, strings: [$0.name], integers: [$0.amountCents, $0.sortOrder], uuids: [$0.groupID])
        }
        records += holdings.map {
            BackupRecord(type: "holding", id: $0.id, strings: [$0.name, $0.symbol], integers: [$0.purchasePriceCents, $0.currentPriceCents], doubles: [$0.quantity], dates: [$0.updatedAt], uuids: [$0.accountID])
        }
        records += articles.map {
            BackupRecord(type: "article", id: $0.id, strings: [$0.title, $0.urlString, $0.notes], dates: [$0.savedAt])
        }
        let backup = LififyBackup(version: 1, exportedAt: .now, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    @MainActor
    static func restore(data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LififyBackup.self, from: data)
        guard backup.version == 1 else { throw CocoaError(.fileReadUnsupportedScheme) }
        try clear(context)
        for record in backup.records { insert(record, into: context) }
        try context.save()
    }

    @MainActor
    private static func clear(_ context: ModelContext) throws {
        try context.fetch(FetchDescriptor<TransactionSplit>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<LedgerEntry>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<Account>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<FixedCost>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<VariableBudget>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<BudgetPool>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<IncomeForecast>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<ShoppingItem>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<DebtEntry>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<ExpenseGroupLine>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<ExpenseGroup>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PortfolioHolding>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<SavedArticle>()).forEach { context.delete($0) }
    }

    @MainActor
    private static func insert(_ r: BackupRecord, into context: ModelContext) {
        func string(_ index: Int) -> String { r.strings.indices.contains(index) ? r.strings[index] : "" }
        func int(_ index: Int) -> Int { r.integers.indices.contains(index) ? r.integers[index] : 0 }
        func bool(_ index: Int) -> Bool { r.booleans.indices.contains(index) ? r.booleans[index] : false }
        func date(_ index: Int) -> Date? { r.dates.indices.contains(index) ? r.dates[index] : nil }
        func uuid(_ index: Int) -> UUID? { r.uuids.indices.contains(index) ? r.uuids[index] : nil }

        switch r.type {
        case "account":
            context.insert(Account(id: r.id, name: string(0), kind: AccountKind(rawValue: string(1)) ?? .checking, isLiquid: bool(0), isMain: bool(1), iban: string(2), parentAccountID: uuid(0), createdAt: date(0) ?? .now))
        case "entry":
            context.insert(LedgerEntry(id: r.id, date: date(0) ?? .now, title: string(0), notes: string(1), amountCents: int(0), kind: LedgerKind(rawValue: string(2)) ?? .expense, accountID: uuid(0), fromAccountID: uuid(1), toAccountID: uuid(2), fixedCostID: uuid(3), variableBudgetID: uuid(4), shoppingItemID: uuid(5), importFingerprint: string(3).isEmpty ? nil : string(3), createdAt: date(1) ?? .now))
        case "split":
            if let transaction = uuid(0), let target = uuid(1) { context.insert(TransactionSplit(id: r.id, transactionID: transaction, targetID: target, kind: SplitKind(rawValue: string(0)) ?? .variableBudget, periodKey: string(1), amountCents: int(0))) }
        case "fixed":
            context.insert(FixedCost(id: r.id, name: string(0), amountCents: int(0), accountID: uuid(0), cadence: Cadence(rawValue: string(1)) ?? .monthly, firstChargeDate: date(0) ?? .now, endChargeDate: date(1), dueRule: DueRule(rawValue: string(2)) ?? .calendarDay, dayOfMonth: int(1), isActive: bool(0)))
        case "variable":
            context.insert(VariableBudget(id: r.id, name: string(0), monthlyAmountCents: int(0), accountID: uuid(0), notes: string(1), createdAt: date(0) ?? .now))
        case "pool":
            context.insert(BudgetPool(id: r.id, name: string(0), amountCents: int(0), accountID: uuid(0), periodMode: BudgetPeriodMode(rawValue: string(1)) ?? .salaryPeriod, salaryStartDay: int(1), isScalable: bool(0), isActive: bool(1), createdAt: date(0) ?? .now))
        case "forecast":
            context.insert(IncomeForecast(id: r.id, name: string(0), amountCents: int(0), accountID: uuid(0), cadence: Cadence(rawValue: string(1)) ?? .monthly, firstPaymentDate: date(0) ?? .now, endPaymentDate: date(1), dueRule: DueRule(rawValue: string(2)) ?? .calendarDay, dayOfMonth: int(1), isActive: bool(0)))
        case "shopping":
            context.insert(ShoppingItem(id: r.id, name: string(0), amountCents: int(0), plannedDate: date(0), groupName: string(1), urlString: string(2), notes: string(3), isPurchased: bool(0), createdAt: date(1) ?? .now))
        case "debt":
            context.insert(DebtEntry(id: r.id, contactName: string(0), title: string(1), amountCents: int(0), direction: DebtDirection(rawValue: string(2)) ?? .owedToMe, date: date(0) ?? .now, isSettled: bool(0)))
        case "group":
            context.insert(ExpenseGroup(id: r.id, name: string(0), date: date(0) ?? .now, notes: string(1)))
        case "line":
            if let group = uuid(0) { context.insert(ExpenseGroupLine(id: r.id, groupID: group, name: string(0), amountCents: int(0), sortOrder: int(1))) }
        case "holding":
            context.insert(PortfolioHolding(id: r.id, accountID: uuid(0), name: string(0), symbol: string(1), quantity: r.doubles.first ?? 0, purchasePriceCents: int(0), currentPriceCents: int(1), updatedAt: date(0) ?? .now))
        case "article":
            context.insert(SavedArticle(id: r.id, title: string(0), urlString: string(1), notes: string(2), savedAt: date(0) ?? .now))
        default:
            break
        }
    }
}
