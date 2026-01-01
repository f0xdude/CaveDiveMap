//
//  OpticalWheelDetector.swift
//  cave-mapper
//
//  Created on 12/25/25.
//

import AVFoundation
import UIKit
import SwiftUI

/// Optical wheel rotation detector using camera and flashlight
/// Detects a wheel with an opening that blocks/unblocks light each rotation
class OpticalWheelDetector: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var currentBrightness: Double = 0.0
    @Published var rotationCount: Int = 0
    @Published var lowBrightnessThreshold: Double = 0.3  // Normalized 0-1
    @Published var highBrightnessThreshold: Double = 0.6 // Normalized 0-1
    @Published var isCalibrating: Bool = false
    @Published var calibrationProgress: Double = 0.0
    @Published var flashlightEnabled: Bool = true
    @Published var flashlightBrightness: Float = 0.5 {  // 0.0 to 1.0 (0% to 100%)
        didSet {
            UserDefaults.standard.set(flashlightBrightness, forKey: "opticalFlashlightBrightness")
            // Update flashlight if currently running
            if isRunning && flashlightBrightness > 0 {
                updateFlashlightBrightness()
            } else if isRunning && flashlightBrightness == 0 {
                enableFlashlight(false)
            } else if isRunning && !flashlightEnabled {
                enableFlashlight(true)
            }
        }
    }
    
    // MARK: - Private Properties
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "optical.wheel.detector")
    private var captureDevice: AVCaptureDevice?
    
    // Detection state
    private var isReadyForNewRotation = true
    private var brightnessHistory: [Double] = []
    private let historySize = 30  // Track last 30 frames
    
    // Calibration
    private var calibrationSamples: [Double] = []
    private let calibrationDuration = 10.0  // seconds
    private var calibrationStartTime: Date?
    
    // Frame processing
    private var lastProcessedTime: Date = Date()
    private let minimumFrameInterval: TimeInterval = 0.05  // Process at most 20 fps
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        // Load saved flashlight brightness
        if let savedBrightness = UserDefaults.standard.object(forKey: "opticalFlashlightBrightness") as? Float {
            self.flashlightBrightness = max(0.0, min(1.0, savedBrightness))  // Clamp to 0-1
        }
        
        setupCamera()
    }
    
    deinit {
        stopDetection()
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .low  // Low quality is fine for brightness detection
            
            // Use macro camera for close-up detection of encoder wheel
            // First try to get ultra-wide camera with macro capability (iPhone 13 Pro+)
            var device: AVCaptureDevice?
            
            if let macroDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                device = macroDevice
                print("✅ Using ultra-wide camera with macro capability")
            } else if let wideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                device = wideDevice
                print("⚠️ Macro camera not available, falling back to wide-angle camera")
            }
            
            guard let device = device else {
                print("❌ No suitable rear camera available")
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureDevice = device
            
            // Configure device for close-up macro detection
            do {
                try device.lockForConfiguration()
                
                // Enable macro mode if available (iOS 15+)
                if #available(iOS 15.4, *) {
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .near
                        print("✅ Auto focus range set to near (macro)")
                    }
                }
                
                // Use continuous autofocus for macro to maintain focus on close objects
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    print("✅ Continuous autofocus enabled for macro")
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                
                // Lock exposure to prevent dynamic changes from interfering with brightness detection
                // First set to auto to let it find a good exposure level
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // Enable low light boost if available for better detection in dark environments
                if device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                    print("✅ Low light boost enabled")
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ Could not configure camera: \(error)")
            }
            
            // Add camera input
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }
            } catch {
                print("❌ Could not create camera input: \(error)")
                self.captureSession.commitConfiguration()
                return
            }
            
            // Configure video output
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    // MARK: - Exposure Locking
    private func lockExposure() {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Lock exposure at current settings to prevent dynamic changes
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                print("🔒 Exposure locked for consistent brightness detection")
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
                print("⚠️ Locked exposure not supported, using autoExpose")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("⚠️ Could not lock exposure: \(error)")
        }
    }
    
    // MARK: - Public Methods
    func startDetection() {
        print("🚀 OpticalWheelDetector.startDetection() called, isRunning=\(isRunning)")
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Stop first if already running to ensure clean state
            if self.captureSession.isRunning {
                print("⚠️ Session already running, stopping first")
                self.captureSession.stopRunning()
            }
            
            self.captureSession.startRunning()
            
            DispatchQueue.main.async {
                self.isRunning = true
                // Only enable flashlight if brightness > 0
                if self.flashlightBrightness > 0 {
                    self.enableFlashlight(true)
                }
                print("✅ Optical detection started, flashlight brightness: \(self.flashlightBrightness * 100)%")
            }
            
            // Lock exposure after camera has had time to adjust (1 second delay)
            self.sessionQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.lockExposure()
            }
        }
    }
    
    func stopDetection() {
        print("🛑 OpticalWheelDetector.stopDetection() called")
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            
            DispatchQueue.main.async {
                self.isRunning = false
                self.enableFlashlight(false)
                print("✅ Optical detection stopped, flashlight disabled")
            }
        }
    }
    
    func resetRotationCount() {
        rotationCount = 0
    }
    
    // MARK: - Calibration
    func startCalibration() {
        guard !isCalibrating else { return }
        
        isCalibrating = true
        calibrationSamples.removeAll()
        calibrationStartTime = Date()
        calibrationProgress = 0.0
        
        print("🔦 Starting optical calibration - rotate the wheel steadily for \(Int(calibrationDuration))s")
    }
    
    func cancelCalibration() {
        isCalibrating = false
        calibrationSamples.removeAll()
        calibrationStartTime = nil
        calibrationProgress = 0.0
    }
    
    private func updateCalibration(brightness: Double) {
        guard isCalibrating, let startTime = calibrationStartTime else { return }
        
        calibrationSamples.append(brightness)
        
        let elapsed = Date().timeIntervalSince(startTime)
        calibrationProgress = min(elapsed / calibrationDuration, 1.0)
        
        if elapsed >= calibrationDuration {
            finishCalibration()
        }
    }
    
    private func finishCalibration() {
        defer {
            isCalibrating = false
            calibrationStartTime = nil
        }
        
        guard calibrationSamples.count >= 50 else {
            print("⚠️ Not enough calibration samples: \(calibrationSamples.count)")
            return
        }
        
        let sorted = calibrationSamples.sorted()
        
        // Use percentiles to find thresholds
        // P25: Lower brightness (wheel is blocking)
        // P75: Higher brightness (wheel opening is visible)
        let p25 = percentile(sorted, percent: 25)
        let p75 = percentile(sorted, percent: 75)
        
        let range = p75 - p25
        let margin = range * 0.15  // 15% margin
        
        // Set thresholds with hysteresis
        lowBrightnessThreshold = p25 + margin
        highBrightnessThreshold = p75 - margin
        
        // Ensure minimum separation
        let minGap = 0.1
        if highBrightnessThreshold - lowBrightnessThreshold < minGap {
            let midpoint = (lowBrightnessThreshold + highBrightnessThreshold) / 2
            lowBrightnessThreshold = midpoint - minGap / 2
            highBrightnessThreshold = midpoint + minGap / 2
        }
        
        print("✅ Optical calibration complete")
        print("   Low threshold: \(String(format: "%.3f", lowBrightnessThreshold))")
        print("   High threshold: \(String(format: "%.3f", highBrightnessThreshold))")
        print("   Range: \(String(format: "%.3f", range))")
        
        // Save to UserDefaults
        UserDefaults.standard.set(lowBrightnessThreshold, forKey: "opticalLowThreshold")
        UserDefaults.standard.set(highBrightnessThreshold, forKey: "opticalHighThreshold")
    }
    
    private func percentile(_ sorted: [Double], percent: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = (percent / 100.0) * Double(sorted.count - 1)
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        
        if lower == upper {
            return sorted[lower]
        }
        
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
    
    // MARK: - Flashlight Control
    private func enableFlashlight(_ enable: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.captureDevice,
                  device.hasTorch else {
                print("⚠️ Flashlight not available")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if enable && self.flashlightBrightness > 0 {
                    // Use the user-configured brightness level (0.01 to 1.0)
                    // Clamp to minimum of 0.01 if brightness is > 0 to ensure it's visible
                    let level = max(0.01, self.flashlightBrightness)
                    try device.setTorchModeOn(level: level)
                    print("🔦 Flashlight turned ON at \(Int(level * 100))% brightness")
                } else {
                    device.torchMode = .off
                    print("🔦 Flashlight turned OFF")
                }
                
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.flashlightEnabled = enable && self.flashlightBrightness > 0
                }
            } catch {
                print("❌ Could not toggle flashlight: \(error)")
            }
        }
    }
    
    // Update flashlight brightness without turning it off/on
    private func updateFlashlightBrightness() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.captureDevice,
                  device.hasTorch,
                  device.torchMode == .on else {
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if self.flashlightBrightness > 0 {
                    let level = max(0.01, self.flashlightBrightness)
                    try device.setTorchModeOn(level: level)
                    print("🔦 Flashlight brightness adjusted to \(Int(level * 100))%")
                } else {
                    device.torchMode = .off
                    print("🔦 Flashlight turned OFF (brightness set to 0)")
                }
                
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.flashlightEnabled = self.flashlightBrightness > 0
                }
            } catch {
                print("❌ Could not adjust flashlight brightness: \(error)")
            }
        }
    }
    
    // MARK: - Brightness Analysis
    private func analyzeBrightness(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            return nil
        }
        
        // Define region of interest (center 30% of image)
        let roiWidth = Int(Double(width) * 0.3)
        let roiHeight = Int(Double(height) * 0.3)
        let startX = (width - roiWidth) / 2
        let startY = (height - roiHeight) / 2
        
        var totalBrightness: UInt64 = 0
        var pixelCount = 0
        
        // Sample brightness in ROI
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        for y in stride(from: startY, to: startY + roiHeight, by: 2) {  // Sample every other row
            for x in stride(from: startX, to: startX + roiWidth, by: 2) {  // Sample every other column
                let pixelIndex = y * bytesPerRow + x * 4
                
                // BGRA format
                let b = UInt64(data[pixelIndex])
                let g = UInt64(data[pixelIndex + 1])
                let r = UInt64(data[pixelIndex + 2])
                
                // Calculate perceived brightness (weighted by human eye sensitivity)
                let brightness = (r * 299 + g * 587 + b * 114) / 1000
                totalBrightness += brightness
                pixelCount += 1
            }
        }
        
        guard pixelCount > 0 else { return nil }
        
        // Normalize to 0-1 range
        let averageBrightness = Double(totalBrightness) / Double(pixelCount)
        return averageBrightness / 255.0
    }
    
    // MARK: - Rotation Detection
    private func detectRotation(brightness: Double) {
        // Add to history
        brightnessHistory.append(brightness)
        if brightnessHistory.count > historySize {
            brightnessHistory.removeFirst()
        }
        
        // Skip if calibrating
        if isCalibrating {
            updateCalibration(brightness: brightness)
            return
        }
        
        // State machine: waiting for high -> detect low -> waiting for high
        if isReadyForNewRotation && brightness < lowBrightnessThreshold {
            // Wheel has blocked the light - rotation detected!
            DispatchQueue.main.async { [weak self] in
                self?.rotationCount += 1
            }
            isReadyForNewRotation = false
            print("🔄 Rotation detected! Count: \(rotationCount + 1), Brightness: \(String(format: "%.3f", brightness))")
        } else if !isReadyForNewRotation && brightness > highBrightnessThreshold {
            // Wheel opening is visible again - ready for next rotation
            isReadyForNewRotation = true
        }
    }
    
    // MARK: - Load Saved Thresholds
    func loadSavedThresholds() {
        if let low = UserDefaults.standard.object(forKey: "opticalLowThreshold") as? Double,
           let high = UserDefaults.standard.object(forKey: "opticalHighThreshold") as? Double {
            lowBrightnessThreshold = low
            highBrightnessThreshold = high
            print("📱 Loaded optical thresholds - Low: \(low), High: \(high)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension OpticalWheelDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle frame processing
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= minimumFrameInterval else {
            return
        }
        lastProcessedTime = now
        
        // Analyze brightness
        guard let brightness = analyzeBrightness(from: sampleBuffer) else {
            return
        }
        
        // Update UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentBrightness = brightness
        }
        
        // Detect rotation
        detectRotation(brightness: brightness)
    }
}
