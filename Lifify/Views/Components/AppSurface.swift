import SwiftUI

enum AppSurface {
    static var canvas: Color { Color(.systemGroupedBackground) }
    static var card: Color { Color(.secondarySystemGroupedBackground) }
}

extension View {
    func appCanvas() -> some View {
        background(AppSurface.canvas.ignoresSafeArea())
    }

    /// Clear page behind Liquid Glass. The finance screens keep `appCanvas()`.
    func appGlassCanvas() -> some View {
        background(Color.clear.ignoresSafeArea())
    }

    func appGlassList() -> some View {
        scrollContentBackground(.hidden)
    }

    @ViewBuilder
    func appGlassCard(radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    func appText(_ role: AppTextRole) -> some View {
        font(AppChrome.font(role))
    }

    @ViewBuilder
    func liquidGlassSurface(prominent: Bool = false) -> some View {
        self
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0.22 : 0.12)))
            .clipShape(Capsule())
    }

    @ViewBuilder
    func boundedBubble(circle: Bool = false) -> some View {
        if circle {
            self
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.22)))
                .clipShape(Circle())
        } else {
            self.liquidGlassSurface()
        }
    }
}
