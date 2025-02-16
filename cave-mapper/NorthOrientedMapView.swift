import SwiftUI
import CoreGraphics
import CoreMotion

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
    
    // Combine magnification, rotation, and drag gestures.
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
    
    /// Draws the cave profile as a closed polygon (built from left/right offsets)
    /// and overlays the center guide line with markers and labels.
    private func drawCaveProfile(in size: CGSize) -> some View {
        let manualData = mapData.filter { $0.rtype == "manual" }
        guard !manualData.isEmpty else {
            return AnyView(Text("No manual data available").foregroundColor(.gray))
        }
        
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let (guidePositions, guideAngles) = createGuideForManualPoints(center: center)
        let count = min(guidePositions.count, manualData.count)
        
        var leftWallPoints: [CGPoint] = []
        var rightWallPoints: [CGPoint] = []
        for i in 0..<count {
            let angle = guideAngles[i]
            // Multiply distances by conversionFactor to increase the size.
            let leftDistance = CGFloat(manualData[i].left) * conversionFactor
            let rightDistance = CGFloat(manualData[i].right) * conversionFactor
            let leftOffset = CGPoint(x: -leftDistance * CGFloat(sin(angle)),
                                     y: -leftDistance * CGFloat(cos(angle)))
            let rightOffset = CGPoint(x: rightDistance * CGFloat(sin(angle)),
                                      y: rightDistance * CGFloat(cos(angle)))
            let leftPoint = CGPoint(x: guidePositions[i].x + leftOffset.x,
                                    y: guidePositions[i].y + leftOffset.y)
            let rightPoint = CGPoint(x: guidePositions[i].x + rightOffset.x,
                                     y: guidePositions[i].y + rightOffset.y)
            leftWallPoints.append(leftPoint)
            rightWallPoints.append(rightPoint)
        }
        
        var cavePolygon = Path()
        if let first = leftWallPoints.first {
            cavePolygon.move(to: first)
            for pt in leftWallPoints.dropFirst() {
                cavePolygon.addLine(to: pt)
            }
            for pt in rightWallPoints.reversed() {
                cavePolygon.addLine(to: pt)
            }
            cavePolygon.closeSubpath()
        }
        
        // Create guide (center) path.
        var guidePath = Path()
        if let firstGuide = guidePositions.first {
            guidePath.move(to: firstGuide)
            for pt in guidePositions.dropFirst() {
                guidePath.addLine(to: pt)
            }
        }
        
        return AnyView(
            ZStack {
                cavePolygon.fill(Color.brown.opacity(0.5))
                cavePolygon.stroke(Color.brown, lineWidth: 2)
                
                guidePath.stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [5]))
                
                if let firstGuide = guidePositions.first {
                    Circle().fill(Color.green)
                        .frame(width: markerSize, height: markerSize)
                        .position(firstGuide)
                    Text("Start")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .position(x: firstGuide.x, y: firstGuide.y - 15)
                }
                if let lastGuide = guidePositions.last {
                    Circle().fill(Color.red)
                        .frame(width: markerSize, height: markerSize)
                        .position(lastGuide)
                    Text("End")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .position(x: lastGuide.x, y: lastGuide.y - 15)
                }
                
                ForEach(0..<count, id: \.self) { idx in
                    let depth = manualData[idx].depth
                    let distance = manualData[idx].distance
                    let guidePoint = guidePositions[idx]
                    Text(String(format: "Depth: %.1f m\nDist: %.1f m", depth, distance))
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                        .padding(4)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(5)
                        .multilineTextAlignment(.center)
                        .position(guidePoint)
                }
            }
        )
    }
    
    /// Computes guide (center) positions and heading angles for manual points only.
    private func createGuideForManualPoints(center: CGPoint) -> (positions: [CGPoint], angles: [Double]) {
        var positions: [CGPoint] = []
        var angles: [Double] = []
        var currentPosition = center
        for data in mapData {
            if data.rtype == "manual" {
                let angle = data.heading.toMathRadiansFromHeading()
                angles.append(angle)
                // Multiply distance by conversionFactor.
                let deltaX = conversionFactor * CGFloat(data.distance * cos(angle))
                let deltaY = conversionFactor * CGFloat(data.distance * sin(angle))
                currentPosition.x += deltaX
                currentPosition.y -= deltaY
                positions.append(currentPosition)
            }
        }
        return (positions, angles)
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
    private func createFullGuidePath(center: CGPoint) -> (path: Path, positions: [CGPoint], angles: [Double]) {
        var path = Path()
        var positions: [CGPoint] = []
        var angles: [Double] = []
        var currentPosition = center
        path.move(to: currentPosition)
        for data in mapData {
            let angle = data.heading.toMathRadiansFromHeading()
            angles.append(angle)
            let deltaX = conversionFactor * CGFloat(data.distance * cos(angle))
            let deltaY = conversionFactor * CGFloat(data.distance * sin(angle))
            currentPosition.x += deltaX
            currentPosition.y -= deltaY
            positions.append(currentPosition)
            path.addLine(to: currentPosition)
        }
        return (path, positions, angles)
    }
}

private extension Double {
    func toMathRadiansFromHeading() -> Double {
        return (90.0 - self) * .pi / 180.0
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
