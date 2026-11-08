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

/// Four hues. Appearance still chooses light or dark, including System.
enum AppPalette: String, CaseIterable, Identifiable {
    case green
    case blue
    case bordeaux
    case violet

    static let storageKey = "appPalette"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .green: L("Grün", "Green")
        case .blue: L("Blau", "Blue")
        case .bordeaux: L("Bordeaux", "Bordeaux")
        case .violet: L("Violett", "Violet")
        }
    }

    static func resolved(_ raw: String) -> AppPalette {
        AppPalette(rawValue: raw) ?? .green
    }
}

/// Light and dark each have their own paint. Every palette keeps that split.
enum AppLook {
    static func canvasTop(_ appearance: AppAppearance, palette: AppPalette = .green) -> AppColor {
        paint(palette).canvasTop(appearance)
    }

    static func canvasBottom(_ appearance: AppAppearance, palette: AppPalette = .green) -> AppColor {
        paint(palette).canvasBottom(appearance)
    }

    static func orb(_ appearance: AppAppearance, index: Int, palette: AppPalette = .green) -> AppColor {
        paint(palette).orb(appearance, index: index)
    }

    static func cardFill(_ appearance: AppAppearance, palette: AppPalette = .green) -> AppColor {
        paint(palette).cardFill(appearance)
    }

    static func cardStroke(_ appearance: AppAppearance, palette: AppPalette = .green) -> AppColor {
        paint(palette).cardStroke(appearance)
    }

    static func accent(_ appearance: AppAppearance, palette: AppPalette = .green) -> AppColor {
        paint(palette).accent(appearance)
    }

    static func modesDiffer(palette: AppPalette = .green) -> Bool {
        let lightTop = canvasTop(.light, palette: palette)
        let darkTop = canvasTop(.dark, palette: palette)
        let lightCard = cardFill(.light, palette: palette)
        let darkCard = cardFill(.dark, palette: palette)
        return lightTop != darkTop
            && lightCard != darkCard
            && lightTop.brightness > 0.75
            && darkTop.brightness < 0.2
            && lightCard.opacity > 0.8
            && darkCard.opacity > 0.8
            && darkCard.brightness < 0.35
            && lightCard.brightness > 0.8
    }

    private static func paint(_ palette: AppPalette) -> PalettePaint {
        switch palette {
        case .green: .green
        case .blue: .blue
        case .bordeaux: .bordeaux
        case .violet: .violet
        }
    }
}

private struct PalettePaint {
    var lightTop: AppColor
    var darkTop: AppColor
    var lightBottom: AppColor
    var darkBottom: AppColor
    var lightOrb: AppColor
    var lightOrbAlt: AppColor
    var darkOrb: AppColor
    var darkOrbAlt: AppColor
    var lightCard: AppColor
    var darkCard: AppColor
    var lightStroke: AppColor
    var darkStroke: AppColor
    var lightAccent: AppColor
    var darkAccent: AppColor

    func canvasTop(_ appearance: AppAppearance) -> AppColor {
        appearance == .light ? lightTop : darkTop
    }

    func canvasBottom(_ appearance: AppAppearance) -> AppColor {
        appearance == .light ? lightBottom : darkBottom
    }

    func orb(_ appearance: AppAppearance, index: Int) -> AppColor {
        if appearance == .light { return index == 0 ? lightOrb : lightOrbAlt }
        return index == 0 ? darkOrb : darkOrbAlt
    }

    func cardFill(_ appearance: AppAppearance) -> AppColor {
        appearance == .light ? lightCard : darkCard
    }

    func cardStroke(_ appearance: AppAppearance) -> AppColor {
        appearance == .light ? lightStroke : darkStroke
    }

    func accent(_ appearance: AppAppearance) -> AppColor {
        appearance == .light ? lightAccent : darkAccent
    }

    static let green = PalettePaint(
        lightTop: AppColor(red: 0.78, green: 0.94, blue: 0.86, opacity: 1),
        darkTop: AppColor(red: 0.04, green: 0.10, blue: 0.09, opacity: 1),
        lightBottom: AppColor(red: 0.99, green: 0.91, blue: 0.82, opacity: 1),
        darkBottom: AppColor(red: 0.05, green: 0.06, blue: 0.11, opacity: 1),
        lightOrb: AppColor(red: 0.42, green: 0.82, blue: 0.60, opacity: 0.55),
        lightOrbAlt: AppColor(red: 0.98, green: 0.68, blue: 0.48, opacity: 0.42),
        darkOrb: AppColor(red: 0.10, green: 0.48, blue: 0.34, opacity: 0.75),
        darkOrbAlt: AppColor(red: 0.55, green: 0.32, blue: 0.12, opacity: 0.50),
        lightCard: AppColor(red: 0.98, green: 0.99, blue: 0.97, opacity: 0.94),
        darkCard: AppColor(red: 0.16, green: 0.22, blue: 0.20, opacity: 0.94),
        lightStroke: AppColor(red: 1, green: 1, blue: 1, opacity: 0.85),
        darkStroke: AppColor(red: 0.62, green: 0.88, blue: 0.72, opacity: 0.28),
        lightAccent: AppColor(red: 0.12, green: 0.58, blue: 0.38, opacity: 1),
        darkAccent: AppColor(red: 0.49, green: 0.86, blue: 0.66, opacity: 1)
    )

