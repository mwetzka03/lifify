import LififyCore
import LififyFinance
import SwiftUI

/// Shows Finance only after unlocking. While locked, the finance screens are not built at all.
struct FinanceLockGate<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: Content
    @Environment(FinanceLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FinanceLockSettings.enabledKey) private var isEnabled = true

    /// Prompts once when Finance is on screen and the app is active.
    private var promptKey: Bool {
        isSelected && scenePhase == .active
    }

    var body: some View {
        Group {
            if !isEnabled || lock.isUnlocked {
                content
            } else {
                lockedScreen
            }
        }
        .task(id: promptKey) {
            guard promptKey, isEnabled, !lock.didFail else { return }
            await lock.unlock()
        }
        .onChange(of: isSelected) {
            if isSelected { lock.allowPrompt() }
        }
    }

    /// The lock symbol with a button for another attempt.
    private var lockedScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L("Finanzen sind gesperrt", "Finance is locked"))
                .font(.headline)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label(L("Entsperren", "Unlock"), systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .liquidGlassSurface()
            }
            .buttonStyle(.plain)
            .disabled(lock.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appGlassCanvas()
    }
}
