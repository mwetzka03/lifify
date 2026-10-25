import SwiftData
import SwiftUI

struct ShopView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \RewardItem.title) private var rewards: [RewardItem]
    @Query(sort: \CoinTransaction.date, order: .reverse) private var transactions: [CoinTransaction]
    @Query private var purchases: [RewardPurchase]
    @Query(sort: \ChallengeItem.title) private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @AppStorage(StreakSettings.revisionKey) private var streakRevision = 0
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
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

    private var streakChallenges: [ChallengeItem] {
        let _ = streakRevision
        return challenges
            .filter { !$0.isArchived && StreakSettings.isEnabled(for: $0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if activeRewards.isEmpty && streakChallenges.isEmpty {
                ContentUnavailableView(L("Der Shop ist leer", "The shop is empty"), systemImage: "gift")
                    .padding(.top, 48)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !streakChallenges.isEmpty {
                        freezeSection
                    }
                    if activeRewards.isEmpty {
                        ContentUnavailableView(L("Keine Belohnungen", "No rewards"), systemImage: "gift")
                            .padding(.top, 12)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(activeRewards) { reward in
                                rewardTile(reward)
                            }
                        }
                        .padding(16)
                    }
                }
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

    private var freezeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Streak-Freezes", "Streak freezes"))
                .font(.headline)
            Text(L(
                "Jede Challenge mit Streaks startet mit zwei Freezes. Eine weitere kostet das Zehnfache der Belohnung und gilt nur für diese Challenge.",
                "Each challenge with streaks starts with two freezes. Another one costs ten times the reward and applies only to that challenge."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(streakChallenges) { challenge in
                freezeRow(challenge)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func freezeRow(_ challenge: ChallengeItem) -> some View {
        let _ = developerMode
        let _ = developerDay
        let today = AppClock.now
        let balance = ChallengeService.freezeBalance(
            for: challenge,
            completions: completions,
            events: calendarEvents,
            on: today
        )
        let streak = ChallengeService.status(
            for: challenge,
            endingOn: today,
            completions: completions,
            events: calendarEvents
        ).count
        let price = StreakSettings.price(for: challenge)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(L("Serie", "Streak")) \(streak) · \(L("Freezes", "Freezes")) \(balance)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                message = ChallengeService.purchaseFreeze(challenge: challenge, transactions: transactions, context: context)
                    ? L("Streak-Freeze gekauft.", "Streak freeze purchased.")
                    : L("Nicht genug Coins.", "Not enough coins.")
            } label: {
                HStack(spacing: 4) {
                    Text(L("Kaufen", "Buy"))
                    CoinAmountView(amount: price)
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rewardTile(_ reward: RewardItem) -> some View {
        let accent = rewardAccent(reward)
        return VStack(alignment: .leading, spacing: 0) {
            Button { edited = reward } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: reward.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(reward.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    CoinAmountView(amount: reward.price, tint: .white)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                if let url = rewardURL(reward) {
                    Button { openURL(url) } label: {
                        Label(reward.urlString, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Text(redemptionLabel(purchases.filter { $0.rewardID == reward.id }.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !reward.details.isEmpty {
                    Text(reward.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
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
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
            if let url = rewardURL(reward) {
                Button { openURL(url) } label: {
                    Label("Link", systemImage: "safari")
                }
            }
            Button(role: .destructive) {
                deleteReward(reward)
            } label: {
                Label(L("Löschen", "Delete"), systemImage: "trash")
            }
        }
    }

    private func deleteReward(_ reward: RewardItem) {
        RewardPolicyStore.remove(for: reward.id)
        context.delete(reward)
        try? context.save()
    }

    private func rewardURL(_ reward: RewardItem) -> URL? {
        let raw = reward.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme != nil { return url }
        return URL(string: "https://\(raw)")
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
    @State private var confirmDelete = false

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
                if existing != nil {
                    Section {
                        Button(L("Belohnung löschen", "Delete reward"), role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(L("Belohnung", "Reward"))
            .confirmationDialog(
                L("Belohnung löschen?", "Delete reward?"),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(L("Löschen", "Delete"), role: .destructive) {
                    guard let existing else { return }
                    RewardPolicyStore.remove(for: existing.id)
                    context.delete(existing)
                    try? context.save()
                    dismiss()
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            } message: {
                Text(L(
                    "Die Belohnung verschwindet aus dem Shop. Bereits verbrauchte Coins bleiben verbucht.",
                    "The reward leaves the shop. Coins already spent stay on the record."
                ))
            }
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
