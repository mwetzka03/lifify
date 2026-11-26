import LififyCore
import SwiftUI
import UIKit

/// The app's loading animation: a turning arc in the style color around a softly pulsing dot, without a box.
///
/// The motion runs as Core Animation on the system's render server, like the system spinner, so it
/// stays smooth while the main thread is busy loading. With Reduce Motion the arc stands still.
struct LififyLoader: View {
    var text: String? = L("Wird geladen", "Loading")
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        VStack(spacing: 12) {
            LoaderRing(color: UIColor(accent), animates: !reduceMotion)
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
}

/// The ring of the loader as layers whose animations the render server plays without the main thread.
private struct LoaderRing: UIViewRepresentable {
    let color: UIColor
    let animates: Bool

    func makeUIView(context: Context) -> LoaderRingView {
        LoaderRingView()
    }

    func updateUIView(_ view: LoaderRingView, context: Context) {
        view.configure(color: color, animates: animates)
    }
}

/// Draws the track, the gradient arc, and the dot, and keeps their animations running.
final class LoaderRingView: UIView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let arcFade = CAGradientLayer()
    private let spinner = CALayer()
    private let dot = CAShapeLayer()
    private var animates = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        track.fillColor = UIColor.clear.cgColor
        arc.fillColor = UIColor.clear.cgColor
        arc.strokeColor = UIColor.black.cgColor
        arc.lineCap = .round
        arcFade.type = .conic
        arcFade.startPoint = CGPoint(x: 0.5, y: 0.5)
        arcFade.endPoint = CGPoint(x: 0.5, y: 0)
        arcFade.mask = arc
        spinner.addSublayer(arcFade)
        layer.addSublayer(track)
        layer.addSublayer(spinner)
        layer.addSublayer(dot)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Sets the color and starts or stops the motion.
    func configure(color: UIColor, animates: Bool) {
        track.strokeColor = color.withAlphaComponent(0.15).cgColor
        arcFade.colors = [color.withAlphaComponent(0).cgColor, color.cgColor]
        arcFade.locations = [0, 0.7]
        dot.fillColor = color.cgColor
        self.animates = animates
        restartAnimations()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let line = max(side * 0.09, 3)
        let frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        // The circle starts at the top, where the conic gradient starts, so the arc fades into its tail.
        let circle = UIBezierPath(
            arcCenter: CGPoint(x: side / 2, y: side / 2),
            radius: (side - line) / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        ).cgPath
        for shape in [track, arc] {
            shape.frame = CGRect(origin: .zero, size: frame.size)
            shape.path = circle
            shape.lineWidth = line
        }
        track.frame = frame
        arc.strokeEnd = 0.7
        spinner.frame = frame
        arcFade.frame = CGRect(origin: .zero, size: frame.size)
        let dotSide = side * 0.28
        dot.frame = CGRect(x: frame.midX - dotSide / 2, y: frame.midY - dotSide / 2, width: dotSide, height: dotSide)
        dot.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: dotSide, height: dotSide))).cgPath
        restartAnimations()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animations stop when a layer leaves the window, so they start again on return.
        restartAnimations()
    }

    /// Adds the endless rotation and pulse, which Core Animation then plays on its own.
    private func restartAnimations() {
        spinner.removeAllAnimations()
        dot.removeAllAnimations()
        guard window != nil else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.75
        pulse.toValue = 1
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
        guard animates else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        spinner.add(spin, forKey: "spin")
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
