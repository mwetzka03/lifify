import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var holdings: [PortfolioHolding]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @StateObject private var workouts = WorkoutStore()
    @StateObject private var financeFilters = FinanceFilterStore()
    @State private var selectedTab = 0
    @State private var financePath = NavigationPath()

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab.tag {
        case 1:
            NavigationStack(path: $financePath) {
                DashboardView(isMainTab: true, path: $financePath)
                    .navigationDestination(for: FinanceRoute.self) { FinanceRouteScreen(route: $0) }
            }
        case 2:
            NavigationStack { ChallengesView() }
        case 3:
            NavigationStack { HealthView() }
        case 4:
            NavigationStack { SettingsView() }
        default:
            NavigationStack { HomeView() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: theme) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTabs.items(), id: \.tag) { tab in
                tabRoot(tab)
                    .tabItem { Image(systemName: tab.symbol).accessibilityLabel(tab.title) }
                    .tag(tab.tag)
            }
        }
        .id(language)
        .environmentObject(workouts)
        .environmentObject(financeFilters)
        .preferredColorScheme(colorScheme)
        .appAccentTint()
        .task {
            SavingsPlanRunner.bookDue(context: context)
            SavingsPlanFixedCosts.sync(context: context)
            NutritionLedger.settle(context: context, sessions: workouts.sessions)
            await MarketDataService.refresh(holdings: holdings, context: context)
        }
        .onAppear { BirthdayBonusService.settle(context: context) }
        .onChange(of: developerMode) { BirthdayBonusService.settle(context: context) }
        .onChange(of: developerDay) { BirthdayBonusService.settle(context: context) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
            AppClock.rebaseSimulatedDayToCurrentTimeZone()
            Task {
                await DailyBriefingService.refresh(context: context)
                await DailyBriefingService.scheduleAbstinence(context: context)
                await DailyBriefingService.scheduleFollowUps(context: context)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await EventKitSyncService().sync(
                context: context,
                existingEvents: calendarEvents,
                existingChallenges: challenges,
                promptForAccess: false
            )
            AbstinenceService.settle(context: context)
            BirthdayBonusService.settle(context: context)
            await DailyBriefingService.refresh(context: context)
            await DailyBriefingService.scheduleAbstinence(context: context)
            await DailyBriefingService.scheduleFollowUps(context: context)
        }
    }
}
