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
        if #available(iOS 26.0, *) {
            if prominent {
                self.glassEffect(.regular.tint(Color.accentColor).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        }
    }
}
