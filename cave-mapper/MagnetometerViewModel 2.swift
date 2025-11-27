//
//  MagnetometerViewModel 2.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 1.04.25.
//

import SwiftUI
import CoreMotion
import CoreLocation

enum MagneticAxis: String, CaseIterable, Identifiable, Codable {
    case x, y, z, magnitude
    var id: String { self.rawValue }
}

class MagnetometerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let selectedAxisKey = "selectedAxis"

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
            if let data = try? JSONEncoder().encode(selectedAxis) {
                UserDefaults.standard.set(data, forKey: selectedAxisKey)
            }
        }
    }

    @Published var revolutions = DataManager.loadPointNumber()
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

    private var isReadyForNewPeak = true
    private var previousMagnitude: Double = 0.0

    // Guided calibration buffers/timers
    private var calibrationSamples: [Double] = []
    private var calibrationTimer: Timer?

    override init() {
        let defaults = UserDefaults.standard
        self.wheelCircumference = defaults.object(forKey: "wheelCircumference") as? Double ?? 11.78

        if let low = defaults.object(forKey: "lowThreshold") as? Double,
           let high = defaults.object(forKey: "highThreshold") as? Double {
            self.lowThreshold = low
            self.highThreshold = high
            self.didCalibrate = true
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
        guard !isRunning else { return }
        isRunning = true

        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = 0.02
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.isRunning = true
            self.currentField = data.magneticField
            self.currentMagnitude = self.calculateMagnitude(data.magneticField)

            // Always add to history for monitoring
            self.magneticFieldHistory.append(self.currentMagnitude)
            if self.magneticFieldHistory.count > 50 {
                self.magneticFieldHistory.removeFirst()
            }
            
            // During guided calibration, collect samples and skip peak detection
            if self.isCalibrating {
                self.calibrationSamples.append(self.currentMagnitude)
            } else {
                // Normal operation: peak detection only
                self.detectPeak(self.currentMagnitude)
            }
        }

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func stopMonitoring() {
        motionManager.stopMagnetometerUpdates()
        locationManager.stopUpdatingHeading()
        isRunning = false
        stopCalibrationTimer()
    }

    private func calculateMagnitude(_ field: CMMagneticField) -> Double {
        switch selectedAxis {
        case .x: return abs(field.x)
        case .y: return abs(field.y)
        case .z: return abs(field.z)
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
        guard magneticFieldHistory.count >= 10 else { return }
        let sorted = magneticFieldHistory.sorted()
        
        // Use percentiles for more robust calibration
        let p30 = percentile(sorted, p: 30)  // Low threshold (baseline)
        let p70 = percentile(sorted, p: 70)  // High threshold (peak zone)
        
        lowThreshold  = p30  // didSet will save automatically
        highThreshold = p70  // didSet will save automatically
        didCalibrate = true
        
        print("📊 Quick calibration - Low: \(lowThreshold), High: \(highThreshold)")
    }

    // MARK: - Guided 10s Calibration

    func startCalibration(durationSeconds: Int = 10) {
        guard !isCalibrating else { return }
        isCalibrating = true
        calibrationSecondsRemaining = durationSeconds
        calibrationSamples.removeAll()

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
            return
        }

        let (low, high) = computeRobustThresholds(from: calibrationSamples)
        print("📊 Computed thresholds - Low: \(low), High: \(high)")

        // Sanity clamp to avoid inverted or too-close thresholds
        let minGap: Double = 20.0
        let finalLow = low
        var finalHigh = high
        if finalHigh - finalLow < minGap {
            finalHigh = finalLow + minGap
        }

        print("✅ Final thresholds - Low: \(finalLow), High: \(finalHigh)")
        
        self.lowThreshold = finalLow   // didSet will save automatically
        self.highThreshold = finalHigh // didSet will save automatically
        self.didCalibrate = true
    }

    // Robust stats: Use percentiles to find valley (baseline) and peak zones
    private func computeRobustThresholds(from samples: [Double]) -> (low: Double, high: Double) {
        let sorted = samples.sorted()
        
        // Find the baseline (valleys) and peak zones
        let p10 = percentile(sorted, p: 10)  // Lower baseline
        let p30 = percentile(sorted, p: 30)  // Upper baseline
        let p70 = percentile(sorted, p: 70)  // Lower peak zone
        let p90 = percentile(sorted, p: 90)  // Peak zone
        
        // Low threshold: Must drop below this to reset for next peak
        // Set it in the baseline zone (between valleys and median)
        let low = p30
        
        // High threshold: Must exceed this to trigger peak detection
        // Set it in the upper region (above median, into peak zone)
        let high = p70
        
        print("📈 Percentiles - P10: \(p10), P30: \(p30), P70: \(p70), P90: \(p90)")

        return (low, high)
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
