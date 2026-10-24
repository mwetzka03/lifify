import SwiftData
import SwiftUI

struct ShopView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    @Query(sort: \CoinTransaction.date, order: .reverse) private var transactions: [CoinTransaction]
    @Query private var purchases: [RewardPurchase]
    @State private var showingNew = false
    @State private var edited: RewardItem?
    @State private var message: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeRewards: [RewardItem] {
        rewards.filter(\.isActive)
    }

    var body: some View {
        ScrollView {
            if activeRewards.isEmpty {
                ContentUnavailableView(L("Der Shop ist leer", "The shop is empty"), systemImage: "gift")
                    .padding(.top, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(activeRewards) { reward in
                        rewardTile(reward)
                    }
                }
                .padding(16)
            }
        }
        .appCanvas()
        .navigationTitle(L("Shop", "Shop"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { RewardForm(reward: nil) }
        .sheet(item: $edited) { RewardForm(reward: $0) }
        .alert(L("Shop", "Shop"), isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func rewardTile(_ reward: RewardItem) -> some View {
        let accent = rewardAccent(reward)
        return VStack(alignment: .leading, spacing: 0) {
            Button { edited = reward } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: reward.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Spacer(minLength: 0)
                        Text(redemptionLabel(purchases.filter { $0.rewardID == reward.id }.count))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                    .background(accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reward.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !reward.details.isEmpty {
                            Text(reward.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        CoinAmountView(amount: reward.price)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Button {
                message = ChallengeService.purchase(reward: reward, transactions: transactions, context: context)
                    ? L("Belohnung gekauft.", "Reward purchased.")
                    : L("Nicht genug Coins.", "Not enough coins.")
            } label: {
                Text(L("Einlösen", "Redeem"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 276, maxHeight: 276, alignment: .top)
        .background(AppSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1)
        )
        .contextMenu {
            Button { edited = reward } label: {
                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
            }
            if let url = URL(string: reward.urlString), !reward.urlString.isEmpty {
                Button { openURL(url) } label: {
                    Label("Link", systemImage: "safari")
                }
            }
            Button(role: .destructive) {
                reward.isActive = false
                try? context.save()
            } label: {
                Label(L("Entfernen", "Remove"), systemImage: "trash")
            }
        }
    }

    private func redemptionLabel(_ count: Int) -> String {
        if count == 1 { return L("1× eingelöst", "Redeemed once") }
        return "\(count)× \(L("eingelöst", "redeemed"))"
    }

    private func rewardAccent(_ reward: RewardItem) -> Color {
        let stored = reward.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, stored.caseInsensitiveCompare("#C78335") != .orderedSame, let custom = color(hex: stored) {
            return custom
        }
        return color(hex: rewardPalette[paletteIndex(reward.id)]) ?? Color(red: 0.78, green: 0.51, blue: 0.21)
    }

    private func paletteIndex(_ id: UUID) -> Int {
        var total = 0
        for scalar in id.uuidString.unicodeScalars {
            total = (total + Int(scalar.value)) % rewardPalette.count
        }
        return total
    }

    private func color(hex: String) -> Color? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private let rewardPalette = [
    "#C45C6A", "#4F7CAC", "#2F9E7A", "#E09A3E", "#7B61A8", "#3D8B8B", "#D4783A", "#5B6EAE"
]
private struct RewardForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let existing: RewardItem?
    @State private var title: String
    @State private var details: String
    @State private var price: Int
    @State private var url: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var allowsMultiple: Bool

    init(reward: RewardItem?) {
        existing = reward
        _title = State(initialValue: reward?.title ?? "")
        _details = State(initialValue: reward?.details ?? "")
        _price = State(initialValue: reward?.price ?? 100)
        _url = State(initialValue: reward?.urlString ?? "")
        _icon = State(initialValue: reward?.icon ?? "gift")
        _colorHex = State(initialValue: reward?.colorHex ?? rewardPalette[0])
        _allowsMultiple = State(initialValue: reward.map { RewardPolicyStore.allowsMultiplePurchases(for: $0.id) } ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                LabeledContent(L("Preis", "Price")) {
                    TextField("0", value: $price, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker(L("Einlösbarkeit", "Redemption"), selection: $allowsMultiple) {
                    Text(L("Einmalig", "One-time")).tag(false)
                    Text(L("Mehrmals", "Repeatable")).tag(true)
                }
                TextField("URL", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                SymbolPicker(title: L("Symbol", "Icon"), selection: $icon)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Farbe", "Color"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(rewardPalette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(rewardColor(hex))
                                    .frame(height: 32)
                                    .overlay {
                                        if colorHex.caseInsensitiveCompare(hex) == .orderedSame {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(L("Belohnung", "Reward"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !title.isEmpty else { return }
                        let reward = existing ?? RewardItem(title: title, price: price)
                        reward.title = title
                        reward.details = details
                        reward.price = max(price, 0)
                        reward.urlString = url
                        reward.icon = icon
                        reward.colorHex = colorHex
                        if existing == nil { context.insert(reward) }
                        RewardPolicyStore.setAllowsMultiplePurchases(allowsMultiple, for: reward.id)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func rewardColor(_ hex: String) -> Color {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return Color(red: 0.78, green: 0.51, blue: 0.21)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
