import SwiftUI

struct CoinAmountView: View {
    let amount: Int
    var showsPlus = false
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "c.circle.fill")
            Text("\(showsPlus && amount > 0 ? "+" : "")\(amount)")
                .monospacedDigit()
        }
        .foregroundStyle(tint)
    }
}
