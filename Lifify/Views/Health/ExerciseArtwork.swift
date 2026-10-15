import ImageIO
import SwiftUI

struct ExerciseArtwork: View {
    let code: String
    var side: CGFloat = 64
    @State private var data: Data?

    var body: some View {
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
        .frame(width: side, height: side)
        .background(AppSurface.canvas, in: RoundedRectangle(cornerRadius: 12))
        .task(id: code) {
            data = await ExerciseImageLoader.load(code: code)
        }
    }

    private var illustration: Image? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1, orientation: .up)
    }
}
