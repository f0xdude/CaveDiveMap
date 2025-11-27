import SwiftUI
import RealityKit
import ARKit
import CoreLocation


struct VisualMapper: UIViewRepresentable {
    /// <#Description#>
    /// - Parameter context: <#context description#>
    /// - Returns: <#description#>
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        
        // 1️⃣ Turn off the real‐world feed by painting the background a solid color
        //    (you can pick .black, .white, any UIColor… or even .clear if you want translucency)
        //arView.environment.background = .color(.clear)
        arView.environment.background = .cameraFeed()


        // 2️⃣ Only show feature points in the debug overlay
        arView.debugOptions = [.showFeaturePoints]

        
        // show only the reconstructed mesh
//        
//        arView.environment.sceneUnderstanding.options.insert(.occlusion)
//        arView.debugOptions.insert(.showSceneUnderstanding)
        
        
        arView.renderOptions = [.disableMotionBlur,
                                .disableDepthOfField,
                                .disablePersonOcclusion,
                                .disableGroundingShadows,
                                .disableFaceMesh,
                                .disableHDR]

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .automatic
        config.sceneReconstruction =   [] //.mesh // []  // if not using scene mesh .mesh uses lidar
        config.isLightEstimationEnabled = true
        config.frameSemantics = []        // disable body/person detection
        //config.worldAlignment = .gravityAndHeading   // BUG; magnetometer drift causes the whole map to drift systematically and warp into a spiral
        config.worldAlignment = .gravity
        //config.isAutoFocusEnabled = false // disable autofocus
        config.planeDetection = [.horizontal, .vertical]



        
        // 1) Build and type your formats array explicitly
        let formats: [ARWorldTrackingConfiguration.VideoFormat] =
            ARWorldTrackingConfiguration.supportedVideoFormats

        // 2) Pick the ultra-wide or wide-angle format
        var chosenFormat: ARWorldTrackingConfiguration.VideoFormat?
        for f in formats {
            let camType = f.captureDeviceType
            if camType == .builtInUltraWideCamera || camType == .builtInWideAngleCamera {
                chosenFormat = f
                break
            }
        }

        // 3) Assign it (if we found one)
        if let wideFormat = chosenFormat {
            config.videoFormat = wideFormat
            print("▶️ Using camera: \(wideFormat.captureDeviceType.rawValue), " +
                  "resolution: \(wideFormat.imageResolution)")
        } else {
            print("ℹ️ Wide-angle camera not available, using default.")
        }

        
        
        
        arView.session.run(config)

        context.coordinator.setup(arView: arView)
        arView.session.delegate = context.coordinator

