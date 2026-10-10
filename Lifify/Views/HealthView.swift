import SwiftUI

struct HealthView: View {
    var body: some View {
        ContentUnavailableView(
            L("Demnächst verfügbar", "Coming soon"),
            systemImage: "apple.logo"
        )
    }
}
