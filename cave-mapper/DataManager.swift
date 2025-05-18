//
//  DataManager.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 20.11.24.
//
import Foundation

class DataManager {
    private static let pointNumberKey = "pointNumberKey"
    private static let savedDataKey = "savedDataKey"

    static func save(savedData: SavedData) {
        var savedDataArray = loadSavedData()
        savedDataArray.append(savedData)
        if let encodedData = try? JSONEncoder().encode(savedDataArray) {
            UserDefaults.standard.set(encodedData, forKey: savedDataKey)
        }
    }

    static func loadSavedData() -> [SavedData] {
        if let savedData = UserDefaults.standard.data(forKey: savedDataKey),
           let decodedData = try? JSONDecoder().decode([SavedData].self, from: savedData) {
            return decodedData
        }
        return []
    }

    static func savePointNumber(_ pointNumber: Int) {
        UserDefaults.standard.set(pointNumber, forKey: pointNumberKey)
    }

    static func loadPointNumber() -> Int {
        return UserDefaults.standard.integer(forKey: pointNumberKey)
    }
    
    static func resetAllData() {
        UserDefaults.standard.removeObject(forKey: pointNumberKey)
        UserDefaults.standard.removeObject(forKey: savedDataKey)
        print("All data has been reset.")
    }
    
    static func loadLastSavedDepth() -> Double {
        let savedDataArray = loadSavedData()
        
        // Filter the array to include only entries where rtype is "manual"
        let manualEntries = savedDataArray.filter { $0.rtype == "manual" }
        
        // Return the depth of the last manual entry or 0.0 if none exist
        return manualEntries.last?.depth ?? 0.0
    }
    
    static func loadLastSavedDistance() -> Double {
        let savedDataArray = loadSavedData()
        return savedDataArray.last?.distance ?? 0.0
    }
    
    
    /// Walks through *all* saved `SavedData` records (via `loadSavedData()`) and emits a CSV string.
    static func exportCSV() -> String {
        let allData = loadSavedData()   // ← your existing method
        // 1) Header row
        var csv = "recordNumber,distance,heading,depth,left,right,up,down,rtype\n"
        // 2) Each line for each record
        for d in allData {
            csv += [
                "\(d.recordNumber)",
                "\(d.distance)",
                "\(d.heading)",
                "\(d.depth)",
                "\(d.left)",
                "\(d.right)",
                "\(d.up)",
                "\(d.down)",
                d.rtype
            ].joined(separator: ",")
            csv += "\n"
        }
        return csv
    }
    
    
}

// Updated SavedData struct to include new parameters.
struct SavedData: Codable {
    let recordNumber: Int
    let distance: Double
    let heading: Double
    let depth: Double
    let left: Double
    let right: Double
    let up: Double
    let down: Double
    let rtype: String
}
