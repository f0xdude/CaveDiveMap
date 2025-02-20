import SwiftUI
import CoreBluetooth

// MARK: - BLEManager with Filtering and Reconnect

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var receivedHex: String = ""
    
    // Decoded sensor values (if needed)
    @Published var decodedTemperature: Double = 0.0
    @Published var decodedDepth: Double = 0.0
    
    // Reference to the connected peripheral.
    @Published var connectedPeripheral: CBPeripheral?
    
    var centralManager: CBCentralManager!
    
    // Depth scaling factor (adjust as needed)
    let depthScalingFactor: Double = 0.00647
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - CBCentralManagerDelegate Methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth is on. Scanning for iceFish devices..."
            // Start scanning for all peripherals. We'll filter by name later.
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        default:
            statusMessage = "Bluetooth unavailable: \(central.state.rawValue)"
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // Filter for devices named "iceFish"
        if let name = peripheral.name, name == "iceFish" {
            // Only add if not already discovered.
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                DispatchQueue.main.async {
                    self.discoveredPeripherals.append(peripheral)
                    self.statusMessage = "Found iceFish: \(name)"
                }
            }
        }
    }
    
    // Connect to the selected peripheral.
    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        statusMessage = "Connecting to iceFish..."
        peripheral.delegate = self
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusMessage = "Connected to iceFish"
        // Discover services (or filter to specific ones if known)
        peripheral.discoverServices(nil)
    }
    
    // Called if the connection fails.
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
    }
    
    // This delegate is called when the peripheral disconnects.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "Disconnected from iceFish. Reconnecting..."
        // Automatically attempt to reconnect after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.centralManager.connect(peripheral, options: nil)
        }
    }
    
    // MARK: - CBPeripheralDelegate Methods
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            statusMessage = "Error discovering services: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            statusMessage = "Discovered service: \(service.uuid)"
            // Discover all characteristics for each service.
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            statusMessage = "Error discovering characteristics: \(error.localizedDescription)"
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            statusMessage = "Error updating value: \(error.localizedDescription)"
            return
        }
        
        // Ensure we have at least 8 bytes.
        guard let data = characteristic.value, data.count >= 8 else { return }
        
        // Convert data to a hex string for debugging.
        let hexString = data.map { String(format: "%02X", $0) }.joined()
        print("BLEManager receivedHex:", hexString)
        
        DispatchQueue.main.async {
            self.receivedHex = hexString
            self.statusMessage = "Data received"
            
            // Check that the depth measurement field starts with the expected identifier 0x04.
            // Expected depth bytes: [0x04, highByte, lowByte] at indices 5, 6, and 7.
            if data[5] == 0x04 {
                // Combine bytes 6 and 7 to form a 16-bit integer (big-endian).
                let rawDepth = (UInt16(data[6]) << 8) | UInt16(data[7])
                // Convert raw depth to meters using a scaling factor of 0.01.
                self.decodedDepth = Double(rawDepth) / 100.0
                print("Decoded depth: \(self.decodedDepth) meters")
            } else {
                print("Unexpected identifier at byte 5: \(data[5]).")
            }
        }
    }

    
    // Disconnect manually.
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            isConnected = false
            statusMessage = "Disconnected"
        }
    }
    
    // Restart scanning.
    func startScan() {
        discoveredPeripherals.removeAll()
        if centralManager.state == .poweredOn {
            statusMessage = "Scanning for iceFish devices..."
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
}
