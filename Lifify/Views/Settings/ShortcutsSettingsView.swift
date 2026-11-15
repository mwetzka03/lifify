import SwiftData
import SwiftUI

struct ShortcutsSettingsView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var templates: [NoticeTemplate] = NoticeTemplateStore.all()
    @State private var edited: NoticeTemplate?
    @State private var creatingFor: UUID?

    private var checking: [Account] {
        accounts.filter { $0.kind == .checking }
    }

    var body: some View {
        List {
            Section {
                Text(L(
                    "In der Kurzbefehle-App: Wenn eine Mitteilung kommt, Aktion Bankmitteilung buchen, Konto Sparkasse oder Trade Republic, Mitteilung der Nachrichtentext. Hier sagst du, wie die Nachricht aussieht und was gebucht wird.",
                    "In the Shortcuts app: when a notice arrives, run Record bank notice, account Sparkasse or Trade Republic, notification as the text. Here you say what the message looks like and what to book."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .appGlassRow()
            if checking.isEmpty {
                Section {
                    Text(L("Lege zuerst ein Girokonto an.", "Create a checking account first."))
                        .foregroundStyle(.secondary)
                }
                .appGlassRow()
            }
            ForEach(checking) { account in
                let rows = templates.filter { $0.accountID == account.id }
                Section {
                    if rows.isEmpty {
                        Text(L("Noch keine Vorlage.", "No template yet."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { template in
                        Button {
                            edited = template
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name.isEmpty ? template.action.label : template.name)
                                    .foregroundStyle(.primary)
                                Text(template.example)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(template.action.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .appGlassRow()
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { rows[$0].id }
                        templates.removeAll { ids.contains($0.id) }
                        NoticeTemplateStore.save(templates)
                    }
                    Button {
                        creatingFor = account.id
                    } label: {
                        Label(L("Vorlage hinzufügen", "Add template"), systemImage: "plus")
                    }
                } header: {
                    Text(account.name)
                } footer: {
                    if account.name.localizedCaseInsensitiveContains("sparkasse") {
                        Text(L(
                            "Apple-Kurzbefehl: Konto Sparkasse. Beispiel: Abbuchung 12,34 EUR REWE.",
                            "Apple Shortcut: account Sparkasse. Example: Abbuchung 12,34 EUR REWE."
                        ))
                    } else if account.name.caseInsensitiveCompare("Trade Republic") == .orderedSame {
                        Text(L(
                            "Apple-Kurzbefehl: Konto Trade Republic. Beispiel: 10,00 € bei Bäcker ausgegeben.",
                            "Apple Shortcut: account Trade Republic. Example: 10,00 € spent at Baker."
                        ))
                    } else {
                        Text(L(
                            "Die Kurzbefehle-App kennt Sparkasse und Trade Republic. Andere Girokonten buchen über den passenden Namen in der Mitteilung nicht von allein.",
                            "The Shortcuts app knows Sparkasse and Trade Republic. Other checking accounts are not chosen from the notice name alone."
                        ))
                    }
                }
            }
        }
        .appGlassList()
        .navigationTitle(L("Kurzbefehle", "Shortcuts"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $edited) { template in
            NoticeTemplateForm(template: template, accounts: checking) { saved in
                if let index = templates.firstIndex(where: { $0.id == saved.id }) {
                    templates[index] = saved
                } else {
                    templates.append(saved)
                }
                NoticeTemplateStore.save(templates)
            }
        }
        .sheet(isPresented: Binding(
            get: { creatingFor != nil },
            set: { if !$0 { creatingFor = nil } }
        )) {
            if let accountID = creatingFor {
                NoticeTemplateForm(
                    template: NoticeTemplate(accountID: accountID, name: "", example: "", action: .expense),
                    accounts: checking
                ) { saved in
                    templates.append(saved)
                    NoticeTemplateStore.save(templates)
                    creatingFor = nil
                }
            }
        }
    }
}

private struct NoticeTemplateForm: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    let onSave: (NoticeTemplate) -> Void
    @State private var template: NoticeTemplate

    init(
        template: NoticeTemplate,
        accounts: [Account],
        onSave: @escaping (NoticeTemplate) -> Void
    ) {
        self.accounts = accounts
        self.onSave = onSave
        _template = State(initialValue: template)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name", "Name"), text: $template.name)
                    Picker(L("Konto", "Account"), selection: $template.accountID) {
                        ForEach(accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Picker(L("Buchung", "Booking"), selection: $template.action) {
                        ForEach(NoticeTemplateAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    if template.action == .transferIn || template.action == .transferOut {
                        Picker(L("Gegenkonto", "Other account"), selection: Binding(
                            get: { template.counterpartyAccountID },
                            set: { template.counterpartyAccountID = $0 }
                        )) {
                            Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                            ForEach(otherAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                } header: {
                    Text(L("Was ausgeführt wird", "What to run"))
                }
                .appGlassRow()
                Section {
                    TextEditor(text: $template.example)
                        .frame(minHeight: 88)
                    if let preview = previewText {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("So sieht die Mitteilung aus", "What the notice looks like"))
                } footer: {
                    Text(L(
                        "Eine Beispielnachricht der Bank. Gleiche Wörter wie Abbuchung oder ausgegeben erkennen spätere Mitteilungen. Der Betrag kommt aus der neuen Nachricht.",
                        "An example bank notice. The same words, such as debit or spent, recognize later notices. The amount comes from the new message."
                    ))
                }
                .appGlassRow()
            }
            .appGlassList()
            .navigationTitle(L("Vorlage", "Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern", "Save")) {
                        onSave(template)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var otherAccounts: [Account] {
        accounts.filter { $0.id != template.accountID }
    }

    private var canSave: Bool {
        !template.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !NoticeTemplate.markers(in: template.example).isEmpty
    }

    private var previewText: String? {
        let accountName = accounts.first(where: { $0.id == template.accountID })?.name ?? ""
        guard let notice = BankNotice.parse(template.example, fallbackTitle: accountName) else {
            return L(
                "Im Beispiel steht noch kein Betrag mit Richtung.",
                "The example does not yet have an amount with a direction."
            )
        }
        return L(
            "Beispiel: \(template.action.label) · \(Money.string(cents: abs(notice.amountCents))) · \(notice.title)",
            "Example: \(template.action.label) · \(Money.string(cents: abs(notice.amountCents))) · \(notice.title)"
        )
    }
}
