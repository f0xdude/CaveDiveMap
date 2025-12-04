import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var viewModel: MagnetometerViewModel
    
    // Formatter used for displaying final formatted values
    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()
    
    // Local edit buffers for smoother typing
    @State private var lowThresholdText: String = ""
    @State private var highThresholdText: String = ""
    @State private var wheelDiameterText: String = ""
    
    // Binding for axis selection
    private var axisSelection: Binding<MagneticAxis> {
        Binding<MagneticAxis>(
            get: { viewModel.selectedAxis },
            set: { viewModel.selectedAxis = $0 }
        )
    }
    
    // Decimal separator (locale-aware)
    private var decimalSeparator: String {
        numberFormatter.decimalSeparator ?? "."
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }

                Form {
                    // 🧭 Axis Selection
                    Section(header: Text("Magnetic Axis for Detection")) {
                        Picker("Axis", selection: axisSelection) {
                            ForEach(MagneticAxis.allCases) { axis in
                                Text(axis.rawValue.uppercased()).tag(axis)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .disabled(viewModel.isCalibrating)
                    }

                    // 🧪 Calibration Thresholds
                    Section(header: Text("Calibration")) {
                        HStack {
                            Text("Low Threshold")
                            Spacer()
                            TextField("Low Threshold", text: $lowThresholdText, onEditingChanged: { editing in
                                if !editing { commitLowThreshold() }
                            })
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(viewModel.isCalibrating)
                            .onReceive(Just(lowThresholdText)) { newValue in
                                let allowed = "0123456789" + decimalSeparator
                                var filtered = ""
                                for char in newValue {
                                    guard allowed.contains(char) else { continue }
                                    if String(char) == decimalSeparator && filtered.contains(decimalSeparator) {
                                        continue
                                    }
                                    filtered.append(char)
                                }
                                if filtered != newValue {
                                    lowThresholdText = filtered
                                }
                            }
                        }

                        HStack {
                            Text("High Threshold")
                            Spacer()
                            TextField("High Threshold", text: $highThresholdText, onEditingChanged: { editing in
                                if !editing { commitHighThreshold() }
                            })
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(viewModel.isCalibrating)
                            .onReceive(Just(highThresholdText)) { newValue in
                                let allowed = "0123456789" + decimalSeparator
                                var filtered = ""
                                for char in newValue {
                                    guard allowed.contains(char) else { continue }
                                    if String(char)  == decimalSeparator && filtered.contains(decimalSeparator) {
                                        continue
                                    }
                                    filtered.append(char)
                                }
                                if filtered != newValue {
                                    highThresholdText = filtered
                                }
                            }
                        }

                        if viewModel.isCalibrating {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rotate the wheel steadily…")
                                HStack {
                                    ProgressView()
                                    Text("Calibrating… \(viewModel.calibrationSecondsRemaining)s left")
                                }
                                Button(role: .destructive) {
                                    viewModel.cancelCalibration()
                                } label: {
                                    Text("Cancel Calibration")
                                }
                            }
                        } else {
                            Button {
                                viewModel.startCalibration(durationSeconds: 10)
                            } label: {
                                Text("Start Calibration (10s)")
                            }
                        }
                    }

                    // 🛞 Wheel Settings
                    Section(header: Text("Wheel Settings")) {
                        HStack {
                            Text("Wheel Diameter (cm)")
                            Spacer()
                            TextField("Diameter", text: $wheelDiameterText, onEditingChanged: { editing in
                                if !editing { commitWheelDiameter() }
                            })
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(viewModel.isCalibrating)
                            .onReceive(Just(wheelDiameterText)) { newValue in
                                let allowed = "0123456789" + decimalSeparator
                                var filtered = ""
                                for char in newValue {
                                    guard allowed.contains(char) else { continue }
                                    if String(char)  == decimalSeparator && filtered.contains(decimalSeparator) {
                                        continue
                                    }
                                    filtered.append(char)
                                }
                                if filtered != newValue {
                                    wheelDiameterText = filtered
                                }
                            }
                        }
                    }

                    // 🧼 Reset
                    Section {
                        Button(action: viewModel.resetToDefaults) {
                            Text("Reset to Defaults")
                                .foregroundColor(.red)
                        }
                        .disabled(viewModel.isCalibrating)
                    }

                    // 📊 Magnetic Debug Info
                    Section {
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
                    }

                    Section {
                        Link("Documentation and help", destination: URL(string: "https://github.com/f0xdude/CaveDiveMap")!)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: ButtonCustomizationView()) {
                        Text("Button Customization")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    NavigationLink(destination: PlyVisualizerView()) {
                        Text("PointCloud to Map")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    viewModel.startMonitoring()
                    UIApplication.shared.isIdleTimerDisabled = true
                    // initialize text buffers
                    lowThresholdText  = numberFormatter.string(from: NSNumber(value: viewModel.lowThreshold)) ?? ""
                    highThresholdText = numberFormatter.string(from: NSNumber(value: viewModel.highThreshold)) ?? ""
                    let diameter      = viewModel.wheelCircumference / Double.pi
                    wheelDiameterText = numberFormatter.string(from: NSNumber(value: diameter)) ?? ""
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                // Refresh text fields whenever thresholds change (e.g., after calibration)
                .onChange(of: viewModel.lowThreshold) { _, newValue in
                    lowThresholdText = numberFormatter.string(from: NSNumber(value: newValue)) ?? ""
                }
                .onChange(of: viewModel.highThreshold) { _, newValue in
                    highThresholdText = numberFormatter.string(from: NSNumber(value: newValue)) ?? ""
                }
            }
        }
    }
    
    // MARK: - Commit Helpers
    private func commitLowThreshold() {
        if let n = numberFormatter.number(from: lowThresholdText)?.doubleValue {
            viewModel.lowThreshold = n
        } else {
            viewModel.lowThreshold = 0
        }
        // Persist immediately so it survives reboot even if calibration isn’t run afterwards
        UserDefaults.standard.set(viewModel.lowThreshold, forKey: "lowThreshold")
        lowThresholdText = numberFormatter.string(from: NSNumber(value: viewModel.lowThreshold)) ?? ""
    }

    private func commitHighThreshold() {
        if let n = numberFormatter.number(from: highThresholdText)?.doubleValue {
            viewModel.highThreshold = n
        } else {
            viewModel.highThreshold = 0
        }
        // Persist immediately so it survives reboot even if calibration isn’t run afterwards
        UserDefaults.standard.set(viewModel.highThreshold, forKey: "highThreshold")
        highThresholdText = numberFormatter.string(from: NSNumber(value: viewModel.highThreshold)) ?? ""
    }

    private func commitWheelDiameter() {
        let parsed = numberFormatter.number(from: wheelDiameterText)?.doubleValue ?? 0
        viewModel.wheelCircumference = parsed * Double.pi
        let diameter = viewModel.wheelCircumference / Double.pi
        wheelDiameterText = numberFormatter.string(from: NSNumber(value: diameter)) ?? ""
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
