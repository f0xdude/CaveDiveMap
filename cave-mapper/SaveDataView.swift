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
            Text("Heading: \(magnetometer.currentHeading?.magneticHeading ?? 0, specifier: "%.2f")°")
            
            // Display the currently selected parameter and its value.
            Text("\(selectedParameter.rawValue): \(currentParameterValue, specifier: "%.2f") m")
                .padding()
            
            ZStack {
                // CSV share button.
                Button(action: { shareData() }) {
                    ZStack {
                        Circle().fill(Color.purple).frame(width: 50, height: 50)
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
                .offset(x: -120, y: 200)
                
                // New Therion share button.
                Button(action: { shareTherionData() }) {
                    ZStack {
                        Circle().fill(Color.gray).frame(width: 50, height: 50)
                        Image(systemName: "doc.text")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
                .offset(x: -120, y: 260)
                
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
                        Image(systemName: "arrow.backward")
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
                            // Dismiss the view after a 3-second press.
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
    
    // Shares the saved data as a CSV file.
    private func shareData() {
        let savedDataArray = DataManager.loadSavedData()
        guard !savedDataArray.isEmpty else {
            print("No data available to share.")
            return
        }
        
        var csvText = "RecordNumber,Distance,Heading,Depth,Left,Right,Up,Down,Type\n"
        for data in savedDataArray {
            csvText += "\(data.recordNumber),\(data.distance),\(data.heading),\(data.depth),\(data.left),\(data.right),\(data.up),\(data.down),\(data.rtype)\n"
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("SavedData.csv")
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write CSV file: \(error.localizedDescription)")
            return
        }
        
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    // Shares the saved data in Therion format, exporting only manual type points.
    // The "from" and "to" numbers are generated sequentially.
    private func shareTherionData() {
        // Filter to only include manual points.
        let manualDataArray = DataManager.loadSavedData()
            .filter { $0.rtype == "manual" }
            .sorted { $0.recordNumber < $1.recordNumber }
        guard manualDataArray.count >= 2 else {
            print("Not enough manual data available to share in Therion format.")
            return
        }
        
        // Build header for Therion file.
        var therionText = """
        survey sump_1 -title "Sump 1"
        centerline
        team "PaldinCaveDivingGroup"
        date 2024.2.26
        calibrate depth 0 -1
        units length depth meters
        units compass degrees
        data diving from to length compass depthchange left right up down
        extend left
        """
        
        therionText += "\n"
        
        // Generate segments between consecutive manual points using sequential numbers.
        for i in 0..<(manualDataArray.count - 1) {
            let start = manualDataArray[i]
            let end = manualDataArray[i + 1]
            
            // Use sequential numbers for from and to.
            let from = i
            let to = i + 1
            
            // Calculate segment length as difference in distance.
            let length = end.distance - start.distance
            
            // Use end point's heading as the compass value.
            let compass = end.heading
            
            // Depth change: difference in depth.
            let depthChange = end.depth - start.depth
            
            // For left, right, up, down, use the measurements from the end point.
            let leftVal = end.left
            let rightVal = end.right
            let upVal = end.up
            let downVal = end.down
            
            // Build a line in Therion format.
            let line = "\(from) \(to) \(String(format: "%.1f", length)) \(Int(compass)) \(String(format: "%.1f", depthChange)) \(String(format: "%.1f", leftVal)) \(String(format: "%.1f", rightVal)) \(String(format: "%.1f", upVal)) \(String(format: "%.1f", downVal))\n"
            therionText += line
        }
        
        therionText += "endcenterline\nendsurvey"
        
        // Save therionText to a temporary file.
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("SavedData.thr")
        
        do {
            try therionText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write Therion file: \(error.localizedDescription)")
            return
        }
        
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
}
