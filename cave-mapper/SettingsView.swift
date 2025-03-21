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
    
    // Binding for the wheel diameter (converted to circumference internally).
    // Since the circumference equals π * diameter,
    // the getter calculates diameter as: diameter = wheelCircumference / π,
    // and the setter converts the entered diameter to circumference.
    private var wheelDiameterString: Binding<String> {
        Binding<String>(
            get: {
                let diameter = viewModel.wheelCircumference / Double.pi
                return numberFormatter.string(from: NSNumber(value: diameter)) ?? ""
            },
            set: { newValue in
                if let number = numberFormatter.number(from: newValue) {
                    // Convert the entered diameter to circumference:
                    // circumference = π * diameter.
                    viewModel.wheelCircumference = Double.pi * number.doubleValue
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
                            Text("Wheel Diameter (cm)")
                            Spacer()
                            TextField("Diameter", text: wheelDiameterString)
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
                        Link("Documentation and help", destination: URL(string: "https://github.com/f0xdude/CaveDiveMap")!)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: VisualOdometer()) {
                        Text("(Experimental) Visual Odometer")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    NavigationLink(destination: AudioOdometer()) {
                        Text("(Experimental) Audio Odometer")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: BLESonarView()) {
                        Text("(Experimental) BLE SONAR")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: VisualOdometer()) {
                        Text("(Experimental) Visual Odometer")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    NavigationLink(destination: AudioOdometer()) {
                        Text("(Experimental) Audio Odometer")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: BLESonarView()) {
                        Text("(Experimental) BLE SONAR")
                            .font(.headline)
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
