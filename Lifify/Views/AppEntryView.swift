import SwiftData
import SwiftUI

struct AppEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("onboardingStep") private var onboardingStep = 0
    @AppStorage("appLanguage") private var language = "de"
    @State private var didCheckExistingInstallation = false

    var body: some View {
        Group {
            if !didCheckExistingInstallation {
                ProgressView()
            } else if hasCompletedOnboarding {
                RootView()
            } else {
                OnboardingView()
            }
        }
        .task {
            guard !didCheckExistingInstallation else { return }
            let hasMainAccount = accounts.contains(where: \.isMain)
            if hasCompletedOnboarding, !hasMainAccount {
                hasCompletedOnboarding = false
                onboardingInProgress = false
                onboardingStep = OnboardingResume.launchStep(isComplete: false, savedStep: onboardingStep)
            } else if !hasCompletedOnboarding {
                onboardingStep = OnboardingResume.launchStep(isComplete: false, savedStep: onboardingStep)
                if !onboardingInProgress, hasMainAccount {
                    hasCompletedOnboarding = true
                }
            }
            PortfolioConsolidation.consolidate(context: modelContext)
            TradeRepublicSample.purgeLegacyPreferences()
            didCheckExistingInstallation = true
        }
        .environment(\.locale, AppDate.locale)
        .id(language)
        .onOpenURL { url in
            BankNoticeIntake.open(url, context: modelContext)
        }
    }
}
