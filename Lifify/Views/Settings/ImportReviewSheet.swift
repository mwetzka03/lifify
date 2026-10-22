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
                            "Gleicher Betrag, bekannte IBAN und ähnliches Datum. Nur angeschaltete Zeilen werden eine Umbuchung.",
                            "Same amount, known IBAN and a similar date. Only enabled rows become a transfer."
                        ))
                    }
                }
                if !review.similar.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach($review.similar) { $choice in
                                Toggle(isOn: $choice.include) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(choice.title.isEmpty ? L("Buchung", "Transaction") : choice.title)
                                        Text("\(Money.string(cents: choice.signedAmountCents)) · \(AppDate.numeric(choice.date))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(L("Vorhanden", "Already booked")): \(choice.existingTitle) · \(AppDate.numeric(choice.existingDate)) · \(Money.string(cents: choice.existingAmountCents))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            Text(L("Ähnliche Buchungen", "Similar transactions"))
                        }
                    } footer: {
                        Text(L(
                            "Doppelte Buchungen sind ausgelassen. Klappe die Liste auf, um eine trotzdem zu übernehmen.",
                            "Duplicate transactions are left out. Expand the list to import one anyway."
                        ))
                    }
                }
            }
            .navigationTitle(L("Import prüfen", "Review import"))
            .navigationBarTitleDisplayMode(.inline)
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
}
