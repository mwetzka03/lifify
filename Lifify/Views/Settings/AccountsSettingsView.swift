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
                            Text(account.kind.label).font(.caption).foregroundStyle(.secondary)
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
                    .forEach(context.delete)
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

    init(account: Account?, allAccounts: [Account]) {
        existing = account
        self.allAccounts = allAccounts
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .checking)
        _iban = State(initialValue: account?.iban ?? "")
        _liquid = State(initialValue: account?.isLiquid ?? true)
        _main = State(initialValue: account?.isMain ?? allAccounts.isEmpty)
        _parentID = State(initialValue: account?.parentAccountID)
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
            }
            .navigationTitle(L("Konto", "Account"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !name.isEmpty else { return }
                        if main { allAccounts.forEach { $0.isMain = false } }
                        let account = existing ?? Account(name: name)
                        account.name = name
                        account.kind = kind
                        account.iban = iban.replacingOccurrences(of: " ", with: "").uppercased()
                        account.isLiquid = liquid
                        account.isMain = kind == .checking && main
                        account.parentAccountID = kind == .savings ? parentID : nil
                        if existing == nil { context.insert(account) }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
