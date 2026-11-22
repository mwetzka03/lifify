import Foundation
import UIKit

public enum MealPhotoFit {
    public static func jpeg(_ data: Data, maxEdge: CGFloat = 768) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: 0.72)
    }
}
