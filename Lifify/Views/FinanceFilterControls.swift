import SwiftData
import SwiftUI

struct FinanceFilterControls: View {
    @EnvironmentObject private var filters: FinanceFilterStore
    let periods: [ForecastPeriod]
    let accounts: [Account]

    var body: some View {
        if let period = filters.period(in: periods) {
            VStack(spacing: 8) {
                periodBar(period)
                accountFilterBar
            }
        }
    }

    private func periodBar(_ period: ForecastPeriod) -> some View {
        let index = periods.firstIndex(of: period)
        return HStack(spacing: 8) {
            Button {
                withAnimation { filters.shiftPeriod(in: periods, by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(AppDate.range(from: period.start, to: period.end))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Button(L("Heute", "Today")) {
                    withAnimation { filters.jumpToToday(in: periods) }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .disabled(period.contains(.now))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { filters.shiftPeriod(in: periods, by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(index == periods.count - 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var accountFilterBar: some View {
        let bankAccounts = accounts.filter { $0.kind != .portfolio }
        let includesDepot = accounts.contains { $0.kind == .portfolio }
        let titles = AccountBubbleBar.titles(
            accountNames: bankAccounts.map(\.name),
            includesDepot: includesDepot
        )
        return EvenBubbleRow(spacing: 8, lineSpacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    chooseAccount(index: index, bankAccounts: bankAccounts, includesDepot: includesDepot)
                } label: {
                    ChoiceBubble(title: title, selected: accountSelected(index: index, bankAccounts: bankAccounts, includesDepot: includesDepot))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chooseAccount(index: Int, bankAccounts: [Account], includesDepot: Bool) {
        if index == 0 {
            filters.selectAllAccounts()
            return
        }
        let accountIndex = index - 1
        if accountIndex < bankAccounts.count {
            filters.select(account: bankAccounts[accountIndex].id)
            return
        }
        if includesDepot {
            filters.selectDepot()
        }
    }

    private func accountSelected(index: Int, bankAccounts: [Account], includesDepot: Bool) -> Bool {
        if filters.showsDepot {
            return includesDepot && index == bankAccounts.count + 1
        }
        if let selected = filters.account(in: accounts),
           let accountIndex = bankAccounts.firstIndex(where: { $0.id == selected.id }) {
            return index == accountIndex + 1
        }
        return index == 0
    }
}
