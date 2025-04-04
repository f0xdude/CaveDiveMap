import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MagnetometerViewModel

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }

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

    private var wheelDiameterString: Binding<String> {
        Binding<String>(
            get: {
                let diameter = viewModel.wheelCircumference / Double.pi
                return numberFormatter.string(from: NSNumber(value: diameter)) ?? ""
            },
            set: { newValue in
                if let number = numberFormatter.number(from: newValue) {
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
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }

                Form {
                    // 🧭 Odometry Mode Selection
                    Section(header: Text("Odometry Mode")) {
                        Picker("Mode", selection: $viewModel.odometryMode) {
                            ForEach(OdometryMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // 🧪 Calibration Thresholds
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

                    // 🛞 Wheel Settings
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

                    // 🧼 Reset
                    Section {
                        Button(action: viewModel.resetToDefaults) {
                            Text("Reset to Defaults")
                                .foregroundColor(.red)
                        }
                    }

                    // 📊 Magnetic Debug Info (using main shared viewModel now)
                    VStack(alignment: .leading) {
                        Text("Magnetic Field Strength (µT):")
                            .font(.headline)
                        HStack {
                            Text("X: \(viewModel.currentField.x, specifier: "%.2f")")
                                .monospacedDigit()
                            Text("Y: \(viewModel.currentField.y, specifier: "%.2f")")
                                .monospacedDigit()
                            Text("Z: \(viewModel.currentField.z, specifier: "%.2f")")
                                .monospacedDigit()
                        }
                        Text("Magnitude: \(viewModel.currentMagnitude, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                    .padding()

                    Section {
                        Link("Documentation and help", destination: URL(string: "https://github.com/f0xdude/CaveDiveMap")!)
                            .foregroundColor(.blue)
                    }
                    
                    
                    NavigationLink(destination: VisualMapper()) {
                        Text("(Experimental) Visual Mapper")
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
                viewModel.startMonitoring()
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                //viewModel.stopMonitoring()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
