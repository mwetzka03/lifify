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
                    "In der Kurzbefehle-App: Wenn eine Mitteilung kommt, Aktion Bankmitteilung buchen, Konto Sparkasse oder Trade Republic, Mitteilung der Nachrichtentext. Hier fügst du die Mitteilung 1:1 ein. Darunter entsteht die Vorlage, und du wählst die Buchung, auch Depotkauf, Verkauf, Dividende oder Zinsen.",
                    "In the Shortcuts app: when a notice arrives, run Record bank notice, account Sparkasse or Trade Republic, notification as the text. Paste the notice here 1:1. The template appears below, and you choose the booking, including a portfolio buy, sale, dividend, or interest."
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
                                Text(NoticeTemplate.displayPattern(from: template.example))
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
                            "Apple-Kurzbefehl: Konto Trade Republic. Neben Ausgaben auch Depotkauf, Verkauf, Dividende und Zinsen.",
                            "Apple Shortcut: account Trade Republic. Besides expenses, also portfolio buy, sale, dividend, and interest."
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
            NoticeTemplateForm(template: template, accounts: accounts) { saved in
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
                    accounts: accounts
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
                        ForEach(checkingAccounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Picker(L("Buchung", "Booking"), selection: $template.action) {
                        ForEach(NoticeTemplateAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    if template.action.needsCounterparty {
                        Picker(counterpartyTitle, selection: Binding(
                            get: { template.counterpartyAccountID },
                            set: { template.counterpartyAccountID = $0 }
                        )) {
                            Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                            ForEach(counterparties) { account in
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
                } header: {
                    Text(L("So sieht die Mitteilung aus", "What the notice looks like"))
                } footer: {
                    Text(L(
                        "Die Bankmitteilung 1:1, mit Betrag und Namen. Darunter entsteht die Vorlage.",
                        "The bank notice 1:1, with amount and names. The template appears below."
                    ))
                }
                .appGlassRow()
                Section {
                    if !pattern.isUsable {
                        Text(L(
                            "Noch keine Vorlage. Sobald ein Betrag in der Mitteilung steht, erscheint sie hier.",
                            "No template yet. It appears here as soon as the notice has an amount."
                        ))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(pattern.display)
                        if let preview = bookingPreview {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Vorlage", "Template"))
                } footer: {
                    Text(L(
                        "Diese Vorlage wird für neue Mitteilungen benutzt. Der Betrag kommt aus der neuen Nachricht. Ein Depotverkauf landet auf dem Giro und geht vom Depotwert ab. Die Stückzahl kommt weiter aus der Anmeldung.",
                        "This template is used for new notices. The amount comes from the new message. A portfolio sale lands on checking and leaves the depot value. The share count still comes from sign-in."
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
            .onAppear { fillCounterparty(template.action) }
            .onChange(of: template.action) { _, action in
                fillCounterparty(action)
            }
            .onChange(of: template.accountID) { _, _ in
                fillCounterparty(template.action)
            }
        }
    }

    private var checkingAccounts: [Account] {
        accounts.filter { $0.kind == .checking }
    }

    private var counterparties: [Account] {
        if template.action.needsPortfolioCounterparty {
            return accounts.filter { $0.kind == .portfolio }
        }
        return accounts.filter { $0.kind == .checking && $0.id != template.accountID }
    }

    private var counterpartyTitle: String {
        if template.action.needsPortfolioCounterparty {
            return L("Depot", "Portfolio")
        }
        return L("Gegenkonto", "Other account")
    }

    private var pattern: NoticePattern {
        NoticePattern.from(example: template.example)
    }

    private var canSave: Bool {
        guard pattern.isUsable else { return false }
        if template.action.needsCounterparty, !counterparties.isEmpty {
            return template.counterpartyAccountID != nil
        }
        return true
    }

    private var bookingPreview: String? {
        let accountName = accounts.first(where: { $0.id == template.accountID })?.name ?? ""
        guard let notice = BankNotice.parse(
            template.example,
            fallbackTitle: accountName,
            defaultDirection: template.action.direction
        ) else {
            return L(
                "Im Beispiel steht noch kein Betrag.",
                "The example does not yet have an amount."
            )
        }
        return L(
            "Buchung: \(template.action.label) · \(Money.string(cents: abs(notice.amountCents))) · \(notice.title)",
            "Booking: \(template.action.label) · \(Money.string(cents: abs(notice.amountCents))) · \(notice.title)"
        )
    }

    private func fillCounterparty(_ action: NoticeTemplateAction) {
        if action.needsPortfolioCounterparty {
            let portfolios = accounts.filter { $0.kind == .portfolio }
            if let current = template.counterpartyAccountID, portfolios.contains(where: { $0.id == current }) {
                return
            }
            if let linked = PortfolioLinkStore.portfolioID(for: template.accountID),
               portfolios.contains(where: { $0.id == linked }) {
                template.counterpartyAccountID = linked
            } else {
                template.counterpartyAccountID = portfolios.first?.id
            }
        } else if action.needsCheckingCounterparty {
            let others = accounts.filter { $0.kind == .checking && $0.id != template.accountID }
            if let current = template.counterpartyAccountID, others.contains(where: { $0.id == current }) {
                return
            }
            template.counterpartyAccountID = others.first?.id
        }
    }
}
