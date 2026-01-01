import SwiftUI
import Combine

struct SettingsView: View {
    // Don't observe viewModel either - just receive it for method calls
    let viewModel: MagnetometerViewModel
    // Don't observe the entire manager - just receive it for method calls
    let detectionManager: WheelDetectionManager
    @State private var showOpticalPreview = false
    
    // Local state for detection method to isolate from high-frequency updates
    @State private var localDetectionMethod: WheelDetectionMethod
    @State private var localSelectedAxis: MagneticAxis
    @State private var isOpticalCalibrating: Bool = false
    @State private var isMagneticCalibrating: Bool = false
    
    init(viewModel: MagnetometerViewModel, detectionManager: WheelDetectionManager) {
        self.viewModel = viewModel
        self.detectionManager = detectionManager
        // Initialize local state from manager
        self._localDetectionMethod = State(initialValue: detectionManager.detectionMethod)
        self._localSelectedAxis = State(initialValue: viewModel.selectedAxis)
        self._isOpticalCalibrating = State(initialValue: detectionManager.opticalDetector.isCalibrating)
        self._isMagneticCalibrating = State(initialValue: viewModel.isCalibrating)
    }
    
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
                    // 🔄 Detection Method Selection - Isolated from high-frequency updates
                    DetectionMethodPickerSection(
                        localDetectionMethod: $localDetectionMethod,
                        isCalibrating: isMagneticCalibrating || isOpticalCalibrating,
                        onMethodChange: { newMethod in
                            print("🎯 SettingsView: Method change requested to \(newMethod.rawValue)")
                            detectionManager.switchDetectionMethod(to: newMethod)
                        }
                    )
                    
                    // 🧭 Magnetic Detection Settings
                    if localDetectionMethod == .magnetic {
                        MagneticAxisPickerSection(
                            localSelectedAxis: $localSelectedAxis,
                            isCalibrating: isMagneticCalibrating,
                            onAxisChange: { newAxis in
                                print("🎯 SettingsView: Axis change requested to \(newAxis.rawValue)")
                                viewModel.selectedAxis = newAxis
                            }
                        )
                        
                        magneticCalibrationSection
                        magneticDebugSection
                    }
                    
                    // 🌊 PCA Magnetic Detection Settings
                    if localDetectionMethod == .magneticPCA {
                        pcaCalibrationSection
                        pcaDebugSection
                    }
                    
                    // 📸 Optical Detection Settings
                    if localDetectionMethod == .optical {
                        opticalCalibrationSection
                        opticalPreviewSection
                    }
                    
                    // 🛞 Wheel Settings (common to both methods)
                    wheelSettingsSection
                    
                    // 🧼 Reset
                    resetSection
                    
                    // 📚 Documentation
                    documentationSection
                    
                    navigationLinksSection
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    print("📱 SettingsView.onAppear - detection method: \(localDetectionMethod)")
                    
                    // Sync local state with manager on appear
                    localDetectionMethod = detectionManager.detectionMethod
                    localSelectedAxis = viewModel.selectedAxis
                    
                    // Initialize text field buffers
                    lowThresholdText  = numberFormatter.string(from: NSNumber(value: viewModel.lowThreshold)) ?? ""
                    highThresholdText = numberFormatter.string(from: NSNumber(value: viewModel.highThreshold)) ?? ""
                    let diameter      = viewModel.wheelCircumference / Double.pi
                    wheelDiameterText = numberFormatter.string(from: NSNumber(value: diameter)) ?? ""
                    
                    // Load optical thresholds
                    detectionManager.opticalDetector.loadSavedThresholds()
                    
