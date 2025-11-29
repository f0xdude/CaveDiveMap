//
//  ButtonCustomizationView.swift
//  cave-mapper
//
//  Created on 29.11.25.
//

import SwiftUI

enum ButtonScreen: String, CaseIterable, Identifiable {
    case mainScreen = "Main Screen"
    case saveDataView = "Save Data View"
    
    var id: String { rawValue }
}

enum MainScreenButton: String, CaseIterable, Identifiable {
    case save = "Save Button"
    case map = "Map Button"
    case reset = "Reset Button"
    case camera = "Camera Button"
    
    var id: String { rawValue }
}

enum SaveDataButton: String, CaseIterable, Identifiable {
    case save = "Save Button"
    case increment = "Plus Button"
    case decrement = "Minus Button"
    case cycle = "Cycle Button"
    
    var id: String { rawValue }
}

struct ButtonCustomizationView: View {
    @ObservedObject var settings = ButtonCustomizationSettings.shared
    @State private var selectedScreen: ButtonScreen = .mainScreen
    @State private var selectedMainButton: MainScreenButton = .save
    @State private var selectedSaveButton: SaveDataButton = .save
    
    var body: some View {
        Form {
            Section(header: Text("Select Screen")) {
                Picker("Screen", selection: $selectedScreen) {
                    ForEach(ButtonScreen.allCases) { screen in
                        Text(screen.rawValue).tag(screen)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            if selectedScreen == .mainScreen {
                mainScreenSettings
            } else {
                saveDataViewSettings
            }
            
            Section {
                Button("Reset All to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Button Customization")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Main Screen Settings
    private var mainScreenSettings: some View {
        Group {
            Section(header: Text("Select Button")) {
                Picker("Button", selection: $selectedMainButton) {
                    ForEach(MainScreenButton.allCases) { button in
                        Text(button.rawValue).tag(button)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("\(selectedMainButton.rawValue) Settings")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Size: \(Int(currentMainConfig.size))")
                        .font(.subheadline)
                    Slider(value: mainSizeBinding, in: 40...150, step: 5)
                    
                    Text("Horizontal Position: \(Int(currentMainConfig.offsetX))")
                        .font(.subheadline)
                    Slider(value: mainOffsetXBinding, in: -200...200, step: 5)
                    
                    Text("Vertical Position: \(Int(currentMainConfig.offsetY))")
                        .font(.subheadline)
                    Slider(value: mainOffsetYBinding, in: -200...200, step: 5)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Preview")) {
                ZStack {
                    Color.gray.opacity(0.1)
                        .frame(height: 300)
                        .cornerRadius(12)
                    
                    previewMainButton
                }
            }
        }
    }
    
    // MARK: - Save Data View Settings
    private var saveDataViewSettings: some View {
        Group {
            Section(header: Text("Select Button")) {
                Picker("Button", selection: $selectedSaveButton) {
                    ForEach(SaveDataButton.allCases) { button in
                        Text(button.rawValue).tag(button)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("\(selectedSaveButton.rawValue) Settings")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Size: \(Int(currentSaveConfig.size))")
                        .font(.subheadline)
                    Slider(value: saveSizeBinding, in: 40...150, step: 5)
                    
                    Text("Horizontal Position: \(Int(currentSaveConfig.offsetX))")
                        .font(.subheadline)
                    Slider(value: saveOffsetXBinding, in: -200...200, step: 5)
                    
                    Text("Vertical Position: \(Int(currentSaveConfig.offsetY))")
                        .font(.subheadline)
                    Slider(value: saveOffsetYBinding, in: -200...200, step: 5)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Preview")) {
                ZStack {
                    Color.gray.opacity(0.1)
                        .frame(height: 300)
                        .cornerRadius(12)
                    
                    previewSaveButton
                }
            }
        }
    }
    
    // MARK: - Preview Buttons
    @ViewBuilder
    private var previewMainButton: some View {
        let config = currentMainConfig
        
        ZStack {
            Circle()
                .fill(buttonColor(for: selectedMainButton))
                .frame(width: config.size, height: config.size)
            
            buttonIcon(for: selectedMainButton)
                .foregroundColor(.white)
                .font(.system(size: config.size * 0.35))
        }
        .offset(x: config.offsetX, y: config.offsetY)
    }
    
    @ViewBuilder
    private var previewSaveButton: some View {
        let config = currentSaveConfig
        
        ZStack {
            Circle()
                .fill(buttonColor(for: selectedSaveButton))
                .frame(width: config.size, height: config.size)
            
            buttonIcon(for: selectedSaveButton)
                .foregroundColor(.white)
                .font(.system(size: config.size * 0.35))
        }
        .offset(x: config.offsetX, y: config.offsetY)
    }
    
    // MARK: - Helpers
    private var currentMainConfig: ButtonConfig {
        switch selectedMainButton {
        case .save: return settings.mainSaveButton
        case .map: return settings.mainMapButton
        case .reset: return settings.mainResetButton
        case .camera: return settings.mainCameraButton
        }
    }
    
    private var currentSaveConfig: ButtonConfig {
        switch selectedSaveButton {
        case .save: return settings.saveViewSaveButton
        case .increment: return settings.saveViewIncrementButton
        case .decrement: return settings.saveViewDecrementButton
        case .cycle: return settings.saveViewCycleButton
        }
    }
    
    private var mainSizeBinding: Binding<Double> {
        switch selectedMainButton {
        case .save: return Binding(
            get: { settings.mainSaveButton.size },
            set: { settings.mainSaveButton.size = $0 }
        )
        case .map: return Binding(
            get: { settings.mainMapButton.size },
            set: { settings.mainMapButton.size = $0 }
        )
        case .reset: return Binding(
            get: { settings.mainResetButton.size },
            set: { settings.mainResetButton.size = $0 }
        )
        case .camera: return Binding(
            get: { settings.mainCameraButton.size },
            set: { settings.mainCameraButton.size = $0 }
        )
        }
    }
    
    private var mainOffsetXBinding: Binding<Double> {
        switch selectedMainButton {
        case .save: return Binding(
            get: { settings.mainSaveButton.offsetX },
            set: { settings.mainSaveButton.offsetX = $0 }
        )
        case .map: return Binding(
            get: { settings.mainMapButton.offsetX },
            set: { settings.mainMapButton.offsetX = $0 }
        )
        case .reset: return Binding(
            get: { settings.mainResetButton.offsetX },
            set: { settings.mainResetButton.offsetX = $0 }
        )
        case .camera: return Binding(
            get: { settings.mainCameraButton.offsetX },
            set: { settings.mainCameraButton.offsetX = $0 }
        )
        }
    }
    
    private var mainOffsetYBinding: Binding<Double> {
        switch selectedMainButton {
        case .save: return Binding(
            get: { settings.mainSaveButton.offsetY },
            set: { settings.mainSaveButton.offsetY = $0 }
        )
        case .map: return Binding(
            get: { settings.mainMapButton.offsetY },
            set: { settings.mainMapButton.offsetY = $0 }
        )
        case .reset: return Binding(
            get: { settings.mainResetButton.offsetY },
            set: { settings.mainResetButton.offsetY = $0 }
        )
        case .camera: return Binding(
            get: { settings.mainCameraButton.offsetY },
            set: { settings.mainCameraButton.offsetY = $0 }
        )
        }
    }
    
    private var saveSizeBinding: Binding<Double> {
        switch selectedSaveButton {
        case .save: return Binding(
            get: { settings.saveViewSaveButton.size },
            set: { settings.saveViewSaveButton.size = $0 }
        )
        case .increment: return Binding(
            get: { settings.saveViewIncrementButton.size },
            set: { settings.saveViewIncrementButton.size = $0 }
        )
        case .decrement: return Binding(
            get: { settings.saveViewDecrementButton.size },
            set: { settings.saveViewDecrementButton.size = $0 }
        )
        case .cycle: return Binding(
            get: { settings.saveViewCycleButton.size },
            set: { settings.saveViewCycleButton.size = $0 }
        )
        }
    }
    
    private var saveOffsetXBinding: Binding<Double> {
        switch selectedSaveButton {
        case .save: return Binding(
            get: { settings.saveViewSaveButton.offsetX },
            set: { settings.saveViewSaveButton.offsetX = $0 }
        )
        case .increment: return Binding(
            get: { settings.saveViewIncrementButton.offsetX },
            set: { settings.saveViewIncrementButton.offsetX = $0 }
        )
        case .decrement: return Binding(
            get: { settings.saveViewDecrementButton.offsetX },
            set: { settings.saveViewDecrementButton.offsetX = $0 }
        )
        case .cycle: return Binding(
            get: { settings.saveViewCycleButton.offsetX },
            set: { settings.saveViewCycleButton.offsetX = $0 }
        )
        }
    }
    
    private var saveOffsetYBinding: Binding<Double> {
        switch selectedSaveButton {
        case .save: return Binding(
            get: { settings.saveViewSaveButton.offsetY },
            set: { settings.saveViewSaveButton.offsetY = $0 }
        )
        case .increment: return Binding(
            get: { settings.saveViewIncrementButton.offsetY },
            set: { settings.saveViewIncrementButton.offsetY = $0 }
        )
        case .decrement: return Binding(
            get: { settings.saveViewDecrementButton.offsetY },
            set: { settings.saveViewDecrementButton.offsetY = $0 }
        )
        case .cycle: return Binding(
            get: { settings.saveViewCycleButton.offsetY },
            set: { settings.saveViewCycleButton.offsetY = $0 }
        )
        }
    }
    
    private func buttonColor(for button: MainScreenButton) -> Color {
        switch button {
        case .save: return .green
        case .map: return .blue
        case .reset: return .red
        case .camera: return .orange
        }
    }
    
    private func buttonColor(for button: SaveDataButton) -> Color {
        switch button {
        case .save: return .green
        case .increment, .decrement: return .orange
        case .cycle: return .blue
        }
    }
    
    @ViewBuilder
    private func buttonIcon(for button: MainScreenButton) -> some View {
        switch button {
        case .save:
            Image(systemName: "square.and.arrow.down.fill")
        case .map:
            Image(systemName: "map.fill")
        case .reset:
            Text("Reset").font(.system(size: 14, weight: .bold))
        case .camera:
            Image(systemName: "camera.fill")
        }
    }
    
    @ViewBuilder
    private func buttonIcon(for button: SaveDataButton) -> some View {
        switch button {
        case .save:
            Text("Save").font(.system(size: 14, weight: .bold))
        case .increment:
            Image(systemName: "plus")
        case .decrement:
            Image(systemName: "minus")
        case .cycle:
            Image(systemName: "arrow.trianglehead.2.clockwise")
        }
    }
}
