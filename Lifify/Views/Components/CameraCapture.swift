import Photos
import SwiftUI
import UIKit

/// Takes one photo with the camera. The system camera does not write it to the photo library.
struct CameraCapture: UIViewControllerRepresentable {
    var onCapture: @MainActor (Data) -> Void
    var onCancel: @MainActor () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: @MainActor (Data) -> Void
        private let onCancel: @MainActor () -> Void

        init(onCapture: @escaping @MainActor (Data) -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        nonisolated func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.86) ?? Data()
            MainActor.assumeIsolated {
                if data.isEmpty {
                    self.onCancel()
                } else {
                    self.onCapture(data)
                }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            MainActor.assumeIsolated {
                self.onCancel()
            }
        }
    }
}

extension MealCapture {
    static func saveToLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
}
