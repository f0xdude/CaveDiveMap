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
    @Published var highThreshold: Double = 1200
    @Published var lowThreshold: Double = 1130
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

    
    
    
    private var isReadyForNewPeak = true
    private let smoothing: Double = 0.1
    private var previousMagnitude: Double = 0.0
    private var calibrationSampleCount: Int = 0
    private let calibrationSamplesNeeded = 20

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
        
        
        guard !isRunning else { return } // Prevent duplicate starts
            isRunning = true
        
        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = 0.02
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.isRunning = true
            self.currentField = data.magneticField
            self.currentMagnitude = self.calculateMagnitude(data.magneticField)
            self.magneticFieldHistory.append(self.currentMagnitude)
            if self.magneticFieldHistory.count > 50 {
                self.magneticFieldHistory.removeFirst()
            }
            self.updateThresholds()
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

    private func calculateMagnitude(_ field: CMMagneticField) -> Double {
        switch selectedAxis {
        case .x:
            return abs(field.x)
        case .y:
            return abs(field.y)
        case .z:
            return abs(field.z)
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

    private func updateThresholds() {
        guard !didCalibrate, magneticFieldHistory.count >= 40 else { return }
        let mean = magneticFieldHistory.reduce(0, +) / Double(magneticFieldHistory.count)
        let sigma = sqrt(magneticFieldHistory.reduce(0) { $0 + pow($1 - mean, 2) } / Double(magneticFieldHistory.count))
        let offsetLow = max(30, sigma)
        let offsetHigh = max(60, sigma * 2)

        lowThreshold = lowThreshold * (1 - smoothing) + (mean + offsetLow) * smoothing
        highThreshold = highThreshold * (1 - smoothing) + (mean + offsetHigh) * smoothing

        calibrationSampleCount += 1
        if calibrationSampleCount >= calibrationSamplesNeeded {
            didCalibrate = true
            let defaults = UserDefaults.standard
            defaults.set(lowThreshold, forKey: "lowThreshold")
            defaults.set(highThreshold, forKey: "highThreshold")
        }
    }

    func runManualCalibration() {
        guard magneticFieldHistory.count >= 10 else { return }

        // Direct min/max rather than σ
        let minVal = magneticFieldHistory.min()!
        let maxVal = magneticFieldHistory.max()!

        // e.g. threshold crossings at 20%/80% of the peak‐to‐peak range:
        let range = maxVal - minVal
        lowThreshold  = minVal + 0.2 * range
        highThreshold = minVal + 0.8 * range

        didCalibrate = true
        let defaults = UserDefaults.standard
        defaults.set(lowThreshold,  forKey: "lowThreshold")
        defaults.set(highThreshold, forKey: "highThreshold")
    }


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
        calibrationSampleCount = 0
        magneticFieldHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "lowThreshold")
        UserDefaults.standard.removeObject(forKey: "highThreshold")
    }
}
