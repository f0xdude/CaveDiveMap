//
//  OpticalDetectionPreviewView.swift
//  cave-mapper
//
//  Created on 12/25/25.
//

import SwiftUI
import AVFoundation

/// Preview view for optical wheel detection setup
/// Shows camera feed and brightness level in real-time
struct OpticalDetectionPreviewView: View {
    @ObservedObject var opticalDetector: OpticalWheelDetector
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Text("Optical Detection Setup")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Spacer()
                
                // Camera preview placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 300)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("Position the phone so the wheel\nopening blocks the camera")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        // Brightness indicator
                        VStack {
                            Text("Current Brightness")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text(String(format: "%.3f", opticalDetector.currentBrightness))
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(brightnessColor)
                        }
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                    }
                }
                .padding()
                
                // Threshold visualization
                VStack(spacing: 8) {
                    HStack {
                        Text("Low: \(String(format: "%.3f", opticalDetector.lowBrightnessThreshold))")
                            .foregroundColor(.red)
                        Spacer()
                        Text("High: \(String(format: "%.3f", opticalDetector.highBrightnessThreshold))")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 40)
                            
                            // Current brightness indicator
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * opticalDetector.currentBrightness, height: 40)
                            
                            // Low threshold marker
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 3, height: 40)
                                .offset(x: geometry.size.width * opticalDetector.lowBrightnessThreshold)
                            
                            // High threshold marker
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 3, height: 40)
                                .offset(x: geometry.size.width * opticalDetector.highBrightnessThreshold)
                            
                            // Labels
                            HStack {
                                Text("Dark")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.leading, 8)
                                Spacer()
                                Text("Bright")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                    .frame(height: 40)
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                // Status
                if opticalDetector.isRunning {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text("Detecting: \(opticalDetector.rotationCount) rotations")
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Close button
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding()
            }
        }
    }
    
    private var brightnessColor: Color {
        if opticalDetector.currentBrightness < opticalDetector.lowBrightnessThreshold {
            return .red
        } else if opticalDetector.currentBrightness > opticalDetector.highBrightnessThreshold {
            return .green
        } else {
            return .yellow
        }
    }
}
