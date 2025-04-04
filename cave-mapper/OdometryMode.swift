//
//  OdometryMode.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 29.03.25.
//

import SwiftUI
import Foundation

enum OdometryMode: String, CaseIterable, Identifiable {
    case magnetic = "Magnetic"
    case acoustic = "Acoustic"
    
    var id: String { rawValue }
}
