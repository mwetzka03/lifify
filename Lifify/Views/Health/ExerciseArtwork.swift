import ImageIO
import SwiftUI

struct ExerciseArtwork: View {
    let code: String
    var side: CGFloat = 64
    var playsVideo = true
    @State private var data: Data?
    @State private var videoData: Data?
    @State private var isLoadingVideo = false
    @State private var showVideo = false

    var body: some View {
        Group {
            if playsVideo && ExerciseMedia.isRemote(code) {
                Button(action: openVideo) { framed }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L("Video öffnen", "Open video"))
            } else {
                framed
            }
        }
        .sheet(isPresented: $showVideo) {
            ExerciseVideoSheet(data: videoData)
        }
    }

    private var framed: some View {
        artwork
            .frame(width: side, height: side)
            .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isLoadingVideo {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .task(id: code) {
                data = await ExerciseImageLoader.load(code: code)
            }
    }

    private var artwork: some View {
        Group {
            if let illustration {
                illustration
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var illustration: Image? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1, orientation: .up)
    }

    private func openVideo() {
        guard !isLoadingVideo, ExerciseMedia.isRemote(code) else { return }
        if let cached = ExerciseImageStore.animationData(for: code), !cached.isEmpty {
            videoData = cached
            showVideo = true
            return
        }
        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            do {
                let loaded = try await WorkoutAPIClient.shared.animationGIF(code: code)
                guard !loaded.isEmpty else { return }
                ExerciseImageStore.saveAnimation(loaded, code: code)
                videoData = loaded
                showVideo = true
            } catch {
                return
            }
        }
    }
}

private struct ExerciseVideoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data?

    var body: some View {
        NavigationStack {
            Group {
                if let data, !GIFDecoder.frames(from: data).isEmpty {
                    AnimatedGIFView(data: data)
                        .padding(24)
                } else {
                    ContentUnavailableView(
                        L("Kein Video", "No video"),
                        systemImage: "film",
                        description: Text(L("Für diese Übung liegt kein Video vor.", "This exercise has no video."))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppSurface.canvas)
            .navigationTitle(L("Video", "Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) { dismiss() }
                }
            }
        }
    }
}

private struct GIFFrame {
    var image: CGImage
    var duration: Double
}

private enum GIFDecoder {
    static func frames(from data: Data) -> [GIFFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        var frames: [GIFFrame] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(GIFFrame(image: image, duration: delay(source: source, index: index)))
        }
        return frames
    }

    private static func delay(source: CGImageSource, index: Int) -> Double {
        let fallback = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else { return fallback }
        let unclamped = number(gif[kCGImagePropertyGIFUnclampedDelayTime as String])
        let clamped = number(gif[kCGImagePropertyGIFDelayTime as String])
        let value = unclamped ?? clamped ?? fallback
        return value < 0.02 ? fallback : value
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

private struct AnimatedGIFView: View {
    private let frames: [GIFFrame]
    private let total: Double

    init(data: Data) {
        let frames = GIFDecoder.frames(from: data)
        self.frames = frames
        total = frames.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            if let image = image(at: context.date) {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private func image(at date: Date) -> CGImage? {
        guard let first = frames.first else { return nil }
        guard frames.count > 1, total > 0 else { return first.image }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        var cursor = 0.0
        for frame in frames {
            cursor += frame.duration
            if elapsed < cursor { return frame.image }
        }
        return frames.last?.image
    }
}
