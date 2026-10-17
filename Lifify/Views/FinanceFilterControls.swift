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
                    .frame(width: 40, height: 40)
            }
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
                .disabled(period.contains(.now))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { filters.shiftPeriod(in: periods, by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .disabled(index == periods.count - 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var accountFilterBar: some View {
        Menu {
            Button(L("Alle Konten", "All accounts")) { filters.selectAllAccounts() }
            ForEach(accounts.filter { $0.kind != .portfolio }) { account in
                Button(account.name) { filters.select(account: account.id) }
            }
            if accounts.contains(where: { $0.kind == .portfolio }) {
                Button(L("Depot", "Portfolio")) { filters.selectDepot() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var selectedTitle: String {
        if filters.showsDepot { return L("Depot", "Portfolio") }
        return filters.account(in: accounts)?.name ?? L("Alle Konten", "All accounts")
    }
}
