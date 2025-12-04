import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var magnetometer = MagnetometerViewModel()
    @ObservedObject private var buttonSettings = ButtonCustomizationSettings.shared
    
    @State private var showCalibrationAlert = false
    @State private var showResetSuccessAlert = false
    @State private var pointNumber: Int = DataManager.loadPointNumber()
    @State private var showSettings = false
    @State private var navigateToSaveDataView = false
    @State private var showCalibrationToast = false
    @State private var showCameraView = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    if let heading = magnetometer.currentHeading {
                        VStack {
                            Text("Magnetic Heading")
                                .font(.largeTitle)
                                .monospacedDigit()
                            Text("\(heading.magneticHeading, specifier: "%.2f")°")
                                .font(.largeTitle)
                                .monospacedDigit()
                            Divider()
                            HStack {
                                Text("Heading error: \(heading.headingAccuracy - 10, specifier: "%.2f")")
                                    .font(.largeTitle)
                                Circle()
                                    .fill(heading.headingAccuracy < 20 ? Color.green : Color.red)
                                    .frame(width: 25, height: 25)
                            }
                        }
                    } else {
                        Text("Heading not available")
                    }

                    Divider()

                    VStack(alignment: .leading) {
                        Text("Distance")
                            .font(.largeTitle)
                        Text("\(magnetometer.dynamicDistanceInMeters, specifier: "%.2f") m")
                            .font(.largeTitle)
                            .monospacedDigit()
                    }

                    Divider()

                    Text("Datapoints collected:")
                    Text("\(pointNumber)")

                    Spacer()

                    ZStack {
                        Button(action: {
                            if let heading = magnetometer.currentHeading, heading.headingAccuracy > 15 {
                                showCalibrationToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    withAnimation {
                                        showCalibrationToast = false
                                    }
                                }
                            } else {
                                navigateToSaveDataView = true
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: buttonSettings.mainSaveButton.size, height: buttonSettings.mainSaveButton.size)
                                Image(systemName: "square.and.arrow.down.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: buttonSettings.mainSaveButton.size * 0.35))
                            }
                        }
                        .offset(x: buttonSettings.mainSaveButton.offsetX, y: buttonSettings.mainSaveButton.offsetY)
                        .padding(.bottom, 20)

                        NavigationLink {
                            NorthOrientedMapView()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: buttonSettings.mainMapButton.size, height: buttonSettings.mainMapButton.size)
                                Image(systemName: "map.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: buttonSettings.mainMapButton.size * 0.35))
                            }
                        }
                        .offset(x: buttonSettings.mainMapButton.offsetX, y: buttonSettings.mainMapButton.offsetY)

                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: buttonSettings.mainResetButton.size, height: buttonSettings.mainResetButton.size)
                            Text("Reset")
                                .foregroundColor(.white)
                                .font(.system(size: buttonSettings.mainResetButton.size * 0.2, weight: .bold))
                        }
                        .onLongPressGesture(minimumDuration: 3) {
                            resetMonitoringData()
                        }
                        .offset(x: buttonSettings.mainResetButton.offsetX, y: buttonSettings.mainResetButton.offsetY)
                        .padding(.bottom, 20)

                        Button(action: {
                            showCameraView = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: buttonSettings.mainCameraButton.size, height: buttonSettings.mainCameraButton.size)
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: buttonSettings.mainCameraButton.size * 0.35))
                            }
                        }
                        .offset(x: buttonSettings.mainCameraButton.offsetX, y: buttonSettings.mainCameraButton.offsetY)
                        .padding(.bottom, 20)
                        
                        .fullScreenCover(isPresented: $showCameraView) {
                                    VisualMapper()
                                }
                    }
                    .padding(.bottom)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                        }
                    }
                }
                .sheet(isPresented: $showSettings, onDismiss: {
                    // Restart sensor updates after returning from settings
                    magnetometer.stopMonitoring()
                    magnetometer.startMonitoring()
                }) {
                    SettingsView(viewModel: magnetometer)
                }
                .onAppear {
                    pointNumber = DataManager.loadPointNumber()
                    magnetometer.startMonitoring()
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    magnetometer.stopMonitoring()
                   // UIApplication.shared.isIdleTimerDisabled = false
                }
                .alert(isPresented: $showCalibrationAlert) {
                    Alert(title: Text("Compass Calibration Needed"),
                          message: Text("Please move your device in a figure-eight motion to calibrate the compass."),
                          dismissButton: .default(Text("OK")))
                }
                .alert(isPresented: $showResetSuccessAlert) {
                    Alert(
                        title: Text("Success"),
                        message: Text("Data reset successfully."),
                        dismissButton: nil
                    )
                }
                .onChange(of: showResetSuccessAlert) { _, isPresented in
                    if isPresented {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.showResetSuccessAlert = false
                        }
                    }
                }
                .onChange(of: magnetometer.revolutionCount) { _, _ in
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
            .navigationDestination(isPresented: $navigateToSaveDataView) {
                SaveDataView(magnetometer: magnetometer)
            }
//            .fullScreenCover(isPresented: $showCameraView) {
//                CameraView(
//                    pointNumber: pointNumber,
//                    distance: magnetometer.dynamicDistanceInMeters,
//                    heading: magnetometer.currentHeading?.trueHeading ?? 0,
//                    depth: 0.00
//                )
//            }
        }
    }

    private func resetMonitoringData() {
        // 1) dump out CSV first
            exportAllDataAsCSV()
        
        pointNumber = 0
        magnetometer.revolutions = 0
        magnetometer.magneticFieldHistory = []       
        DataManager.resetAllData()
        showResetSuccessAlert = true
    }
    
    private func exportAllDataAsCSV() {
        let csv = DataManager.exportCSV()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileName = "survey_\(timestamp).csv"

        if let docs = FileManager.default
                           .urls(for: .documentDirectory, in: .userDomainMask)
                           .first
        {
            let fileURL = docs.appendingPathComponent(fileName)
            do {
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ CSV exported to \(fileURL.path)")
            } catch {
                print("❌ Error exporting CSV: \(error)")
            }
        }
    }

    
    
}
