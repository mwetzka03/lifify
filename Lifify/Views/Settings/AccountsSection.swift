import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI

/// The accounts as a section of the finance settings: tap to edit, swipe to delete, a row to add one.
///
/// The forms open through `accountEditor(showingNew:edited:)` on the settings screen, because a sheet
/// attached to a row inside a form can close the form when it opens.
struct AccountsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Binding var showingNew: Bool
    @Binding var edited: Account?

    var body: some View {
        Section {
            ForEach(accounts) { account in
                Button {
                    edited = account
                } label: {
                    accountRow(account)
                }
                .deleteDisabled(account.isMain)
            }
            .onDelete(perform: delete)
            Button {
                showingNew = true
            } label: {
                Label(L("Konto anlegen", "Add account"), systemImage: "plus")
            }
        } header: {
            Text(L("Konten", "Accounts"))
        } footer: {
            Text(L("Tippen bearbeitet ein Konto, Wischen löscht es. Das Hauptkonto bleibt.", "Tap to edit an account, swipe to delete it. The main account stays."))
        }
        .appGlassRow()
    }

    /// One account with its kind and whether it counts as cash.
    private func accountRow(_ account: Account) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(account.name).foregroundStyle(.primary)
                Text(accountSubtitle(account)).font(.caption).foregroundStyle(.secondary)
            }
            if account.isMain {
                Text(L("Hauptkonto", "Main")).font(.caption).appAccentForeground()
            }
            Spacer()
            Image(systemName: account.isLiquid ? "drop.fill" : "drop")
                .foregroundStyle(.secondary)
        }
    }

    /// Deletes the swiped accounts, never the main account, and unlinks portfolios.
    private func delete(_ offsets: IndexSet) {
        offsets.map { accounts[$0] }
            .filter { !$0.isMain }
            .forEach { account in
                if account.kind == .portfolio {
                    PortfolioLinkStore.unlink(portfolio: account.id)
                } else if account.kind == .checking {
                    PortfolioLinkStore.unlink(checkingID: account.id)
                }
                context.delete(account)
            }
        try? context.save()
    }

    /// Describes an account.
    private func accountSubtitle(_ account: Account) -> String {
        guard account.kind == .portfolio,
              let checkingID = PortfolioLinkStore.checkingID(for: account.id),
              let checking = accounts.first(where: { $0.id == checkingID })
        else { return account.kind.label }
        return "\(account.kind.label) · \(checking.name)"
    }
}

/// Presents the account forms of `AccountsSection`.
private struct AccountEditorModifier: ViewModifier {
    @Binding var showingNew: Bool
    @Binding var edited: Account?
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingNew) { AccountForm(account: nil, allAccounts: accounts) }
            .sheet(item: $edited) { AccountForm(account: $0, allAccounts: accounts) }
    }
}

extension View {
    /// Opens the form to add or edit an account from the settings screen.
    func accountEditor(showingNew: Binding<Bool>, edited: Binding<Account?>) -> some View {
        modifier(AccountEditorModifier(showingNew: showingNew, edited: edited))
    }
}

/// Creates or edits an account.
private struct AccountForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let existing: Account?
    let allAccounts: [Account]
    @State private var name: String
    @State private var kind: AccountKind
    @State private var iban: String
    @State private var liquid: Bool
    @State private var main: Bool
    @State private var parentID: UUID?
    @State private var linkedCheckingID: UUID?
    @State private var validationMessage: String?

    init(account: Account?, allAccounts: [Account]) {
        existing = account
        self.allAccounts = allAccounts
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .checking)
        _iban = State(initialValue: account?.iban ?? "")
        _liquid = State(initialValue: account?.isLiquid ?? true)
        _main = State(initialValue: account?.isMain ?? allAccounts.isEmpty)
        _parentID = State(initialValue: account?.parentAccountID)
        _linkedCheckingID = State(initialValue: account.flatMap { PortfolioLinkStore.checkingID(for: $0.id) })
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                TextField(L("Name", "Name"), text: $name)
                Picker(L("Kontotyp", "Account type"), selection: $kind) {
                    ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("IBAN", text: $iban).textInputAutocapitalization(.characters)
                Toggle(L("Liquide", "Liquid"), isOn: $liquid)
                if kind == .checking {
                    Toggle(L("Hauptkonto", "Main account"), isOn: $main)
                }
                if kind == .savings {
                    Picker(L("Oberspartopf", "Savings group"), selection: $parentID) {
                        Text(L("Keiner", "None")).tag(Optional<UUID>.none)
                        ForEach(allAccounts.filter { $0.kind == .savingsGroup }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                }
                if kind == .portfolio {
                    if linkableCheckingAccounts.isEmpty {
                        Text(L(
                            "Lege zuerst ein Girokonto an. Ein Depot muss daran hängen.",
                            "Create a checking account first. A portfolio has to be linked to one."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Picker(L("Verknüpftes Girokonto", "Linked checking account"), selection: $linkedCheckingID) {
                            Text(L("Auswählen", "Choose")).tag(Optional<UUID>.none)
                            ForEach(linkableCheckingAccounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
                }
                .appGlassRow()
            }
            .appGlassList()
            .navigationTitle(L("Konto", "Account"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private var linkableCheckingAccounts: [Account] {
        allAccounts.filter { account in
            guard account.kind == .checking else { return false }
            guard let linked = PortfolioLinkStore.portfolioID(for: account.id) else { return true }
            return linked == existing?.id
        }
    }

    /// Saves the account and its depot link.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if kind == .portfolio, linkedCheckingID == nil {
            validationMessage = L(
                "Ein Depot muss mit einem Girokonto verknüpft sein.",
                "A portfolio must be linked to a checking account."
            )
            return
        }
        if main { allAccounts.forEach { $0.isMain = false } }
        let account = existing ?? Account(name: trimmed)
        let wasPortfolio = existing?.kind == .portfolio
        account.name = trimmed
        account.kind = kind
        account.iban = iban.replacingOccurrences(of: " ", with: "").uppercased()
        account.isLiquid = kind == .portfolio ? false : liquid
        account.isMain = kind == .checking && main
        account.parentAccountID = kind == .savings ? parentID : nil
        if existing == nil { context.insert(account) }
        if kind == .portfolio, let linkedCheckingID {
            PortfolioLinkStore.link(portfolio: account.id, to: linkedCheckingID)
        } else if wasPortfolio {
            PortfolioLinkStore.unlink(portfolio: account.id)
        }
        try? context.save()
        dismiss()
    }
}
