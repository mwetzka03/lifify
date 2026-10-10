import SwiftUI

struct HealthView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.fill").font(.system(size: 48))
            Text(L("Demnächst verfügbar", "Coming soon"))
                .font(.headline)
        }
        .foregroundStyle(.secondary)
    }
}
