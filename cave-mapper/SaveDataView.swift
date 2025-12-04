import SwiftUI
import UIKit

// Define the parameters in the order to cycle through.
enum ParameterType: String, CaseIterable {
    case depth = "Depth"
    case left = "Left"
    case right = "Right"
    case up = "Up"
    case down = "Down"
}

struct SaveDataView: View {
    
    @State private var pointNumber: Int = DataManager.loadPointNumber()
    @ObservedObject var magnetometer: MagnetometerViewModel
    @ObservedObject private var buttonSettings = ButtonCustomizationSettings.shared
    @State private var depth: Double = DataManager.loadLastSavedDepth() // Initialize with last saved depth
    @State private var distance: Double = DataManager.loadLastSavedDistance() // Initialize with last saved distance
    
    // New state variables for the additional parameters.
    @State private var left: Double = 0.0
    @State private var right: Double = 0.0
    @State private var up: Double = 0.0
    @State private var down: Double = 0.0
    
    // Track which parameter is currently selected.
    @State private var selectedParameter: ParameterType = .depth
    
    @Environment(\.presentationMode) var presentationMode

    // Shared button sizing (match Save button) - removed as we'll use settings
    // private let bigButtonSize: CGFloat = 70
    // private let smallIconSize: CGFloat = 28

    // Auto-repeat timers for press-and-hold
    @State private var incrementTimer: Timer?
    @State private var decrementTimer: Timer?

    // Hold-threshold work items (to decide tap vs hold)
    @State private var incHoldWork: DispatchWorkItem?
    @State private var decHoldWork: DispatchWorkItem?

    // Whether the long-press path is active (to suppress tap on release)
    @State private var isIncrementHolding = false
    @State private var isDecrementHolding = false

