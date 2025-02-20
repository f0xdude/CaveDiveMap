import SwiftUI
import CoreLocation

struct ContentView: View {
    // Use one instance of the view model for the entire view.
    @StateObject private var magnetometer = MagnetometerViewModel()
    
    @State private var showCalibrationAlert = false
    @State private var showResetSuccessAlert = false
    @State private var pointNumber: Int = DataManager.loadPointNumber()
    @State private var showSettings = false // State variable for settings
    
    // New state variables for save navigation and calibration toast.
    @State private var navigateToSaveDataView = false
    @State private var showCalibrationToast = false
    
    // New state variable for showing the camera view.
    @State private var showCameraView = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content.
                VStack {
                    // Display the current compass heading.
                    if let heading = magnetometer.currentHeading {
                        VStack {
                            Text("Magnetic Heading")
                                .font(.largeTitle)
                                .monospacedDigit()
                            Text("\(heading.magneticHeading, specifier: "%.2f")°")
                                .font(.largeTitle)
                                .monospacedDigit()
                           
                            
                            Divider()
                            
                            // Show heading accuracy with a colored dot.
                            HStack {
                                Text("Accuracy: \(heading.headingAccuracy, specifier: "%.2f")")
                                    .font(.largeTitle)
                                Circle()
                                    .fill(heading.headingAccuracy < 20 ? Color.green : Color.red)
                                    .frame(width: 20, height: 20)
                            }
                        }
                    } else {
                        Text("Heading not available")
                    }
                    
                    Divider()
                    
                    // Display the calculated distance.
                    VStack(alignment: .leading) {
                        Text("Distance")
                            .font(.largeTitle)
                        Text("\(magnetometer.distanceInMeters, specifier: "%.2f") m")
                            .font(.largeTitle)
                            .monospacedDigit()
                    }
                    
                    Divider()
                    
                    Text("Datapoints collected:")
                    Text("\(pointNumber)")
                    
                    Spacer() // Push content up to leave space for the buttons at the bottom
                    
                    // Bottom buttons
                    ZStack {
                        // --- Save Button ---
                        Button(action: {
                            // If there is a heading, check its accuracy.
                            if let heading = magnetometer.currentHeading, heading.headingAccuracy > 20 {
                                // Show a calibration toast for 1 second.
                                showCalibrationToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    withAnimation {
                                        showCalibrationToast = false
                                    }
                                }
                            } else {
                                // Accuracy is good, so navigate to SaveDataView.
                                navigateToSaveDataView = true
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 70, height: 70) // Increased to 70x70
                                Image(systemName: "square.and.arrow.down.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        .padding(.bottom, 20)
                        
                        // Navigation button to show a north-oriented map.
                        NavigationLink {
                            NorthOrientedMapView()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 70, height: 70)
                                Image(systemName: "map.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        .offset(x: 130, y: 10)
                        
                        // --- Reset Button ---
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70) // Decreased to 50x50
                            Text("Reset")
                                .foregroundColor(.white)
                                .bold()
                        }
                        .onLongPressGesture(minimumDuration: 3) {
                            resetMonitoringData()
                        }
                        .offset(x: -70, y: -70)
                        .padding(.bottom, 20)
                        
                        // --- New Camera Button ---
                        Button(action: {
                            showCameraView = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 70, height: 70)
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        .offset(x: 70, y: -70)
                        .padding(.bottom, 20)
                    }
                    .padding(.bottom) // Adjust padding as needed
                }
                .toolbar {
                    // Add the settings button to the navigation bar.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                        }
                    }
                }
                // Present the settings view, passing the same magnetometer instance.
                .sheet(isPresented: $showSettings) {
                    SettingsView(viewModel: magnetometer)
                }
                .onAppear {
                    pointNumber = DataManager.loadPointNumber()
                    magnetometer.startMonitoring()
                    UIApplication.shared.isIdleTimerDisabled = true // Prevent screen from sleeping.
                }
                .onDisappear {
                    magnetometer.stopMonitoring()
                    UIApplication.shared.isIdleTimerDisabled = false // Allow screen to sleep again.
                }
                .alert(isPresented: $showCalibrationAlert) {
                    Alert(title: Text("Compass Calibration Needed"),
                          message: Text("Please move your device in a figure-eight motion to calibrate the compass."),
                          dismissButton: .default(Text("OK")))
                }
                // Alert for reset success message.
                .alert(isPresented: $showResetSuccessAlert) {
                    Alert(
                        title: Text("Success"),
                        message: Text("Data reset successfully."),
                        dismissButton: nil
                    )
                }
                .onChange(of: showResetSuccessAlert) { _, isPresented in
                    if isPresented {
                        // Dismiss the alert after 2 seconds.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.showResetSuccessAlert = false
                        }
                    }
                }
                // Save new revolution data whenever the count changes.
                .onChange(of: magnetometer.revolutions) { _, _ in
                    _ = DataManager.loadLastSavedDepth()
                    let savedData = SavedData(
                        recordNumber: pointNumber,
                        distance: magnetometer.roundedDistanceInMeters,
                        heading: magnetometer.roundedMagneticHeading ?? 0,
                        depth: 0.00,
                        left: 0.0,
                        right: 0.0,
                        up: 0.0,
                        down: 0.0,
                        rtype: "auto"
                    )
                    pointNumber += 1
                    DataManager.save(savedData: savedData)
                    DataManager.savePointNumber(pointNumber)
                }
                
                // Overlay toast for calibration message.
                if showCalibrationToast {
                    VStack {
                        Spacer()
                        Text("Move to calibrate")
                            .padding()
                            .font(.largeTitle)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeInOut, value: showCalibrationToast)
                }
            }
            // Programmatic navigation for SaveDataView.
            .navigationDestination(isPresented: $navigateToSaveDataView) {
                SaveDataView(magnetometer: magnetometer)
            }
            // Present the camera view when needed.
            .fullScreenCover(isPresented: $showCameraView) {
                CameraView(
                    pointNumber: pointNumber,
                    distance: magnetometer.distanceInMeters,
                    heading: magnetometer.currentHeading?.trueHeading ?? 0,
                    depth: 0.00
                )
            }
        }
    }

    /// Resets monitoring data and clears stored values.
    private func resetMonitoringData() {
        pointNumber = 0
        magnetometer.revolutions = 0
        magnetometer.magneticFieldHistory = []
        DataManager.resetAllData()
        showResetSuccessAlert = true // Show success message.
    }
}
