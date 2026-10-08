import Foundation
import SwiftData

struct SplitDraft: Identifiable {
    let id: UUID
    var targetID: UUID?
    var amountText: String

    init(id: UUID = UUID(), targetID: UUID? = nil, amountText: String = "") {
        self.id = id
        self.targetID = targetID
        self.amountText = amountText
    }
}

@MainActor
final class TransactionFormViewModel: ObservableObject {
    let id: UUID
    private let existing: LedgerEntry?

    @Published var date: Date
    @Published var title: String
    @Published var notes: String
    @Published var amountText: String
    @Published var kind: LedgerKind
    @Published var accountID: UUID?
    @Published var fromAccountID: UUID?
    @Published var toAccountID: UUID?
    @Published var fixedCostID: UUID?
    @Published var variableBudgetID: UUID?
    @Published var shoppingItemID: UUID?
    @Published var variableSplits: [SplitDraft]
    @Published var poolSplits: [SplitDraft]
    @Published var errorMessage: String?

    init(entry: LedgerEntry?, splits: [TransactionSplit]) {
        id = entry?.id ?? UUID()
        existing = entry
        date = entry?.date ?? .now
        title = entry?.title ?? ""
        notes = entry?.notes ?? ""
        amountText = entry.map { String(format: "%.2f", Double(abs($0.amountCents)) / 100) } ?? ""
        kind = entry?.kind ?? .expense
        accountID = entry?.accountID
        fromAccountID = entry?.fromAccountID
        toAccountID = entry?.toAccountID
        fixedCostID = entry?.fixedCostID
        variableBudgetID = entry?.variableBudgetID
        shoppingItemID = entry?.shoppingItemID
        variableSplits = splits
            .filter { $0.transactionID == entry?.id && $0.kind == .variableBudget }
            .map { SplitDraft(targetID: $0.targetID, amountText: String(format: "%.2f", Double($0.amountCents) / 100)) }
        poolSplits = splits
            .filter { $0.transactionID == entry?.id && $0.kind == .budgetPool }
            .map { SplitDraft(targetID: $0.targetID, amountText: String(format: "%.2f", Double($0.amountCents) / 100)) }
    }

    func save(context: ModelContext, pools: [BudgetPool], allSplits: [TransactionSplit]) -> Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = L("Bitte einen Titel eingeben.", "Please enter a title.")
            return false
        }
        guard let rawAmount = Money.cents(from: amountText), rawAmount != 0 else {
            errorMessage = L("Bitte einen gültigen Betrag eingeben.", "Please enter a valid amount.")
            return false
        }
        if kind == .transfer && (fromAccountID == nil || toAccountID == nil || fromAccountID == toAccountID) {
            errorMessage = L("Für eine Umbuchung werden zwei verschiedene Konten benötigt.", "A transfer needs two different accounts.")
            return false
        }
        if kind != .transfer && accountID == nil {
            errorMessage = L("Bitte ein Konto auswählen.", "Please select an account.")
            return false
        }
        let variableValues = splitValues(variableSplits)
        let poolValues = splitValues(poolSplits)
        guard variableValues != nil, poolValues != nil else {
            errorMessage = L("Alle Splits benötigen Ziel und Betrag.", "Every split needs a target and amount.")
            return false
        }
        let absolute = abs(rawAmount)
        if let values = variableValues, !values.isEmpty, values.reduce(0, { $0 + $1.amount }) != absolute {
            errorMessage = L("Variable Splits müssen dem Gesamtbetrag entsprechen.", "Variable splits must equal the total.")
            return false
        }
        if let values = poolValues, !values.isEmpty, values.reduce(0, { $0 + $1.amount }) != absolute {
            errorMessage = L("Pool-Splits müssen dem Gesamtbetrag entsprechen.", "Pool splits must equal the total.")
            return false
        }
        if variableValues?.isEmpty == false && (fixedCostID != nil || shoppingItemID != nil) {
            errorMessage = L(
                "Variable Splits können nicht zugleich Fixkosten oder einem Einkauf zugeordnet werden.",
                "Variable splits cannot also be assigned to a fixed cost or shopping item."
            )
            return false
        }

        let signedAmount = kind == .expense ? -absolute : absolute
        let entry = existing ?? LedgerEntry(id: id, title: title, amountCents: signedAmount, kind: kind)
        entry.date = date
        entry.title = title.trimmingCharacters(in: .whitespaces)
        entry.notes = notes
        entry.amountCents = signedAmount
        entry.kind = kind
        entry.accountID = kind == .transfer ? nil : accountID
        entry.fromAccountID = kind == .transfer ? fromAccountID : nil
        entry.toAccountID = kind == .transfer ? toAccountID : nil
        entry.fixedCostID = kind == .expense ? fixedCostID : nil
        entry.variableBudgetID = kind == .expense && variableValues?.isEmpty != false ? variableBudgetID : nil
        entry.shoppingItemID = kind == .expense ? shoppingItemID : nil
        if existing == nil { context.insert(entry) }

        allSplits.filter { $0.transactionID == id }.forEach { context.delete($0) }
        variableValues?.forEach {
            context.insert(TransactionSplit(transactionID: id, targetID: $0.targetID, kind: .variableBudget, periodKey: date.monthKey, amountCents: $0.amount))
        }
        poolValues?.forEach { value in
            guard let pool = pools.first(where: { $0.id == value.targetID }) else { return }
            context.insert(TransactionSplit(transactionID: id, targetID: value.targetID, kind: .budgetPool, periodKey: CalendarService.periodKey(for: date, pool: pool), amountCents: value.amount))
        }
        do {
            try context.save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func splitValues(_ drafts: [SplitDraft]) -> [(targetID: UUID, amount: Int)]? {
        var result: [(UUID, Int)] = []
        for draft in drafts {
            guard let target = draft.targetID, let amount = Money.cents(from: draft.amountText), amount > 0 else { return nil }
            result.append((target, amount))
        }
        return result
    }
}
