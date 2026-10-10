import SwiftData
import SwiftUI

struct AppEntryView: View {
    @Query private var accounts: [Account]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
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
            } else if !hasCompletedOnboarding,
                      !onboardingInProgress,
                      hasMainAccount {
                hasCompletedOnboarding = true
            }
            didCheckExistingInstallation = true
        }
    }
}
