import LififyCore
import SwiftUI

/// The app's loading animation: a turning arc in the style color around a softly pulsing dot, without a box.
///
/// With Reduce Motion the arc stands still and only the dot pulses gently.
struct LififyLoader: View {
    var text: String? = L("Wird geladen", "Loading")
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                ring(at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: size, height: size)
            if let text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text ?? L("Wird geladen", "Loading"))
    }

    private var accent: Color {
        AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
    }

    /// The arc, the track, and the dot at one moment of the animation.
    private func ring(at seconds: Double) -> some View {
        let turn = reduceMotion ? 0 : seconds.truncatingRemainder(dividingBy: 1.1) / 1.1
        let pulse = 0.75 + 0.25 * sin(seconds * 2 * .pi / 1.6)
        let line = max(size * 0.09, 3)
        return ZStack {
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(colors: [accent.opacity(0), accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(252)),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .rotationEffect(.degrees(turn * 360))
            Circle()
                .fill(accent.gradient)
                .frame(width: size * 0.28, height: size * 0.28)
                .scaleEffect(pulse)
                .opacity(0.6 + 0.4 * pulse)
        }
    }
}

/// The first screen while the app checks its data: the name in the style color above the loader.
struct LaunchScreen: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Text("Lifify")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .appAccentForeground()
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
            LififyLoader(text: nil, size: 36)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appGlassCanvas()
        .onAppear {
            withAnimation(.spring(duration: 0.6)) { appeared = true }
        }
    }
}
