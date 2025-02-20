import SwiftUI
import AVFoundation
import CoreImage

struct VisualOdometer: View {
    @StateObject private var lightMonitor = AmbientLightMonitor()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Light Level: \(String(format: "%.2f", lightMonitor.lightLevel))")
                .font(.title2)
                .padding()
            
            Text("Dips Count: \(lightMonitor.dipCount)")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.red)
            
            HStack {
                Button("Reset Count") {
                    lightMonitor.resetCount()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Button("Flashlight Low") {
                    lightMonitor.turnFlashlightOnLow()
                }
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear {
            lightMonitor.startMonitoring()
        }
        .onDisappear {
            lightMonitor.stopMonitoring()
        }
    }
}

class AmbientLightMonitor: NSObject, ObservableObject {
    @Published var lightLevel: Float = 0.0
    @Published var dipCount: Int = 0
    
    private var previousLightLevel: Float = -1.0
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private let sessionQueue = DispatchQueue(label: "cameraSessionQueue")
    
    // Throttle frame processing: process one frame every 0.5 seconds.
    private let frameProcessingInterval: CFTimeInterval = 0.05
    private var lastProcessingTime: CFTimeInterval = 0
    
    func startMonitoring() {
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(for: .video) else {
                print("No video device found.")
                return
            }
            
            self.captureSession.beginConfiguration()
            // Set a lower resolution to reduce processing load.
            if self.captureSession.canSetSessionPreset(.low) {
                self.captureSession.sessionPreset = .low
            }
            self.captureSession.commitConfiguration()
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }
                
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                // Discard late frames to avoid backlog.
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                }
                
                self.captureSession.startRunning()
            } catch {
                print("Error setting up capture session: \(error)")
            }
        }
    }
    
    func stopMonitoring() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func resetCount() {
        DispatchQueue.main.async {
            self.dipCount = 0
        }
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        // Only process a frame if the interval has passed.
        if currentTime - lastProcessingTime < frameProcessingInterval {
            return
        }
        lastProcessingTime = currentTime
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]),
        let outputImage = filter.outputImage else { return }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        self.context.render(outputImage,
                            toBitmap: &bitmap,
                            rowBytes: 4,
                            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                            format: .RGBA8,
                            colorSpace: nil)
        
        let red = Float(bitmap[0])
        let green = Float(bitmap[1])
        let blue = Float(bitmap[2])
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        let normalizedLuminance = luminance / 255.0
        
        DispatchQueue.main.async {
            self.lightLevel = normalizedLuminance
            
            if self.previousLightLevel >= 0.0 && normalizedLuminance < self.previousLightLevel - 0.1 {
                self.dipCount += 1
            }
            self.previousLightLevel = normalizedLuminance
        }
    }
    
    /// Turns on the device's flashlight (torch) at a low brightness level.
    func turnFlashlightOnLow() {
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                print("Torch not available on this device.")
                return
            }
            
            do {
                try device.lockForConfiguration()
                try device.setTorchModeOn(level: 0.2)
                device.unlockForConfiguration()
                print("Flashlight turned on at low brightness.")
            } catch {
                print("Error turning on flashlight: \(error)")
            }
        }
    }
}

extension AmbientLightMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        processSampleBuffer(sampleBuffer)
    }
}
