import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
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
    @State private var resumeLocked = false
    @State private var leftForeground = false

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
        .overlay {
            if resumeLocked {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(L("Wird geladen", "Loading"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            }
        }
        .task(id: scenePhase) {
            switch scenePhase {
            case .background, .inactive:
                leftForeground = true
                resumeLocked = true
            case .active:
                if leftForeground {
                    resumeLocked = true
                    await Task.yield()
                    await resumeForegroundWork()
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(250))
                    leftForeground = false
                    resumeLocked = false
                } else {
                    await resumeForegroundWork()
                }
            @unknown default:
                break
            }
        }
    }

    private func resumeForegroundWork() async {
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
