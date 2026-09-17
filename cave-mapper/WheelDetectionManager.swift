//
//  WheelDetectionManager.swift
//  cave-mapper
//
//  Created on 12/26/25.
//

import SwiftUI
import Combine
import QuartzCore

/// Unified manager for wheel rotation detection
/// Coordinates between magnetic and optical detection methods
class WheelDetectionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var detectionMethod: WheelDetectionMethod {
        didSet {
            guard detectionMethod != oldValue else { return }
            // Save to UserDefaults on background thread to avoid blocking UI
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(self.detectionMethod.rawValue, forKey: "wheelDetectionMethod")
            }
        }
    }
    
    @Published var rotationCount: Int = 0 {
        // The wheel count is the survey's odometer: persist it on every change,
        // under its own key — the station counter advances on every saved
        // record, so seeding one from the other corrupts distance on relaunch.
        didSet { DataManager.saveRotationCount(rotationCount) }
    }
    @Published var isRunning = false
    
    // Counts change once per wheel revolution, so they are forwarded unthrottled:
    // the old 10 Hz gate dropped any update that landed inside its window, and if
    // the wheel then stopped the odometer stayed one revolution short.
    private var isSwitchingMethod = false // Prevent concurrent switches
    
    // MARK: - Detection Components
    let magneticDetector: MagnetometerViewModel
    let pcaDetector: PCAPhaseTrackingDetector
    let opticalDetector: OpticalWheelDetector
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(magneticDetector: MagnetometerViewModel, pcaDetector: PCAPhaseTrackingDetector, opticalDetector: OpticalWheelDetector) {
        self.magneticDetector = magneticDetector
        self.pcaDetector = pcaDetector
        self.opticalDetector = opticalDetector
        
        // Load saved detection method
        if let savedMethod = UserDefaults.standard.string(forKey: "wheelDetectionMethod"),
           let method = WheelDetectionMethod(rawValue: savedMethod) {
            self.detectionMethod = method
        } else {
            self.detectionMethod = .magnetic // Default
        }
        
        setupObservers()
        loadRotationCount()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe magnetic detector rotation count
        magneticDetector.$revolutions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self, self.detectionMethod == .magnetic else { return }
                if self.rotationCount != count { self.rotationCount = count }
            }
            .store(in: &cancellables)
        
        // Observe PCA detector rotation count
        pcaDetector.$revolutions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self, self.detectionMethod == .magneticPCA else { return }
                if self.rotationCount != count { self.rotationCount = count }
            }
            .store(in: &cancellables)
        
        // Observe optical detector rotation count
        opticalDetector.$rotationCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self, self.detectionMethod == .optical else { return }
                if self.rotationCount != count { self.rotationCount = count }
            }
            .store(in: &cancellables)
        
        // Observe running states (these don't need throttling, less frequent)
        magneticDetector.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self = self, self.detectionMethod == .magnetic else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)
        
        pcaDetector.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self = self, self.detectionMethod == .magneticPCA else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)
        
        opticalDetector.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self = self, self.detectionMethod == .optical else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Detection Control
    func startDetection() {
        // Always stop all first to ensure clean state
        magneticDetector.stopMonitoring()
        pcaDetector.stopMonitoring()
        opticalDetector.stopDetection()
        
        // Start the appropriate detector
        switch detectionMethod {
        case .magnetic:
            magneticDetector.startMonitoring()
        case .magneticPCA:
            pcaDetector.startMonitoring()
        case .optical:
            opticalDetector.startDetection()
        }
        isRunning = true
    }
    
    func stopDetection() {
        magneticDetector.stopMonitoring()
        pcaDetector.stopMonitoring()
        opticalDetector.stopDetection()
        isRunning = false
    }
    
    func resetRotationCount() {
        rotationCount = 0
        
        // Reset all detectors asynchronously to avoid publishing warnings
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.magneticDetector.revolutions = 0
            self.pcaDetector.revolutions = 0
            self.opticalDetector.resetRotationCount()
            self.saveRotationCount()
        }
    }
    
    func switchDetectionMethod(to method: WheelDetectionMethod) {
        print("🔄 Switching detection method from \(detectionMethod.rawValue) to \(method.rawValue)")
        guard method != detectionMethod else { 
            print("⚠️ Already using \(method.rawValue), no switch needed")
            return 
        }
        
        // Prevent concurrent switches
        guard !isSwitchingMethod else {
            print("⚠️ Switch already in progress, ignoring duplicate call")
            return
        }
        
        isSwitchingMethod = true
        
        // Capture state before switching
        let wasRunning = isRunning
        let currentCount = rotationCount
        
        print("📊 Current state - Running: \(wasRunning), Count: \(currentCount)")
        
        // STEP 1: Update UI immediately for instant feedback
        detectionMethod = method
        print("✅ Detection method updated to \(method.rawValue)")
        
        // STEP 2: Perform heavy operations
        // Stop current detection on main thread (required)
        stopDetection()
        
        // Sync rotation counts
        magneticDetector.revolutions = currentCount
        pcaDetector.revolutions = currentCount
        opticalDetector.rotationCount = currentCount
        print("✅ Rotation counts synced: \(currentCount)")
        
        // Restart detection if it was running (with small delay for clean state)
        if wasRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                self.startDetection()
                self.isSwitchingMethod = false
                print("✅ Detection restarted with \(method.rawValue)")
            }
        } else {
            isSwitchingMethod = false
        }
    }
    
    // MARK: - Distance Calculation
    var wheelCircumference: Double {
        magneticDetector.wheelCircumference
    }
    
    var distanceInMeters: Double {
        Double(rotationCount) * wheelCircumference / 100.0
    }
    
    var roundedDistanceInMeters: Double {
        (distanceInMeters * 100).rounded() / 100
    }
    
    // MARK: - Persistence
    private func loadRotationCount() {
        // Use the magnetic detector's saved revolution count as the initial value.
        // The PCA and optical detectors are seeded with the same count where they
        // are created (ContentView.init), before any observer is attached.
        rotationCount = magneticDetector.revolutions
    }
    
    private func saveRotationCount() {
        DataManager.saveRotationCount(rotationCount)
    }
}
