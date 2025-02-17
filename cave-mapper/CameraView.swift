import SwiftUI
import UIKit

struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss

    var pointNumber: Int
    var distance: Double
    var heading: Double
    var depth: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.showsCameraControls = false
        
        // Create an overlay view matching the screen's bounds.
        let overlay = UIView(frame: UIScreen.main.bounds)
        overlay.backgroundColor = .clear
        
        // Create a custom capture button.
        let buttonSize: CGFloat = 70
        let captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = buttonSize / 2
        captureButton.backgroundColor = UIColor.systemOrange
        captureButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        captureButton.tintColor = .white
        captureButton.addTarget(context.coordinator, action: #selector(Coordinator.capturePhoto), for: .touchUpInside)
        overlay.addSubview(captureButton)
        
        // Position the button: centered horizontally and pinned 40 points above the bottom.
        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: buttonSize),
            captureButton.heightAnchor.constraint(equalToConstant: buttonSize),
            captureButton.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -125)
        ])
        
        picker.cameraOverlayView = overlay
        context.coordinator.picker = picker
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed.
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        weak var picker: UIImagePickerController?

        init(parent: CameraView) {
            self.parent = parent
        }

        @objc func capturePhoto() {
            picker?.takePicture()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                let stampedImage = overlayText(
                    on: image,
                    pointNumber: parent.pointNumber,
                    distance: parent.distance,
                    heading: parent.heading,
                    depth: parent.depth
                )
                UIImageWriteToSavedPhotosAlbum(stampedImage, nil, nil, nil)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
        
        // Helper to overlay text on the image.
        private func overlayText(on image: UIImage,
                                 pointNumber: Int,
                                 distance: Double,
                                 heading: Double,
                                 depth: Double) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { context in
                image.draw(at: .zero)
                let text = """
                Point: \(pointNumber)
                Distance: \(String(format: "%.2f", distance)) m
                Heading: \(String(format: "%.2f", heading))°
                Depth: \(String(format: "%.2f", depth))
                """
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: image.size.width * 0.05),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.black.withAlphaComponent(0.5)
                ]
                let margin: CGFloat = 10
                let textRect = CGRect(
                    x: margin,
                    y: image.size.height - (image.size.height * 0.2) - margin,
                    width: image.size.width - 2 * margin,
                    height: image.size.height * 0.2
                )
                text.draw(in: textRect, withAttributes: attributes)
            }
        }
    }
}
