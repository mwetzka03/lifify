import SwiftData
import SwiftUI

struct LiveLifeHubView: View {
    @Query private var transactions: [CoinTransaction]

    var body: some View {
        List {
            Section {
                LabeledContent(L("Coin-Guthaben", "Coin balance"), value: "\(LiveLifeService.walletBalance(transactions: transactions))")
            }
            NavigationLink { LifeCalendarView() } label: {
                Label(L("Kalender", "Calendar"), systemImage: "calendar")
            }
            NavigationLink { ChallengesView() } label: {
                Label(L("Challenges", "Challenges"), systemImage: "target")
            }
            NavigationLink { VisionBoardView() } label: {
                Label(L("Visionboard & Bucketlist", "Vision board & bucket list"), systemImage: "rectangle.3.group")
            }
            NavigationLink { ShopView() } label: {
                Label(L("Belohnungsshop", "Reward shop"), systemImage: "gift")
            }
            NavigationLink { WalletView() } label: {
                Label(L("Wallet", "Wallet"), systemImage: "wallet.bifold")
            }
        }
        .navigationTitle("Live Life")
    }
}