    var body: some View {
        VStack(spacing: 18) {
            // Header info card
            VStack(alignment: .leading, spacing: 10) {
                Text("Point Number: \(pointNumber)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Distance: \(distance, specifier: "%.2f") m")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Heading: \(magnetometer.currentHeading?.magneticHeading ?? 0, specifier: "%.2f")°")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(26)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .padding(.top, 8)

            Divider().padding(.horizontal, 4)

            // Selected parameter card
            VStack(spacing: 8) {
                Text(selectedParameter.rawValue)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text("\(currentParameterValue, specifier: "%.2f") m")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            Divider().padding(.horizontal, 4)

            // Big control buttons row
            ZStack {
                // Minus button with tap vs hold handling
                Button(action: {
                    // Tap handled on release in gesture below
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: buttonSettings.saveViewDecrementButton.size, height: buttonSettings.saveViewDecrementButton.size)
                        Image(systemName: "minus")
                            .foregroundColor(.white)
                            .font(.system(size: buttonSettings.saveViewDecrementButton.size * 0.4, weight: .bold))
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            // On first touch-down: schedule a hold task if not already
                            if decHoldWork == nil && !isDecrementHolding {
                                let work = DispatchWorkItem {
                                    // Hold threshold passed: start repeating and mark holding
                                    isDecrementHolding = true
                                    startDecrementTimer()
                                }
                                decHoldWork = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                            }
                        }
                        .onEnded { _ in
                            // Touch up: if hold not started, treat as tap (-1)
                            if !isDecrementHolding {
                                decrement(by: 1)
                            }
                            // Cleanup
                            decHoldWork?.cancel()
                            decHoldWork = nil
                            stopDecrementTimer()
                            isDecrementHolding = false
                        }
                )
                .accessibilityLabel("Decrease \(selectedParameter.rawValue)")
                .offset(x: buttonSettings.saveViewDecrementButton.offsetX, y: buttonSettings.saveViewDecrementButton.offsetY)

                // Save (center)
                Button(action: { saveData() }) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: buttonSettings.saveViewSaveButton.size, height: buttonSettings.saveViewSaveButton.size)
                        Text("Save")
                            .foregroundColor(.white)
                            .font(.system(size: buttonSettings.saveViewSaveButton.size * 0.26, weight: .bold, design: .rounded))
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    }
                }
                .accessibilityLabel("Save point")
                .offset(x: buttonSettings.saveViewSaveButton.offsetX, y: buttonSettings.saveViewSaveButton.offsetY)

                // Plus button with tap vs hold handling
                Button(action: {
                    // Tap handled on release in gesture below
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: buttonSettings.saveViewIncrementButton.size, height: buttonSettings.saveViewIncrementButton.size)
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.system(size: buttonSettings.saveViewIncrementButton.size * 0.4, weight: .bold))
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if incHoldWork == nil && !isIncrementHolding {
                                let work = DispatchWorkItem {
                                    isIncrementHolding = true
                                    startIncrementTimer()
                                }
                                incHoldWork = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                            }
                        }
                        .onEnded { _ in
                            if !isIncrementHolding {
                                increment(by: 1)
                            }
                            incHoldWork?.cancel()
                            incHoldWork = nil
                            stopIncrementTimer()
                            isIncrementHolding = false
                        }
                )
                .accessibilityLabel("Increase \(selectedParameter.rawValue)")
                .offset(x: buttonSettings.saveViewIncrementButton.offsetX, y: buttonSettings.saveViewIncrementButton.offsetY)

                // Cycle parameter (make same size as Save)
                Button(action: { cycleParameter() }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: buttonSettings.saveViewCycleButton.size, height: buttonSettings.saveViewCycleButton.size)
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .foregroundColor(.white)
                            .font(.system(size: buttonSettings.saveViewCycleButton.size * 0.4, weight: .bold))
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    }
                }
                .accessibilityLabel("Cycle parameter")
                .offset(x: buttonSettings.saveViewCycleButton.offsetX, y: buttonSettings.saveViewCycleButton.offsetY)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .onDisappear {
            // Safety: stop timers and cancel pending holds if view goes away
            stopIncrementTimer()
            stopDecrementTimer()
            incHoldWork?.cancel(); incHoldWork = nil
            decHoldWork?.cancel(); decHoldWork = nil
            isIncrementHolding = false
            isDecrementHolding = false
        }
    }
    
    // Returns the value for the currently selected parameter.
    private var currentParameterValue: Double {
        switch selectedParameter {
        case .depth: return depth
        case .left: return left
        case .right: return right
        case .up: return up
        case .down: return down
        }
    }

    // Helpers to change by an arbitrary step (used by tap and timers)
    private func increment(by step: Double) {
        switch selectedParameter {
        case .depth: depth += step
        case .left: left += step
        case .right: right += step
        case .up: up += step
        case .down: down += step
        }
    }

    private func decrement(by step: Double) {
        switch selectedParameter {
        case .depth: depth = max(0, depth - step)
        case .left: left = max(0, left - step)
        case .right: right = max(0, right - step)
        case .up: up = max(0, up - step)
        case .down: down = max(0, down - step)
        }
    }

    // Auto-repeat management (fires only after hold threshold)
    private func startIncrementTimer() {
        stopIncrementTimer()
        incrementTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            increment(by: 10)
        }
        RunLoop.current.add(incrementTimer!, forMode: .common)
    }

    private func stopIncrementTimer() {
        incrementTimer?.invalidate()
        incrementTimer = nil
    }

    private func startDecrementTimer() {
        stopDecrementTimer()
        decrementTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            decrement(by: 10)
        }
        RunLoop.current.add(decrementTimer!, forMode: .common)
    }

    private func stopDecrementTimer() {
        decrementTimer?.invalidate()
        decrementTimer = nil
    }
    
    // Cycles to the next parameter (Depth → Left → Right → Up → Down → Depth …).
    private func cycleParameter() {
        let allParameters = ParameterType.allCases
        if let currentIndex = allParameters.firstIndex(of: selectedParameter) {
            let nextIndex = (currentIndex + 1) % allParameters.count
            selectedParameter = allParameters[nextIndex]
        }
    }
    
    // Save data using the updated SavedData that includes all parameters.
    private func saveData() {
        let savedData = SavedData(
            recordNumber: pointNumber,
            distance: distance,
            heading: magnetometer.roundedMagneticHeading ?? 0,
            depth: depth,
            left: left,
            right: right,
            up: up,
            down: down,
            rtype: "manual"
        )
        DataManager.save(savedData: savedData)
        pointNumber += 1
        DataManager.savePointNumber(pointNumber)
                
        presentationMode.wrappedValue.dismiss()
    }
}
