import LififyCore
import SwiftUI
import UIKit

/// The app's loading animation: three rings in the style color, each showing its top quarter and
/// turning counterclockwise at its own speed, without a box.
///
/// The motion runs as Core Animation on the system's render server, like the system spinner, so it
/// stays smooth while the main thread is busy loading. With Reduce Motion the rings stand still.
struct LififyLoader: View {
    var text: String? = L("Wird geladen", "Loading")
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue

    var body: some View {
        VStack(spacing: 14) {
            LoaderRings(color: UIColor(accent), animates: !reduceMotion)
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

/// The rings of the loader as layers whose animations the render server plays without the main thread.
private struct LoaderRings: UIViewRepresentable {
    let color: UIColor
    let animates: Bool

    func makeUIView(context: Context) -> LoaderRingsView {
        LoaderRingsView()
    }

    func updateUIView(_ view: LoaderRingsView, context: Context) {
        view.configure(color: color, animates: animates)
    }
}

/// Draws three concentric quarter arcs and keeps each turning.
///
/// A running rotation is never restarted: SwiftUI updates and layout passes happen often, and a
/// restart made the rings jump back to their start.
final class LoaderRingsView: UIView {
    /// The relative size and the seconds per turn of each ring, inner to outer.
    private static let rings: [(scale: CGFloat, seconds: Double)] = [(0.5, 0.85), (0.75, 0.95), (1, 1.05)]
    private static let spinKey = "spin"
    private var holders: [CALayer] = []
    private var arcs: [CAShapeLayer] = []
    private var animates = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for _ in Self.rings {
            let holder = CALayer()
            let arc = CAShapeLayer()
            arc.fillColor = UIColor.clear.cgColor
            arc.lineCap = .butt
            holder.addSublayer(arc)
            layer.addSublayer(holder)
            holders.append(holder)
            arcs.append(arc)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Sets the color and starts or stops the motion.
    func configure(color: UIColor, animates: Bool) {
        arcs.forEach { $0.strokeColor = color.cgColor }
        if self.animates != animates {
            self.animates = animates
            holders.forEach { $0.removeAnimation(forKey: Self.spinKey) }
        }
        startMissingAnimations()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let full = min(bounds.width, bounds.height)
        let line = max(full * 0.035, 2.5)
        // Frame changes must not animate implicitly, or the rings slide while the view settles.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, ring) in Self.rings.enumerated() {
            let side = full * ring.scale
            let frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            holders[index].bounds = CGRect(origin: .zero, size: frame.size)
            holders[index].position = CGPoint(x: frame.midX, y: frame.midY)
            arcs[index].frame = holders[index].bounds
            arcs[index].lineWidth = line
            // The top quarter of the circle, like a border-top on a round box.
            arcs[index].path = UIBezierPath(
                arcCenter: CGPoint(x: side / 2, y: side / 2),
                radius: (side - line) / 2,
                startAngle: -.pi * 0.75,
                endAngle: -.pi * 0.25,
                clockwise: true
            ).cgPath
        }
        CATransaction.commit()
        startMissingAnimations()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Core Animation drops animations when a layer leaves the window; they come back on return.
        startMissingAnimations()
    }

    /// Adds the endless counterclockwise turn to each ring that has none yet.
    private func startMissingAnimations() {
        guard animates, window != nil else { return }
        for (index, ring) in Self.rings.enumerated() where holders[index].animation(forKey: Self.spinKey) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = Double.pi * 2
            spin.toValue = 0
            spin.duration = ring.seconds
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            holders[index].add(spin, forKey: Self.spinKey)
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
            LififyLoader(text: nil, size: 52)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appGlassCanvas()
        .onAppear {
            withAnimation(.spring(duration: 0.6)) { appeared = true }
        }
    }
}
