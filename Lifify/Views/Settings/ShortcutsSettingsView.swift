import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI

/// The Shortcuts setup and notice templates.
struct ShortcutsSettingsView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var templates: [NoticeTemplate] = NoticeTemplateStore.all()
    @State private var edited: NoticeTemplate?
    @State private var creatingFor: UUID?

    private var named: [NamedAccount] {
        accounts.map { NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain) }
    }

    /// Turns a template on or off.
    private func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].isEnabled = enabled
        NoticeTemplateStore.save(templates)
    }

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
            Section(L("PayPal", "PayPal")) {
                Text(L(
                    "Automation „E-Mail“ in der Kurzbefehle-App: Absender service@paypal.de, Betreff enthält „Zahlung“. Aktion Bankmitteilung buchen, Konto PayPal, Mitteilung der Inhalt der E-Mail. Die Zahlung landet auf dem Konto PayPal; die spätere Lastschrift vom Girokonto wird zur Umbuchung zu PayPal.",
                    "Automation \"Email\" in the Shortcuts app: sender service@paypal.de, subject contains \"payment\". Run Record bank notice, account PayPal, notification as the email content. The payment lands on the PayPal account; the later direct debit from the checking account becomes a transfer to PayPal."
                ))
                Text(L(
                    "Für ältere Zahlungen: Aktivitäten in PayPal als CSV herunterladen und unter Finanzen › Bankimport öffnen. Lifify erkennt die PayPal-Datei und bucht auf das Konto PayPal.",
                    "For older payments: download your PayPal activity as CSV and open it under Finance › Bank import. Lifify recognizes the PayPal file and books onto the PayPal account."
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                        HStack(spacing: 12) {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(template.isEnabled ? 1 : 0.5)
                            Toggle(L("Aktiv", "Active"), isOn: Binding(
                                get: { template.isEnabled },
                                set: { setEnabled($0, for: template.id) }
                            ))
                            .labelsHidden()
                        }
                        .appGlassRow()
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { rows[$0].id })
                        templates = NoticeTemplateDefaults.delete(ids, from: templates)
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
        .task(id: accounts.count) {
            templates = NoticeTemplateDefaults.install(accounts: named)
        }
        .sheet(item: $edited) { template in
            NoticeTemplateForm(template: template, accounts: checking) { edited in
                let saved = NoticeTemplateDefaults.detachedIfEdited(edited)
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

/// Creates or edits a template.
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
            AppForm {
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
        guard !template.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let format = template.format, format.example == template.example { return true }
        return !NoticeTemplate.markers(in: template.example).isEmpty
    }

    private var previewText: String? {
        if template.action == .ignore {
            return L("Diese Mitteilung wird nicht gebucht.", "This notice is not booked.")
        }
        let accountName = accounts.first(where: { $0.id == template.accountID })?.name ?? ""
        let unchanged = template.format?.example == template.example
        let parsed = unchanged ? template.format?.parse(template.example) : BankNotice.parse(template.example, fallbackTitle: accountName)
        guard let notice = parsed else {
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
