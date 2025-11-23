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
    @State private var isEditingWalls = false
    @State private var customWallPoints: [CGPoint] = []
    

    
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
    
    
    
    /// Find the index of the segment in `points` nearest to `location`
    private func findClosestSegmentIndex(points: [CGPoint], location: CGPoint) -> Int {
        guard points.count > 1 else { return 0 }
        var bestIndex = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            let d = distanceToSegment(pt: location, a: points[i], b: points[i+1])
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        return bestIndex
    }

    /// Perpendicular distance from point `pt` to segment `ab`
    private func distanceToSegment(pt: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y
        let wx = pt.x - a.x, wy = pt.y - a.y
        let c1 = vx*wx + vy*wy
        if c1 <= 0 { return hypot(pt.x - a.x, pt.y - a.y) }
        let c2 = vx*vx + vy*vy
        if c2 <= c1 { return hypot(pt.x - b.x, pt.y - b.y) }
        let t = c1 / c2
        let proj = CGPoint(x: a.x + t*vx, y: a.y + t*vy)
        return hypot(pt.x - proj.x, pt.y - proj.y)
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
        // 1) sort your manual points
        let manualData = mapData
            .filter { $0.rtype == "manual" }
            .sorted { $0.recordNumber < $1.recordNumber }

        guard manualData.count >= 2 else {
            return AnyView(
                Text("Need at least two manual points to draw profile")
                    .foregroundColor(.gray)
            )
        }

        // 2) compute centre-line
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let (guidePos, guideAng, segDist) =
            createGuideForManualPoints(center: center, manualData: manualData)

        // 3) build miter-joined wall points
        let count = guidePos.count
        var leftPts: [CGPoint] = []
        var rightPts: [CGPoint] = []

        for i in 0 ..< count {
            let gp     = guidePos[i]
            let leftD  = CGFloat(manualData[i].left)  * conversionFactor
            let rightD = CGFloat(manualData[i].right) * conversionFactor

            if i == 0 || i == count - 1 {
                // endpoints: perpendicular offset
                let θ    = guideAng[i]
                let lOff = CGPoint(x: -leftD * sin(θ),
                                   y: -leftD * cos(θ))
                let rOff = CGPoint(x:  rightD * sin(θ),
                                   y:  rightD * cos(θ))
                leftPts.append(
                    gp.applying(
                        CGAffineTransform(translationX: lOff.x,
                                          y: lOff.y)
                    )
                )
                rightPts.append(
                    gp.applying(
                        CGAffineTransform(translationX: rOff.x,
                                          y: rOff.y)
                    )
                )
            } else {
                // interior: miter‐join
                let θ1    = guideAng[i]
                let θ2    = guideAng[i + 1]

                // left normals
                let n1L   = CGVector(dx: -sin(θ1), dy: -cos(θ1))
                let n2L   = CGVector(dx: -sin(θ2), dy: -cos(θ2))
                let sumL  = CGVector(dx: n1L.dx + n2L.dx,
                                     dy: n1L.dy + n2L.dy)
                let dotL  = sumL.dx * n1L.dx + sumL.dy * n1L.dy
                let mL    = CGPoint(x: sumL.dx * (leftD  / dotL),
                                    y: sumL.dy * (leftD  / dotL))
                leftPts.append(CGPoint(x: gp.x + mL.x,
                                       y: gp.y + mL.y))

                // right normals
                let n1R   = CGVector(dx:  sin(θ1), dy:  cos(θ1))
                let n2R   = CGVector(dx:  sin(θ2), dy:  cos(θ2))
                let sumR  = CGVector(dx: n1R.dx + n2R.dx,
                                     dy: n1R.dy + n2R.dy)
                let dotR  = sumR.dx * n1R.dx + sumR.dy * n1R.dy
                let mR    = CGPoint(x: sumR.dx * (rightD / dotR),
                                    y: sumR.dy * (rightD / dotR))
                rightPts.append(CGPoint(x: gp.x + mR.x,
                                        y: gp.y + mR.y))
            }
        }

        // 4) assemble the computed polygon
        let computedPolygon = leftPts + rightPts.reversed()

        // 5) sync edit-mode buffer
        DispatchQueue.main.async {
            if isEditingWalls && customWallPoints.isEmpty {
                customWallPoints = computedPolygon
            }
            if !isEditingWalls {
                customWallPoints.removeAll()
            }
        }

        // which polygon to draw?
        let wallPts = isEditingWalls ? customWallPoints : computedPolygon

        // 6) build the wall path
        var wallPath = Path()
        if let first = wallPts.first {
            wallPath.move(to: first)
            for pt in wallPts.dropFirst() {
                wallPath.addLine(to: pt)
            }
            wallPath.closeSubpath()
        }

        // 7) build the centre‐line
        var guidePath = Path()
        guidePath.move(to: guidePos.first!)
        for pt in guidePos.dropFirst() {
            guidePath.addLine(to: pt)
        }

        // tweak this to require “close enough” taps
        let insertionThreshold: CGFloat = 30.0

        return AnyView(
            ZStack {
                // — walls —
                wallPath.fill(Color.brown.opacity(0.5))
                wallPath.stroke(Color.brown, lineWidth: 2)

                // — centre line —
                guidePath.stroke(
                    Color.blue,
                    style: StrokeStyle(lineWidth: 1, dash: [5])
                )

                // — start/end markers —
                Circle()
                    .fill(Color.green)
                    .frame(width: markerSize, height: markerSize)
                    .position(guidePos.first!)
                Circle()
                    .fill(Color.red)
                    .frame(width: markerSize, height: markerSize)
                    .position(guidePos.last!)

                // — labels —
                ForEach(0 ..< guidePos.count, id: \.self) { i in
                    Text(
                        String(
                            format: "Depth: %.1f m\nShot: %.1f m",
                            manualData[i].depth,
                            segDist[i]
                        )
                    )
                    .font(.system(size: 12))
                    .padding(4)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(5)
                    .multilineTextAlignment(.center)
                    .position(guidePos[i])
                }

                // — EDIT MODE OVERLAYS —
                if isEditingWalls {
                    // long-press + drag to insert new point
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onEnded { seq in
                                    if case .second(true, let drag?) = seq {
                                        let loc = drag.location
                                        let idx = findClosestSegmentIndex(
                                            points: wallPts,
                                            location: loc
                                        )
                                        // only insert if you really tapped near it
                                        let dist = distanceToSegment(
                                            pt: loc,
                                            a: wallPts[idx],
                                            b: wallPts[idx + 1]
                                        )
                                        if dist < insertionThreshold {
                                            customWallPoints.insert(loc, at: idx + 1)
                                        }
                                    }
                                }
                        )

                    // draggable handles
                    ForEach(wallPts.indices, id: \.self) { i in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.black))
                            .position(wallPts[i])
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        customWallPoints[i] = value.location
                                    }
                            )
                    }
                }
            }
            // Edit button
            .overlay(
                Button(action: { isEditingWalls.toggle() }) {
                    Text(isEditingWalls ? "Done Editing" : "Edit Walls")
                        .padding(8)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(5)
                }
                .padding(),
                alignment: .topLeading
            )
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