        let label = UILabel()
        label.textColor = .white
        label.numberOfLines = 3
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 101
        arView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: arView.topAnchor, constant: 40),
            label.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])

        


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

        
        let commentButton = UIButton(type: .system)
        commentButton.setTitle("ADD COMMENT", for: .normal)
        commentButton.setTitleColor(.white, for: .normal)
        commentButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        commentButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        commentButton.layer.cornerRadius = 35
        commentButton.translatesAutoresizingMaskIntoConstraints = false
        commentButton.addTarget(context.coordinator, action: #selector(Coordinator.promptForComment), for: .touchUpInside)
        arView.addSubview(commentButton)

        NSLayoutConstraint.activate([
            // позиция спрямо STOP
            commentButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 20),
            commentButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 140),
            commentButton.heightAnchor.constraint(equalToConstant: 70)
        ])
        
        
        
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

        // Heading label (shows True/Magnetic, accuracy)
        let headingLabel = UILabel()
        headingLabel.textColor = .white
        headingLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        headingLabel.translatesAutoresizingMaskIntoConstraints = false
        headingLabel.tag = 105
        headingLabel.text = "Heading: --"
        arView.addSubview(headingLabel)

        NSLayoutConstraint.activate([
            headingLabel.topAnchor.constraint(equalTo: arView.topAnchor, constant: 190),
            headingLabel.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])
        
        NSLayoutConstraint.activate([
//            resetButton.trailingAnchor.constraint(equalTo: arView.centerXAnchor, constant: -40),
//            resetButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -90),
//            resetButton.widthAnchor.constraint(equalToConstant: 70),
//            resetButton.heightAnchor.constraint(equalToConstant: 70),

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
        private let updateInterval: TimeInterval = 0.5
        private var isSessionActive: Bool = true
        private var loopClosureEnabled: Bool = true
        var stopButton: UIButton?
        private var idleTimerEnforcer: Timer?
        private var commentsByPathIndex: [Int: String] = [:]

       
        /// Map each ARKit feature ID to its latest world-space position
        private var featurePointDict: [UInt64: SIMD3<Float>] = [:]

        ///  Add a container anchor and a lookup for already-drawn points
        private var featurePointAnchor = AnchorEntity()
        private var featurePointEntities: [UInt64: ModelEntity] = [:]
        private let samplingRate = 5
        private let maxPoints     = 1_000
        private var liveVisualization: Bool = false // Enableds or disables live pointcloud visualization ( cpu heavy )

        



        func setup(arView: ARView) {
            self.arView = arView
            UIApplication.shared.isIdleTimerDisabled = true
            
            idleTimerEnforcer?.invalidate()
            idleTimerEnforcer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                UIApplication.shared.isIdleTimerDisabled = true
            }

            locationManager.delegate = self
            locationManager.headingFilter = 1
            locationManager.startUpdatingHeading()
            locationManager.requestWhenInUseAuthorization()
            
            //  Immediately add the container anchor to the scene
            arView.scene.addAnchor(featurePointAnchor)

        }

        
        func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
            return true
        }


        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            currentHeading = newHeading
            // Update heading UI when we receive new heading
            DispatchQueue.main.async {
                self.updateHeadingLabel(with: newHeading)
            }
        }
        
        // Ask system to show calibration UI when heading accuracy is poor or unknown
        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
            // Show calibration if accuracy is unknown or worse than 15 degrees
            if let h = currentHeading {
                return h.headingAccuracy < 0 || h.headingAccuracy > 15
            } else {
                return true
            }
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

          // Throttle to 0.5s to save cpu/battery
          let t = frame.timestamp
          guard t - lastUpdateTime >= updateInterval else { return }
          lastUpdateTime = t
            
           

          // now both features AND markers only update every 0.5 s
          if let raw = frame.rawFeaturePoints {
            for (i, id) in raw.identifiers.enumerated() {
              featurePointDict[id] = raw.points[i]
            }
              
              if liveVisualization
              {
                  visualizeFeaturePoints(raw)
              }
              
          }

          let transform = frame.camera.transform
          let position = SIMD3<Float>(transform.columns.3.x,
                                      transform.columns.3.y,
                                      transform.columns.3.z)
          placeMarker(at: position)
        }

        
        
        
       
        
        

        func checkForLoopClosure(at currentPosition: SIMD3<Float>, heading: Double) -> Bool {
            guard loopClosureEnabled, pathPoints.count > 20 else { return false }

            var bestMatchIndex: Int? = nil
            var lowestDrift: Float = .greatestFiniteMagnitude

            for i in 0..<(pathPoints.count - 20) {
                let prev = pathPoints[i]
                let spatialDistance = simd_distance(prev.position, currentPosition)
                let headingDiff = abs(prev.heading - heading)

                // ✅ Looser match thresholds
                //if spatialDistance < 0.5 && headingDiff < 25 {
                if spatialDistance < 0.5{
                    let drift = simd_length(prev.position - currentPosition)

                    if drift < lowestDrift && drift > 0.1 {
                        bestMatchIndex = i
                        lowestDrift = drift
                    }
                }
            }

            guard let matchIndex = bestMatchIndex else {
                return false
            }

            print("🔁 Loop closure confirmed at index \(matchIndex) with drift \(lowestDrift)")
            showLoopClosureIndicator(at: currentPosition)

            // 🔀 Correct from both sides
            let midIndex = (matchIndex + pathPoints.count - 1) / 2

            let matchedPos = pathPoints[matchIndex].position
            correctDriftSmoothly(from: matchIndex, to: midIndex, currentPos: currentPosition, matchedPos: matchedPos)
            correctDriftSmoothly(from: midIndex, to: pathPoints.count - 1, currentPos: currentPosition, matchedPos: matchedPos)

            return true
        }

        

        func correctDriftSmoothly(from startIndex: Int, to endIndex: Int, currentPos: SIMD3<Float>, matchedPos: SIMD3<Float>) {
            let rawCorrection = matchedPos - currentPos
            let maxCorrectionLength: Float = 2.0

            // Clamp to max correction length to prevent extreme jumps
            let correction: SIMD3<Float> = {
                let len = simd_length(rawCorrection)
                if len > maxCorrectionLength {
                    return simd_normalize(rawCorrection) * maxCorrectionLength
                } else {
                    return rawCorrection
                }
            }()

            let rangeLength = Float(endIndex - startIndex + 1)
            print("🔧 Applying smooth correction over range \(startIndex)-\(endIndex): \(correction)")

            for (offset, i) in (startIndex...endIndex).enumerated() {
                let t = Float(offset) / rangeLength
                let smoothedCorrection = correction * t

                pathPoints[i].position += smoothedCorrection
                pathPoints[i].drift = simd_length(smoothedCorrection)
            }

            updateDriftLabel()
        }


        func updateDriftLabel() {
            guard let arView = arView,
                  let label = arView.viewWithTag(104) as? UILabel else { return }

            guard pathPoints.count >= 2 else {
                label.text = "Drift: --"
                label.textColor = .white
                return
            }
            
            let start = pathPoints.first!.position
            let end = pathPoints.last!.position
            
            let straightLineDistance = simd_distance(start, end)
            let traveledDistance = totalDistance
            
            let driftAmount = traveledDistance - straightLineDistance
            
            if driftAmount <= 0 {
                label.text = "Drift: 0.00 m"
                label.textColor = .green
                return
            }
            
            label.text = String(format: "Drift: %.2f m", driftAmount)
            
            if driftAmount < 0.2 {
                label.textColor = .green
            } else if driftAmount < 0.5 {
                label.textColor = .orange
            } else {
                label.textColor = .red
            }
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
            
            // Only place markers if distance from previous position is over 50cm
            let threshold: Float = 0.3   // 30 cm
            if let prev = previousPosition,
               simd_distance(position, prev) < threshold {
              return
            }
            
            
            guard let arView = arView else { return }

            let headingInfo = preferredHeading()
            let headingValue = headingInfo.value ?? -1
            _ = checkForLoopClosure(at: position, heading: headingValue)

            // Direction to previous point (local path orientation)
            var direction = SIMD3<Float>(0, 0, -1)
            if let previous = previousPosition {
                direction = simd_normalize(previous - position)
            }

            // Load the USDZ arrow model
            guard let arrowEntity = try? Entity.loadModel(named: "cave_arrow.usdz") else {
                print("❌ Failed to load cave_arrow.usdz")
                return
            }

            // Apply glowing yellow material to all parts (RealityKit 2 compatible)
            let glowingYellow = UnlitMaterial(color: .yellow)

            func applyMaterialRecursively(to entity: Entity, material: RealityKit.Material) {
                if let model = entity as? ModelEntity {
                    model.model?.materials = [material]
                }
                for child in entity.children {
                    applyMaterialRecursively(to: child, material: material)
                }
            }

            applyMaterialRecursively(to: arrowEntity, material: glowingYellow)

            // Scale the arrow to a usable size
            arrowEntity.scale = SIMD3<Float>(repeating: 0.001)

            // Orient arrow to face previous path point
            let lookAtTarget = position + direction

            arrowEntity.look(at: lookAtTarget, from: position, relativeTo: nil)

            // Slight upward offset so it doesn't clip the surface
            arrowEntity.position = SIMD3<Float>(0, 0.015, 0)

            // Anchor it to the world
            let anchor = AnchorEntity(world: position)
            anchor.addChild(arrowEntity)
            arView.scene.addAnchor(anchor)

            // Path line and distance logic
            var segmentDistance: Float = 0.0
            var shouldCountDistance = false

            if let previous = previousPosition {
                let displacement = position - previous
                segmentDistance = simd_length(displacement)

                if segmentDistance > 0.05 {
                    if pathPoints.count >= 2 {
                        let prevDir = simd_normalize(previous - pathPoints[pathPoints.count - 2].position)
                        let newDir = simd_normalize(displacement)
                        let directionChange = simd_dot(prevDir, newDir)
                        shouldCountDistance = directionChange > 0.4
                    } else {
                        shouldCountDistance = true
                    }
                }

                if shouldCountDistance {
                    let lineEntity = generateLine(from: .zero, to: position - previous)
                    if let previousAnchor = previousAnchor {
                        previousAnchor.addChild(lineEntity)
                    }
                    totalDistance += segmentDistance
                }
            }

            let depthToStart = abs(position.y - (pathPoints.first?.position.y ?? position.y))
            pathPoints.append((position: position, distance: totalDistance, heading: headingValue, depth: depthToStart, drift: 0.0))

            updateLabel()
            updateMaxDepthLabel()
            
            previousAnchor = anchor
            previousPosition = position
        }



        func updateLabel() {
            guard let arView = arView,
                  let label = arView.viewWithTag(101) as? UILabel else { return }
            let distanceStr = String(format: "Distance: %.2f m", totalDistance)
           // let headingStr = currentHeading != nil ? String(format: "Heading: %.0f\u{00B0}", currentHeading!.magneticHeading) : "Heading: --"
            //label.text = "\(distanceStr)\n\(headingStr)"
            label.text = "\(distanceStr)"
        }

        func updateMaxDepthLabel() {
            guard let arView = arView else { return }
            let tag = 102
            var label = arView.viewWithTag(tag) as? UILabel
            if label == nil {
                label = UILabel()
                label?.textColor = .white
                label?.font = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium)
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
            guard self.arView != nil else { return }

            let pathSnapshot    = self.pathPoints
            let featureSnapshot = Array(self.featurePointDict.values)
            let commentSnapshot = self.commentsByPathIndex  // index -> text

            DispatchQueue.global(qos: .userInitiated).async {
                // 0) Име на файл и целеви URL
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let ts = fmt.string(from: Date())
                let fn = "pointcloud_\(ts).ply"

                let fm = FileManager.default
                guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("❌ Couldn't find Documents folder")
                    return
                }
                let url = docs.appendingPathComponent(fn)

                // 1) Отвори поток за писане
                guard let stream = OutputStream(url: url, append: false) else {
                    print("❌ Could not open stream at \(url.path)")
                    return
                }
                stream.open()
                defer { stream.close() }

                // 2) Построи стабилна мапинг таблица: pathIndex -> commentID (0..N-1)
                let sortedCommentPairs = commentSnapshot.sorted { $0.key < $1.key } // [(pathIdx, text)]
                var commentIDByPathIndex: [Int: Int] = [:]
                for (cid, pair) in sortedCommentPairs.enumerated() {
                    commentIDByPathIndex[pair.0] = cid
                }

                // 3) HEADER — добавяме property int comment_id + comment редове
                var header = """
                ply
                format ascii 1.0
                element vertex \(pathSnapshot.count + featureSnapshot.count)
                property float x
                property float y
                property float z
                property uchar red
                property uchar green
                property uchar blue
                property float depth
                property float heading
                property int comment_id
                """

                if !sortedCommentPairs.isEmpty {
                    header += "\n"
                    for (cid, pair) in sortedCommentPairs.enumerated() {
                        let idx = pair.0
                        let text = self.sanitizeForPLYComment(pair.1)
                        header += "comment annotation id=\(cid) vertex_index=\(idx) text=\(text)\n"
                    }
                }

                header += "\nend_header\n"

                if let data = header.data(using: .utf8) {
                    _ = data.withUnsafeBytes { ptr in
                        stream.write(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                     maxLength: ptr.count)
                    }
                }

                // 4) WAYPOINTS — със comment_id (или -1 ако няма)
                for (i, wp) in pathSnapshot.enumerated() {
                    let cid = commentIDByPathIndex[i] ?? -1
                    let line = String(
                        format: "%.4f %.4f %.4f 255 255 0 %.2f %.0f %d\n",
                        wp.position.x, wp.position.y, wp.position.z,
                        wp.depth, wp.heading, cid
                    )
                    if let data = line.data(using: .utf8) {
                        _ = data.withUnsafeBytes { ptr in
                            stream.write(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                         maxLength: ptr.count)
                        }
                    }
                }

                // 5) FEATURES — без коментари: comment_id = -1
                for fp in featureSnapshot {
                    let line = String(
                        format: "%.4f %.4f %.4f 0 255 255 -1.0 -1 -1\n",
                        fp.x, fp.y, fp.z
                    )
                    if let data = line.data(using: .utf8) {
                        _ = data.withUnsafeBytes { ptr in
                            stream.write(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                         maxLength: ptr.count)
                        }
                    }
                }

                // 6) Done
                DispatchQueue.main.async {
                    print("✅ Saved PLY to \(url.path)")
                }
            }
        }





        
        

        @objc func resetSession() {
                guard let arView = arView else { return }
                arView.scene.anchors.removeAll()

                // clear both your path + features
                previousPosition = nil
                previousAnchor   = nil
                totalDistance    = 0.0
                pathPoints.removeAll()
            
                
                featurePointEntities.values.forEach { $0.removeFromParent() }


                featurePointEntities.removeAll()
                featurePointAnchor = AnchorEntity()
                arView.scene.addAnchor(featurePointAnchor)
                commentsByPathIndex.removeAll() // <— добавено
            
                isSessionActive = true
                updateLabel()
                updateMaxDepthLabel()
            }


        @objc func stopSession() {
            if isSessionActive {
                // First tap: Stop mapping, but keep session running
                exportTapped() // Dump data to disk
                
//                saveCSVToDisk()

                isSessionActive = false

                DispatchQueue.main.async { [weak self] in
                    self?.stopButton?.setTitle("EXIT", for: .normal)
                }
            } else {
                // Second tap: Exit the view
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          let vc = self.arView?.parentViewController() else { return }
                    vc.dismiss(animated: true, completion: nil)
                }
            }
        }



        
        

        
       


        /// Write the current pathPoints out to a CSV in the app's Documents folder
            private func saveCSVToDisk() {
                // 1) Build the CSV string
                var csv = "From,To,Distance,Heading\n"
                for i in 1..<pathPoints.count {
                    let from = i
                    let to   = i + 1
                    let segmentDist = pathPoints[i].distance - pathPoints[i - 1].distance
                    let heading     = Int(round(pathPoints[i].heading))
                    csv += "\(from),\(to),\(String(format: "%.2f", segmentDist))m,\(heading)\n"
                }

                // 2) File URL in Documents
                let docs = FileManager.default
                           .urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = docs.appendingPathComponent("path_data.csv")

                // 3) Write it
                do {
                    try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ Saved CSV to: \(fileURL.path)")
                } catch {
                    print("❌ Failed to save CSV: \(error)")
                }
            }

        
        ///  For every identifier in the ARPointCloud, if we haven't yet drawn it, make a little sphere
        private func visualizeFeaturePoints(_ cloud: ARPointCloud) {
            guard let arView = arView else { return }
            
            // Camera position in world-space
            let camTransform = arView.cameraTransform
            let camPosition  = camTransform.translation
            
            // —— PARAMETERS YOU CAN TUNE ——
            let samplingRate     = 10      // 1 in 10 points
            let maxPoints        = 2_000   // absolute cap
            let keepRadius: Float = 10.0   // only show points within 10 m of the camera
            
            // Add new points (sparse sampling + never repeat an ID)
            for (i, id) in cloud.identifiers.enumerated() {
                guard i % samplingRate == 0,
                      featurePointEntities[id] == nil
                else { continue }

                let pt = cloud.points[i]
                let worldPt = simd_make_float3(pt)  // since your anchor is world-aligned

                // Skip points that are really far from the user
                if simd_distance(worldPt, camPosition) > keepRadius { continue }

                // cheap box
                let mesh = MeshResource.generateBox(size: 0.003)
                let mat  = UnlitMaterial(color: .cyan)
                let ent  = ModelEntity(mesh: mesh, materials: [mat])
                ent.position = worldPt

                featurePointAnchor.addChild(ent)
                featurePointEntities[id] = ent
            }

            //  Cull old points when we exceed budget OR when they drift outside the keepRadius
            for (id, ent) in featurePointEntities {
                let pos = ent.position
                if featurePointEntities.count > maxPoints
                   || simd_distance(pos, camPosition) > keepRadius {
                    ent.removeFromParent()
                    featurePointEntities.removeValue(forKey: id)
                }
            }
        }

        @objc func promptForComment() {
            guard let vc = arView?.parentViewController() else { return }
            guard !pathPoints.isEmpty else {
                print("⚠️ No path points yet. Can't attach a comment.")
                return
            }
            let alert = UIAlertController(title: "Add Comment",
                                          message: "Will attach to last path point (#\(pathPoints.count - 1)).",
                                          preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "Your comment"
                tf.autocapitalizationType = .sentences
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return }
                self.addComment(text)
            }))
            vc.safePresent(alert, animated: true)
        }

        private func addComment(_ text: String) {
            let idx = pathPoints.count - 1
            commentsByPathIndex[idx] = text

            // визуален маркер (по желание): малка магента сфера на коментираната точка
            if let arView = arView, let lastPos = pathPoints.last?.position {
                let sphere = MeshResource.generateSphere(radius: 0.02)
                let mat = UnlitMaterial(color: .magenta)
                let ent = ModelEntity(mesh: sphere, materials: [mat])
                let anchor = AnchorEntity(world: lastPos)
                anchor.addChild(ent)
                arView.scene.addAnchor(anchor)
            }
            print("📝 Comment attached to path point \(idx): \(text)")
        }

        // помощник за безопасен текст в PLY header comments (ASCII, едноредов)
        private func sanitizeForPLYComment(_ s: String) -> String {
            let noNewlines = s.replacingOccurrences(of: "\n", with: " ")
                              .replacingOccurrences(of: "\r", with: " ")
                              .replacingOccurrences(of: "\"", with: "'")
            let scalars = noNewlines.unicodeScalars.filter { $0.isASCII && $0.value >= 32 && $0.value < 127 }
            return String(String.UnicodeScalarView(scalars))
        }

        // MARK: - Heading helpers and UI
        
        // Compute preferred heading value (True if valid, otherwise Magnetic) and provide accuracy
        private func preferredHeading() -> (value: Double?, isTrue: Bool, accuracy: CLLocationDirection?) {
            guard let h = currentHeading else {
                return (nil, false, nil)
            }
            // True heading is valid if accuracy >= 0 and trueHeading >= 0
            if h.headingAccuracy >= 0, h.trueHeading >= 0 {
                return (h.trueHeading, true, h.headingAccuracy)
            } else {
                // Fallback to magnetic; accuracy still describes the heading error (if >= 0)
                let acc = h.headingAccuracy >= 0 ? h.headingAccuracy : nil
                return (h.magneticHeading, false, acc)
            }
        }
        
        // Update or create the heading label (tag 105) with value, accuracy and type (T/M)
        private func updateHeadingLabel(with heading: CLHeading) {
            guard let arView = arView,
                  let label = arView.viewWithTag(105) as? UILabel else { return }
            
            let info = preferredHeading()
            let suffix = info.isTrue ? "T" : "M"
            
            let text: String
            let color: UIColor
            
            if let value = info.value {
                let valueStr = String(format: "%.0f°", value)
                if let acc = info.accuracy {
                    let accStr = String(format: "±%.0f°", acc)
                    text = "Heading: \(valueStr) (\(accStr)) \(suffix)"
                    // Color code by accuracy
                    if acc <= 5 {
                        color = .green
                    } else if acc <= 15 {
                        color = .orange
                    } else {
                        color = .red
                    }
                } else {
                    text = "Heading: \(valueStr) (unknown) \(suffix)"
                    color = .red
                }
            } else {
                text = "Heading: --"
                color = .white
            }
            
            label.text = text
            label.textColor = color
        }

        
        
    }
}



extension UIView {
    /// Walks the responder chain until it finds a UIViewController
    func parentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                return vc
            }
            responder = r.next
        }
        return nil
    }
}

extension UIViewController {
    func safePresent(_ viewController: UIViewController, animated: Bool = true) {
        if self.presentedViewController == nil {
            self.present(viewController, animated: animated, completion: nil)
        } else {
            print("⚠️ Skipping present: another view controller is already shown.")
        }
    }
}
