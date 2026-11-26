import Foundation

/// Whether a training session is on screen, so the app does not block it with a loading overlay
/// when the person comes back from the Lock Screen or another app.
@MainActor
public enum WorkoutRunState {
    /// `true` while a session screen is open.
    public static var isRunning = false

    /// Whether returning to the app may show the loading overlay: never during a training, and
    /// otherwise only when catching up takes longer than a moment.
    ///
    /// - Parameter waited: How long the catching up has taken so far.
    /// - Returns: `true` when the overlay should appear now.
    public static func showsResumeOverlay(after waited: Duration) -> Bool {
        !isRunning && waited >= resumeOverlayDelay
    }

    /// How long catching up may take before the overlay appears.
    public static let resumeOverlayDelay: Duration = .milliseconds(500)
}
