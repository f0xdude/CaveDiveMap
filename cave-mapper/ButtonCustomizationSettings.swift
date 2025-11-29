//
//  ButtonCustomizationSettings.swift
//  cave-mapper
//
//  Created on 29.11.25.
//

import SwiftUI

/// Represents customizable properties for a button
struct ButtonConfig: Codable {
    var size: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    
    static var `default`: ButtonConfig {
        ButtonConfig(size: 75, offsetX: 0, offsetY: 0)
    }
}

/// Manages button customization settings for the app
class ButtonCustomizationSettings: ObservableObject {
    static let shared = ButtonCustomizationSettings()
    
    // MARK: - Main Screen Buttons
    @Published var mainSaveButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var mainMapButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var mainResetButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var mainCameraButton: ButtonConfig {
        didSet { save() }
    }
    
    // MARK: - Save Data View Buttons
    @Published var saveViewSaveButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var saveViewIncrementButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var saveViewDecrementButton: ButtonConfig {
        didSet { save() }
    }
    
    @Published var saveViewCycleButton: ButtonConfig {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        // Load or use defaults for Main Screen
        mainSaveButton = Self.load(key: "mainSaveButton") ?? ButtonConfig(size: 75, offsetX: 0, offsetY: 20)
        mainMapButton = Self.load(key: "mainMapButton") ?? ButtonConfig(size: 75, offsetX: 130, offsetY: 10)
        mainResetButton = Self.load(key: "mainResetButton") ?? ButtonConfig(size: 75, offsetX: -70, offsetY: -70)
        mainCameraButton = Self.load(key: "mainCameraButton") ?? ButtonConfig(size: 75, offsetX: 70, offsetY: -70)
        
        // Load or use defaults for Save Data View
        saveViewSaveButton = Self.load(key: "saveViewSaveButton") ?? ButtonConfig(size: 70, offsetX: 0, offsetY: 120)
        saveViewIncrementButton = Self.load(key: "saveViewIncrementButton") ?? ButtonConfig(size: 70, offsetX: 100, offsetY: 80)
        saveViewDecrementButton = Self.load(key: "saveViewDecrementButton") ?? ButtonConfig(size: 70, offsetX: -100, offsetY: 80)
        saveViewCycleButton = Self.load(key: "saveViewCycleButton") ?? ButtonConfig(size: 70, offsetX: 150, offsetY: 150)
    }
    
    private static func load(key: String) -> ButtonConfig? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(ButtonConfig.self, from: data) else {
            return nil
        }
        return config
    }
    
    private func save() {
        save(mainSaveButton, key: "mainSaveButton")
        save(mainMapButton, key: "mainMapButton")
        save(mainResetButton, key: "mainResetButton")
        save(mainCameraButton, key: "mainCameraButton")
        
        save(saveViewSaveButton, key: "saveViewSaveButton")
        save(saveViewIncrementButton, key: "saveViewIncrementButton")
        save(saveViewDecrementButton, key: "saveViewDecrementButton")
        save(saveViewCycleButton, key: "saveViewCycleButton")
    }
    
    private func save(_ config: ButtonConfig, key: String) {
        if let data = try? encoder.encode(config) {
            defaults.set(data, forKey: key)
        }
    }
    
    func resetToDefaults() {
        mainSaveButton = ButtonConfig(size: 75, offsetX: 0, offsetY: 20)
        mainMapButton = ButtonConfig(size: 75, offsetX: 130, offsetY: 10)
        mainResetButton = ButtonConfig(size: 75, offsetX: -70, offsetY: -70)
        mainCameraButton = ButtonConfig(size: 75, offsetX: 70, offsetY: -70)
        
        saveViewSaveButton = ButtonConfig(size: 70, offsetX: 0, offsetY: 120)
        saveViewIncrementButton = ButtonConfig(size: 70, offsetX: 100, offsetY: 80)
        saveViewDecrementButton = ButtonConfig(size: 70, offsetX: -100, offsetY: 80)
        saveViewCycleButton = ButtonConfig(size: 70, offsetX: 150, offsetY: 150)
    }
}
