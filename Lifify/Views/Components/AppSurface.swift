import SwiftUI

enum AppSurface {
    static var canvas: Color { Color(.systemGroupedBackground) }
    static var card: Color { Color(.secondarySystemGroupedBackground) }
}

extension View {
    func appCanvas() -> some View {
        background(AppSurface.canvas.ignoresSafeArea())
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
