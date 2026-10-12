import SwiftUI

enum AppSurface {
    static var canvas: Color { Color(.systemGroupedBackground) }
    static var card: Color { Color(.secondarySystemGroupedBackground) }
}

extension View {
    func appCanvas() -> some View {
        background(AppSurface.canvas.ignoresSafeArea())
    }
}
