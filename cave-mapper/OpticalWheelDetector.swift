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
    /// Outcome of the last calibration, for the settings screen.
    @Published var calibrationMessage: String?
    @Published var calibrationFailed: Bool = false
    @Published var flashlightEnabled: Bool = true
    @Published var flashlightBrightness: Float = 0.5 {  // 0.0 to 1.0 (0% to 100%)
        didSet {
            UserDefaults.standard.set(flashlightBrightness, forKey: "opticalFlashlightBrightness")
            // Update flashlight if currently running
            if isRunning {
                if flashlightBrightness > 0 {
                    // Turn on or update brightness
                    updateFlashlightBrightness()
                } else {
                    // Turn off when set to 0
                    enableFlashlight(false)
                }
            }
        }
    }
    
    // MARK: - Private Properties
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "optical.wheel.detector")
    private var captureDevice: AVCaptureDevice?
    
    // Threading: the capture queue only measures a frame's brightness. Everything
    // that reads or writes detector state — thresholds, calibration, the rotation
    // state machine, every @Published property — runs on the main thread. It used
    // to be split across both with no synchronisation, and calibration published
    // to SwiftUI from the capture queue.

    // Detection state
    private var isReadyForNewRotation = true
    private var brightnessHistory: [Double] = []
    private let historySize = 30  // Track last 30 frames
    
    // Calibration
    private var calibrationSamples: [Double] = []
    private let calibrationDuration = 10.0  // seconds
    private var calibrationStartTime: Date?
    /// Auto-exposure meters the turning wheel for this long before it is locked;
    /// only samples taken after the lock count towards the thresholds.
    private let calibrationExposureSettleTime = 2.0
    /// Below this dark-to-bright swing (normalised 0–1) the wheel was not turning
    /// or the opening is not in view.
    private let minCalibrationSwing = 0.1

    // Exposure. Brightness thresholds only mean anything at the exposure they
    // were calibrated under, so that exposure is stored with them and restored on
    // every start. Detection restarts at every station; re-metering each time
    // locked onto whatever the wheel happened to show at that moment.
    private let exposureDurationKey = "opticalExposureDurationSeconds"
    private let exposureISOKey = "opticalExposureISO"
    /// Bumped on every exposure change so a pending delayed lock from an earlier
    /// start cannot fire into a later one. Capture queue only.
    private var exposureGeneration = 0

    // Every frame is analysed (the old 20 fps cap could step right over the
    // opening on a fast wheel); only the UI readout is rate-limited.
    private var lastBrightnessPublishTime: TimeInterval = 0
    private let brightnessPublishInterval: TimeInterval = 0.1
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        // Load saved flashlight brightness
        if let savedBrightness = UserDefaults.standard.object(forKey: "opticalFlashlightBrightness") as? Float {
            self.flashlightBrightness = max(0.0, min(1.0, savedBrightness))  // Clamp to 0-1
        }

        // Calibrated thresholds were only loaded when the Settings screen opened,
        // so after a relaunch detection ran on the 0.3/0.6 defaults until then.
        loadSavedThresholds()

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
    
    // MARK: - Exposure (capture queue)

    /// Restores the calibrated exposure, or — before the first calibration under
    /// this scheme — meters for a second and locks, as older builds did.
    private func applyExposurePolicy() {
        exposureGeneration += 1
        if applySavedExposure() { return }

        setContinuousAutoExposure()
        lockExposure(after: 1.0)
    }

    private func applySavedExposure() -> Bool {
        let defaults = UserDefaults.standard
        guard let device = captureDevice,
              device.isExposureModeSupported(.custom),
              let seconds = defaults.object(forKey: exposureDurationKey) as? Double,
              let iso = defaults.object(forKey: exposureISOKey) as? Float,
              seconds > 0, iso > 0 else { return false }

        let format = device.activeFormat
        let minSeconds = CMTimeGetSeconds(format.minExposureDuration)
        let maxSeconds = CMTimeGetSeconds(format.maxExposureDuration)
        let duration = CMTimeMakeWithSeconds(min(max(seconds, minSeconds), maxSeconds),
                                             preferredTimescale: 1_000_000)
        let clampedISO = min(max(iso, format.minISO), format.maxISO)

        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            device.unlockForConfiguration()
            print("🔒 Restored calibrated exposure: \(seconds)s, ISO \(clampedISO)")
            return true
        } catch {
            print("⚠️ Could not restore exposure: \(error)")
            return false
        }
    }

    private func setContinuousAutoExposure() {
        guard let device = captureDevice,
              device.isExposureModeSupported(.continuousAutoExposure) else { return }
        do {
            try device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        } catch {
            print("⚠️ Could not enable auto exposure: \(error)")
        }
    }

    private func lockExposure(after delay: TimeInterval) {
        let generation = exposureGeneration
        sessionQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.exposureGeneration == generation else { return }
            self.lockExposure()
        }
    }

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
            
            self.applyExposurePolicy()
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
                // With no frames arriving a calibration could never finish, and
                // rotation counting stays off for as long as it is "running".
                self.cancelCalibration()
                self.enableFlashlight(false)
                print("✅ Optical detection stopped, flashlight disabled")
            }
        }
    }
    
    func resetRotationCount() {
        rotationCount = 0
    }
    
    // MARK: - Calibration (main thread)
    func startCalibration() {
        guard !isCalibrating else { return }
        
        isCalibrating = true
        calibrationSamples.removeAll()
        calibrationStartTime = Date()
        calibrationProgress = 0.0
        calibrationMessage = nil
        calibrationFailed = false

        // Meter on the turning wheel, so the exposure is set by the average of
        // blocked and open rather than by whichever one is in view, then lock it
        // before any sample is taken.
        let settle = calibrationExposureSettleTime
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.exposureGeneration += 1
            self.setContinuousAutoExposure()
            self.lockExposure(after: settle)
        }
        
        print("🔦 Starting optical calibration - rotate the wheel steadily for \(Int(calibrationDuration))s")
    }
    
    func cancelCalibration() {
        guard isCalibrating else { return }
        isCalibrating = false
        calibrationSamples.removeAll()
        calibrationStartTime = nil
        calibrationProgress = 0.0
        restoreExposureAfterAbandonedCalibration()
    }

    /// The existing thresholds stay in force, so the exposure they belong to has
    /// to come back too.
    private func restoreExposureAfterAbandonedCalibration() {
        sessionQueue.async { [weak self] in
            self?.applyExposurePolicy()
        }
    }
    
    private func updateCalibration(brightness: Double) {
        guard isCalibrating, let startTime = calibrationStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        calibrationProgress = min(elapsed / calibrationDuration, 1.0)

        // Exposure is still moving until the lock (plus a little slack for it to
        // take effect); brightness measured before then is not comparable.
        if elapsed >= calibrationExposureSettleTime + 0.3 {
            calibrationSamples.append(brightness)
        }
        
        if elapsed >= calibrationDuration {
            finishCalibration()
        }
    }
    
    private func finishCalibration() {
        isCalibrating = false
        calibrationStartTime = nil
        defer { calibrationSamples.removeAll() }
        
        guard calibrationSamples.count >= 50 else {
            print("⚠️ Not enough calibration samples: \(calibrationSamples.count)")
            calibrationFailed = true
            calibrationMessage = "Calibration failed: no camera frames. Thresholds unchanged."
            restoreExposureAfterAbandonedCalibration()
            return
        }
        
        let sorted = calibrationSamples.sorted()
        
        // Thresholds at 35 % and 65 % of the dark-to-bright swing. They used to
        // be derived from the 25th/75th percentiles, which measure how long the
        // wheel spends at each level: an opening narrower than a quarter turn put
        // both percentiles on the blocked level and the thresholds in its noise.
        // The 5th/95th percentiles stand in for min/max so a stray frame cannot
        // set the scale.
        let dark = percentile(sorted, percent: 5)
        let bright = percentile(sorted, percent: 95)
        let swing = bright - dark

        guard swing >= minCalibrationSwing else {
            print("⚠️ Optical calibration swing too small: \(swing)")
            calibrationFailed = true
            calibrationMessage = String(format: "Calibration failed: brightness only varied by %.2f. Keep the wheel turning and check the opening is in view. Thresholds unchanged.", swing)
            restoreExposureAfterAbandonedCalibration()
            return
        }

        lowBrightnessThreshold = dark + 0.35 * swing
        highBrightnessThreshold = dark + 0.65 * swing
        
        print("✅ Optical calibration complete")
        print("   Low threshold: \(String(format: "%.3f", lowBrightnessThreshold))")
        print("   High threshold: \(String(format: "%.3f", highBrightnessThreshold))")
        print("   Swing: \(String(format: "%.3f", swing))")
        
        // Save to UserDefaults, together with the exposure they were measured at.
        let defaults = UserDefaults.standard
        defaults.set(lowBrightnessThreshold, forKey: "opticalLowThreshold")
        defaults.set(highBrightnessThreshold, forKey: "opticalHighThreshold")
        if let device = captureDevice {
            let seconds = CMTimeGetSeconds(device.exposureDuration)
            if seconds.isFinite, seconds > 0, device.iso > 0 {
                defaults.set(seconds, forKey: exposureDurationKey)
                defaults.set(device.iso, forKey: exposureISOKey)
            }
        }

        calibrationFailed = false
        calibrationMessage = String(format: "Calibrated. Brightness swing %.2f.", swing)
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
    
    // Update flashlight brightness, turning it on if needed
    private func updateFlashlightBrightness() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.captureDevice,
                  device.hasTorch else {
                print("⚠️ Flashlight not available for brightness update")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if self.flashlightBrightness > 0 {
                    let level = max(0.01, self.flashlightBrightness)
                    try device.setTorchModeOn(level: level)
                    print("🔦 Flashlight brightness set to \(Int(level * 100))%")
                    
                    DispatchQueue.main.async {
                        self.flashlightEnabled = true
                    }
                } else {
                    device.torchMode = .off
                    print("🔦 Flashlight turned OFF (brightness set to 0)")
                    
                    DispatchQueue.main.async {
                        self.flashlightEnabled = false
                    }
                }
                
                device.unlockForConfiguration()
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
    
    // MARK: - Rotation Detection (main thread)
    private func handleBrightness(_ brightness: Double) {
        let now = CACurrentMediaTime()
        if now - lastBrightnessPublishTime >= brightnessPublishInterval {
            currentBrightness = brightness
            lastBrightnessPublishTime = now
        }
        detectRotation(brightness: brightness)
    }

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
            rotationCount += 1
            isReadyForNewRotation = false
            print("🔄 Rotation detected! Count: \(rotationCount), Brightness: \(String(format: "%.3f", brightness))")
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
        // Capture queue: measure only, then hand over to the main thread, which
        // owns all detector state. Blocks run in order, so no frame is skipped or
        // reordered even if the main thread is briefly busy.
        guard let brightness = analyzeBrightness(from: sampleBuffer) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.handleBrightness(brightness)
        }
    }
}
