import SwiftUI

struct BLESonarView: View {
    @StateObject private var bleManager = BLEManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("BLE Sonar")
                .font(.largeTitle)
                .padding(.top)
            
            Text("Status: \(bleManager.statusMessage)")
                .padding()
            
            if bleManager.isConnected {
                VStack(spacing: 12) {
                    Text("Connected to: \(bleManager.connectedPeripheral?.name ?? "Unknown")")
                        .font(.headline)
                    
                    Group {
                        Text("Raw Data: \(bleManager.receivedHex)")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        
                        Text("Depth: \(bleManager.decodedDepth, specifier: "%.2f") m")
                        Text("Strength: \(bleManager.decodedStrength, specifier: "%.0f")%")
                        
                        Text("Fish Depth: \(bleManager.decodedFishDepth, specifier: "%.2f") m")
                        Text("Fish Strength: \(bleManager.decodedFishStrength, specifier: "%.0f")%")
                        
                        Text("Battery: \(bleManager.decodedBattery, specifier: "%.0f")%")
                        Text("Temp: \(bleManager.decodedTemperature, specifier: "%.1f")℃")
                    }
                    .font(.subheadline)
                    
                    Button("Disconnect") {
                        bleManager.disconnect()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                
            } else {
                Button("Start Scan") {
                    bleManager.startScan()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button(action: {
                        bleManager.connect(to: peripheral)
                    }) {
                        HStack {
                            Text(peripheral.name ?? "Unknown")
                            Spacer()
                            Text(peripheral.identifier.uuidString)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("BLE Sonar")
    }
}
