import SwiftData
import SwiftUI

struct ShopView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    @Query(sort: \CoinTransaction.date, order: .reverse) private var transactions: [CoinTransaction]
    @State private var showingNew = false
    @State private var edited: RewardItem?
    @State private var message: String?

    var body: some View {
        List {
            Section(L("Shop", "Shop")) {
                if rewards.filter(\.isActive).isEmpty {
                    Text(L("Der Shop ist leer", "The shop is empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(rewards.filter(\.isActive)) { reward in
                    Button {
                        edited = reward
                    } label: {
                        HStack {
                            Image(systemName: reward.icon)
                                .font(.title2)
                                .frame(width: 38)
                            VStack(alignment: .leading) {
                                Text(reward.title).foregroundStyle(.primary)
                                if !reward.details.isEmpty {
                                    Text(reward.details).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            CoinAmountView(amount: reward.price)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            message = ChallengeService.purchase(reward: reward, transactions: transactions, context: context)
                                ? L("Belohnung gekauft.", "Reward purchased.")
                                : L("Nicht genug Coins.", "Not enough coins.")
                        } label: {
                            Label(L("Kaufen", "Buy"), systemImage: "cart")
                        }
                        .tint(.green)
                        if let url = URL(string: reward.urlString), !reward.urlString.isEmpty {
                            Button { openURL(url) } label: { Label("Link", systemImage: "safari") }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { rewards.filter(\.isActive)[$0] }.forEach { $0.isActive = false }
                    try? context.save()
                }
            }
        }
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

    init(reward: RewardItem?) {
        existing = reward
        _title = State(initialValue: reward?.title ?? "")
        _details = State(initialValue: reward?.details ?? "")
        _price = State(initialValue: reward?.price ?? 100)
        _url = State(initialValue: reward?.urlString ?? "")
        _icon = State(initialValue: reward?.icon ?? "gift")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Titel", "Title"), text: $title)
                TextField(L("Beschreibung", "Description"), text: $details, axis: .vertical)
                Stepper(value: $price, in: 0...100_000) {
                    HStack {
                        Text("\(L("Preis", "Price")):")
                        CoinAmountView(amount: price)
                    }
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
                        reward.price = price
                        reward.urlString = url
                        reward.icon = icon
                        if existing == nil { context.insert(reward) }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
