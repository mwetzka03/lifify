import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// The IBANs and payee names whose bookings a variable cost or a pool takes on its own, typed or
/// picked from the payees of earlier bookings.
///
/// The picker opens through `payeeRulePicker(isPresented:rules:)` on the form itself: a sheet
/// attached to a row inside a form dismissed the whole form when it opened.
struct PayeeRulesSection: View {
    @Binding var rules: [String]
    @Binding var newRule: String
    @Binding var showingPicker: Bool

    var body: some View {
        Section {
            ForEach(rules, id: \.self) { rule in
                Label(rule, systemImage: BudgetPayeeRules.isIBAN(rule) ? "building.columns" : "textformat")
            }
            .onDelete { rules.remove(atOffsets: $0) }
            HStack {
                TextField(L("IBAN oder Name, z. B. REWE", "IBAN or name, e.g. REWE"), text: $newRule)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTypedRule)
                Button(L("Hinzufügen", "Add"), action: addTypedRule)
                    .disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button {
                showingPicker = true
            } label: {
                Label(L("Aus Buchungen wählen", "Pick from bookings"), systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text(L("Automatisch zuordnen", "Assign automatically"))
        } footer: {
            Text(L(
                "Ausgaben, deren Empfänger-IBAN passt oder deren Name den Text enthält, kommen hierher: beim Speichern alle bisherigen ohne Zuordnung, danach jede neue aus Bankimport und Mitteilungen. Einzelne Buchungen lassen sich jederzeit anders zuordnen.",
                "Expenses whose recipient IBAN fits or whose name contains the text land here: on saving all earlier ones without an assignment, then every new one from bank imports and notices. Single bookings can always be assigned differently."
            ))
        }
        .appGlassRow()
    }

    /// Adds the typed rule to the list.
    private func addTypedRule() {
        add(newRule)
        newRule = ""
    }

    /// Adds a rule unless it is empty or already there.
    private func add(_ rule: String) {
        PayeeRuleList.add(rule, to: &rules)
    }
}

/// Adds rules to a list without empty or repeated ones.
enum PayeeRuleList {
    /// Adds a rule unless it is empty or already there, ignoring case.
    static func add(_ rule: String, to rules: inout [String]) {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !rules.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        rules.append(trimmed)
    }
}

extension View {
    /// Presents the payee picker from the form, adding the picked payees as rules.
    func payeeRulePicker(isPresented: Binding<Bool>, rules: Binding<[String]>) -> some View {
        sheet(isPresented: isPresented) {
            PayeeRulePicker(existing: rules.wrappedValue) { picked in
                picked.forEach { PayeeRuleList.add($0, to: &rules.wrappedValue) }
            }
        }
    }
}

/// Lists the distinct payees of earlier expenses; each picked payee becomes a rule (its IBAN or name).
struct PayeeRulePicker: View {
    let existing: [String]
    let onPick: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [LedgerEntry]
    @State private var query = ""
    @State private var chosen: Set<String> = []
    @State private var groups: [PayeeGroup] = []

    /// The payees not yet used as a rule, filtered by the search text.
    private var shown: [PayeeGroup] {
        let used = Set(existing.map { $0.lowercased() })
        let text = query.trimmingCharacters(in: .whitespaces)
        return groups.filter { group in
            !used.contains(group.id)
                && (text.isEmpty || group.rule.localizedCaseInsensitiveContains(text) || group.sampleTitle.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    ForEach(shown) { group in
                        Button {
                            if chosen.contains(group.id) { chosen.remove(group.id) } else { chosen.insert(group.id) }
                        } label: {
                            payeeRow(group)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L(
                        "Ein Eintrag je Abbucher: die Empfänger-IBAN, sonst der Name. Beim Speichern werden alle bisherigen Buchungen dieses Abbuchers ohne Zuordnung übernommen.",
                        "One row per payee: the recipient IBAN, otherwise the name. On saving, all earlier bookings of the payee without an assignment are taken over."
                    ))
                }
            }
            .searchable(text: $query, prompt: L("Abbucher suchen", "Search payees"))
            .navigationTitle(L("Abbucher wählen", "Pick payees"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Übernehmen", "Add")) {
                        onPick(groups.filter { chosen.contains($0.id) }.map(\.rule))
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .task { groups = BudgetPayeeRules.payeeGroups(in: entries) }
        }
    }

    /// One payee with how often and when it was last paid.
    private func payeeRow(_ group: PayeeGroup) -> some View {
        HStack {
            Image(systemName: chosen.contains(group.id) ? "checkmark.circle.fill" : "circle")
                .appAccentForeground()
            VStack(alignment: .leading, spacing: 2) {
                Label(group.rule, systemImage: BudgetPayeeRules.isIBAN(group.rule) ? "building.columns" : "textformat")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(group.sampleTitle) · \(group.count)× · \(L("zuletzt", "last")) \(AppDate.numeric(group.lastDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Money.string(cents: -group.totalCents))
                .foregroundStyle(.red)
        }
    }
}
