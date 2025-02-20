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
                Text("Connected to: \(bleManager.connectedPeripheral?.name ?? "Unknown")")
                    .font(.headline)
                
                Text("Raw Data: \(bleManager.receivedHex)")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                
                Text("Depth: \(bleManager.decodedDepth, specifier: "%.2f") m")
                    .font(.headline)
                
                Button("Disconnect") {
                    bleManager.disconnect()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
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


