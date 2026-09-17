//
//  MagnetometerViewModel 2.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 1.04.25.
//

import SwiftUI
import CoreMotion
import CoreLocation
import QuartzCore

enum MagneticAxis: String, CaseIterable, Identifiable, Codable {
    case x, y, z, magnitude
    var id: String { self.rawValue }
}

class MagnetometerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let selectedAxisKey = "selectedAxis"
    private let signedAxisKey = "axisThresholdsAreSigned"

    /// Single-axis detection used to threshold `abs(axis)`. When the magnet swings
    /// that axis through zero, the absolute value has two humps per revolution and
    /// the wheel double counts. The signed value has exactly one cycle per
    /// revolution whatever its polarity.
    ///
    /// Thresholds saved by an older build were calibrated against the absolute
    /// value, so they keep that meaning until the next guided calibration, which
    /// samples the signed signal and switches this on for good.
    private var useSignedAxis: Bool
    private var signedAxisBeforeCalibration: Bool?

    // MARK: - Published Properties
    @Published var highThreshold: Double = 1200 {
        didSet {
            UserDefaults.standard.set(highThreshold, forKey: "highThreshold")
        }
    }
    @Published var lowThreshold: Double = 1130 {
        didSet {
            UserDefaults.standard.set(lowThreshold, forKey: "lowThreshold")
        }
    }
    @Published var wheelCircumference: Double {
        didSet {
            UserDefaults.standard.set(wheelCircumference, forKey: "wheelCircumference")
        }
    }

    @Published var selectedAxis: MagneticAxis {
        didSet {
            // Debounce UserDefaults writes to avoid blocking main thread
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(self.selectedAxis) {
                    UserDefaults.standard.set(data, forKey: self.selectedAxisKey)
                }
            }
        }
    }

    @Published var revolutions = DataManager.loadRotationCount()
    @Published var isRunning = false
    @Published var currentField: CMMagneticField = CMMagneticField(x: 0, y: 0, z: 0)
    @Published var currentMagnitude: Double = 0.0
    @Published var magneticFieldHistory: [Double] = []
    @Published var currentHeading: CLHeading?
    @Published var calibrationNeeded: Bool = false
    @Published var didCalibrate: Bool = false

    // Guided calibration session
    @Published var isCalibrating: Bool = false
    @Published var calibrationSecondsRemaining: Int = 0
    /// Outcome of the last guided calibration, for the settings screen.
    @Published var calibrationMessage: String?
    @Published var calibrationFailed: Bool = false

    /// Below this peak-to-peak swing (µT) the samples are just sensor noise and
    /// phone movement: the wheel was not turning, or the magnet is out of range.
    private let minCalibrationSwing: Double = 20.0

    private var isReadyForNewPeak = true
    private var previousMagnitude: Double = 0.0

    // Guided calibration buffers/timers
    private var calibrationSamples: [Double] = []
    private var calibrationTimer: Timer?
    
    // Throttle UI updates to reduce main thread congestion
    private var lastUIUpdateTime: TimeInterval = 0
    private let uiUpdateInterval: TimeInterval = 0.1 // Update UI at most 10Hz instead of 50Hz

    override init() {
        let defaults = UserDefaults.standard
        self.wheelCircumference = defaults.object(forKey: "wheelCircumference") as? Double ?? 11.78

        if let low = defaults.object(forKey: "lowThreshold") as? Double,
           let high = defaults.object(forKey: "highThreshold") as? Double {
            self.lowThreshold = low
            self.highThreshold = high
            self.didCalibrate = true
            self.useSignedAxis = defaults.bool(forKey: signedAxisKey)
        } else {
            // Nothing calibrated yet, so there is no legacy meaning to preserve.
            self.useSignedAxis = true
        }

        if let data = defaults.data(forKey: selectedAxisKey),
           let axis = try? JSONDecoder().decode(MagneticAxis.self, from: data) {
            self.selectedAxis = axis
        } else {
            self.selectedAxis = .magnitude
        }

        super.init()

        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.requestWhenInUseAuthorization()
    }

    func startMonitoring() {
        print("🧲 MagnetometerViewModel.startMonitoring() called, isRunning=\(isRunning)")
        
        // Stop first if already running to ensure clean state
        if isRunning || motionManager.isMagnetometerActive {
            print("⚠️ Magnetometer already active, stopping first")
            stopMonitoring()
        }
        
        isRunning = true

        guard motionManager.isMagnetometerAvailable else { 
            print("❌ Magnetometer not available")
            return 
        }
        
        motionManager.magnetometerUpdateInterval = 0.02
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.isRunning = true
            
            // Calculate magnitude immediately (needed for peak detection)
            let magnitude = self.calculateMagnitude(data.magneticField)
            
            // Throttle UI updates to reduce main thread congestion
            // Only update @Published properties at most 10Hz instead of 50Hz
            let now = CACurrentMediaTime()
            let shouldUpdateUI = (now - self.lastUIUpdateTime) >= self.uiUpdateInterval
            
            if shouldUpdateUI {
                self.currentField = data.magneticField
                self.currentMagnitude = magnitude
                self.lastUIUpdateTime = now
                
                // Update history for monitoring (but less frequently)
                self.magneticFieldHistory.append(magnitude)
                if self.magneticFieldHistory.count > 50 {
                    self.magneticFieldHistory.removeFirst()
                }
            }
            
            // During guided calibration, collect samples and skip peak detection
            if self.isCalibrating {
                self.calibrationSamples.append(magnitude)
            } else {
                // Normal operation: peak detection runs at full rate (50Hz) for accuracy
                self.detectPeak(magnitude)
            }
        }

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        print("✅ Magnetic monitoring started")
    }

    func stopMonitoring() {
        print("🛑 MagnetometerViewModel.stopMonitoring() called")
        motionManager.stopMagnetometerUpdates()
        locationManager.stopUpdatingHeading()
        isRunning = false
        // Not just the timer: left with isCalibrating == true and no timer to end
        // it, peak detection would stay switched off for good.
        cancelCalibration()
        print("✅ Magnetic monitoring stopped")
    }

    private func calculateMagnitude(_ field: CMMagneticField) -> Double {
        switch selectedAxis {
        case .x: return useSignedAxis ? field.x : abs(field.x)
        case .y: return useSignedAxis ? field.y : abs(field.y)
        case .z: return useSignedAxis ? field.z : abs(field.z)
        case .magnitude:
            return sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        }
    }

    private func detectPeak(_ magnitude: Double) {
        if isReadyForNewPeak && magnitude > highThreshold {
            revolutions += 1
            isReadyForNewPeak = false
        } else if !isReadyForNewPeak && magnitude < lowThreshold {
            isReadyForNewPeak = true
        }
        previousMagnitude = magnitude
    }

    // MARK: - Manual Calibrations
    func runManualCalibration() {
        guard magneticFieldHistory.count >= 10,
              let (low, high) = computeRobustThresholds(from: magneticFieldHistory) else { return }

        lowThreshold  = low   // didSet will save automatically
        highThreshold = high  // didSet will save automatically
        didCalibrate = true

        print("📊 Quick calibration - Low: \(lowThreshold), High: \(highThreshold)")
    }

    // MARK: - Guided 10s Calibration

    func startCalibration(durationSeconds: Int = 10) {
        guard !isCalibrating else { return }
        isCalibrating = true
        calibrationSecondsRemaining = durationSeconds
        calibrationSamples.removeAll()
        calibrationMessage = nil
        calibrationFailed = false
        // Sample the signed axis from here on; restored if this run is abandoned.
        signedAxisBeforeCalibration = useSignedAxis
        useSignedAxis = true

        stopCalibrationTimer()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { return }
            self.calibrationSecondsRemaining -= 1
            if self.calibrationSecondsRemaining <= 0 {
                t.invalidate()
                self.finishCalibration()
            }
        }
        RunLoop.current.add(calibrationTimer!, forMode: .common)
    }

    func cancelCalibration() {
        guard isCalibrating else { return }
        stopCalibrationTimer()
        isCalibrating = false
        calibrationSamples.removeAll()
        calibrationSecondsRemaining = 0
        restoreAxisModeAfterAbandonedCalibration()
    }

    private func restoreAxisModeAfterAbandonedCalibration() {
        if let previous = signedAxisBeforeCalibration {
            useSignedAxis = previous
        }
        signedAxisBeforeCalibration = nil
    }

    private func stopCalibrationTimer() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
    }

    private func finishCalibration() {
        isCalibrating = false
        defer { calibrationSamples.removeAll() }

        print("🔧 Calibration finished. Sample count: \(calibrationSamples.count)")
        
        guard calibrationSamples.count >= 100 else {
            // Not enough data; do not change thresholds
            print("⚠️ Not enough samples collected. Need at least 100, got \(calibrationSamples.count)")
            restoreAxisModeAfterAbandonedCalibration()
            calibrationFailed = true
            calibrationMessage = "Calibration failed: no magnetometer data. Thresholds unchanged."
            return
        }

        guard let (low, high) = computeRobustThresholds(from: calibrationSamples) else {
            // The old code pressed on and planted both thresholds inside the
            // noise, which counts phantom rotations from then on.
            restoreAxisModeAfterAbandonedCalibration()
            calibrationFailed = true
            calibrationMessage = String(format: "Calibration failed: the signal varied by less than %.0f µT. Keep the wheel turning for the whole 10 s. Thresholds unchanged.", minCalibrationSwing)
            return
        }

        print("✅ Final thresholds - Low: \(low), High: \(high)")

        self.lowThreshold = low    // didSet will save automatically
        self.highThreshold = high  // didSet will save automatically
        self.didCalibrate = true

        signedAxisBeforeCalibration = nil
        UserDefaults.standard.set(true, forKey: signedAxisKey)

        calibrationFailed = false
        calibrationMessage = String(format: "Calibrated. Signal swing %.0f µT.", (high - low) / 0.3)
    }

    /// Thresholds at 35 % and 65 % of the measured swing, or nil when there is no
    /// usable swing.
    ///
    /// These used to be the 30th and 70th percentile of the samples, which places
    /// them by how much *time* the signal spends at each level rather than by its
    /// amplitude. A magnet that is only close for a short part of each turn puts
    /// both percentiles inside the resting level, and the raw magnetometer's
    /// resting level moves by tens of µT as the phone turns in the Earth's field
    /// — enough to lift it over the low threshold, after which the detector
    /// never re-arms and the count stops. Amplitude-based thresholds sit in the
    /// middle of the swing with the widest margin to both the rest level and the
    /// peak. The 2nd/98th percentiles stand in for min/max so a single spike
    /// cannot set the scale.
    private func computeRobustThresholds(from samples: [Double]) -> (low: Double, high: Double)? {
        let sorted = samples.sorted()
        let rest = percentile(sorted, p: 2)
        let peak = percentile(sorted, p: 98)
        let swing = peak - rest

        print("📈 Calibration - rest: \(rest), peak: \(peak), swing: \(swing)")

        guard swing >= minCalibrationSwing else { return nil }
        return (rest + 0.35 * swing, rest + 0.65 * swing)
    }

    private func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clampedP = max(0, min(100, p))
        let idx = (clampedP / 100.0) * Double(sorted.count - 1)
        let lo = Int(floor(idx))
        let hi = Int(ceil(idx))
        if lo == hi { return sorted[lo] }
        let t = idx - Double(lo)
        return (1 - t) * sorted[lo] + t * sorted[hi]
    }

    // MARK: - CLLocation

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading
            self.calibrationNeeded = newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > 11
        }
    }

    var revolutionCount: Int {
        return revolutions
    }

    var dynamicDistanceInMeters: Double {
        Double(revolutionCount) * wheelCircumference / 100.0
    }

    var roundedDistanceInMeters: Double {
        (dynamicDistanceInMeters * 100).rounded() / 100
    }

    var roundedMagneticHeading: Double? {
        guard let heading = currentHeading else { return nil }
        return (heading.magneticHeading * 100).rounded() / 100
    }

    func resetToDefaults() {
        wheelCircumference = 11.78
    }

    func resetThresholdCalibration() {
        didCalibrate = false
        magneticFieldHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "lowThreshold")
        UserDefaults.standard.removeObject(forKey: "highThreshold")
    }
}
