import SwiftUI
import CoreGraphics
import CoreMotion
import UIKit

struct NorthOrientedMapView: View {
    @State private var mapData: [SavedData] = []
    
    // Persistent state variables
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Angle = .zero
    @State private var offset: CGSize = .zero
    
    // Gesture state variables
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    
    @State private var initialFitDone = false
    private let markerSize: CGFloat = 10.0
    // Conversion factor to scale your measured distances (assumed in meters) to screen points.
    private let conversionFactor: CGFloat = 20.0

    @StateObject private var motionDetector = MotionDetector()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                
                ZStack {
                    if mapData.isEmpty {
                        Text("No manual data available to draw the cave walls")
                            .font(.headline)
                            .foregroundColor(.gray)
                    } else {
                        drawCaveProfile(in: geometry.size)
                    }
                }
                .scaleEffect(scale * gestureScale, anchor: .center)
                .rotationEffect(rotation + gestureRotation)
                .offset(x: offset.width + gestureOffset.width,
                        y: offset.height + gestureOffset.height)
                .onAppear {
                    loadMapData()
                    DispatchQueue.main.async {
                        if !initialFitDone && !mapData.isEmpty {
                            fitMap(in: geometry.size)
                            initialFitDone = true
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(combinedGesture())
            // Overlay the compass in the top-right.
            .overlay(
                CompassView(mapRotation: rotation + gestureRotation)
                    .padding(10),
                alignment: .topTrailing
            )
            // Overlay export share buttons at the bottom left.
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 20) {
                    Button(action: { shareData() }) {
                        ZStack {
                            Circle().fill(Color.purple).frame(width: 50, height: 50)
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                    }
              
                        
                    Button(action: { shareTherionData() }) {
                        ZStack {
                            Circle().fill(Color.gray).frame(width: 50, height: 50)
                            Image(systemName: "doc.text")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Map Viewer")
        .onAppear {
            motionDetector.doubleTapDetected = {
                self.presentationMode.wrappedValue.dismiss()
            }
            motionDetector.startDetection()
        }
        .onDisappear {
            motionDetector.stopDetection()
        }
    }
    
    // MARK: - Gesture Handling
    
    private func combinedGesture() -> some Gesture {
        let magnifyGesture = MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                let totalScale = self.scale * value
                let limitedScale = max(0.1, min(totalScale, 10.0))
                state = limitedScale / self.scale
            }
            .onEnded { value in
                let totalScale = self.scale * value
                self.scale = max(0.1, min(totalScale, 10.0))
            }
        let rotationGesture = RotationGesture()
            .updating($gestureRotation) { value, state, _ in
                state = value
            }
            .onEnded { value in
                self.rotation += value
            }
        let dragGesture = DragGesture()
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                self.offset.width += value.translation.width
                self.offset.height += value.translation.height
            }
        return SimultaneousGesture(
            SimultaneousGesture(magnifyGesture, rotationGesture),
            dragGesture
        )
    }
    
    // MARK: - Cave Drawing
    
    
    /// Draws the cave profile as a closed polygon (built from left/right offsets)
    /// and overlays the center guide line with markers, labels, and correctly-joined walls.
    private func drawCaveProfile(in size: CGSize) -> some View {
        // 1) pull out & sort your manual points
        let manualData = mapData
            .filter { $0.rtype == "manual" }
            .sorted { $0.recordNumber < $1.recordNumber }

        // Need at least two points for a polygon
        guard manualData.count >= 2 else {
            return AnyView(Text("Need at least two manual points to draw profile")
                .foregroundColor(.gray))
        }

        // 2) compute centre-line positions & angles
        let center = CGPoint(x: size.width/2, y: size.height/2)
        let (guidePositions, guideAngles, segmentDistances) =
            createGuideForManualPoints(center: center, manualData: manualData)

        let count = guidePositions.count
        var leftWallPoints: [CGPoint] = []
        var rightWallPoints: [CGPoint] = []

        // 3) build left/right wall points with miter joins
        for i in 0..<count {
            let gp = guidePositions[i]
            let leftD  = CGFloat(manualData[i].left)  * conversionFactor
            let rightD = CGFloat(manualData[i].right) * conversionFactor

            if i == 0 || i == count - 1 {
                // endpoints: simple perpendicular offset
                let angle = guideAngles[i]
                let leftOffset  = CGPoint(x: -leftD * sin(angle), y: -leftD * cos(angle))
                let rightOffset = CGPoint(x:  rightD * sin(angle), y:  rightD * cos(angle))
                leftWallPoints.append(CGPoint(x: gp.x + leftOffset.x,
                                             y: gp.y + leftOffset.y))
                rightWallPoints.append(CGPoint(x: gp.x + rightOffset.x,
                                              y: gp.y + rightOffset.y))
            } else {
                // interior: miter-join along bisector of angle change

                // incoming/outgoing bearings
                let angleIn  = guideAngles[i]
                let angleOut = guideAngles[i+1]

                // LEFT‐side normals (unit vectors)
                let nInL  = CGPoint(x: -sin(angleIn),  y: -cos(angleIn))
                let nOutL = CGPoint(x: -sin(angleOut), y: -cos(angleOut))
                let sumL  = CGPoint(x: nInL.x + nOutL.x, y: nInL.y + nOutL.y)
                let dotL  = sumL.x * nInL.x + sumL.y * nInL.y
                let miterL = CGPoint(x: sumL.x * (leftD  / dotL),
                                     y: sumL.y * (leftD  / dotL))
                leftWallPoints.append(CGPoint(x: gp.x + miterL.x,
                                             y: gp.y + miterL.y))

                // RIGHT‐side normals
                let nInR  = CGPoint(x:  sin(angleIn), y:  cos(angleIn))
                let nOutR = CGPoint(x:  sin(angleOut), y:  cos(angleOut))
                let sumR  = CGPoint(x: nInR.x + nOutR.x, y: nInR.y + nOutR.y)
                let dotR  = sumR.x * nInR.x + sumR.y * nInR.y
                let miterR = CGPoint(x: sumR.x * (rightD / dotR),
                                     y: sumR.y * (rightD / dotR))
                rightWallPoints.append(CGPoint(x: gp.x + miterR.x,
                                              y: gp.y + miterR.y))
            }
        }

        // 4) build the cave polygon path
        var cavePolygon = Path()
        if let start = leftWallPoints.first {
            cavePolygon.move(to: start)
            for pt in leftWallPoints.dropFirst() { cavePolygon.addLine(to: pt) }
            for pt in rightWallPoints.reversed() { cavePolygon.addLine(to: pt) }
            cavePolygon.closeSubpath()
        }

        // 5) build the centre-line path
        var guidePath = Path()
        if let start = guidePositions.first {
            guidePath.move(to: start)
            for pt in guidePositions.dropFirst() { guidePath.addLine(to: pt) }
        }

        // 6) render everything
        return AnyView(
            ZStack {
                // cave walls
                cavePolygon.fill(Color.brown.opacity(0.5))
                cavePolygon.stroke(Color.brown, lineWidth: 2)

                // centre line
                guidePath.stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [5]))

                // start/end markers
                Circle().fill(Color.green)
                    .frame(width: markerSize, height: markerSize)
                    .position(guidePositions.first!)
                Circle().fill(Color.red)
                    .frame(width: markerSize, height: markerSize)
                    .position(guidePositions.last!)

                // depth & shot labels at each station
                ForEach(0..<guidePositions.count, id: \.self) { i in
                    let depth    = manualData[i].depth
                    let segmentD = segmentDistances[i]
                    Text(String(format: "Depth: %.1f m\nShot: %.1f m", depth, segmentD))
                        .font(.system(size: 12))
                        .padding(4)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(5)
                        .multilineTextAlignment(.center)
                        .position(guidePositions[i])
                }
            }
        )
    }


    
    
    
    /// Computes guide (center) positions and heading angles for manual points only.
    /// Iterates only your sorted manualData,
    /// computing (1) the delta‐distance for each shot and
    /// (2) the moving position + heading.
    private func createGuideForManualPoints(
        center: CGPoint,
        manualData: [SavedData]
    ) -> (positions: [CGPoint], angles: [Double], segmentDistances: [Double]) {
        var positions: [CGPoint] = []
        var angles:    [Double]  = []
        var segmentDistances: [Double] = []
        var currentPosition = center
        var previousDistance: Double = 0.0

        for data in manualData {
            let angle = data.heading.toMathRadiansFromHeading()
            angles.append(angle)

            // compute shot length between this station and the last
            let segmentDist = data.distance - previousDistance
            segmentDistances.append(segmentDist)
            previousDistance = data.distance

            // move out along this bearing by segmentDist
            let dx = conversionFactor * CGFloat(segmentDist * cos(angle))
            let dy = conversionFactor * CGFloat(segmentDist * sin(angle))
            currentPosition.x += dx
            currentPosition.y -= dy

            positions.append(currentPosition)
        }

        return (positions, angles, segmentDistances)
    }

    
    private func loadMapData() {
        mapData = DataManager.loadSavedData()
    }
    
    private func fitMap(in size: CGSize) {
        guard !mapData.isEmpty else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let (guidePath, _, _) = createFullGuidePath(center: center)
        let boundingRect = guidePath.boundingRect
        
        let widthRatio = size.width / boundingRect.width
        let heightRatio = size.height / boundingRect.height
        let fitScale = min(widthRatio, heightRatio) * 0.9
        
        scale = fitScale
        offset = CGSize(
            width: (center.x - boundingRect.midX) * fitScale,
            height: (center.y - boundingRect.midY) * fitScale
        )
    }
    
    /// Creates a full guide (center) path for all data (used for fitting the view).
    private func createFullGuidePath(center: CGPoint)
        -> (path: Path, positions: [CGPoint], angles: [Double]) {
        var path = Path()
        var positions: [CGPoint] = []
        var angles: [Double] = []
        var currentPosition = center
        var previousDistance: Double = 0.0

        let manualData = mapData
            .filter { $0.rtype == "manual" }
            .sorted { $0.recordNumber < $1.recordNumber }

        path.move(to: currentPosition)
        for data in manualData {
            let angle = data.heading.toMathRadiansFromHeading()
            angles.append(angle)

            let segmentDist = data.distance - previousDistance
            previousDistance = data.distance

            let dx = conversionFactor * CGFloat(segmentDist * cos(angle))
            let dy = conversionFactor * CGFloat(segmentDist * sin(angle))
            currentPosition.x += dx
            currentPosition.y -= dy

            positions.append(currentPosition)
            path.addLine(to: currentPosition)
        }
        return (path, positions, angles)
    }

    
    // MARK: - Export Data Functions
    
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
    
    private func shareTherionData() {
        let manualDataArray = DataManager.loadSavedData()
            .filter { $0.rtype == "manual" }
            .sorted { $0.recordNumber < $1.recordNumber }
        guard manualDataArray.count >= 2 else {
            print("Not enough manual data available to share in Therion format.")
            return
        }
        
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
        
        for i in 0..<(manualDataArray.count - 1) {
            let start = manualDataArray[i]
            let end = manualDataArray[i + 1]
            
            let from = i
            let to = i + 1
            
            let length = end.distance - start.distance
            let compass = end.heading
            let depthChange = end.depth - start.depth
            let leftVal = end.left
            let rightVal = end.right
            let upVal = end.up
            let downVal = end.down
            
            let line = "\(from) \(to) \(String(format: "%.1f", length)) \(Int(compass)) \(String(format: "%.1f", depthChange)) \(String(format: "%.1f", leftVal)) \(String(format: "%.1f", rightVal)) \(String(format: "%.1f", upVal)) \(String(format: "%.1f", downVal))\n"
            therionText += line
        }
        
        therionText += "endcenterline\nendsurvey"
        
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

private extension Double {
    func toMathRadiansFromHeading() -> Double {
        return (90.0 - self) * .pi / 180.0
    }
}

struct CompassView: View {
    let mapRotation: Angle

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 50, height: 50)
                .shadow(radius: 3)
            Image(systemName: "location.north.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .foregroundColor(.red)
                // Remove the negative sign so the arrow rotates with the map.
                .rotationEffect(mapRotation)
        }
    }
}


class MotionDetector: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastTapTime: Date?
    private var tapCount = 0
    private let accelerationThreshold = 4.0
    private let tapTimeWindow = 0.3
    
    var doubleTapDetected: (() -> Void)?
    
    func startDetection() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.01
            motionManager.startAccelerometerUpdates(to: OperationQueue()) { (data, error) in
                guard let data = data else { return }
                self.processAccelerationData(data.acceleration)
            }
        }
    }
    
    func stopDetection() {
        motionManager.stopAccelerometerUpdates()
    }
    
    private func processAccelerationData(_ acceleration: CMAcceleration) {
        let totalAcceleration = sqrt(pow(acceleration.x, 2) +
                                     pow(acceleration.y, 2) +
                                     pow(acceleration.z, 2))
        if totalAcceleration > accelerationThreshold {
            DispatchQueue.main.async {
                let now = Date()
                if let lastTapTime = self.lastTapTime {
                    let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
                    if timeSinceLastTap < self.tapTimeWindow {
                        self.tapCount += 1
                    } else {
                        self.tapCount = 1
                    }
                } else {
                    self.tapCount = 1
                }
                self.lastTapTime = now
                if self.tapCount >= 3 {
                    self.tapCount = 0
                    self.doubleTapDetected?()
                }
            }
        }
    }
}
