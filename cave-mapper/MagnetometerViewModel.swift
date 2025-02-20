//
//  MagnetometerViewModel.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 22.11.24.
//  Modified for one-time automatic magnetometer calibration with noise filtering
//

import SwiftUI
import CoreMotion
import CoreLocation

class MagnetometerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Properties
    
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // MARK: - UserDefaults Keys
    private struct DefaultsKeys {
        static let wheelCircumference = "wheelCircumference"
        static let lowThreshold = "lowThreshold"
        static let highThreshold = "highThreshold"
    }
    
    // MARK: - Published Properties
    // Default threshold values. (These will be updated during initial calibration.)
    @Published var highThreshold: Double = 1200
    @Published var lowThreshold: Double = 1130
    
    @Published var wheelCircumference: Double {
        didSet {
            UserDefaults.standard.set(wheelCircumference, forKey: DefaultsKeys.wheelCircumference)
        }
    }
    
    // Internal State
    @Published var revolutions = DataManager.loadPointNumber()
    @Published var isRunning = false
    @Published var currentField: CMMagneticField = CMMagneticField(x: 0, y: 0, z: 0)
    @Published var currentMagnitude: Double = 0.0
    /// Stores recent magnetometer magnitudes for auto calibration.
    @Published var magneticFieldHistory: [Double] = []
    @Published var currentHeading: CLHeading?          // Current heading from CoreLocation
    @Published var calibrationNeeded: Bool = false       // (For heading calibration)
    
    private var isReadyForNewPeak: Bool = true // Ensures a single revolution is counted per magnet pass
    private var lastPosition = CGPoint.zero    // Last position on the stick map
    
    // Smoothing constant for threshold updates.
    private let smoothing: Double = 0.1
    private var previousMagnitude: Double = 0.0
    
    // MARK: - Calibration State
    /// When `didCalibrate` is true, thresholds will no longer be updated.
    @Published var didCalibrate: Bool = false
    /// Computed property that returns true when calibration is in progress.
    var isCalibrating: Bool {
        return !didCalibrate
    }
    /// Count how many calibration samples we have processed.
    private var calibrationSampleCount: Int = 0
    /// The number of samples to use for calibration.
    private let calibrationSamplesNeeded = 20
    
    // MARK: - Initializer
    override init() {
        let userDefaults = UserDefaults.standard
        
        // Load wheelCircumference from UserDefaults or use a default value.
        if userDefaults.object(forKey: DefaultsKeys.wheelCircumference) != nil {
            self.wheelCircumference = userDefaults.double(forKey: DefaultsKeys.wheelCircumference)
        } else {
            self.wheelCircumference = 11.78 // Default value in centimeters
        }
        
        // Load previously calibrated thresholds if they exist.
        if let savedLowThreshold = userDefaults.object(forKey: DefaultsKeys.lowThreshold) as? Double,
           let savedHighThreshold = userDefaults.object(forKey: DefaultsKeys.highThreshold) as? Double {
            self.lowThreshold = savedLowThreshold
            self.highThreshold = savedHighThreshold
            self.didCalibrate = true
        }
        
        super.init()
        
        // Setup Location Manager for heading updates.
        locationManager.delegate = self
        locationManager.headingFilter = 1 // Update for every degree of heading change
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Monitoring Methods
    
    func startMonitoring() {
        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = 0.02  // Fast update interval
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.isRunning = true
            self.currentField = data.magneticField
            self.currentMagnitude = self.calculateMagnitude(data.magneticField)
            
            // Append the new reading to our history.
            self.magneticFieldHistory.append(self.currentMagnitude)
            if self.magneticFieldHistory.count > 50 {
                self.magneticFieldHistory.removeFirst()
            }
            
            // Update the thresholds only during the calibration period.
            self.updateThresholds()
            
            // Check for a magnet “peak” (a revolution) using the current thresholds.
            self.detectPeak(self.currentMagnitude)
        }
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    func stopMonitoring() {
        motionManager.stopMagnetometerUpdates()
        locationManager.stopUpdatingHeading()
        isRunning = false
    }
    
    // MARK: - Helper Methods
    
    /// Calculates the magnitude of the magnetic field vector.
    private func calculateMagnitude(_ magneticField: CMMagneticField) -> Double {
        return sqrt(pow(magneticField.x, 2) +
                    pow(magneticField.y, 2) +
                    pow(magneticField.z, 2))
    }
    
    /// Detects a magnet “peak” (when a revolution should be counted).
    ///
    /// The algorithm requires the reading to rise above the high threshold,
    /// then drop below the low threshold before allowing another revolution.
    private func detectPeak(_ magnitude: Double) {
        if isReadyForNewPeak && magnitude > highThreshold {
            // Peak detected – count a revolution.
            revolutions += 1
            isReadyForNewPeak = false
        } else if !isReadyForNewPeak && magnitude < lowThreshold {
            // Reset state – ready for the next peak.
            isReadyForNewPeak = true
        }
        previousMagnitude = magnitude
    }
    
    /// Updates the thresholds automatically based on a running average and standard deviation.
    ///
    /// This method computes the mean and standard deviation of the recent magnetometer values.
    /// It then sets the low threshold to (mean + offsetLow) and the high threshold to (mean + offsetHigh).
    /// After processing a fixed number of samples (calibration period), the thresholds are saved to UserDefaults
    /// and further updates are disabled.
    ///
    private func updateThresholds() {
        // If calibration is complete, do not update thresholds.
        guard !didCalibrate else { return }
        
        let count = magneticFieldHistory.count
        guard count >= 20 else { return }
        
        // Compute the average of the recent readings.
        let mean = magneticFieldHistory.reduce(0, +) / Double(count)
        
        // Compute standard deviation.
        let variance = magneticFieldHistory.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count)
        let sigma = sqrt(variance)
        
        // Determine offsets (using a minimum value to avoid false triggers when noise is low).
        let offsetLow = max(30, sigma)
        let offsetHigh = max(60, sigma * 2)
        
        let newLowThreshold = mean + offsetLow
        let newHighThreshold = mean + offsetHigh
        
        // Smoothly update the thresholds.
        lowThreshold = lowThreshold * (1 - smoothing) + newLowThreshold * smoothing
        highThreshold = highThreshold * (1 - smoothing) + newHighThreshold * smoothing
        
        calibrationSampleCount += 1
        // Once we have enough samples, finalize calibration and save the thresholds.
        if calibrationSampleCount >= calibrationSamplesNeeded {
            didCalibrate = true
            UserDefaults.standard.set(lowThreshold, forKey: DefaultsKeys.lowThreshold)
            UserDefaults.standard.set(highThreshold, forKey: DefaultsKeys.highThreshold)
            print("Calibration complete. Saved thresholds: low = \(lowThreshold), high = \(highThreshold)")
        }
    }
    
    /// Immediately runs calibration using the current magnetic field history.
    func runManualCalibration() {
        let count = magneticFieldHistory.count
        guard count >= 10 else {
            print("Not enough samples for calibration.")
            return
        }
        
        // Compute the mean of the recent readings.
        let mean = magneticFieldHistory.reduce(0, +) / Double(count)
        
        // Compute standard deviation.
        let variance = magneticFieldHistory.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count)
        let sigma = sqrt(variance)
        
        // Determine offsets (using a minimum value to avoid false triggers when noise is low).
        let offsetLow = max(30, sigma)
        let offsetHigh = max(60, sigma * 2)
        
        // Calculate new thresholds.
        let newLowThreshold = mean + offsetLow
        let newHighThreshold = mean + offsetHigh
        
        // Update thresholds immediately.
        lowThreshold = newLowThreshold
        highThreshold = newHighThreshold
        
        // Mark calibration as complete and store thresholds.
        didCalibrate = true
        UserDefaults.standard.set(lowThreshold, forKey: DefaultsKeys.lowThreshold)
        UserDefaults.standard.set(highThreshold, forKey: DefaultsKeys.highThreshold)
        
        print("Manual calibration complete: Low = \(lowThreshold), High = \(highThreshold)")
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading
            
            if newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > 11 {
                self.calibrationNeeded = true
            } else {
                self.calibrationNeeded = false
            }
        }
    }
    
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
//        if let currentHeading = currentHeading {
//            return currentHeading.headingAccuracy < 0 || currentHeading.headingAccuracy > 20
//        }
        return true
    }
    
    /// (Optional) Method to trigger heading calibration.
    func startCalibration() {
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    // MARK: - Computed Properties for Distance
    
    var distanceInCentimeters: Double {
        return Double(revolutions) * wheelCircumference
    }
    
    var distanceInMeters: Double {
        return distanceInCentimeters / 100.0
    }
    
    /// Distance in meters rounded to two decimal places.
    var roundedDistanceInMeters: Double {
        return (distanceInMeters * 100).rounded() / 100
    }
    
    /// Magnetic heading rounded to two decimal places.
    var roundedMagneticHeading: Double? {
        guard let heading = currentHeading else { return nil }
        return (heading.magneticHeading * 100).rounded() / 100
    }
    
    /// True heading rounded to two decimal places.
    var roundedTrueHeading: Double? {
        guard let heading = currentHeading else { return nil }
        return (heading.trueHeading * 100).rounded() / 100
    }
    
    // MARK: - Reset Method
    
    /// Resets the wheel circumference to its default value.
    /// (Note: Thresholds are now computed automatically at startup.)
    func resetToDefaults() {
        wheelCircumference = 11.78
    }
    
    /// (Optional) Resets the magnetometer thresholds to force recalibration.
    /// This method clears the stored threshold values and resets the calibration state.
    func resetThresholdCalibration() {
        didCalibrate = false
        calibrationSampleCount = 0
        magneticFieldHistory.removeAll()
        // Optionally, remove the stored thresholds.
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.lowThreshold)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.highThreshold)
    }
}
