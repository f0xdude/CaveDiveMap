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
    @State private var depth: Double = DataManager.loadLastSavedDepth() // Initialize with last saved depth
    @State private var distance: Double = DataManager.loadLastSavedDistance() // Initialize with last saved distance
    
    // New state variables for the additional parameters.
    @State private var left: Double = 0.0
    @State private var right: Double = 0.0
    @State private var up: Double = 0.0
    @State private var down: Double = 0.0
    
    // Track which parameter is currently selected.
    @State private var selectedParameter: ParameterType = .depth
    
    // Used to detect a long press on the back button.
    @GestureState private var isLongPressing = false
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Text("Point Number: \(pointNumber)")
                .font(.title2)
                .padding()
            
            Text("Distance: \(distance, specifier: "%.2f") meters")
                .font(.title2)
            Text("Heading: \(magnetometer.currentHeading?.magneticHeading ?? 0, specifier: "%.2f")°")
                .font(.title2)

            
            // Display the currently selected parameter and its value.
            Text("\(selectedParameter.rawValue): \(currentParameterValue, specifier: "%.2f") m")
                .font(.title2)
                .padding()
            
            ZStack {
                // Minus button: decreases the value for the current parameter.
                Button(action: { decrementSelectedValue() }) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 50, height: 50)
                        Image(systemName: "minus")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
                .offset(x: -70, y: 140)
                
                // Save button.
                Button(action: { saveData() }) {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 70, height: 70)
                        Text("Save")
                            .foregroundColor(.white)
                            .bold()
                    }
                }
                .offset(y: 200)
                
                // Plus button: increases the value for the current parameter.
                Button(action: { incrementSelectedValue() }) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 50, height: 50)
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
                .offset(x: 70, y: 140)
                
                // Back button: tap cycles parameters; long press (3 sec) dismisses.
                Button(action: { cycleParameter() }) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 50, height: 50)
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 3.0)
                        .updating($isLongPressing) { currentState, gestureState, transaction in
                            gestureState = currentState
                        }
                        .onEnded { _ in
                            presentationMode.wrappedValue.dismiss()
                        }
                )
                .offset(x: 120, y: 200)
            }
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
    
    // Increases the value for the currently selected parameter.
    private func incrementSelectedValue() {
        switch selectedParameter {
        case .depth: depth += 1
        case .left: left += 1
        case .right: right += 1
        case .up: up += 1
        case .down: down += 1
        }
    }
    
    // Decreases the value for the currently selected parameter.
    private func decrementSelectedValue() {
        switch selectedParameter {
        case .depth: depth -= 1
        case .left: left -= 1
        case .right: right -= 1
        case .up: up -= 1
        case .down: down -= 1
        }
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
        DataManager.savePointNumber(pointNumber)
        
        pointNumber += 1
        
        presentationMode.wrappedValue.dismiss()
    }
}
