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
    private static let rotationCountKey = "wheelRotationCountKey"

    // MARK: - Survey record storage
    //
    // Records live in an append-only JSON-lines file, mirrored by an in-memory
    // cache. The previous store kept the whole survey as one JSON blob in
    // UserDefaults and decoded, appended and re-encoded all of it on the main
    // thread for every wheel rotation — quadratic over a dive, on the same
    // thread that receives the magnetometer samples the distance count depends
    // on. An append costs the same at record 10 000 as at record 1.
    //
    // Main thread only, like every caller.

    private static var cache: [SavedData]?
    private static var appendHandle: FileHandle?

    private static var recordsFileURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("survey_records.jsonl")
    }

    static func save(savedData: SavedData) {
        if cache == nil { _ = loadSavedData() }
        cache?.append(savedData)   // in place: no copy of the survey per record

        guard var line = try? JSONEncoder().encode(savedData) else {
            print("❌ Could not encode survey record \(savedData.recordNumber)")
            return
        }
        line.append(0x0A)
        do {
            let handle = try openAppendHandle()
            try handle.write(contentsOf: line)
            // A station is entered by hand and cannot be re-measured after the
            // dive: force it to disk. Auto records ride the page cache, which
            // already survives an app crash.
            if savedData.rtype == "manual" {
                try handle.synchronize()
            }
        } catch {
            print("❌ Could not write survey record: \(error)")
            appendHandle = nil
        }
    }

    static func loadSavedData() -> [SavedData] {
        if let cache = cache { return cache }

        let fm = FileManager.default
        var records: [SavedData] = []

        if fm.fileExists(atPath: recordsFileURL.path) {
            records = readRecordsFile()
        } else if let legacy = UserDefaults.standard.data(forKey: savedDataKey),
                  let decoded = try? JSONDecoder().decode([SavedData].self, from: legacy) {
            // One-time migration of a survey stored by an older build. The
            // UserDefaults copy is only dropped once the file is safely written.
            records = decoded
            if writeRecordsFile(records) {
                UserDefaults.standard.removeObject(forKey: savedDataKey)
            }
        }

        cache = records
        return records
    }

    private static func openAppendHandle() throws -> FileHandle {
        if let handle = appendHandle { return handle }
        let url = recordsFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: url)
        let end = try handle.seekToEnd()
        // A crash mid-write leaves a last line with no newline. Terminate it
        // first, or the next record is glued onto the fragment and lost with it.
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data([0x0A]))
            }
            try handle.seekToEnd()
        }
        appendHandle = handle
        return handle
    }

    private static func readRecordsFile() -> [SavedData] {
        guard let data = try? Data(contentsOf: recordsFileURL) else { return [] }
        let decoder = JSONDecoder()
        var records: [SavedData] = []
        // Line by line, so a final line torn by a crash or a flat battery costs
        // that one record rather than the whole survey.
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let record = try? decoder.decode(SavedData.self, from: Data(line)) {
                records.append(record)
            }
        }
        return records
    }

    private static func writeRecordsFile(_ records: [SavedData]) -> Bool {
        let encoder = JSONEncoder()
        var blob = Data()
        for record in records {
            guard let line = try? encoder.encode(record) else { return false }
            blob.append(line)
            blob.append(0x0A)
        }
        do {
            try blob.write(to: recordsFileURL, options: .atomic)
            return true
        } catch {
            print("❌ Could not migrate survey records: \(error)")
            return false
        }
    }

    static func savePointNumber(_ pointNumber: Int) {
        UserDefaults.standard.set(pointNumber, forKey: pointNumberKey)
    }

    static func loadPointNumber() -> Int {
        return UserDefaults.standard.integer(forKey: pointNumberKey)
    }

    static func saveRotationCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: rotationCountKey)
    }

    static func loadRotationCount() -> Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: rotationCountKey) != nil {
            return defaults.integer(forKey: rotationCountKey)
        }
        // Older builds never stored the wheel count on its own — it was conflated
        // with the station counter, which also advances on every saved record.
        // Rebuild it from the last record's distance and the configured wheel
        // circumference so an in-progress survey keeps its distance across the
        // update instead of restarting from a wrong counter.
        let circumferenceCm = defaults.object(forKey: "wheelCircumference") as? Double ?? 11.78
        guard circumferenceCm > 0 else { return 0 }
        return Int((loadLastSavedDistance() * 100.0 / circumferenceCm).rounded())
    }
    
    static func resetAllData() {
        UserDefaults.standard.removeObject(forKey: pointNumberKey)
        UserDefaults.standard.removeObject(forKey: savedDataKey)
        UserDefaults.standard.removeObject(forKey: rotationCountKey)
        try? appendHandle?.close()
        appendHandle = nil
        try? FileManager.default.removeItem(at: recordsFileURL)
        cache = []
        print("All data has been reset.")
    }
    
    static func loadLastSavedDepth() -> Double {
        // Depth of the last manual entry, or 0.0 if none exist
        return loadSavedData().last(where: { $0.rtype == "manual" })?.depth ?? 0.0
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
