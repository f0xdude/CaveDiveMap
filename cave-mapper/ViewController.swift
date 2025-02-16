//
//  ViewController.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 21.11.24.
//

import SwiftUI

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {

    // MARK: - Properties

    var captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var depthLabel: UILabel!

    // Queue for processing video frames
    let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupDepthLabel()
    }

    // MARK: - Setup Methods

    func setupCamera() {
        // Configure capture session
        captureSession.sessionPreset = .high

        // Set up camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Could not find a back camera.")
            return
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
            } else {
                print("Could not add video device input to the session")
                return
            }
        } catch {
            print("Could not create video device input: \(error)")
            return
        }

        // Set up video output
        let videoDataOutput = AVCaptureVideoDataOutput()

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)

            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        } else {
            print("Could not add video data output to the session")
            return
        }

        // Set up preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        // Start the session
        captureSession.startRunning()
    }

    func setupDepthLabel() {
        depthLabel = UILabel()
        depthLabel.translatesAutoresizingMaskIntoConstraints = false
        depthLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        depthLabel.textColor = .white
        depthLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        depthLabel.textAlignment = .center
        depthLabel.text = "Depth: --"

        view.addSubview(depthLabel)

        // Constraints
        NSLayoutConstraint.activate([
            depthLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            depthLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            depthLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            depthLabel.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Create a request handler.
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // Create a text recognition request.
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

        // Set recognition level
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false

        // Perform the text recognition request.
        do {
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the requests: \(error).")
        }
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
        if let error = error {
            print("Error recognizing text: \(error)")
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

        var detectedDepth: String?

        for observation in observations {
            guard let bestCandidate = observation.topCandidates(1).first else { continue }

            let recognizedText = bestCandidate.string

            // Extract depth value from recognized text
            if let depthValue = extractDepth(from: recognizedText) {
                detectedDepth = depthValue
                break // Assuming we only need one depth value
            }
        }

        if let depth = detectedDepth {
            // Update the depth label on the main thread
            DispatchQueue.main.async {
                self.depthLabel.text = "Depth: \(depth)"
            }
        }
    }

    func extractDepth(from text: String) -> String? {
        // Regular expression pattern for depth (e.g., "30 m", "100 ft")
        let pattern = "\\b\\d+(?:\\.\\d+)?\\s?(m|ft)\\b"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: text.utf16.count)

        if let match = regex?.firstMatch(in: text, options: [], range: range),
           let matchRange = Range(match.range, in: text) {
            let depthString = String(text[matchRange])
            return depthString
        }

        return nil
    }
}
