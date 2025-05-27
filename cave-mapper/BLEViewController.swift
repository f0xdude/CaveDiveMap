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
    
    @Published var decodedStrength: Double = 0.0
    @Published var decodedFishDepth: Double = 0.0
    @Published var decodedFishStrength: Double = 0.0
    @Published var decodedBattery: Double = 0.0
    

    
    struct SonarBluetooth {
        static let ID0: UInt8 = 0x53    // 'S'
        static let ID1: UInt8 = 0x46    // 'F'
    }

    
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
        guard let data = characteristic.value, data.count >= 20 else { return }
        
        // Header + trailer check (SF … 0x55AA)
        guard data[0] == SonarBluetooth.ID0,
              data[1] == SonarBluetooth.ID1,
              data[data.count-2] == 0x55,
              data[data.count-1] == 0xAA
        else {
          print("Bad frame:", data.map { String(format: "%02X", $0) })
          return
        }
        
        // Strip out the 18-byte core packet
        let packet = Array(data[0..<18])
        // Checksum over bytes 0…16 matches byte 17
        var sum = 0
        for i in 0..<17 { sum = (sum + Int(packet[i])) & 0xFF }
        guard sum == Int(packet[17]) else {
          print("Bad checksum \(sum) != \(packet[17])")
          return
        }
        
        // MARK: – Decoding helpers
        func be(_ hi: UInt8, _ lo: UInt8) -> UInt16 {
            return (UInt16(hi) << 8) | UInt16(lo)
        }
        /// matches Java’s b2f: raw 16-bit ÷ 100.0
        func b2f(_ hi: UInt8, _ lo: UInt8) -> Double {
            return Double(be(hi, lo)) / 100.0
        }
        
        let flags = packet[4]
        let isDry = (flags & 0x08) != 0
        let ft2m: Double = 0.3048
        
        // 1) Depth: b2f → feet → meters
        let depthFeet = b2f(packet[6], packet[7])
        let depthMeters = isDry ? -0.01 : depthFeet * ft2m
        
        // 2) Bottom strength
        let strengthPct = Double(packet[8]) / 256.0 * 100.0
        
        // 3) Fish depth
        let fishFeet = b2f(packet[9], packet[10])
        let fishMeters = fishFeet * ft2m
        
        // 4) Fish strength nibble
        let fishN = Int(packet[11]) & 0x0F
        let fishStrengthPct = Double(fishN) / 16.0 * 100.0
        
        // 5) Battery nibble
        let batN = (Int(packet[11]) >> 4) & 0x0F
        let batteryPct = Double(batN) / 6.0 * 100.0
        
        // 6) Temperature: b2f → °F → °C
        let tempF = b2f(packet[12], packet[13])
        let tempC = (tempF - 32.0) * 5.0 / 9.0
        
        // Publish back on main
        DispatchQueue.main.async {
            self.receivedHex         = data.map { String(format: "%02X", $0) }.joined()
            self.statusMessage       = "Data received"
            self.decodedDepth        = depthMeters
            self.decodedStrength     = strengthPct
            self.decodedFishDepth    = fishMeters
            self.decodedFishStrength = fishStrengthPct
            self.decodedBattery      = batteryPct
            self.decodedTemperature  = tempC
            print(String(format:
                "D: %.2fm  S: %.0f%%  Fd: %.2fm  Fs: %.0f%%  Bat: %.0f%%  T: %.1f℃",
                depthMeters, strengthPct,
                fishMeters, fishStrengthPct,
                batteryPct, tempC))
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
