import SwiftUI

enum AppSurface {
    static var canvas: Color { Color(.systemGroupedBackground) }
    static var card: Color { Color(.secondarySystemGroupedBackground) }
}

enum AppAppearance: String, Equatable, CaseIterable {
    case light
    case dark

    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

struct AppColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var brightness: Double { ((red + green + blue) / 3) * opacity }

    func color() -> Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }
}

/// Light and dark each have their own paint. Finance uses the same wash.
enum AppLook {
    static func canvasTop(_ appearance: AppAppearance) -> AppColor {
        switch appearance {
        case .light: AppColor(red: 0.78, green: 0.94, blue: 0.86, opacity: 1)
        case .dark: AppColor(red: 0.04, green: 0.10, blue: 0.09, opacity: 1)
        }
    }

    static func canvasBottom(_ appearance: AppAppearance) -> AppColor {
        switch appearance {
        case .light: AppColor(red: 0.99, green: 0.91, blue: 0.82, opacity: 1)
        case .dark: AppColor(red: 0.05, green: 0.06, blue: 0.11, opacity: 1)
        }
    }

    static func orb(_ appearance: AppAppearance, index: Int) -> AppColor {
        switch (appearance, index) {
        case (.light, 0): AppColor(red: 0.42, green: 0.82, blue: 0.60, opacity: 0.55)
        case (.light, _): AppColor(red: 0.98, green: 0.68, blue: 0.48, opacity: 0.42)
        case (.dark, 0): AppColor(red: 0.10, green: 0.48, blue: 0.34, opacity: 0.75)
        case (.dark, _): AppColor(red: 0.55, green: 0.32, blue: 0.12, opacity: 0.50)
        }
    }

    static func cardFill(_ appearance: AppAppearance) -> AppColor {
        switch appearance {
        case .light: AppColor(red: 0.98, green: 0.99, blue: 0.97, opacity: 0.94)
        case .dark: AppColor(red: 0.16, green: 0.22, blue: 0.20, opacity: 0.94)
        }
    }

    static func cardStroke(_ appearance: AppAppearance) -> AppColor {
        switch appearance {
        case .light: AppColor(red: 1, green: 1, blue: 1, opacity: 0.85)
        case .dark: AppColor(red: 0.62, green: 0.88, blue: 0.72, opacity: 0.28)
        }
    }

    static func accent(_ appearance: AppAppearance) -> AppColor {
        switch appearance {
        case .light: AppColor(red: 0.12, green: 0.58, blue: 0.38, opacity: 1)
        case .dark: AppColor(red: 0.49, green: 0.86, blue: 0.66, opacity: 1)
        }
    }

    static func modesDiffer() -> Bool {
        let lightTop = canvasTop(.light)
        let darkTop = canvasTop(.dark)
        let lightCard = cardFill(.light)
        let darkCard = cardFill(.dark)
        return lightTop != darkTop
            && lightCard != darkCard
            && lightTop.brightness > 0.75
            && darkTop.brightness < 0.2
            && lightCard.opacity > 0.8
            && darkCard.opacity > 0.8
            && darkCard.brightness < 0.35
            && lightCard.brightness > 0.8
    }
}

struct AppPlayfulCanvas: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let appearance = AppAppearance(scheme)
        ZStack {
            LinearGradient(
                colors: [AppLook.canvasTop(appearance).color(), AppLook.canvasBottom(appearance).color()],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppLook.orb(appearance, index: 0).color())
                .frame(width: 280, height: 280)
                .blur(radius: 24)
                .offset(x: -140, y: -260)
            Circle()
                .fill(AppLook.orb(appearance, index: 1).color())
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: 170, y: 320)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appCanvas() -> some View {
        background(AppSurface.canvas.ignoresSafeArea())
    }

    /// Tinted page for every screen except Finance.
    func appGlassCanvas() -> some View {
        background(AppPlayfulCanvas())
    }

    func appGlassList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background(AppPlayfulCanvas())
    }

    func appGlassRow() -> some View {
        listRowBackground(AppGlassRowFill())
    }

    func appGlassCard(radius: CGFloat = 22) -> some View {
        modifier(AppGlassCardModifier(radius: radius))
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

struct AppGlassRowFill: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AppLook.cardFill(AppAppearance(scheme)).color()
    }
}

private struct AppGlassCardModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let appearance = AppAppearance(scheme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(AppLook.cardFill(appearance).color(), in: shape)
            .overlay(shape.strokeBorder(AppLook.cardStroke(appearance).color(), lineWidth: 1))
            .shadow(color: appearance == .light ? Color.black.opacity(0.08) : .clear, radius: 14, y: 8)
    }
}