    static let blue = PalettePaint(
        lightTop: AppColor(red: 0.78, green: 0.88, blue: 0.96, opacity: 1),
        darkTop: AppColor(red: 0.04, green: 0.07, blue: 0.12, opacity: 1),
        lightBottom: AppColor(red: 0.90, green: 0.93, blue: 0.99, opacity: 1),
        darkBottom: AppColor(red: 0.05, green: 0.06, blue: 0.14, opacity: 1),
        lightOrb: AppColor(red: 0.45, green: 0.68, blue: 0.92, opacity: 0.50),
        lightOrbAlt: AppColor(red: 0.62, green: 0.78, blue: 0.96, opacity: 0.40),
        darkOrb: AppColor(red: 0.12, green: 0.32, blue: 0.58, opacity: 0.75),
        darkOrbAlt: AppColor(red: 0.20, green: 0.36, blue: 0.62, opacity: 0.50),
        lightCard: AppColor(red: 0.96, green: 0.98, blue: 0.99, opacity: 0.94),
        darkCard: AppColor(red: 0.14, green: 0.18, blue: 0.24, opacity: 0.94),
        lightStroke: AppColor(red: 1, green: 1, blue: 1, opacity: 0.85),
        darkStroke: AppColor(red: 0.62, green: 0.76, blue: 0.92, opacity: 0.28),
        lightAccent: AppColor(red: 0.16, green: 0.40, blue: 0.72, opacity: 1),
        darkAccent: AppColor(red: 0.55, green: 0.74, blue: 0.95, opacity: 1)
    )

    static let bordeaux = PalettePaint(
        lightTop: AppColor(red: 0.96, green: 0.86, blue: 0.88, opacity: 1),
        darkTop: AppColor(red: 0.12, green: 0.04, blue: 0.06, opacity: 1),
        lightBottom: AppColor(red: 0.98, green: 0.90, blue: 0.86, opacity: 1),
        darkBottom: AppColor(red: 0.10, green: 0.05, blue: 0.07, opacity: 1),
        lightOrb: AppColor(red: 0.72, green: 0.32, blue: 0.40, opacity: 0.42),
        lightOrbAlt: AppColor(red: 0.86, green: 0.55, blue: 0.48, opacity: 0.38),
        darkOrb: AppColor(red: 0.48, green: 0.12, blue: 0.20, opacity: 0.75),
        darkOrbAlt: AppColor(red: 0.42, green: 0.16, blue: 0.18, opacity: 0.50),
        lightCard: AppColor(red: 0.99, green: 0.96, blue: 0.96, opacity: 0.94),
        darkCard: AppColor(red: 0.24, green: 0.14, blue: 0.16, opacity: 0.94),
        lightStroke: AppColor(red: 1, green: 1, blue: 1, opacity: 0.85),
        darkStroke: AppColor(red: 0.90, green: 0.62, blue: 0.66, opacity: 0.28),
        lightAccent: AppColor(red: 0.55, green: 0.12, blue: 0.22, opacity: 1),
        darkAccent: AppColor(red: 0.86, green: 0.45, blue: 0.52, opacity: 1)
    )

    static let violet = PalettePaint(
        lightTop: AppColor(red: 0.90, green: 0.84, blue: 0.96, opacity: 1),
        darkTop: AppColor(red: 0.08, green: 0.05, blue: 0.12, opacity: 1),
        lightBottom: AppColor(red: 0.94, green: 0.88, blue: 0.98, opacity: 1),
        darkBottom: AppColor(red: 0.07, green: 0.05, blue: 0.11, opacity: 1),
        lightOrb: AppColor(red: 0.55, green: 0.38, blue: 0.82, opacity: 0.45),
        lightOrbAlt: AppColor(red: 0.72, green: 0.55, blue: 0.90, opacity: 0.38),
        darkOrb: AppColor(red: 0.32, green: 0.16, blue: 0.55, opacity: 0.75),
        darkOrbAlt: AppColor(red: 0.28, green: 0.14, blue: 0.42, opacity: 0.50),
        lightCard: AppColor(red: 0.97, green: 0.96, blue: 0.99, opacity: 0.94),
        darkCard: AppColor(red: 0.18, green: 0.15, blue: 0.24, opacity: 0.94),
        lightStroke: AppColor(red: 1, green: 1, blue: 1, opacity: 0.85),
        darkStroke: AppColor(red: 0.76, green: 0.64, blue: 0.92, opacity: 0.28),
        lightAccent: AppColor(red: 0.36, green: 0.22, blue: 0.62, opacity: 1),
        darkAccent: AppColor(red: 0.72, green: 0.58, blue: 0.92, opacity: 1)
    )
}

