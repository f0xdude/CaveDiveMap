//
//  PCAMagneticDetector.swift
//  cave-mapper
//
//  Created on 12/27/25.
//

import SwiftUI
import CoreMotion
import CoreLocation
import Accelerate

/// PCA-based magnetic rotation detector
/// Uses Principal Component Analysis to find the dominant direction of magnetic field variation
/// and projects samples onto that direction for more robust rotation counting
class PCAMagneticDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // MARK: - Published Properties
    @Published var revolutions = 0
    @Published var isRunning = false
    @Published var currentField: CMMagneticField = CMMagneticField(x: 0, y: 0, z: 0)
    @Published var currentMagnitude: Double = 0.0
    @Published var currentHeading: CLHeading?
    @Published var calibrationNeeded: Bool = false
    @Published var signalQuality: Double = 0.0 // 0-1, how dominant the first eigenvalue is
    
    @Published var wheelCircumference: Double {
        didSet {
            UserDefaults.standard.set(wheelCircumference, forKey: "wheelCircumference")
        }
    }
    
    // MARK: - PCA Configuration
    private let windowSize = 100 // Number of recent samples to keep for PCA
    private let minSamplesForPCA = 50 // Minimum samples needed before running PCA
    private let updatePCAEvery = 10 // Update PCA every N samples
    
    // MARK: - Sliding Window
    private var magneticSamples: [(x: Double, y: Double, z: Double)] = []
    private var sampleCounter = 0
    
    // MARK: - PCA Results
    private var principalComponent: (x: Double, y: Double, z: Double) = (1, 0, 0) // Default to X axis
    private var projectedSignal: [Double] = []
    private var lastProjectedValue: Double = 0
    
    // MARK: - Peak Detection
    @Published var highThreshold: Double = 0.5 {
        didSet {
            UserDefaults.standard.set(highThreshold, forKey: "pcaHighThreshold")
        }
    }
    @Published var lowThreshold: Double = -0.5 {
        didSet {
            UserDefaults.standard.set(lowThreshold, forKey: "pcaLowThreshold")
        }
    }
    
    private var isReadyForNewPeak = true
    
    // MARK: - Motion Filtering (suppress during phone rotation)
    private let gyroThreshold: Double = 0.5 // rad/s - suppress if phone is rotating faster than this
    private var isPhoneMoving = false
    
    // MARK: - Calibration
    @Published var isCalibrating: Bool = false
    @Published var calibrationSecondsRemaining: Int = 0
    @Published var didCalibrate: Bool = false
    
    private var calibrationSamples: [Double] = []
    private var calibrationTimer: Timer?
    
    override init() {
        let defaults = UserDefaults.standard
        self.wheelCircumference = defaults.object(forKey: "wheelCircumference") as? Double ?? 11.78
        
        if let low = defaults.object(forKey: "pcaLowThreshold") as? Double,
           let high = defaults.object(forKey: "pcaHighThreshold") as? Double {
            self.lowThreshold = low
            self.highThreshold = high
            self.didCalibrate = true
        }
        
        super.init()
        
        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Start/Stop
    func startMonitoring() {
        print("🧲 PCAMagneticDetector.startMonitoring() called")
        
        if isRunning || motionManager.isMagnetometerActive {
            print("⚠️ PCA detector already active, stopping first")
            stopMonitoring()
        }
        
        isRunning = true
        
        guard motionManager.isMagnetometerAvailable else {
            print("❌ Magnetometer not available")
            return
        }
        
        // Start magnetometer updates
        motionManager.magnetometerUpdateInterval = 0.02 // 50 Hz
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.processMagnetometerData(data.magneticField)
        }
        
        // Start gyroscope for motion detection
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1 // 10 Hz is sufficient for motion detection
            motionManager.startGyroUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let data = data, error == nil else { return }
                self.processGyroData(data.rotationRate)
            }
        }
        
        // Start heading updates
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        print("✅ PCA magnetic monitoring started")
    }
    
    func stopMonitoring() {
        print("🛑 PCAMagneticDetector.stopMonitoring() called")
        motionManager.stopMagnetometerUpdates()
        motionManager.stopGyroUpdates()
        locationManager.stopUpdatingHeading()
        isRunning = false
        stopCalibrationTimer()
        print("✅ PCA magnetic monitoring stopped")
    }
    
    // MARK: - Data Processing
    private func processMagnetometerData(_ field: CMMagneticField) {
        currentField = field
        currentMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        
        // Add to sliding window
        magneticSamples.append((x: field.x, y: field.y, z: field.z))
        if magneticSamples.count > windowSize {
            magneticSamples.removeFirst()
        }
        
        sampleCounter += 1
        
        // Update PCA periodically
        if sampleCounter % updatePCAEvery == 0 && magneticSamples.count >= minSamplesForPCA {
            updatePCA()
        }
        
        // Project current sample onto principal component
        let projected = projectSample(field)
        
        // During calibration, collect samples
        if isCalibrating {
            calibrationSamples.append(projected)
        } else if !isPhoneMoving {
            // Only detect peaks when phone is stable
            detectPeak(projected)
        }
        
        // Keep history of projected signal for visualization
        projectedSignal.append(projected)
        if projectedSignal.count > 50 {
            projectedSignal.removeFirst()
        }
        
        lastProjectedValue = projected
    }
    
    private func processGyroData(_ rotationRate: CMRotationRate) {
        // Check if phone is rotating
        let totalRotation = sqrt(
            rotationRate.x * rotationRate.x +
            rotationRate.y * rotationRate.y +
            rotationRate.z * rotationRate.z
        )
        
        isPhoneMoving = totalRotation > gyroThreshold
    }
    
    // MARK: - PCA Algorithm
    private func updatePCA() {
        guard magneticSamples.count >= minSamplesForPCA else { return }
        
        // Step 1: Compute mean of each axis
        var meanX: Double = 0
        var meanY: Double = 0
        var meanZ: Double = 0
        
        for sample in magneticSamples {
            meanX += sample.x
            meanY += sample.y
            meanZ += sample.z
        }
        
        let n = Double(magneticSamples.count)
        meanX /= n
        meanY /= n
        meanZ /= n
        
        // Step 2: Center the data
        var centeredSamples: [(x: Double, y: Double, z: Double)] = []
        for sample in magneticSamples {
            centeredSamples.append((
                x: sample.x - meanX,
                y: sample.y - meanY,
                z: sample.z - meanZ
            ))
        }
        
        // Step 3: Compute covariance matrix (3x3)
        // Cov = (1/n) * X^T * X where X is the centered data matrix
        var cxx: Double = 0, cxy: Double = 0, cxz: Double = 0
        var cyy: Double = 0, cyz: Double = 0, czz: Double = 0
        
        for sample in centeredSamples {
            cxx += sample.x * sample.x
            cxy += sample.x * sample.y
            cxz += sample.x * sample.z
            cyy += sample.y * sample.y
            cyz += sample.y * sample.z
            czz += sample.z * sample.z
        }
        
        cxx /= n
        cxy /= n
        cxz /= n
        cyy /= n
        cyz /= n
        czz /= n
        
        // Covariance matrix is symmetric:
        // [cxx cxy cxz]
        // [cxy cyy cyz]
        // [cxz cyz czz]
        
        // Step 4: Find eigenvalues and eigenvectors using Accelerate framework
        // We need to convert to a format Accelerate can use
        var matrix = [cxx, cxy, cxz,
                      cxy, cyy, cyz,
                      cxz, cyz, czz]
        
        var eigenvalues = [Double](repeating: 0, count: 3)
        var eigenvectors = [Double](repeating: 0, count: 9)
        
        var n_int32: __CLPK_integer = 3
        var lda: __CLPK_integer = 3
        var lwork: __CLPK_integer = 9
        var work = [Double](repeating: 0, count: Int(lwork))
        var info: __CLPK_integer = 0
        var jobz: Int8 = Int8(UnicodeScalar("V").value) // Compute eigenvectors
        var uplo: Int8 = Int8(UnicodeScalar("U").value) // Upper triangle
        
        // Call LAPACK's dsyev to compute eigenvalues and eigenvectors
        dsyev_(&jobz, &uplo, &n_int32, &matrix, &lda, &eigenvalues, &work, &lwork, &info)
        
        if info == 0 {
            // Success! The eigenvalues are sorted in ascending order
            // The last eigenvalue is the largest (first principal component)
            // The corresponding eigenvector is in the last 3 elements
            
            // Extract the first principal component (eigenvector with largest eigenvalue)
            principalComponent = (
                x: matrix[6], // Last column, first row
                y: matrix[7], // Last column, second row
                z: matrix[8]  // Last column, third row
            )
            
            // Normalize (should already be normalized, but just to be safe)
            let norm = sqrt(
                principalComponent.x * principalComponent.x +
                principalComponent.y * principalComponent.y +
                principalComponent.z * principalComponent.z
            )
            
            if norm > 0 {
                principalComponent.x /= norm
                principalComponent.y /= norm
                principalComponent.z /= norm
            }
            
            // Compute signal quality: ratio of largest eigenvalue to sum of all eigenvalues
            let totalVariance = eigenvalues[0] + eigenvalues[1] + eigenvalues[2]
            if totalVariance > 0 {
                signalQuality = eigenvalues[2] / totalVariance // eigenvalues[2] is the largest
            }
            
            print("🔍 PCA updated - PC: (\(principalComponent.x), \(principalComponent.y), \(principalComponent.z)), Quality: \(signalQuality)")
        } else {
            print("❌ PCA failed with info: \(info)")
        }
    }
    
    // MARK: - Projection
    private func projectSample(_ field: CMMagneticField) -> Double {
        // Project onto principal component: s_t = û · B_t
        return principalComponent.x * field.x +
               principalComponent.y * field.y +
               principalComponent.z * field.z
    }
    
    // MARK: - Peak Detection
    private func detectPeak(_ projected: Double) {
        if isReadyForNewPeak && projected > highThreshold {
            revolutions += 1
            isReadyForNewPeak = false
            print("🎯 Peak detected! Revolutions: \(revolutions)")
        } else if !isReadyForNewPeak && projected < lowThreshold {
            isReadyForNewPeak = true
        }
    }
    
    // MARK: - Calibration
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
        
        print("🔧 PCA Calibration finished. Sample count: \(calibrationSamples.count)")
        
        guard calibrationSamples.count >= 100 else {
            print("⚠️ Not enough samples collected. Need at least 100, got \(calibrationSamples.count)")
            return
        }
        
        let sorted = calibrationSamples.sorted()
        
        // Low threshold: 30th percentile (baseline)
        let p30 = percentile(sorted, p: 30)
        // High threshold: 70th percentile (peak zone)
        let p70 = percentile(sorted, p: 70)
        
        print("📊 PCA Computed thresholds - Low: \(p30), High: \(p70)")
        
        // Ensure minimum gap
        let minGap: Double = 0.2
        var finalLow = p30
        var finalHigh = p70
        if finalHigh - finalLow < minGap {
            let mid = (finalLow + finalHigh) / 2
            finalLow = mid - minGap / 2
            finalHigh = mid + minGap / 2
        }
        
        print("✅ Final PCA thresholds - Low: \(finalLow), High: \(finalHigh)")
        
        self.lowThreshold = finalLow
        self.highThreshold = finalHigh
        self.didCalibrate = true
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
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading
            self.calibrationNeeded = newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > 11
        }
    }
    
    // MARK: - Computed Properties
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
        calibrationSamples.removeAll()
        projectedSignal.removeAll()
        UserDefaults.standard.removeObject(forKey: "pcaLowThreshold")
        UserDefaults.standard.removeObject(forKey: "pcaHighThreshold")
    }
}
