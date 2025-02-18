import SwiftUI
import UIKit
import AVFoundation
import CoreLocation

// MARK: - SwiftUI Wrapper

struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss

    var pointNumber: Int
    var distance: Double
    var heading: Double  // Initial heading value; will update dynamically.
    var depth: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController(pointNumber: pointNumber,
                                      distance: distance,
                                      heading: heading,
                                      depth: depth)
        // Assign the coordinator as the photo capture delegate.
        vc.photoCaptureDelegate = context.coordinator
        vc.modalPresentationStyle = .fullScreen
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update if needed.
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate, CLLocationManagerDelegate {
        let parent: CameraView
        var locationManager: CLLocationManager?
        // Keep track of the latest heading.
        var currentHeading: Double

        init(parent: CameraView) {
            self.parent = parent
            self.currentHeading = parent.heading
            super.init()
            setupLocationManager()
        }

        private func setupLocationManager() {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.requestWhenInUseAuthorization()
            if CLLocationManager.headingAvailable() {
                locationManager?.headingFilter = 1  // Update for each degree change.
                locationManager?.startUpdatingHeading()
            }
        }

        // MARK: - AVCapturePhotoCaptureDelegate

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                parent.dismiss()
                return
            }

            // Overlay text on the image with the latest heading.
            let stampedImage = overlayText(
                on: image,
                pointNumber: parent.pointNumber,
                distance: parent.distance,
                heading: currentHeading,
                depth: parent.depth
            )
            UIImageWriteToSavedPhotosAlbum(stampedImage, nil, nil, nil)
            parent.dismiss()
        }

        // MARK: - CLLocationManagerDelegate

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            self.currentHeading = newHeading.magneticHeading
            // Post a notification so that the preview overlay can update.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .headingUpdated, object: newHeading)
            }
        }

        // Helper to overlay text on the captured image.
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

// MARK: - Custom Camera View Controller Using AVFoundation

class CameraViewController: UIViewController {
    // Data passed in from SwiftUI.
    var pointNumber: Int
    var distance: Double
    var heading: Double
    var depth: Double

    // AVFoundation properties.
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    var photoOutput: AVCapturePhotoOutput!

    // Delegate to handle photo capture.
    var photoCaptureDelegate: AVCapturePhotoCaptureDelegate?

    // UI Overlay Elements.
    var infoLabel: UILabel!
    var captureButton: UIButton!

    init(pointNumber: Int, distance: Double, heading: Double, depth: Double) {
        self.pointNumber = pointNumber
        self.distance = distance
        self.heading = heading
        self.depth = depth
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCaptureSession()
        setupUI()

        // Listen for heading updates.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleHeadingUpdate(_:)),
                                               name: .headingUpdated,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // Choose the ultra‑wide camera if available; otherwise, use the standard wide‑angle camera.
        let device: AVCaptureDevice?
        if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            device = ultraWide
        } else if let wideAngle = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            device = wideAngle
        } else {
            device = nil
        }
        guard let captureDevice = device,
              let input = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("No suitable camera available")
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        captureSession.commitConfiguration()

        // Set up the preview layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = view.layer.bounds
        view.layer.insertSublayer(videoPreviewLayer, at: 0)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.stopRunning()
            }
        }
    }

    func setupUI() {
        // Info label to display the embedded data.
        infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .left
        infoLabel.textColor = .white
        infoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        infoLabel.font = UIFont.systemFont(ofSize: 16)
        infoLabel.text = """
        Point: \(pointNumber)
        Distance: \(String(format: "%.2f", distance)) m
        Heading: \(String(format: "%.2f", heading))°
        Depth: \(String(format: "%.2f", depth))
        """
        view.addSubview(infoLabel)
        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            infoLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10)
        ])

        // Capture button.
        captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.backgroundColor = .systemOrange
        captureButton.tintColor = .white
        captureButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40)
        ])
    }

    @objc func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: photoCaptureDelegate!)
    }

    @objc func handleHeadingUpdate(_ notification: Notification) {
        if let newHeading = notification.object as? CLHeading {
            DispatchQueue.main.async {
                self.infoLabel.text = """
                Point: \(self.pointNumber)
                Distance: \(String(format: "%.2f", self.distance)) m
                Heading: \(String(format: "%.2f", newHeading.magneticHeading))°
                Depth: \(String(format: "%.2f", self.depth))
                """
            }
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let headingUpdated = Notification.Name("headingUpdated")
}