struct AppPlayfulCanvas: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        let appearance = AppAppearance(scheme)
        let palette = AppPalette.resolved(paletteRaw)
        ZStack {
            LinearGradient(
                colors: [
                    AppLook.canvasTop(appearance, palette: palette).color(),
                    AppLook.canvasBottom(appearance, palette: palette).color()
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppLook.orb(appearance, index: 0, palette: palette).color())
                .frame(width: 280, height: 280)
                .blur(radius: 24)
                .offset(x: -140, y: -260)
            Circle()
                .fill(AppLook.orb(appearance, index: 1, palette: palette).color())
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: 170, y: 320)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appCanvas() -> some View {
        background(AppPlayfulCanvas())
    }

    func appTintedPlate(radius: CGFloat = 14) -> some View {
        background(AppTintedPlate(radius: radius))
    }

    func appTintedCapsule() -> some View {
        background(AppTintedCapsuleFill())
    }

    /// Tinted page. The fill follows the chosen style.
    func appGlassCanvas() -> some View {
        background(AppPlayfulCanvas())
    }

    func appGlassList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background(AppPlayfulCanvas())
            .appAccentTint()
    }

    func appGlassRow() -> some View {
        listRowBackground(AppGlassRowFill())
    }

    /// Links, pickers, and the tab bar follow the selected style instead of system blue.
    func appAccentTint() -> some View {
        modifier(AppAccentTintModifier())
    }

    func appAccentForeground() -> some View {
        modifier(AppAccentForegroundModifier())
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
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        AppLook.cardFill(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
    }
}

private struct AppTintedPlate: View {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        let appearance = AppAppearance(scheme)
        let palette = AppPalette.resolved(paletteRaw)
        let fill = AppLook.cardFill(appearance, palette: palette).color()
        let stroke = AppLook.cardStroke(appearance, palette: palette).color()
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape.fill(fill).overlay(shape.strokeBorder(stroke, lineWidth: 1))
    }
}

private struct AppTintedCapsuleFill: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        let appearance = AppAppearance(scheme)
        let palette = AppPalette.resolved(paletteRaw)
        let fill = AppLook.cardFill(appearance, palette: palette).color()
        let stroke = AppLook.cardStroke(appearance, palette: palette).color()
        return Capsule().fill(fill).overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }
}

private struct AppAccentTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    func body(content: Content) -> some View {
        content.tint(AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color())
    }
}

private struct AppAccentForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    func body(content: Content) -> some View {
        content.foregroundStyle(AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color())
    }
}

private struct AppGlassCardModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    func body(content: Content) -> some View {
        let appearance = AppAppearance(scheme)
        let palette = AppPalette.resolved(paletteRaw)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(AppLook.cardFill(appearance, palette: palette).color(), in: shape)
            .overlay(shape.strokeBorder(AppLook.cardStroke(appearance, palette: palette).color(), lineWidth: 1))
            .shadow(color: appearance == .light ? Color.black.opacity(0.08) : .clear, radius: 14, y: 8)
    }
}

private struct PairHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PairRowHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var pairRowHeight: CGFloat {
        get { self[PairRowHeightKey.self] }
        set { self[PairRowHeightKey.self] = newValue }
    }
}

/// Two cards in one row grow to the taller card. The measurement is the content, before that stretch.
struct EqualHeightPair<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content()
        }
        .environment(\.pairRowHeight, height)
        .onPreferenceChange(PairHeightPreference.self) { height = $0 }
    }
}

extension View {
    func equalPairCard(radius: CGFloat = 18) -> some View {
        modifier(EqualPairCardModifier(radius: radius))
    }
}

private struct EqualPairCardModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.pairRowHeight) private var rowHeight

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: PairHeightPreference.self, value: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight > 0 ? rowHeight : nil, alignment: .topLeading)
            .appGlassCard(radius: radius)
    }
}
