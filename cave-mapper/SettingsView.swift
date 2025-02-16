import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MagnetometerViewModel
    
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
            Form {
                // MARK: - Calibration Section
                Section(header: Text("Calibration")) {
                    HStack {
                        Text("Low Threshold")
                        Spacer()
                        // Editable TextField to display and edit the low threshold.
                        TextField("Low Threshold", text: lowThresholdString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("High Threshold")
                        Spacer()
                        // Editable TextField to display and edit the high threshold.
                        TextField("High Threshold", text: highThresholdString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    Button(action: {
                        viewModel.runManualCalibration()
                    }) {
                        Text("Run Calibration Manually")
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
                    Text("Needed to accurately calculate distance")
                }
                
                // MARK: - Reset Section
                Section {
                    Button(action: viewModel.resetToDefaults) {
                        Text("Reset to Defaults")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
                hideKeyboard()
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
