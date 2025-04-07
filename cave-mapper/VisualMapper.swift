import SwiftUI
import RealityKit
import ARKit
import CoreLocation

struct VisualMapper: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        arView.debugOptions.insert(.showFeaturePoints)
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.renderOptions = [.disableMotionBlur,
                                .disableDepthOfField,
                                .disablePersonOcclusion,
                                .disableGroundingShadows,
                                .disableFaceMesh,
                                .disableHDR]

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .none
        arView.session.run(config)

        context.coordinator.setup(arView: arView)
        arView.session.delegate = context.coordinator

        let label = UILabel()
        label.textColor = .white
        label.numberOfLines = 3
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 101
        arView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: arView.topAnchor, constant: 40),
            label.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])

        let exportButton = UIButton(type: .system)
        exportButton.setTitle("Export PLY", for: .normal)
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        exportButton.layer.cornerRadius = 8
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.addTarget(context.coordinator, action: #selector(Coordinator.exportTapped), for: .touchUpInside)
        arView.addSubview(exportButton)

        NSLayoutConstraint.activate([
            exportButton.topAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.topAnchor, constant: 10),
            exportButton.trailingAnchor.constraint(equalTo: arView.trailingAnchor, constant: -20),
            exportButton.widthAnchor.constraint(equalToConstant: 100),
            exportButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("RESET", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        resetButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        resetButton.layer.cornerRadius = 35
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addTarget(context.coordinator, action: #selector(Coordinator.resetSession), for: .touchUpInside)
        arView.addSubview(resetButton)

        let stopButton = UIButton(type: .system)
        context.coordinator.stopButton = stopButton

        stopButton.setTitle("STOP", for: .normal)
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        stopButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
        stopButton.layer.cornerRadius = 35
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(context.coordinator, action: #selector(Coordinator.stopSession), for: .touchUpInside)
        arView.addSubview(stopButton)

        
        let trackingLabel = UILabel()
        trackingLabel.textColor = .white
        trackingLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        trackingLabel.translatesAutoresizingMaskIntoConstraints = false
        trackingLabel.tag = 103
        trackingLabel.text = "Tracking: --"
        arView.addSubview(trackingLabel)

        NSLayoutConstraint.activate([
            trackingLabel.topAnchor.constraint(equalTo: arView.topAnchor, constant: 160),
            trackingLabel.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])
        
        let driftLabel = UILabel()
        driftLabel.textColor = .white
        driftLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        driftLabel.translatesAutoresizingMaskIntoConstraints = false
        driftLabel.tag = 104
        driftLabel.text = "Drift: --"
        arView.addSubview(driftLabel)

        NSLayoutConstraint.activate([
            driftLabel.topAnchor.constraint(equalTo: arView.topAnchor, constant: 130),
            driftLabel.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])

        
        NSLayoutConstraint.activate([
            resetButton.trailingAnchor.constraint(equalTo: arView.centerXAnchor, constant: -40),
            resetButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            resetButton.widthAnchor.constraint(equalToConstant: 70),
            resetButton.heightAnchor.constraint(equalToConstant: 70),

            stopButton.leadingAnchor.constraint(equalTo: arView.centerXAnchor, constant: -30),
            stopButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            stopButton.widthAnchor.constraint(equalToConstant: 70),
            stopButton.heightAnchor.constraint(equalToConstant: 70)
        ])

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSessionDelegate, CLLocationManagerDelegate {
        private var arView: ARView?
        private var previousAnchor: AnchorEntity?
        private var previousPosition: SIMD3<Float>?
        private var totalDistance: Float = 0.0
        private var pathPoints: [(position: SIMD3<Float>, distance: Float, heading: Double, depth: Float, drift: Float)] = []
        private let locationManager = CLLocationManager()
        private var currentHeading: CLHeading?
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.3
        private var isSessionActive: Bool = true
        private var loopClosureEnabled: Bool = true
        var stopButton: UIButton?

        func setup(arView: ARView) {
            self.arView = arView
            UIApplication.shared.isIdleTimerDisabled = true
            locationManager.delegate = self
            locationManager.headingFilter = 1
            locationManager.startUpdatingHeading()
            locationManager.requestWhenInUseAuthorization()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            currentHeading = newHeading
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            DispatchQueue.main.async {
                self.updateTrackingStateLabel(camera.trackingState)
            }
        }

        func updateTrackingStateLabel(_ trackingState: ARCamera.TrackingState) {
            guard let arView = arView,
                  let label = arView.viewWithTag(103) as? UILabel else { return }

            var text = "Tracking: "
            var color = UIColor.white

            switch trackingState {
            case .notAvailable:
                text += "Not Available"
                color = .red
            case .normal:
                text += "Normal"
                color = .green
            case .limited(let reason):
                text += "Limited ("
                switch reason {
                case .excessiveMotion: text += "Motion"
                case .insufficientFeatures: text += "Low Features"
                case .initializing: text += "Initializing"
                case .relocalizing: text += "Relocalizing"
                @unknown default: text += "Unknown"
                }
                text += ")"
                color = .orange
            }

            label.text = text
            label.textColor = color
        }

        
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            UIApplication.shared.isIdleTimerDisabled = true

            guard isSessionActive else { return }
            let currentTime = frame.timestamp
            guard currentTime - lastUpdateTime >= updateInterval else { return }
            lastUpdateTime = currentTime

            let transform = frame.camera.transform
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

            DispatchQueue.main.async {
                self.placeMarker(at: position)
            }
        }

        func checkForLoopClosure(at currentPosition: SIMD3<Float>, heading: Double) -> Bool {
            guard loopClosureEnabled, pathPoints.count > 20 else { return false }

            for i in 0..<(pathPoints.count - 20) {
                let prev = pathPoints[i]
                let distance = simd_distance(prev.position, currentPosition)
                let headingDiff = abs(prev.heading - heading)

                if distance < 0.2 && headingDiff < 10 {
                    let drift = simd_length(prev.position - currentPosition)
                    if drift < 0.3 {
                        // Too small to correct—likely noise
                        return false
                    }

                    print("\u{1F501} Loop closure detected at index \(i)")
                    showLoopClosureIndicator(at: currentPosition)
                    drawCorrectionLine(from: currentPosition, to: prev.position)
                    correctDriftSmoothly(from: i, to: pathPoints.count - 1, currentPos: currentPosition, matchedPos: prev.position)
                    return true
                }
            }
            return false
        }

        func correctDriftSmoothly(from startIndex: Int, to endIndex: Int, currentPos: SIMD3<Float>, matchedPos: SIMD3<Float>) {
            let correction = matchedPos - currentPos
            let rangeLength = Float(endIndex - startIndex + 1)
            print("Applying smooth correction over range \(startIndex)-\(endIndex): \(correction)")

            for (offset, i) in (startIndex...endIndex).enumerated() {
                let factor = Float(offset) / rangeLength
                let blendedCorrection = correction * factor
                pathPoints[i].position += blendedCorrection
                pathPoints[i].drift = simd_length(blendedCorrection)
            }

            updateDriftLabel()
        }


        func updateDriftLabel() {
            guard let arView = arView,
                  let label = arView.viewWithTag(104) as? UILabel else { return }

            let recent = pathPoints.suffix(10)
            guard !recent.isEmpty else {
                label.text = "Drift: --"
                label.textColor = .white
                return
            }

            let avgDrift = recent.map { $0.drift }.reduce(0, +) / Float(recent.count)
            label.text = String(format: "Drift: %.2f m", avgDrift)

            // Color-code based on accuracy
            if avgDrift < 0.05 {
                label.textColor = .green
            } else if avgDrift < 0.15 {
                label.textColor = .orange
            } else {
                label.textColor = .red
            }
        }


        func drawCorrectionLine(from: SIMD3<Float>, to: SIMD3<Float>) {
            guard let arView = arView else { return }
            let vector = to - from
            let distance = simd_length(vector)
            let midPoint = (from + to) / 2

            let cylinder = MeshResource.generateCylinder(height: distance, radius: 0.002)
            let material = UnlitMaterial(color: .magenta)
            let entity = ModelEntity(mesh: cylinder, materials: [material])
            let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), vector))
            let angle = acos(simd_dot(simd_normalize(vector), SIMD3<Float>(0, 1, 0)))
            if angle.isFinite {
                entity.transform.rotation = simd_quatf(angle: angle, axis: axis)
            }
            entity.position = .zero

            let container = ModelEntity()
            container.position = midPoint
            container.addChild(entity)

            let anchor = AnchorEntity(world: midPoint)
            anchor.addChild(container)
            arView.scene.addAnchor(anchor)
        }

        func showLoopClosureIndicator(at position: SIMD3<Float>) {
            guard let arView = arView else { return }
            let sphere = MeshResource.generateSphere(radius: 0.03)
            let material = UnlitMaterial(color: .cyan)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = [0, 0, 0]

            let anchor = AnchorEntity(world: position)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }

        func placeMarker(at position: SIMD3<Float>) {
            guard let arView = arView else { return }

            let heading = currentHeading?.magneticHeading ?? -1
            _ = checkForLoopClosure(at: position, heading: heading)

            let sphere = MeshResource.generateSphere(radius: 0.020)
            let material = UnlitMaterial(color: .yellow)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = [0, 0, 0]

            let anchor = AnchorEntity(world: position)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            var segmentDistance: Float = 0.0
            var shouldCountDistance = false

            if let previous = previousPosition {
                let displacement = position - previous
                segmentDistance = simd_length(displacement)

                if segmentDistance > 0.05 { // Minimum threshold
                    if pathPoints.count >= 2 {
                        let prevDir = simd_normalize(previous - pathPoints[pathPoints.count - 2].position)
                        let newDir = simd_normalize(displacement)
                        let directionChange = simd_dot(prevDir, newDir)
                        shouldCountDistance = directionChange > 0.7 // Angle threshold
                    } else {
                        shouldCountDistance = true
                    }
                }

                if shouldCountDistance {
                    let lineEntity = generateLine(from: .zero, to: displacement)
                    if let previousAnchor = previousAnchor {
                        previousAnchor.addChild(lineEntity)
                    }
                    totalDistance += segmentDistance
                }
            }

            //let depth = simd_length(position - (pathPoints.first?.position ?? position))
            let depth = abs(position.y - (pathPoints.first?.position.y ?? position.y))

            
            pathPoints.append((position: position, distance: totalDistance, heading: heading, depth: depth, drift: 0.0))

            updateLabel()
            updateMaxDepthLabel()

            previousAnchor = anchor
            previousPosition = position
        }

        func updateLabel() {
            guard let arView = arView,
                  let label = arView.viewWithTag(101) as? UILabel else { return }
            let distanceStr = String(format: "Distance: %.2f m", totalDistance)
            let headingStr = currentHeading != nil ? String(format: "Heading: %.0f\u{00B0}", currentHeading!.magneticHeading) : "Heading: --"
            label.text = "\(distanceStr)\n\(headingStr)"
        }

        func updateMaxDepthLabel() {
            guard let arView = arView else { return }
            let tag = 102
            var label = arView.viewWithTag(tag) as? UILabel
            if label == nil {
                label = UILabel()
                label?.textColor = .white
                label?.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
                label?.translatesAutoresizingMaskIntoConstraints = false
                label?.tag = tag
                arView.addSubview(label!)

                NSLayoutConstraint.activate([
                    label!.topAnchor.constraint(equalTo: arView.topAnchor, constant: 100),
                    label!.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
                ])
            }

            let maxDepth = pathPoints.map { $0.depth }.max() ?? 0.0
            label?.text = String(format: "Max Depth: %.2f m", maxDepth)
        }

        func generateLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> ModelEntity {
            let vector = end - start
            let distance = simd_length(vector)
            let midPoint = (start + end) / 2

            let cylinder = MeshResource.generateCylinder(height: distance, radius: 0.001)
            let material = UnlitMaterial(color: .yellow)

            let entity = ModelEntity(mesh: cylinder, materials: [material])
            entity.position = [0, 0, 0]

            let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), vector))
            let angle = acos(simd_dot(simd_normalize(vector), SIMD3<Float>(0, 1, 0)))
            if angle.isFinite {
                entity.transform.rotation = simd_quatf(angle: angle, axis: axis)
            }

            let container = ModelEntity()
            container.position = midPoint
            container.addChild(entity)

            return container
        }

        @objc func exportTapped() {
            guard let arView = arView,
                  let currentFrame = arView.session.currentFrame else {
                print("No ARFrame available.")
                return
            }

            let filename = FileManager.default.temporaryDirectory.appendingPathComponent("cave_pointcloud_colored.ply")

            struct ColoredPoint {
                var x: Float
                var y: Float
                var z: Float
                var r: UInt8
                var g: UInt8
                var b: UInt8
                var depth: Float?
                var heading: Double?
            }

            var allPoints: [ColoredPoint] = []

            for point in pathPoints {
                let p = point.position
                allPoints.append(ColoredPoint(x: p.x, y: p.y, z: p.z, r: 255, g: 255, b: 0, depth: point.depth, heading: point.heading))
            }

            if let rawFeatures = currentFrame.rawFeaturePoints {
                for p in rawFeatures.points {
                    allPoints.append(ColoredPoint(x: p.x, y: p.y, z: p.z, r: 0, g: 255, b: 255))
                }
            }

            var plyString = "ply\nformat ascii 1.0\n"
            plyString += "element vertex \(allPoints.count)\n"
            plyString += "property float x\n"
            plyString += "property float y\n"
            plyString += "property float z\n"
            plyString += "property uchar red\n"
            plyString += "property uchar green\n"
            plyString += "property uchar blue\n"
            plyString += "property float depth\n"
            plyString += "property float heading\n"
            plyString += "end_header\n"

            for point in allPoints {
                let depthStr = point.depth != nil ? String(format: "%.2f", point.depth!) : "-1.0"
                let headingStr = point.heading != nil ? String(format: "%.0f", point.heading!) : "-1"
                plyString += "\(point.x) \(point.y) \(point.z) \(point.r) \(point.g) \(point.b) \(depthStr) \(headingStr)\n"
            }

            do {
                try plyString.write(to: filename, atomically: true, encoding: .utf8)
                print("Colored PLY with depth exported to: \(filename)")

                let vc = UIActivityViewController(activityItems: [filename], applicationActivities: nil)
                vc.modalPresentationStyle = .automatic

                DispatchQueue.main.async {
                    if let topController = arView.window?.rootViewController {
                        var presented = topController
                        while let next = presented.presentedViewController {
                            presented = next
                        }
                        if !presented.isBeingPresented && presented.presentedViewController == nil {
                            presented.present(vc, animated: true)
                        } else {
                            print("Export aborted: another view controller is already being presented.")
                        }
                    }
                }

            } catch {
                print("Failed to export PLY: \(error)")
            }
        }

        @objc func resetSession() {
            guard let arView = arView else { return }
            arView.scene.anchors.removeAll()
            previousPosition = nil
            previousAnchor = nil
            totalDistance = 0.0
            pathPoints.removeAll()
            isSessionActive = true
            updateLabel()
            updateMaxDepthLabel()
        }

        @objc func stopSession() {
            isSessionActive.toggle()
            let newTitle = isSessionActive ? "STOP" : "START"
            stopButton?.setTitle(newTitle, for: .normal)
        }
    }
}
