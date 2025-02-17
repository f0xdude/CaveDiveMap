import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MagnetometerViewModel
    @StateObject private var magnetometer = MagnetometerViewModel()

    // NumberFormatter to handle decimal input.
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    // Binding for the highThreshold field.
    private var highThresholdString: Binding<String> {
        Binding<String>(
            get: {
                numberFormatter.string(from: NSNumber(value: viewModel.highThreshold)) ?? ""
            },
            set: { newValue in
                if let number = numberFormatter.number(from: newValue) {
                    viewModel.highThreshold = number.doubleValue
                } else if newValue.isEmpty {
                    viewModel.highThreshold = 0
                }
            }
        )
    }
    
    // Binding for the lowThreshold field.
    private var lowThresholdString: Binding<String> {
        Binding<String>(
            get: {
                numberFormatter.string(from: NSNumber(value: viewModel.lowThreshold)) ?? ""
            },
            set: { newValue in
                if let number = numberFormatter.number(from: newValue) {
                    viewModel.lowThreshold = number.doubleValue
                } else if newValue.isEmpty {
                    viewModel.lowThreshold = 0
                }
            }
        )
    }
    
    // Binding for the wheel radius (converted from circumference).
    private var wheelRadiusString: Binding<String> {
        Binding<String>(
            get: {
                let radius = viewModel.wheelCircumference / (2 * Double.pi)
                return numberFormatter.string(from: NSNumber(value: radius)) ?? ""
            },
            set: { newValue in
                if let number = numberFormatter.number(from: newValue) {
                    viewModel.wheelCircumference = 2 * Double.pi * number.doubleValue
                } else if newValue.isEmpty {
                    viewModel.wheelCircumference = 0
                }
            }
        )
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background view to catch taps and dismiss the keyboard.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                    }
                
                Form {
                    // MARK: - Calibration Section
                    Section(header: Text("Calibration")) {
                        HStack {
                            Text("Low Threshold")
                            Spacer()
                            TextField("Low Threshold", text: lowThresholdString)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        
                        HStack {
                            Text("High Threshold")
                            Spacer()
                            TextField("High Threshold", text: highThresholdString)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        
                        Button(action: {
                            viewModel.runManualCalibration()
                        }) {
                            Text("Detect Automatically")
                        }
                    }
                    
                    // MARK: - Wheel Settings Section
                    Section(header: Text("Wheel Settings")) {
                        HStack {
                            Text("Wheel Radius (cm)")
                            Spacer()
                            TextField("7", text: wheelRadiusString)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                    
                    // MARK: - Reset Section
                    Section {
                        Button(action: viewModel.resetToDefaults) {
                            Text("Reset to Defaults")
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Debugging: Display Magnetic Field Strength.
                    VStack(alignment: .leading) {
                        Text("Magnetic Field Strength (µT):")
                            .font(.headline)
                        
                        HStack {
                            Text("X: \(magnetometer.currentField.x, specifier: "%.2f")")
                                .monospacedDigit()
                            Text("Y: \(magnetometer.currentField.y, specifier: "%.2f")")
                                .monospacedDigit()
                            Text("Z: \(magnetometer.currentField.z, specifier: "%.2f")")
                                .monospacedDigit()
                        }
                        
                        Text("Magnitude: \(magnetometer.currentMagnitude, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                    .padding()
                    
                    // MARK: - About App Section
                    Section {
                        Link("About App", destination: URL(string: "https://example.com")!)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                magnetometer.startMonitoring()
                UIApplication.shared.isIdleTimerDisabled = true // Prevent screen from sleeping.
            }
            .onDisappear {
                magnetometer.stopMonitoring()
                UIApplication.shared.isIdleTimerDisabled = false // Allow screen to sleep again.
            }
        }
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
#endif
