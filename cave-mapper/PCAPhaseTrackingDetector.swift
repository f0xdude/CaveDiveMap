//
//  PCAPhaseTrackingDetector.swift
//  cave-mapper
//
//  Created on 12/27/25.
//

import SwiftUI
import CoreMotion
import CoreLocation
import Accelerate

/// PCA-based phase tracking rotation detector
/// Detects wheel rotations by measuring 2π phase advances in the magnetometer signal.
/// Each complete 2π cycle = one rotation.
///
/// Pipeline:
/// 1. Baseline removal (Earth field + drift)
/// 2. Sliding window buffer
/// 3. PCA on 3D vectors → find rotation plane
/// 4. Stabilize PCA basis (prevent sign flips)
/// 5. Project samples into 2D rotation plane
/// 6. Compute phase θ(t) = atan2(v, u)
/// 7. Unwrap phase and track total phase
/// 8. Validity gates (planarity, motion detection, inertial rejection)
/// 9. Count rotations by accumulating +2π of forward phase
class PCAPhaseTrackingDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // MARK: - Published Properties
    @Published var revolutions = 0
    @Published var isRunning = false
    @Published var currentField: CMMagneticField = CMMagneticField(x: 0, y: 0, z: 0)
    @Published var currentMagnitude: Double = 0.0
    @Published var currentHeading: CLHeading?
    @Published var calibrationNeeded: Bool = false
    @Published var signalQuality: Double = 0.0 // 0-1, planarity metric
    @Published var phaseAngle: Double = 0.0 // Current phase in radians
    
    @Published var wheelCircumference: Double {
        didSet {
            UserDefaults.standard.set(wheelCircumference, forKey: "wheelCircumference")
        }
    }
    
    // MARK: - Configuration
    private let samplingRateHz: Double = 50.0
    private let windowSizeSeconds: Double = 1.0
    private let minWindowFillFraction: Double = 0.5
    private let baselineAlpha: Double = 0.01 // EMA coefficient for baseline
    private let baselineSlowdownFactor: Double = 0.1 // Slow baseline during pauses
    
    // MARK: - Baseline Removal
    private var baseline: (x: Double, y: Double, z: Double) = (0, 0, 0)
    private var isBaselineInitialized = false
    
    // MARK: - Sliding Window
    private var correctedSamples: [(x: Double, y: Double, z: Double)] = []
    private var windowSize: Int { Int(windowSizeSeconds * samplingRateHz) }
    private var minWindowSize: Int { Int(Double(windowSize) * minWindowFillFraction) }
    
    // MARK: - PCA Results
    private struct PCABasis {
        var pc1: (x: Double, y: Double, z: Double) // First principal component
        var pc2: (x: Double, y: Double, z: Double) // Second principal component
        var normal: (x: Double, y: Double, z: Double) // Normal to rotation plane
        var eigenvalues: [Double] // [λ1, λ2, λ3] sorted descending
        
        var planarity: Double {
            // How flat is the motion? (λ1 + λ2) / (λ1 + λ2 + λ3)
            let sum = eigenvalues.reduce(0, +)
            guard sum > 0 else { return 0 }
            return (eigenvalues[0] + eigenvalues[1]) / sum
        }
    }
    
    private var latestPCA: PCABasis?
    private var lockedPCA: PCABasis?
    private var previousPCA: PCABasis?
    
    // MARK: - Phase Tracking
    private var totalPhase: Double = 0.0
    private var lastPhase: Double = 0.0
    private var forwardPhaseAccum: Double = 0.0
    private var forwardSign: Double = 0.0 // +1 or -1, learned from first stable motion
    private var hasLearnedForwardSign = false
    
    // MARK: - Validity Gates
    private var lastValidMotionTime: Date?
    private var planarGraceMs: Double = 500 // Grace period for planarity loss
    private var inertialGraceMs: Double = 500 // Grace period for phone motion
    private var minPlanarity: Double = 0.7 // Minimum planarity to be valid
    
    // MARK: - Inertial Filtering
    private var gyroHistory: [(Date, CMRotationRate)] = []
    private var accelHistory: [(Date, CMAcceleration)] = []
    private var inertialHistorySeconds: Double = 1.0
    private var gyroMaxThreshold: Double = 1.0 // rad/s
    private var accelStdDevThreshold: Double = 0.5 // m/s²
    
    // MARK: - Motion Detection
    private var lastMotionTime: Date?
    private var motionThreshold: Double = 0.1 // Minimum phase velocity to be "moving"
    
    override init() {
        let defaults = UserDefaults.standard
        self.wheelCircumference = defaults.object(forKey: "wheelCircumference") as? Double ?? 11.78
        
        super.init()
        
        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Start/Stop
    func startMonitoring() {
        print("🧲 PCAPhaseTrackingDetector.startMonitoring() called")
        
        if isRunning || motionManager.isMagnetometerActive {
            print("⚠️ PCA phase detector already active, stopping first")
            stopMonitoring()
        }
        
        // Reset state
        resetState()
        
        isRunning = true
        
        guard motionManager.isMagnetometerAvailable else {
            print("❌ Magnetometer not available")
            return
        }
        
        // Start magnetometer updates
        motionManager.magnetometerUpdateInterval = 1.0 / samplingRateHz
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.processMagnetometerData(data.magneticField)
        }
        
        // Start gyroscope for inertial rejection
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let data = data, error == nil else { return }
                self.processGyroData(data.rotationRate)
            }
        }
        
        // Start accelerometer for inertial rejection
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let data = data, error == nil else { return }
                self.processAccelData(data.acceleration)
            }
        }
        
        // Start heading updates
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        print("✅ PCA phase tracking started")
    }
    
    func stopMonitoring() {
        print("🛑 PCAPhaseTrackingDetector.stopMonitoring() called")
        motionManager.stopMagnetometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopAccelerometerUpdates()
        locationManager.stopUpdatingHeading()
        isRunning = false
        print("✅ PCA phase tracking stopped")
    }
    
    private func resetState() {
        baseline = (0, 0, 0)
        isBaselineInitialized = false
        correctedSamples.removeAll()
        latestPCA = nil
        lockedPCA = nil
        previousPCA = nil
        totalPhase = 0.0
        lastPhase = 0.0
        forwardPhaseAccum = 0.0
        forwardSign = 0.0
        hasLearnedForwardSign = false
        gyroHistory.removeAll()
        accelHistory.removeAll()
        lastValidMotionTime = nil
        lastMotionTime = nil
    }
    
    // MARK: - Data Processing
    private func processMagnetometerData(_ field: CMMagneticField) {
        currentField = field
        currentMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        
        // Step 1: Baseline removal (EMA of raw signal)
        if !isBaselineInitialized {
            baseline = (field.x, field.y, field.z)
            isBaselineInitialized = true
            return // Need at least one sample for baseline
        }
        
        // Detect if we're in a pause (low motion) and slow baseline adaptation
        let alpha = isInMotion() ? baselineAlpha : baselineAlpha * baselineSlowdownFactor
        
        baseline.x = alpha * field.x + (1 - alpha) * baseline.x
        baseline.y = alpha * field.y + (1 - alpha) * baseline.y
        baseline.z = alpha * field.z + (1 - alpha) * baseline.z
        
        // Corrected sample (remove baseline)
        let corrected = (
            x: field.x - baseline.x,
            y: field.y - baseline.y,
            z: field.z - baseline.z
        )
        
        // Step 2: Add to sliding window
        correctedSamples.append(corrected)
        if correctedSamples.count > windowSize {
            correctedSamples.removeFirst()
        }
        
        // Need minimum samples before proceeding
        guard correctedSamples.count >= minWindowSize else { return }
        
        // Step 3: Compute PCA on window
        if let pca = computePCA(samples: correctedSamples) {
            // Step 4: Stabilize PCA basis
            let stabilized = stabilizePCA(pca)
            latestPCA = stabilized
            
            // Step 5: Lock PCA if quality is good
            updateLockedPCA(stabilized)
            
            // Use locked PCA if available, else latest
            guard let projectionBasis = lockedPCA ?? latestPCA else { return }
            
            // Step 6: Project current sample into 2D rotation plane
            let projected = projectTo2D(corrected, basis: projectionBasis)
            
            // Step 7: Compute phase angle θ = atan2(v, u)
            let phase = atan2(projected.v, projected.u)
            phaseAngle = phase
            
            // Step 8: Unwrap and track phase
            let phaseDelta = unwrapPhaseDelta(from: lastPhase, to: phase)
            totalPhase += phaseDelta
            lastPhase = phase
            
            // Step 9: Validity gates
            let isValid = checkValidityGates(projectionBasis)
            
            if isValid {
                lastValidMotionTime = Date()
                
                // Learn forward sign from first stable motion
                if !hasLearnedForwardSign && abs(phaseDelta) > 0.01 {
                    forwardSign = phaseDelta > 0 ? 1.0 : -1.0
                    hasLearnedForwardSign = true
                    print("🎯 Learned forward sign: \(forwardSign)")
                }
                
                // Step 10: Accumulate forward phase and count rotations
                if hasLearnedForwardSign {
                    let signedDelta = phaseDelta * forwardSign
                    if signedDelta > 0 {
                        forwardPhaseAccum += signedDelta
                        
                        // Count complete 2π rotations
                        let pendingRotations = Int(floor(forwardPhaseAccum / (2.0 * .pi)))
                        if pendingRotations > 0 {
                            revolutions += pendingRotations
                            forwardPhaseAccum -= Double(pendingRotations) * 2.0 * .pi
                            print("🎯 Rotation detected! Total: \(revolutions)")
                        }
                    }
                }
            }
            
            previousPCA = stabilized
        }
    }
    
    private func processGyroData(_ rotationRate: CMRotationRate) {
        let now = Date()
        gyroHistory.append((now, rotationRate))
        
        // Keep only recent history
        let cutoff = now.addingTimeInterval(-inertialHistorySeconds)
        gyroHistory.removeAll { $0.0 < cutoff }
    }
    
    private func processAccelData(_ acceleration: CMAcceleration) {
        let now = Date()
        accelHistory.append((now, acceleration))
        
        // Keep only recent history
        let cutoff = now.addingTimeInterval(-inertialHistorySeconds)
        accelHistory.removeAll { $0.0 < cutoff }
    }
    
    // MARK: - PCA Computation
    private func computePCA(samples: [(x: Double, y: Double, z: Double)]) -> PCABasis? {
        guard samples.count >= minWindowSize else { return nil }
        
        let n = Double(samples.count)
        
        // Compute mean
        var meanX: Double = 0, meanY: Double = 0, meanZ: Double = 0
        for sample in samples {
            meanX += sample.x
            meanY += sample.y
            meanZ += sample.z
        }
        meanX /= n
        meanY /= n
        meanZ /= n
        
        // Compute covariance matrix
        var cxx: Double = 0, cxy: Double = 0, cxz: Double = 0
        var cyy: Double = 0, cyz: Double = 0, czz: Double = 0
        
        for sample in samples {
            let dx = sample.x - meanX
            let dy = sample.y - meanY
            let dz = sample.z - meanZ
            
            cxx += dx * dx
            cxy += dx * dy
            cxz += dx * dz
            cyy += dy * dy
            cyz += dy * dz
            czz += dz * dz
        }
        
        cxx /= n
        cxy /= n
        cxz /= n
        cyy /= n
        cyz /= n
        czz /= n
        
        // Solve eigenvalue problem using LAPACK
        var matrix = [cxx, cxy, cxz,
                      cxy, cyy, cyz,
                      cxz, cyz, czz]
        
        var eigenvalues = [Double](repeating: 0, count: 3)
        var n_int32: __CLPK_integer = 3
        var lda: __CLPK_integer = 3
        var lwork: __CLPK_integer = 9
        var work = [Double](repeating: 0, count: Int(lwork))
        var info: __CLPK_integer = 0
        var jobz: Int8 = Int8(UnicodeScalar("V").value)
        var uplo: Int8 = Int8(UnicodeScalar("U").value)
        
        dsyev_(&jobz, &uplo, &n_int32, &matrix, &lda, &eigenvalues, &work, &lwork, &info)
        
        guard info == 0 else { return nil }
        
        // Extract eigenvectors (columns of matrix, sorted by eigenvalue)
        // LAPACK returns eigenvalues in ascending order, we want descending
        let pc1 = (x: matrix[6], y: matrix[7], z: matrix[8]) // Largest eigenvalue
        let pc2 = (x: matrix[3], y: matrix[4], z: matrix[5]) // Second largest
        
        // Normal = pc1 × pc2 (cross product)
        let normal = crossProduct(pc1, pc2)
        
        return PCABasis(
            pc1: normalize(pc1),
            pc2: normalize(pc2),
            normal: normalize(normal),
            eigenvalues: [eigenvalues[2], eigenvalues[1], eigenvalues[0]] // Descending order
        )
    }
    
    // MARK: - PCA Stabilization
    private func stabilizePCA(_ pca: PCABasis) -> PCABasis {
        guard let prev = previousPCA else { return pca }
        
        var stabilized = pca
        
        // Try all combinations of sign flips and pc1/pc2 swaps
        var bestAlignment = dotProduct(pca.pc1, prev.pc1) + dotProduct(pca.pc2, prev.pc2)
        
        // Try flipping pc1
        let flipped1 = flipVector(pca.pc1)
        let align1 = dotProduct(flipped1, prev.pc1) + dotProduct(pca.pc2, prev.pc2)
        if align1 > bestAlignment {
            bestAlignment = align1
            stabilized.pc1 = flipped1
        }
        
        // Try flipping pc2
        let flipped2 = flipVector(pca.pc2)
        let align2 = dotProduct(stabilized.pc1, prev.pc1) + dotProduct(flipped2, prev.pc2)
        if align2 > bestAlignment {
            bestAlignment = align2
            stabilized.pc2 = flipped2
        }
        
        // Try swapping pc1 and pc2
        let swapped = PCABasis(
            pc1: stabilized.pc2,
            pc2: stabilized.pc1,
            normal: stabilized.normal,
            eigenvalues: stabilized.eigenvalues
        )
        let alignSwap = dotProduct(swapped.pc1, prev.pc1) + dotProduct(swapped.pc2, prev.pc2)
        if alignSwap > bestAlignment {
            stabilized = swapped
        }
        
        // Ensure normal direction is consistent
        if dotProduct(stabilized.normal, prev.normal) < 0 {
            stabilized.normal = flipVector(stabilized.normal)
        }
        
        return stabilized
    }
    
    private func updateLockedPCA(_ pca: PCABasis) {
        // Lock PCA when planarity is good and maintain with hysteresis
        if pca.planarity > minPlanarity {
            if lockedPCA == nil {
                lockedPCA = pca
                print("🔒 PCA basis locked (planarity: \(pca.planarity))")
            } else {
                // Slowly adapt locked basis
                lockedPCA = pca
            }
        } else if pca.planarity < minPlanarity * 0.8 {
            // Unlock if planarity drops significantly
            if lockedPCA != nil {
                print("🔓 PCA basis unlocked (planarity: \(pca.planarity))")
            }
            lockedPCA = nil
        }
    }
    
    // MARK: - Projection
    private func projectTo2D(_ sample: (x: Double, y: Double, z: Double), basis: PCABasis) -> (u: Double, v: Double) {
        let u = dotProduct(sample, basis.pc1)
        let v = dotProduct(sample, basis.pc2)
        return (u, v)
    }
    
    // MARK: - Phase Unwrapping
    private func unwrapPhaseDelta(from prev: Double, to current: Double) -> Double {
        var delta = current - prev
        
        // Wrap to [-π, π]
        while delta > .pi {
            delta -= 2.0 * .pi
        }
        while delta < -.pi {
            delta += 2.0 * .pi
        }
        
        return delta
    }
    
    // MARK: - Validity Gates
    private func checkValidityGates(_ basis: PCABasis) -> Bool {
        // Gate 1: Planarity check (with grace period)
        if basis.planarity < minPlanarity {
            if let lastValid = lastValidMotionTime {
                let elapsed = Date().timeIntervalSince(lastValid) * 1000 // ms
                if elapsed > planarGraceMs {
                    return false
                }
            } else {
                return false
            }
        }
        
        // Gate 2: Inertial rejection (check if phone is moving)
        if isPhoneMovingTooMuch() {
            return false
        }
        
        // Gate 3: Motion detection (must be actually rotating)
        if !isInMotion() {
            return false
        }
        
        signalQuality = basis.planarity
        return true
    }
    
    private func isPhoneMovingTooMuch() -> Bool {
        // Check gyro max over recent history
        if !gyroHistory.isEmpty {
            let maxGyro = gyroHistory.map { data in
                sqrt(data.1.x * data.1.x + data.1.y * data.1.y + data.1.z * data.1.z)
            }.max() ?? 0
            
            if maxGyro > gyroMaxThreshold {
                return true
            }
        }
        
        // Check accelerometer standard deviation
        if accelHistory.count > 5 {
            let magnitudes = accelHistory.map { data in
                sqrt(data.1.x * data.1.x + data.1.y * data.1.y + data.1.z * data.1.z)
            }
            
            let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
            let variance = magnitudes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(magnitudes.count)
            let stdDev = sqrt(variance)
            
            if stdDev > accelStdDevThreshold {
                return true
            }
        }
        
        return false
    }
    
    private func isInMotion() -> Bool {
        // Check if phase is changing (wheel is rotating)
        if let lastMotion = lastMotionTime {
            let elapsed = Date().timeIntervalSince(lastMotion)
            if elapsed > 0.5 { // No motion for 0.5s
                return false
            }
        }
        
        // If we see phase changes above threshold, we're in motion
        if abs(phaseAngle - lastPhase) > motionThreshold {
            lastMotionTime = Date()
            return true
        }
        
        return lastMotionTime != nil
    }
    
    // MARK: - Vector Math Utilities
    private func normalize(_ v: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) {
        let mag = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        guard mag > 0 else { return v }
        return (v.x / mag, v.y / mag, v.z / mag)
    }
    
    private func dotProduct(_ a: (x: Double, y: Double, z: Double), _ b: (x: Double, y: Double, z: Double)) -> Double {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }
    
    private func crossProduct(_ a: (x: Double, y: Double, z: Double), _ b: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) {
        return (
            x: a.y * b.z - a.z * b.y,
            y: a.z * b.x - a.x * b.z,
            z: a.x * b.y - a.y * b.x
        )
    }
    
    private func flipVector(_ v: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) {
        return (-v.x, -v.y, -v.z)
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
}
