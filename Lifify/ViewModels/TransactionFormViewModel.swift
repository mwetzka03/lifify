import Combine
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
    @Published var category: BookingCategory
    @Published var accountID: UUID?
    @Published var fromAccountID: UUID?
    @Published var toAccountID: UUID?
    @Published var fixedCostID: UUID?
    @Published var variableBudgetID: UUID?
    @Published var shoppingItemID: UUID?
    @Published var variableSplits: [SplitDraft]
    @Published var poolSplits: [SplitDraft]
    @Published var errorMessage: String?
    private var didRefine = false

    init(entry: LedgerEntry?, splits: [TransactionSplit]) {
        id = entry?.id ?? UUID()
        existing = entry
        date = entry?.date ?? .now
        title = entry?.title ?? ""
        notes = entry?.notes ?? ""
        amountText = entry.map { String(format: "%.2f", Double(abs($0.amountCents)) / 100) } ?? ""
        category = entry.map {
            BookingClassification.category(of: $0, accounts: [], viewedAccountID: nil)
        } ?? .expense
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

    func refineIfNeeded(accounts: [Account]) {
        guard !didRefine, let existing else { return }
        didRefine = true
        category = BookingClassification.category(of: existing, accounts: accounts, viewedAccountID: nil)
    }

    func fillAccounts(for category: BookingCategory, accounts: [Account]) {
        let portfolios = accounts.filter { $0.kind == .portfolio }
        let checking = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
        switch category {
        case .portfolioBuy, .savingsPlan:
            if fromAccountID == nil {
                fromAccountID = TradeAccountPreference.accountID() ?? checking.first?.id
            }
            if toAccountID == nil {
                toAccountID = portfolios.first?.id
            }
        case .portfolioSale:
            if fromAccountID == nil {
                fromAccountID = portfolios.first?.id
            }
            if toAccountID == nil {
                toAccountID = TradeAccountPreference.accountID() ?? checking.first?.id
            }
        case .income, .interest, .dividend, .expense, .transfer, .adjustment:
            break
        }
    }

    func save(
        context: ModelContext,
        pools: [BudgetPool],
        allSplits: [TransactionSplit],
        accounts: [Account]
    ) -> Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = L("Bitte einen Titel eingeben.", "Please enter a title.")
            return false
        }
        guard let rawAmount = Money.cents(from: amountText), rawAmount != 0 else {
            errorMessage = L("Bitte einen gültigen Betrag eingeben.", "Please enter a valid amount.")
            return false
        }
        let portfolios = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        if category.usesTwoAccounts {
            guard let fromAccountID, let toAccountID, fromAccountID != toAccountID else {
                errorMessage = L("Für eine Umbuchung werden zwei verschiedene Konten benötigt.", "A transfer needs two different accounts.")
                return false
            }
            switch category {
            case .portfolioBuy, .savingsPlan:
                guard portfolios.contains(toAccountID), !portfolios.contains(fromAccountID) else {
                    errorMessage = L("Wähle ein Konto und ein Depot.", "Choose an account and a portfolio.")
                    return false
                }
            case .portfolioSale:
                guard portfolios.contains(fromAccountID), !portfolios.contains(toAccountID) else {
                    errorMessage = L("Wähle ein Depot und ein Konto.", "Choose a portfolio and an account.")
                    return false
                }
            case .transfer, .income, .interest, .dividend, .expense, .adjustment:
                break
            }
        } else if accountID == nil {
            errorMessage = L("Bitte ein Konto auswählen.", "Please select an account.")
            return false
        }
        let variableValues: [(targetID: UUID, amount: Int)]?
        let poolValues: [(targetID: UUID, amount: Int)]?
        if category == .expense {
            variableValues = splitValues(variableSplits)
            poolValues = splitValues(poolSplits)
        } else {
            variableValues = []
            poolValues = []
        }
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

        let kind = category.storedKind
        let signedAmount = kind == .expense ? -absolute : absolute
        let storedTitle = BookingClassification.preparedTitle(title, for: category)
        let storedNotes = BookingClassification.preparedNotes(notes, for: category)
        let entry = existing ?? LedgerEntry(id: id, title: storedTitle, amountCents: signedAmount, kind: kind)
        entry.date = date
        entry.title = storedTitle
        entry.notes = storedNotes
        entry.amountCents = signedAmount
        entry.kind = kind
        entry.accountID = category.usesTwoAccounts ? nil : accountID
        entry.fromAccountID = category.usesTwoAccounts ? fromAccountID : nil
        entry.toAccountID = category.usesTwoAccounts ? toAccountID : nil
        entry.fixedCostID = category == .expense ? fixedCostID : nil
        entry.variableBudgetID = category == .expense && variableValues?.isEmpty != false ? variableBudgetID : nil
        entry.shoppingItemID = category == .expense ? shoppingItemID : nil
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
