//
//  OpticalDetectionTests.swift
//  cave-mapper Tests
//
//  Created on 12/25/25.
//

import XCTest
@testable import cave_mapper

/// Unit tests for optical wheel detection
class OpticalDetectionTests: XCTestCase {
    
    var detector: OpticalWheelDetector!
    
    override func setUp() {
        super.setUp()
        detector = OpticalWheelDetector()
    }
    
    override func tearDown() {
        detector.stopDetection()
        detector = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(detector)
        XCTAssertFalse(detector.isRunning)
        XCTAssertEqual(detector.rotationCount, 0)
        XCTAssertFalse(detector.isCalibrating)
    }
    
    func testDefaultThresholds() {
        XCTAssertGreaterThan(detector.highBrightnessThreshold, detector.lowBrightnessThreshold)
        XCTAssertGreaterThan(detector.lowBrightnessThreshold, 0)
        XCTAssertLessThan(detector.highBrightnessThreshold, 1)
    }
    
    // MARK: - Detection State Tests
    
    func testStartStopDetection() {
        detector.startDetection()
        
        // Give it a moment to start
        let expectation = XCTestExpectation(description: "Detection starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.detector.isRunning)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        detector.stopDetection()
        
        let stopExpectation = XCTestExpectation(description: "Detection stops")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(self.detector.isRunning)
            stopExpectation.fulfill()
        }
        
        wait(for: [stopExpectation], timeout: 1.0)
    }
    
    func testResetRotationCount() {
        // Manually set rotation count
        detector.rotationCount = 10
        XCTAssertEqual(detector.rotationCount, 10)
        
        detector.resetRotationCount()
        XCTAssertEqual(detector.rotationCount, 0)
    }
    
    // MARK: - Calibration Tests
    
    func testCalibrationStartStop() {
        XCTAssertFalse(detector.isCalibrating)
        
        detector.startCalibration()
        XCTAssertTrue(detector.isCalibrating)
        XCTAssertEqual(detector.calibrationProgress, 0.0)
        
        detector.cancelCalibration()
        XCTAssertFalse(detector.isCalibrating)
    }
    
    func testLoadSavedThresholds() {
        // Save thresholds
        let testLow = 0.25
        let testHigh = 0.75
        UserDefaults.standard.set(testLow, forKey: "opticalLowThreshold")
        UserDefaults.standard.set(testHigh, forKey: "opticalHighThreshold")
        
        // Create new detector to load saved values
        let newDetector = OpticalWheelDetector()
        newDetector.loadSavedThresholds()
        
        XCTAssertEqual(newDetector.lowBrightnessThreshold, testLow, accuracy: 0.001)
        XCTAssertEqual(newDetector.highBrightnessThreshold, testHigh, accuracy: 0.001)
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "opticalLowThreshold")
        UserDefaults.standard.removeObject(forKey: "opticalHighThreshold")
    }
    
    // MARK: - Threshold Tests
    
    func testThresholdSeparation() {
        // Thresholds should always be separated
        let minSeparation = 0.1
        let separation = detector.highBrightnessThreshold - detector.lowBrightnessThreshold
        XCTAssertGreaterThanOrEqual(separation, minSeparation)
    }
    
    func testThresholdBounds() {
        // Thresholds should be within 0-1 range
        XCTAssertGreaterThanOrEqual(detector.lowBrightnessThreshold, 0.0)
        XCTAssertLessThanOrEqual(detector.lowBrightnessThreshold, 1.0)
        XCTAssertGreaterThanOrEqual(detector.highBrightnessThreshold, 0.0)
        XCTAssertLessThanOrEqual(detector.highBrightnessThreshold, 1.0)
    }
}

// MARK: - Detection Method Tests

class DetectionMethodTests: XCTestCase {
    
    func testDetectionMethodEnum() {
        let magnetic = DetectionMethod.magnetic
        let optical = DetectionMethod.optical
        
        XCTAssertEqual(magnetic.rawValue, "Magnetic")
        XCTAssertEqual(optical.rawValue, "Optical")
        
        XCTAssertEqual(DetectionMethod.allCases.count, 2)
    }
    
    func testDetectionMethodCodable() throws {
        let magnetic = DetectionMethod.magnetic
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(magnetic)
        XCTAssertNotNil(data)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DetectionMethod.self, from: data)
        XCTAssertEqual(decoded, magnetic)
    }
}

// MARK: - Integration Tests

class OpticalIntegrationTests: XCTestCase {
    
    var viewModel: MagnetometerViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = MagnetometerViewModel()
    }
    
    override func tearDown() {
        viewModel.stopMonitoring()
        viewModel = nil
        super.tearDown()
    }
    
    func testDetectionMethodSwitching() {
        // Start with magnetic
        viewModel.detectionMethod = .magnetic
        XCTAssertEqual(viewModel.detectionMethod, .magnetic)
        
        // Switch to optical
        viewModel.detectionMethod = .optical
        XCTAssertEqual(viewModel.detectionMethod, .optical)
        XCTAssertNotNil(viewModel.opticalDetector)
    }
    
    func testDetectionMethodPersistence() {
        // Set optical mode
        viewModel.detectionMethod = .optical
        
        // Create new view model to test persistence
        let newViewModel = MagnetometerViewModel()
        XCTAssertEqual(newViewModel.detectionMethod, .optical)
        
        // Cleanup
        newViewModel.detectionMethod = .magnetic
    }
    
    func testOpticalDetectorIntegration() {
        XCTAssertNotNil(viewModel.opticalDetector)
        XCTAssertFalse(viewModel.opticalDetector.isRunning)
        
        viewModel.detectionMethod = .optical
        viewModel.startMonitoring()
        
        let expectation = XCTestExpectation(description: "Optical detector starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Note: May not actually start on simulator without camera
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        viewModel.stopMonitoring()
    }
    
    func testCalibrationIntegration() {
        viewModel.detectionMethod = .optical
        
        XCTAssertFalse(viewModel.isCalibrating)
        XCTAssertFalse(viewModel.opticalDetector.isCalibrating)
        
        viewModel.startCalibration(durationSeconds: 1)
        
        // Optical calibration should start
        XCTAssertTrue(viewModel.opticalDetector.isCalibrating)
        
        viewModel.cancelCalibration()
        
        XCTAssertFalse(viewModel.isCalibrating)
        XCTAssertFalse(viewModel.opticalDetector.isCalibrating)
    }
}

// MARK: - Performance Tests

class OpticalPerformanceTests: XCTestCase {
    
    func testDetectorInitializationPerformance() {
        measure {
            let detector = OpticalWheelDetector()
            detector.stopDetection()
        }
    }
    
    func testBrightnessCalculationPerformance() {
        // This would need actual camera frames to test
        // Left as placeholder for manual testing
    }
}

// MARK: - Mock Data Tests

class OpticalMockDataTests: XCTestCase {
    
    func testPercentileCalculation() {
        // Test percentile calculation used in calibration
        let samples: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        
        // Helper function (copied from OpticalWheelDetector)
        func percentile(_ sorted: [Double], percent: Double) -> Double {
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
        
        let p25 = percentile(samples, percent: 25)
        let p75 = percentile(samples, percent: 75)
        
        XCTAssertEqual(p25, 0.325, accuracy: 0.01)
        XCTAssertEqual(p75, 0.775, accuracy: 0.01)
    }
}
