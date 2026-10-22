import SwiftData
import SwiftUI

struct AccountsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showingNew = false
    @State private var edited: Account?

    var body: some View {
        List {
            ForEach(accounts) { account in
                Button {
                    edited = account
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.name).foregroundStyle(.primary)
                            Text(accountSubtitle(account)).font(.caption).foregroundStyle(.secondary)
                        }
                        if account.isMain {
                            Text(L("Hauptkonto", "Main")).font(.caption).foregroundStyle(.blue)
                        }
                        Spacer()
                        Image(systemName: account.isLiquid ? "drop.fill" : "drop")
                    }
                }
                .deleteDisabled(account.isMain)
            }
            .onDelete { offsets in
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
        }
        .overlay {
            if accounts.isEmpty { ContentUnavailableView(L("Keine Konten", "No accounts"), systemImage: "building.columns") }
        }
        .navigationTitle(L("Konten", "Accounts"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { AccountForm(account: nil, allAccounts: accounts) }
        .sheet(item: $edited) { AccountForm(account: $0, allAccounts: accounts) }
    }

    private func accountSubtitle(_ account: Account) -> String {
        guard account.kind == .portfolio,
              let checkingID = PortfolioLinkStore.checkingID(for: account.id),
              let checking = accounts.first(where: { $0.id == checkingID })
        else { return account.kind.label }
        return "\(account.kind.label) · \(checking.name)"
    }
}

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
            Form {
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
                            "Lege zuerst ein Girokonto an. Ein Depot muss damit verknüpft sein.",
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
