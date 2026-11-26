import CoreGraphics
import Foundation
import ImageIO
import LififyCore
import LififyHealth
import UniformTypeIdentifiers

/// Writes the picture of the current exercise to the shared folder, so the Live Activity can show it.
enum ExerciseActivityImage {
    /// Makes sure the exercise's picture is in the shared folder, made once per exercise.
    ///
    /// The first frame of the cached animation, or the cached still, is scaled down and its white
    /// background removed, as in the app.
    static func prepare(code: String?) {
        guard let code, let target = WorkoutActivityImages.url(for: code),
              !FileManager.default.fileExists(atPath: target.path),
              let data = ExerciseImageStore.animationData(for: code) ?? ExerciseImageStore.data(for: code),
              let image = thumbnail(from: data)
        else { return }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, ArtworkMatte.withoutWhite(image), nil)
        CGImageDestinationFinalize(destination)
    }

    /// The first frame, at most `WorkoutActivityImages.side` pixels on its longest side.
    private static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: WorkoutActivityImages.side,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
