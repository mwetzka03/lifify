import SwiftData
import SwiftUI

struct WalletView: View {
    @Query(sort: \CoinTransaction.date, order: .reverse) private var transactions: [CoinTransaction]
    @Query(sort: \RewardPurchase.date, order: .reverse) private var purchases: [RewardPurchase]

    var body: some View {
        List {
            Section {
                LabeledContent {
                    CoinAmountView(amount: ChallengeService.walletBalance(transactions: transactions))
                } label: {
                    Text(L("Guthaben", "Balance"))
                }
                LabeledContent(
                    L("Verdient", "Earned"),
                    value: "\(transactions.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount })"
                )
                LabeledContent(
                    L("Ausgegeben", "Spent"),
                    value: "\(abs(transactions.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }))"
                )
                LabeledContent(L("Käufe", "Purchases"), value: "\(purchases.count)")
            }

            Section(L("Transaktionen", "Transactions")) {
                ForEach(transactions) { transaction in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(transaction.title)
                            Text(transaction.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        CoinAmountView(
                            amount: transaction.amount,
                            showsPlus: transaction.amount > 0
                        )
                    }
                }
            }

            Section(L("Käufe", "Purchases")) {
                ForEach(purchases) { purchase in
                    LabeledContent {
                        CoinAmountView(amount: purchase.price)
                    } label: {
                        Text(purchase.title)
                    }
                }
            }
        }
        .navigationTitle(L("Wallet", "Wallet"))
    }
}
