import SwiftUI

struct HealthView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🍎").font(.system(size: 54))
            Text(L("Demnächst verfügbar", "Coming soon"))
                .font(.headline)
        }
        .foregroundStyle(.secondary)
    }
}
