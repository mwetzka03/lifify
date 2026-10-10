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
            if !hasCompletedOnboarding,
               !onboardingInProgress,
               accounts.contains(where: \.isMain) {
                hasCompletedOnboarding = true
            }
            didCheckExistingInstallation = true
        }
    }
}
