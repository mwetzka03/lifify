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
        VStack(alignment: .leading, spacing: 10) {
            Button { edited = reward } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: reward.icon)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(reward.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !reward.details.isEmpty {
                        Text(reward.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(redemptionLabel(purchases.filter { $0.rewardID == reward.id }.count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CoinAmountView(amount: reward.price)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                message = ChallengeService.purchase(reward: reward, transactions: transactions, context: context)
                    ? L("Belohnung gekauft.", "Reward purchased.")
                    : L("Nicht genug Coins.", "Not enough coins.")
            } label: {
                Text(L("Einlösen", "Redeem"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
}
private struct RewardForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let existing: RewardItem?
    @State private var title: String
    @State private var details: String
    @State private var price: Int
    @State private var url: String
    @State private var icon: String
    @State private var allowsMultiple: Bool

    init(reward: RewardItem?) {
        existing = reward
        _title = State(initialValue: reward?.title ?? "")
        _details = State(initialValue: reward?.details ?? "")
        _price = State(initialValue: reward?.price ?? 100)
        _url = State(initialValue: reward?.urlString ?? "")
        _icon = State(initialValue: reward?.icon ?? "gift")
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
                        if existing == nil { context.insert(reward) }
                        RewardPolicyStore.setAllowsMultiplePurchases(allowsMultiple, for: reward.id)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
