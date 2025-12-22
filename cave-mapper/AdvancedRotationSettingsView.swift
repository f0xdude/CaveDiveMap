//
//  AdvancedRotationSettingsView.swift
//  cave-mapper
//
//  Advanced tuning parameters for vector rotation detection
//

import SwiftUI

struct AdvancedRotationSettingsView: View {
    @ObservedObject var viewModel: MagnetometerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Form {
            Section(header: Text("Detection Algorithm")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Method: Vector Rotation Analysis")
                        .font(.headline)
                    Text("Tracks full 3D magnetic vector and detects complete rotation cycles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Sensitivity Tuning")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("kHigh: \(viewModel.kHigh, specifier: "%.2f")")
                        .font(.headline)
                    Slider(value: Binding(
                        get: { viewModel.kHigh },
                        set: { viewModel.kHigh = $0 }
                    ), in: 1.0...5.0, step: 0.1)
                    
                    Text("Controls detection threshold. Higher = less sensitive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("kLow: \(viewModel.kLow, specifier: "%.2f")")
                        .font(.headline)
                    Slider(value: Binding(
                        get: { viewModel.kLow },
                        set: { viewModel.kLow = $0 }
                    ), in: 0.5...3.0, step: 0.1)
                    
                    Text("Controls reset threshold for next detection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Real-time Diagnostics")) {
                VStack(alignment: .leading, spacing: 8) {
                    DiagnosticRow(
                        label: "Current State",
                        value: viewModel.detectedRotationState.capitalized,
                        color: stateColor(for: viewModel.detectedRotationState)
                    )
                    
                    DiagnosticRow(
                        label: "Vector Magnitude",
                        value: "\(viewModel.vectorMagnitude, specifier: "%.1f") µT",
                        color: viewModel.vectorMagnitude > viewModel.adaptiveHighThreshold ? .green : .primary
                    )
                    
                    DiagnosticRow(
                        label: "Detection Threshold",
                        value: "\(viewModel.adaptiveHighThreshold, specifier: "%.1f") µT",
                        color: .orange
                    )
                    
                    DiagnosticRow(
                        label: "Ambient Field",
                        value: "\(viewModel.currentBaseline, specifier: "%.1f") µT",
                        color: .blue
                    )
                }
            }
            
            Section(header: Text("Test Rotation Detection")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotate your wheel while watching the diagnostics above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("You should see the state cycle through:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        StateLabel(text: "Idle", color: .gray)
                        Text("→")
                        StateLabel(text: "Approach", color: .blue)
                        Text("→")
                        StateLabel(text: "Pass", color: .green)
                        Text("→")
                        StateLabel(text: "Recede", color: .orange)
                    }
                    .font(.caption)
                }
            }
            
            Section(header: Text("Quick Actions")) {
                Button(action: {
                    viewModel.kHigh = 2.5
                    viewModel.kLow = 1.0
                }) {
                    Text("Reset to Defaults")
                        .foregroundColor(.blue)
                }
                
                NavigationLink(destination: MagneticVectorVisualizationView(viewModel: viewModel)) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                        Text("Open Vector Visualization")
                    }
                }
            }
            
            Section(header: Text("Algorithm Information")) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Update Rate", value: "50 Hz")
                    InfoRow(label: "Vector History", value: "50 samples (~1s)")
                    InfoRow(label: "Detection Plane", value: axisDescription)
                    InfoRow(label: "Angle Tracking", value: "Full 360°")
                    InfoRow(label: "State Machine", value: "4 states")
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startMonitoring()
        }
    }
    
    private var axisDescription: String {
        switch viewModel.selectedAxis {
        case .x: return "YZ plane (X-axis rotation)"
        case .y: return "XZ plane (Y-axis rotation)"
        case .z: return "XY plane (Z-axis rotation)"
        case .magnitude: return "XY plane (default)"
        }
    }
    
    private func stateColor(for state: String) -> Color {
        switch state.lowercased() {
        case "idle": return .gray
        case "approaching": return .blue
        case "passing": return .green
        case "receding": return .orange
        default: return .primary
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundColor(color)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }
}

struct StateLabel: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct AdvancedRotationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AdvancedRotationSettingsView(viewModel: MagnetometerViewModel())
        }
    }
}
