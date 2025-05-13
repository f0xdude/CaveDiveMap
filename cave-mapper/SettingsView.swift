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
                            .onReceive(Just(lowThresholdText)) { newValue in
                                // Break up filter into explicit loop to aid type-checking
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
                            .onReceive(Just(highThresholdText)) { newValue in
                                // Break up filter into explicit loop
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

                        Button(action: viewModel.runManualCalibration) {
                            Text("Detect Automatically")
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
                            .onReceive(Just(wheelDiameterText)) { newValue in
                                // Break up filter into explicit loop
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
                    
                    NavigationLink(destination: VisualMapper()) {
                        Text("(Experimental) Visual Mapper")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    NavigationLink(destination: BLESonarView()) {
                        Text("(Experimental) BLE SONAR")
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
        lowThresholdText = numberFormatter.string(from: NSNumber(value: viewModel.lowThreshold)) ?? ""
    }

    private func commitHighThreshold() {
        if let n = numberFormatter.number(from: highThresholdText)?.doubleValue {
            viewModel.highThreshold = n
        } else {
            viewModel.highThreshold = 0
        }
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
