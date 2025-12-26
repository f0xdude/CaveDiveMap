//
//  WheelDetectionManager.swift
//  cave-mapper
//
//  Created on 12/26/25.
//

import SwiftUI
import Combine

/// Unified manager for wheel rotation detection
/// Coordinates between magnetic and optical detection methods
class WheelDetectionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var detectionMethod: WheelDetectionMethod {
        didSet {
            saveDetectionMethod()
            switchDetectionMethod()
        }
    }
    
    @Published var rotationCount: Int = 0
    @Published var isRunning = false
    
    // MARK: - Detection Components
    let magneticDetector: MagnetometerViewModel
    let opticalDetector: OpticalWheelDetector
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(magneticDetector: MagnetometerViewModel, opticalDetector: OpticalWheelDetector) {
        self.magneticDetector = magneticDetector
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
        magneticDetector.$revolutionCount
            .sink { [weak self] count in
                guard let self = self, self.detectionMethod == .magnetic else { return }
                self.rotationCount = count
            }
            .store(in: &cancellables)
        
        // Observe optical detector rotation count
        opticalDetector.$rotationCount
            .sink { [weak self] count in
                guard let self = self, self.detectionMethod == .optical else { return }
                self.rotationCount = count
            }
            .store(in: &cancellables)
        
        // Observe running states
        magneticDetector.$isRunning
            .sink { [weak self] running in
                guard let self = self, self.detectionMethod == .magnetic else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)
        
        opticalDetector.$isRunning
            .sink { [weak self] running in
                guard let self = self, self.detectionMethod == .optical else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Detection Control
    func startDetection() {
        switch detectionMethod {
        case .magnetic:
            magneticDetector.startMonitoring()
        case .optical:
            opticalDetector.startDetection()
        }
        isRunning = true
    }
    
    func stopDetection() {
        magneticDetector.stopMonitoring()
        opticalDetector.stopDetection()
        isRunning = false
    }
    
    func resetRotationCount() {
        rotationCount = 0
        magneticDetector.revolutions = 0
        opticalDetector.resetRotationCount()
        saveRotationCount()
    }
    
    private func switchDetectionMethod() {
        // Stop current detection
        stopDetection()
        
        // Sync rotation counts when switching
        switch detectionMethod {
        case .magnetic:
            magneticDetector.revolutions = rotationCount
            print("🔄 Switched to magnetic detection")
        case .optical:
            opticalDetector.rotationCount = rotationCount
            print("🔄 Switched to optical detection")
        }
        
        // Start new detection method
        startDetection()
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
    private func saveDetectionMethod() {
        UserDefaults.standard.set(detectionMethod.rawValue, forKey: "wheelDetectionMethod")
    }
    
    private func loadRotationCount() {
        // Use the magnetic detector's saved revolution count as the initial value
        rotationCount = magneticDetector.revolutions
        
        // Sync to optical detector
        opticalDetector.rotationCount = rotationCount
    }
    
    private func saveRotationCount() {
        DataManager.savePointNumber(rotationCount)
    }
}