                    // Keep screen awake
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    print("📱 SettingsView.onDisappear")
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                // Refresh text fields whenever thresholds change (e.g., after calibration)
                .onChange(of: viewModel.lowThreshold) { _, newValue in
                    lowThresholdText = numberFormatter.string(from: NSNumber(value: newValue)) ?? ""
                }
                .onChange(of: viewModel.highThreshold) { _, newValue in
                    highThresholdText = numberFormatter.string(from: NSNumber(value: newValue)) ?? ""
                }
                .sheet(isPresented: $showOpticalPreview) {
                    OpticalDetectionPreviewView(opticalDetector: detectionManager.opticalDetector)
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
    
    // MARK: - Section Views
    private var magneticCalibrationSection: some View {
        Section(header: Text("Magnetic Calibration")) {
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
                        if String(char) == decimalSeparator && filtered.contains(decimalSeparator) {
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
    }
    
    private var magneticDebugSection: some View {
        Section(header: Text("Magnetic Debug Info")) {
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
    }
    
    // MARK: - PCA Sections
    private var pcaCalibrationSection: some View {
        Section(header: Text("PCA Phase Tracking")) {
            VStack(alignment: .leading, spacing: 12) {
                // Signal Strength Bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Signal Strength")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.2f µT", detectionManager.pcaDetector.currentSignalAmplitude))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(signalStrengthColor)
                    }
                    
                    // Visual bar indicator
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 20)
                                .cornerRadius(10)
                            
                            // Threshold marker
                            let thresholdPosition = min(1.0, detectionManager.pcaDetector.minSignalAmplitude / maxDisplayAmplitude) * geometry.size.width
                            Rectangle()
                                .fill(Color.orange.opacity(0.3))
                                .frame(width: 2, height: 20)
                                .offset(x: thresholdPosition)
                            
                            // Signal strength bar
                            let signalWidth = min(1.0, detectionManager.pcaDetector.currentSignalAmplitude / maxDisplayAmplitude) * geometry.size.width
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [signalStrengthColor, signalStrengthColor.opacity(0.7)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, signalWidth), height: 20)
                                .cornerRadius(10)
                                .animation(.easeOut(duration: 0.1), value: detectionManager.pcaDetector.currentSignalAmplitude)
                        }
                    }
                    .frame(height: 20)
                    
                    HStack {
                        Text("Threshold: \(String(format: "%.2f", detectionManager.pcaDetector.minSignalAmplitude)) µT")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Max: \(String(format: "%.1f", maxDisplayAmplitude)) µT")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                
                HStack {
                    Text("Phase Angle")
                    Spacer()
                    Text(String(format: "%.2f°", detectionManager.pcaDetector.phaseAngle * 180 / .pi))
                        .monospacedDigit()
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Signal Quality (Planarity)")
                    Spacer()
                    Text(String(format: "%.1f%%", detectionManager.pcaDetector.signalQuality * 100))
                        .monospacedDigit()
                        .foregroundColor(detectionManager.pcaDetector.signalQuality > 0.7 ? .green : (detectionManager.pcaDetector.signalQuality > 0.5 ? .orange : .red))
                }
                
                Text("Planarity measures how flat the rotation is in the PCA-derived plane. Higher values indicate cleaner rotation signal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Calibration UI
            if detectionManager.pcaDetector.isCalibrating {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotate the wheel steadily to calibrate amplitude threshold…")
                        .font(.subheadline)
                    HStack {
                        ProgressView(value: detectionManager.pcaDetector.calibrationProgress)
                        Text("\(Int(detectionManager.pcaDetector.calibrationProgress * 100))%")
                            .monospacedDigit()
                    }
                    Button(role: .destructive) {
                        detectionManager.pcaDetector.cancelCalibration()
                    } label: {
                        Text("Cancel Calibration")
                    }
                }
                .padding(.top, 8)
            } else {
                Button {
                    detectionManager.pcaDetector.startCalibration()
                } label: {
                    HStack {
                        Image(systemName: "waveform.circle")
                        Text("Calibrate Signal Threshold (10s)")
                    }
                }
                .padding(.top, 8)
                
                Text("Calibration helps filter out noise by measuring magnet signal strength. Rotate the wheel during calibration to capture strong signals.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
    
    // Helper computed properties for signal strength visualization
    private var maxDisplayAmplitude: Double {
        // Use 3x threshold or minimum 5.0 µT for display scale
        max(5.0, detectionManager.pcaDetector.minSignalAmplitude * 3.0)
    }
    
    private var signalStrengthColor: Color {
        let amplitude = detectionManager.pcaDetector.currentSignalAmplitude
        let threshold = detectionManager.pcaDetector.minSignalAmplitude
        
        if amplitude < threshold * 0.5 {
            return .red
        } else if amplitude < threshold {
            return .orange
        } else if amplitude < threshold * 2.0 {
            return .green
        } else {
            return .blue // Very strong signal
        }
    }
    
    private var pcaDebugSection: some View {
        Section(header: Text("PCA Debug Info")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Raw Magnetic Field (µT):")
                    .font(.headline)
                HStack {
                    Text("X: \(detectionManager.pcaDetector.currentField.x, specifier: "%.2f")")
                        .monospacedDigit()
                    Text("Y: \(detectionManager.pcaDetector.currentField.y, specifier: "%.2f")")
                        .monospacedDigit()
                    Text("Z: \(detectionManager.pcaDetector.currentField.z, specifier: "%.2f")")
                        .monospacedDigit()
                }
                Text("Magnitude: \(detectionManager.pcaDetector.currentMagnitude, specifier: "%.2f")")
                    .monospacedDigit()
                
                Divider()
                
                Text("Phase Tracking:")
                    .font(.headline)
                HStack {
                    Text("Current Phase:")
                    Spacer()
                    Text(String(format: "%.2f°", detectionManager.pcaDetector.phaseAngle * 180 / .pi))
                        .monospacedDigit()
                }
                
                Divider()
                
                HStack {
                    Text("Planarity:")
                    Spacer()
                    Text(String(format: "%.1f%%", detectionManager.pcaDetector.signalQuality * 100))
                        .monospacedDigit()
                        .foregroundColor(detectionManager.pcaDetector.signalQuality > 0.7 ? .green : .orange)
                }
                
                Text("Algorithm: Baseline removal → PCA → 2D projection → θ=atan2(v,u) → unwrap → count 2π")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Includes inertial rejection (gyro + accel) to suppress false counts during phone movement.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    private var opticalCalibrationSection: some View {
        Section(header: Text("Optical Calibration")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Low Threshold")
                    Spacer()
                    Text(String(format: "%.3f", detectionManager.opticalDetector.lowBrightnessThreshold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("High Threshold")
                    Spacer()
                    Text(String(format: "%.3f", detectionManager.opticalDetector.highBrightnessThreshold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Current Brightness")
                    Spacer()
                    Text(String(format: "%.3f", detectionManager.opticalDetector.currentBrightness))
                        .monospacedDigit()
                        .foregroundColor(.blue)
                }
                
                Divider()
                
                // Flashlight Brightness Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: detectionManager.opticalDetector.flashlightBrightness > 0 ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundColor(detectionManager.opticalDetector.flashlightBrightness > 0 ? .yellow : .gray)
                        Text("Flashlight Brightness")
                        Spacer()
                        Text("\(Int(detectionManager.opticalDetector.flashlightBrightness * 100))%")
                            .monospacedDigit()
                            .foregroundColor(detectionManager.opticalDetector.flashlightBrightness > 0 ? .primary : .secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { detectionManager.opticalDetector.flashlightBrightness },
                            set: { newValue in
                                detectionManager.opticalDetector.flashlightBrightness = Float(newValue)
                            }
                        ),
                        in: 0...1,
                        step: 0.05  // 5% increments
                    ) {
                        Text("Brightness")
                    } minimumValueLabel: {
                        Text("0%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("100%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if detectionManager.opticalDetector.flashlightBrightness == 0 {
                        Text("Flashlight is off. Slide to enable.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if detectionManager.opticalDetector.flashlightBrightness >= 0.8 {
                        Text("High brightness may cause overheating")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if detectionManager.opticalDetector.isCalibrating {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotate the wheel steadily…")
                    HStack {
                        ProgressView(value: detectionManager.opticalDetector.calibrationProgress)
                        Text("\(Int(detectionManager.opticalDetector.calibrationProgress * 100))%")
                            .monospacedDigit()
                    }
                    Button(role: .destructive) {
                        detectionManager.opticalDetector.cancelCalibration()
                    } label: {
                        Text("Cancel Calibration")
                    }
                }
            } else {
                Button {
                    detectionManager.opticalDetector.startCalibration()
                } label: {
                    Text("Start Calibration (10s)")
                }
            }
        }
    }
    
    private var opticalPreviewSection: some View {
        Section(header: Text("Camera Preview")) {
            Button {
                showOpticalPreview = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Show Detection Preview")
                }
            }
        }
    }
    
    private var wheelSettingsSection: some View {
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
                        if String(char) == decimalSeparator && filtered.contains(decimalSeparator) {
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
    }
    
    private var resetSection: some View {
        Section {
            Button(action: viewModel.resetToDefaults) {
                Text("Reset to Defaults")
                    .foregroundColor(.red)
            }
            .disabled(viewModel.isCalibrating || detectionManager.opticalDetector.isCalibrating)
        }
    }
    
    private var documentationSection: some View {
        Section {
            Link("Documentation and help", destination: URL(string: "https://github.com/f0xdude/CaveDiveMap")!)
                .foregroundColor(.blue)
        }
    }
    
    private var navigationLinksSection: some View {
        Group {
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
    }
}

// MARK: - Isolated Magnetic Axis Picker Section
// This view does NOT observe the MagnetometerViewModel to avoid re-renders from high-frequency updates
struct MagneticAxisPickerSection: View {
    @Binding var localSelectedAxis: MagneticAxis
    let isCalibrating: Bool
    let onAxisChange: (MagneticAxis) -> Void
    
    var body: some View {
        Section(header: Text("Magnetic Axis for Detection")) {
            // Use custom buttons instead of Picker for guaranteed responsiveness
            HStack(spacing: 4) {
                ForEach(MagneticAxis.allCases) { axis in
                    Button(action: {
                        print("🔘 Axis button tapped for: \(axis.rawValue)")
                        guard !isCalibrating else {
                            print("⚠️ Calibration in progress, ignoring tap")
                            return
                        }
                        
                        // Update local state FIRST for immediate UI feedback
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localSelectedAxis = axis
                        }
                        
                        // Then notify parent
                        onAxisChange(axis)
                    }) {
                        Text(axis.rawValue.uppercased())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(localSelectedAxis == axis ? .white : .blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(localSelectedAxis == axis ? Color.blue : Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                    .disabled(isCalibrating)
                }
            }
        }
    }
}

// MARK: - Isolated Detection Method Picker Section
// This view does NOT observe the WheelDetectionManager to avoid re-renders from high-frequency updates
struct DetectionMethodPickerSection: View {
    @Binding var localDetectionMethod: WheelDetectionMethod
    let isCalibrating: Bool
    let onMethodChange: (WheelDetectionMethod) -> Void
    
    var body: some View {
        Section(header: Text("Detection Method")) {
            // Use custom buttons instead of Picker for guaranteed responsiveness
            VStack(spacing: 0) {
                ForEach(WheelDetectionMethod.allCases) { method in
                    Button(action: {
                        print("🔘 Button tapped for method: \(method.rawValue)")
                        guard !isCalibrating else {
                            print("⚠️ Calibration in progress, ignoring tap")
                            return
                        }
                        
                        // Update local state FIRST for immediate UI feedback
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localDetectionMethod = method
                        }
                        
                        // Then notify parent
                        onMethodChange(method)
                    }) {
                        HStack {
                            Image(systemName: method.icon)
                                .foregroundColor(localDetectionMethod == method ? .white : .blue)
                            Text(method.rawValue)
                                .foregroundColor(localDetectionMethod == method ? .white : .primary)
                            Spacer()
                            if localDetectionMethod == method {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(localDetectionMethod == method ? Color.blue : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                    .disabled(isCalibrating)
                }
            }
            
            Text(localDetectionMethod.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
#endif
