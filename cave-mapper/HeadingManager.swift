//
//  HeadingManager.swift
//  cave-mapper
//
//  Created on 1/1/26.
//

import Foundation
import CoreLocation
import SwiftUI

/// Manages compass heading independently from rotation detection
/// This ensures heading is always available regardless of detection method
class HeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // MARK: - Published Properties
    @Published var currentHeading: CLHeading?
    @Published var calibrationNeeded: Bool = false
    @Published var isRunning: Bool = false
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.headingFilter = 1  // Update when heading changes by 1 degree
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Public Methods
    func startMonitoring() {
        guard CLLocationManager.headingAvailable() else {
            print("⚠️ Heading not available on this device")
            return
        }
        
        locationManager.startUpdatingHeading()
        isRunning = true
        print("🧭 Heading monitoring started")
    }
    
    func stopMonitoring() {
        locationManager.stopUpdatingHeading()
        isRunning = false
        print("🧭 Heading monitoring stopped")
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async { [weak self] in
            self?.currentHeading = newHeading
            self?.calibrationNeeded = newHeading.headingAccuracy < 0 || newHeading.headingAccuracy > 11
        }
    }
    
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true  // Allow iOS to show calibration UI when needed
    }
    
    // MARK: - Computed Properties
    var roundedMagneticHeading: Double? {
        guard let heading = currentHeading else { return nil }
        return (heading.magneticHeading * 100).rounded() / 100
    }
}
