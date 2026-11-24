import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Combine
import SwiftData
import SwiftUI

/// The tab bar with the work that runs around it.
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
    @State private var healthPath = NavigationPath()
    @State private var financeLock = FinanceLock()
    @State private var resumeLocked = false
    @State private var leftForeground = false

    /// The root screen of a tab.
    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab.tag {
        case 1:
            FinanceLockGate(isSelected: selectedTab == tab.tag) {
                NavigationStack(path: $financePath) {
                    DashboardView(isMainTab: true, path: $financePath)
                        .navigationDestination(for: FinanceRoute.self) { FinanceRouteScreen(route: $0) }
                }
            }
        case 2:
            NavigationStack { ChallengesView() }
        case 3:
            NavigationStack(path: $healthPath) { HealthView() }
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
        .environment(financeLock)
        .preferredColorScheme(colorScheme)
        .appAccentTint()
        .task {
            SavingsPlanRunner.bookDue(context: context)
            SavingsPlanFixedCosts.sync(context: context)
            NutritionLedger.settle(context: context, sessions: workouts.sessions)
            WidgetPublisher.refresh(context: context, plans: workouts.plans)
            await MarketDataService.refresh(holdings: holdings, context: context)
        }
        .onAppear {
            BirthdayBonusService.settle(context: context)
            openNotificationRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationRoute.didChange)) { _ in
            openNotificationRoute()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        ) { _ in
            Task {
                await BudgetAlertService.check(context: context)
                await DailyBriefingService.scheduleFollowUps(context: context, sessions: workouts.sessions)
            }
            WidgetPublisher.refresh(context: context, plans: workouts.plans)
        }
        .onChange(of: developerMode) { BirthdayBonusService.settle(context: context) }
        .onChange(of: developerDay) { BirthdayBonusService.settle(context: context) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
            AppClock.rebaseSimulatedDayToCurrentTimeZone()
            Task {
                await DailyBriefingService.refresh(context: context)
                await DailyBriefingService.scheduleAbstinence(context: context)
                await DailyBriefingService.scheduleFollowUps(context: context, sessions: workouts.sessions)
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
                if scenePhase == .background { financeLock.lock() }
                // The Face ID prompt makes the app inactive. That is not leaving the app.
                guard scenePhase == .background || !financeLock.isAuthenticating else { break }
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

    /// Opens the screen of a tapped notification. Finance stays behind its lock.
    private func openNotificationRoute() {
        let route = NotificationRoute.take()
        if let plan = WidgetRoute.plan(in: route) {
            openTraining(plan)
        } else if route == PeriodReviewNotifier.route {
            selectedTab = 1
            financePath.append(FinanceRoute.periodReview)
        }
    }

    /// Opens a training from a widget. A session already on screen is never replaced.
    private func openTraining(_ plan: UUID) {
        selectedTab = 3
        guard healthPath.isEmpty else { return }
        healthPath.append(HealthRoute.session(plan))
    }

    /// Announces a newly finished period, when that is turned on.
    private func announcePeriodReview() async {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let inputs = PeriodReviewBuilder.Inputs(entries: entries, splits: [], costs: [], budgets: [], pools: [])
        let periods = PeriodReviewBuilder.periods(
            mode: AppDefaults.store.string(forKey: "dashboardPeriodMode") ?? DashboardPeriodMode.calendarMonth.rawValue,
            entries: entries,
            forecasts: (try? context.fetch(FetchDescriptor<IncomeForecast>())) ?? [],
            accounts: (try? context.fetch(FetchDescriptor<Account>())) ?? []
        )
        if let period = PeriodReviewNotifier.periodToAnnounce(PeriodReviewBuilder.make(inputs, periods: periods)?.period) {
            await PeriodReviewNotifier.announce(period)
        }
    }

    /// Refreshes calendar, bonuses, and notifications on return.
    private func resumeForegroundWork() async {
        WidgetPublisher.refresh(context: context, plans: workouts.plans)
        await announcePeriodReview()
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
        await DailyBriefingService.scheduleFollowUps(context: context, sessions: workouts.sessions)
    }
}
