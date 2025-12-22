//
//  MagneticVectorVisualizationView.swift
//  cave-mapper
//
//  Vector visualization for debugging magnetic rotation detection
//

import SwiftUI

struct MagneticVectorVisualizationView: View {
    @ObservedObject var viewModel: MagnetometerViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Magnetic Vector Visualization")
                .font(.title2)
                .fontWeight(.bold)
            
            // 2D Vector Plot in Detection Plane
            VStack {
                Text("Detection Plane View")
                    .font(.headline)
                
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 250, height: 250)
                    
                    // Threshold circle
                    Circle()
                        .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                        .frame(width: 200, height: 200)
                    
                    // Concentric circles for reference
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        Circle()
                            .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            .frame(width: 250 * fraction, height: 250 * fraction)
                    }
                    
                    // Axis lines
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 125))
                        path.addLine(to: CGPoint(x: 250, y: 125))
                        path.move(to: CGPoint(x: 125, y: 0))
                        path.addLine(to: CGPoint(x: 125, y: 250))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    
                    // Magnetic vector
                    MagneticVectorArrow(
                        angle: Angle(degrees: viewModel.magnetAngle),
                        magnitude: min(viewModel.vectorMagnitude / 200.0, 1.0),
                        color: stateColor(for: viewModel.detectedRotationState)
                    )
                    
                    // Center dot
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 250, height: 250)
                
                Text("Angle: \(viewModel.magnetAngle, specifier: "%.1f")°")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // State and magnitude info
            HStack(spacing: 30) {
                VStack {
                    Text(viewModel.detectedRotationState.capitalized)
                        .font(.headline)
                        .foregroundColor(stateColor(for: viewModel.detectedRotationState))
                    Text("State")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(viewModel.vectorMagnitude, specifier: "%.1f")")
                        .font(.headline)
                        .monospacedDigit()
                    Text("Magnitude (µT)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(viewModel.magnetDistance, specifier: "%.2f")")
                        .font(.headline)
                        .monospacedDigit()
                    Text("Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            // 3D Vector Components
            VStack(alignment: .leading, spacing: 12) {
                Text("Raw Field Components")
                    .font(.headline)
                
                HStack {
                    VectorComponentBar(label: "X", value: viewModel.currentField.x, maxValue: 100)
                    VectorComponentBar(label: "Y", value: viewModel.currentField.y, maxValue: 100)
                    VectorComponentBar(label: "Z", value: viewModel.currentField.z, maxValue: 100)
                }
                
                Text("Ambient Field: \(viewModel.currentBaseline, specifier: "%.1f") µT")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Vector Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startMonitoring()
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

struct MagneticVectorArrow: View {
    let angle: Angle
    let magnitude: Double
    let color: Color
    
    var body: some View {
        let length = 100.0 * magnitude
        let endX = 125 + length * cos(angle.radians - .pi / 2)
        let endY = 125 + length * sin(angle.radians - .pi / 2)
        
        return ZStack {
            // Arrow line
            Path { path in
                path.move(to: CGPoint(x: 125, y: 125))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // Arrowhead
            Path { path in
                let arrowSize: Double = 10
                let angle1 = angle.radians - .pi / 2 + 2.5
                let angle2 = angle.radians - .pi / 2 - 2.5
                
                path.move(to: CGPoint(x: endX, y: endY))
                path.addLine(to: CGPoint(
                    x: endX - arrowSize * cos(angle1),
                    y: endY - arrowSize * sin(angle1)
                ))
                path.move(to: CGPoint(x: endX, y: endY))
                path.addLine(to: CGPoint(
                    x: endX - arrowSize * cos(angle2),
                    y: endY - arrowSize * sin(angle2)
                ))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // Glow effect for better visibility
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
                .position(x: endX, y: endY)
        }
    }
}

struct VectorComponentBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    
    private var normalizedValue: Double {
        abs(value) / maxValue
    }
    
    private var barColor: Color {
        if abs(value) > maxValue * 0.7 {
            return .red
        } else if abs(value) > maxValue * 0.4 {
            return .orange
        } else {
            return .blue
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
            
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 100)
                
                // Value bar
                Rectangle()
                    .fill(barColor)
                    .frame(width: 60, height: min(100 * normalizedValue, 100))
            }
            .cornerRadius(4)
            
            Text("\(value, specifier: "%.1f")")
                .font(.caption)
                .monospacedDigit()
        }
    }
}

struct MagneticVectorVisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MagneticVectorVisualizationView(viewModel: MagnetometerViewModel())
        }
    }
}
