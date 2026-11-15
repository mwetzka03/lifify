import SwiftUI

struct ImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var review: ImportReview
    private let onCommit: (ImportReview) -> Void

    init(review: ImportReview, onCommit: @escaping (ImportReview) -> Void) {
        _review = State(initialValue: review)
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            List {
                if !review.transfers.isEmpty {
                    Section {
                        ForEach($review.transfers) { $choice in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(choice.title.isEmpty ? L("Umbuchung", "Transfer") : choice.title)
                                    .font(.body.weight(.semibold))
                                Text("\(Money.string(cents: abs(choice.signedAmountCents))) · \(AppDate.numeric(choice.date))")
                                    .font(.subheadline)
                                Text("\(choice.otherAccountName) · \(choice.iban)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(L("Passende Buchung", "Matching transaction")): \(choice.matchedTitle) · \(AppDate.numeric(choice.matchedDate)) · \(Money.string(cents: abs(choice.matchedAmountCents)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Toggle(L("Als Umbuchung buchen", "Book as a transfer"), isOn: $choice.accept)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(L("Mögliche Umbuchung", "Possible transfer"))
                    } footer: {
                        Text(L(
                            "Gleicher Betrag und bekannte IBAN. Nur angeschaltete Zeilen werden eine Umbuchung.",
                            "Same amount and a known IBAN. Only enabled rows become a transfer."
                        ))
                    }
                    .appGlassRow()
                }
                if review.similar.contains(where: \.isExtra) {
                    Section {
                        ForEach($review.similar) { $choice in
                            if choice.isExtra {
                                similarToggle($choice)
                            }
                        }
                    } header: {
                        Text(L("Noch nicht gebucht", "Not booked yet"))
                    } footer: {
                        Text(L(
                            "An diesem Tag hat die Datei mehr Zeilen als das Konto. Übernehmen ist an. Ausschalten lässt die Zeile weg.",
                            "This day has more rows in the file than on the account. Import is on. Turn it off to leave the row out."
                        ))
                    }
                    .appGlassRow()
                }
                if review.similar.contains(where: { !$0.isExtra }) {
                    Section {
                        DisclosureGroup {
                            ForEach($review.similar) { $choice in
                                if !choice.isExtra {
                                    similarToggle($choice)
                                }
                            }
                        } label: {
                            Text(L("Ähnliche Buchungen", "Similar transactions"))
                        }
                    } footer: {
                        Text(L(
                            "Gleicher Empfänger, gleicher Betrag, nahes Datum. Klappe die Liste auf, um eine trotzdem zu übernehmen.",
                            "Same payee, same amount, nearby date. Expand the list to import one anyway."
                        ))
                    }
                    .appGlassRow()
                }
            }
            .appGlassList()
            .navigationTitle(L("Import prüfen", "Review import"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Übernehmen", "Apply")) {
                        onCommit(review)
                        dismiss()
                    }
                }
            }
        }
    }

    private func similarToggle(_ choice: Binding<ImportSimilarChoice>) -> some View {
        Toggle(isOn: choice.include) {
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.wrappedValue.title.isEmpty ? L("Buchung", "Transaction") : choice.wrappedValue.title)
                Text("\(Money.string(cents: choice.wrappedValue.signedAmountCents)) · \(AppDate.numeric(choice.wrappedValue.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(L("Vorhanden", "Already booked")): \(choice.wrappedValue.existingTitle) · \(AppDate.numeric(choice.wrappedValue.existingDate)) · \(Money.string(cents: choice.wrappedValue.existingAmountCents))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
