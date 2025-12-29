//
//  WheelDetectionMethod.swift
//  cave-mapper
//
//  Created on 12/26/25.
//

import Foundation

/// Enum for selecting wheel rotation detection method
enum WheelDetectionMethod: String, CaseIterable, Identifiable, Codable {
    case magnetic = "Magnetic"
    case magneticPCA = "Magnetic (PCA Phase)"
    case optical = "Optical"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .magnetic:
            return "Uses magnetometer to detect wheel rotations with threshold-based peak detection"
        case .magneticPCA:
            return "Uses PCA phase tracking to measure 2π advances in magnetometer signal. Most robust to phone orientation."
        case .optical:
            return "Uses camera and flashlight to detect wheel rotations"
        }
    }
    
    var icon: String {
        switch self {
        case .magnetic:
            return "gyroscope"
        case .magneticPCA:
            return "waveform.circle"
        case .optical:
            return "camera.fill"
        }
    }
}
