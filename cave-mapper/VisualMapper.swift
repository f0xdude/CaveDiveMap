import SwiftUI
import RealityKit
import ARKit
import CoreLocation


// MARK: - Tuning

/// All VIO capture/quality parameters in one place so they can be tuned without
/// hunting through the code.
private enum Tuning {
    /// How often we sample the ARFrame. Feature accumulation benefits from a
    /// faster cadence than marker placement, which is gated by `markerSpacing`.
    static let updateInterval: TimeInterval = 0.2

    /// Minimum travel between recorded path points.
    static let markerSpacing: Float = 0.3

    /// Any apparent motion faster than this is treated as a tracking glitch,
    /// not as travel. Caving on foot is well under 3 m/s.
    static let maxPlausibleSpeed: Float = 3.0

    /// A feature must be seen in at least this many sampled frames before it is
    /// exported. Filters out transient / badly triangulated points.
    static let minFeatureObservations = 3

    /// Features further than this from the camera are discarded: triangulation
    /// uncertainty grows quadratically with range.
    static let maxFeatureRange: Float = 8.0

    /// Export-time voxel grid. One point survives per occupied voxel.
    static let featureVoxelSize: Float = 0.05

    /// Hard cap on tracked feature IDs before single-observation points are pruned.
    static let featureBudget = 400_000

    /// Live AR overlay only. Older marker anchors are removed from the scene to
    /// keep the render cost flat; the underlying path data is never discarded.
    static let maxRenderedMarkers = 300

    /// Periodic crash-safety dump.
    static let autosaveInterval: TimeInterval = 60

    /// Heading samples worse than this (degrees) are rejected for north calibration.
    static let headingAccuracyLimit: CLLocationDirection = 20
}


// MARK: - Model

/// One recorded point on the survey centerline.
private struct PathPoint {
    var position: SIMD3<Float>
    /// Cumulative travelled distance up to this point, in metres.
    var distance: Float
    /// True (or magnetic, see `headingIsTrue`) heading in degrees, or -1 if unavailable.
    var heading: Double
    /// Positive is *below* the session origin, matching survey convention.
    var depth: Float
    /// Residual applied to this point by the last loop closure, in metres.
    var drift: Float
    /// Increments whenever tracking is lost. Points in different segments are not
    /// connected and their separation is not counted as travel.
    var segment: Int
}

/// A feature point plus the evidence we have for it.
private struct FeatureObservation {
    var position: SIMD3<Float>
    var count: Int
    /// Index into `pathPoints` at the time of last observation, so loop-closure
    /// corrections can be applied to the wall cloud as well as the centerline.
    var lastPathIndex: Int
}


struct VisualMapper: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        arView.environment.background = .cameraFeed()

        // Feature points are the only debug overlay worth its cost: they tell the
        // surveyor at a glance whether the passage has enough texture to track.
        arView.debugOptions = [.showFeaturePoints]

        arView.renderOptions = [.disableMotionBlur,
                                .disableDepthOfField,
                                .disablePersonOcclusion,
                                .disableGroundingShadows,
                                .disableFaceMesh,
                                .disableHDR]

        let config = ARWorldTrackingConfiguration()

        // Nothing in a cave survey uses planes, environment probes or light
        // estimation. Leaving them on costs CPU/GPU and thermal headroom, and
        // thermal throttling degrades tracking quality directly.
        config.planeDetection = []
        config.environmentTexturing = .none
        config.isLightEstimationEnabled = false
        config.frameSemantics = []

        // LiDAR is useless underwater and adds little in a dry passage beyond
        // what the sparse cloud gives us, at significant power cost.
        config.sceneReconstruction = []

        // .gravityAndHeading continuously folds magnetometer readings into the
        // world frame; in iron-bearing rock that yaws the map mid-session and
        // warps long passages into a spiral. We align to gravity only and record
        // the north offset separately (see `calibrateNorth`).
        config.worldAlignment = .gravity

        // Autofocus hunting changes the camera intrinsics from frame to frame,
        // which shows up as tracking jitter. Lock it.
        config.isAutoFocusEnabled = false

        // Prefer ultra-wide (more parallax and better feature retention in a
        // confined passage), then the highest frame rate (shorter exposures, less
        // motion blur, more frequent pose updates), then the lowest resolution
        // that satisfies both — ARKit downsamples for tracking anyway.
        let ranked = ARWorldTrackingConfiguration.supportedVideoFormats.sorted { a, b in
            let aUltraWide = a.captureDeviceType == .builtInUltraWideCamera
            let bUltraWide = b.captureDeviceType == .builtInUltraWideCamera
            if aUltraWide != bUltraWide { return aUltraWide }
            if a.framesPerSecond != b.framesPerSecond { return a.framesPerSecond > b.framesPerSecond }
            let aPixels = a.imageResolution.width * a.imageResolution.height
            let bPixels = b.imageResolution.width * b.imageResolution.height
            return aPixels < bPixels
        }
        if let format = ranked.first {
            config.videoFormat = format
            print("▶️ Using camera: \(format.captureDeviceType.rawValue), " +
                  "resolution: \(format.imageResolution), \(format.framesPerSecond) fps")
        }

        arView.session.run(config)

        context.coordinator.setup(arView: arView)
        arView.session.delegate = context.coordinator

        buildOverlay(on: arView, coordinator: context.coordinator)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Overlay

    private func buildOverlay(on arView: ARView, coordinator: Coordinator) {
        func makeLabel(tag: Int, size: CGFloat, weight: UIFont.Weight, topOffset: CGFloat, text: String) -> UILabel {
            let label = UILabel()
            label.textColor = .white
            label.numberOfLines = 1
            label.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.tag = tag
            label.text = text
            arView.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.topAnchor, constant: topOffset),
                label.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
            ])
            return label
        }

        _ = makeLabel(tag: 101, size: 24, weight: .medium, topOffset: 8,   text: "Distance: 0.00 m")
        _ = makeLabel(tag: 102, size: 24, weight: .medium, topOffset: 44,  text: "Depth: 0.00 m")
        _ = makeLabel(tag: 104, size: 14, weight: .medium, topOffset: 82,  text: "Closure: --")
        _ = makeLabel(tag: 103, size: 14, weight: .medium, topOffset: 104, text: "Tracking: --")
        _ = makeLabel(tag: 105, size: 14, weight: .medium, topOffset: 126, text: "Heading: --")
        _ = makeLabel(tag: 106, size: 14, weight: .medium, topOffset: 148, text: "North: not set")

        let stopButton = UIButton(type: .system)
        coordinator.stopButton = stopButton
        stopButton.setTitle("STOP", for: .normal)
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        stopButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
        stopButton.layer.cornerRadius = 35
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(coordinator, action: #selector(Coordinator.stopSession), for: .touchUpInside)
        arView.addSubview(stopButton)

        let commentButton = UIButton(type: .system)
        commentButton.setTitle("ADD COMMENT", for: .normal)
        commentButton.setTitleColor(.white, for: .normal)
        commentButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        commentButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        commentButton.layer.cornerRadius = 35
        commentButton.translatesAutoresizingMaskIntoConstraints = false
        commentButton.addTarget(coordinator, action: #selector(Coordinator.promptForComment), for: .touchUpInside)
        arView.addSubview(commentButton)

        let northButton = UIButton(type: .system)
        coordinator.northButton = northButton
        northButton.setTitle("SET N", for: .normal)
        northButton.setTitleColor(.white, for: .normal)
        northButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        northButton.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.9)
        northButton.layer.cornerRadius = 35
        northButton.translatesAutoresizingMaskIntoConstraints = false
        northButton.addTarget(coordinator, action: #selector(Coordinator.calibrateNorth), for: .touchUpInside)
        arView.addSubview(northButton)

        NSLayoutConstraint.activate([
            stopButton.leadingAnchor.constraint(equalTo: arView.centerXAnchor, constant: -30),
            stopButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            stopButton.widthAnchor.constraint(equalToConstant: 70),
            stopButton.heightAnchor.constraint(equalToConstant: 70),

            commentButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 20),
            commentButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 140),
            commentButton.heightAnchor.constraint(equalToConstant: 70),

            northButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -20),
            northButton.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            northButton.widthAnchor.constraint(equalToConstant: 70),
            northButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }


    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate, CLLocationManagerDelegate {

        private var arView: ARView?

        // Path state
        private var pathPoints: [PathPoint] = []
        private var previousAnchor: AnchorEntity?
        private var previousPosition: SIMD3<Float>?
        private var previousAcceptedTime: TimeInterval?
        private var totalDistance: Float = 0.0
        private var originY: Float?
        private var currentSegment: Int = 0
        private var commentsByPathIndex: [Int: String] = [:]

        // Wall cloud
        private var featureObservations: [UInt64: FeatureObservation] = [:]

        // Tracking quality
        private var isTrackingUsable: Bool = false
        private var needsNewSegment: Bool = true
        private var trackingGapCount: Int = 0
        private var rejectedJumpCount: Int = 0

        // Heading / north
        private let locationManager = CLLocationManager()
        private var currentHeading: CLHeading?
        private var lastCameraTransform: simd_float4x4?
        /// Degrees to add to an ARKit-frame azimuth to obtain a compass bearing.
        private var northOffsetDegrees: Double?
        private var northOffsetAccuracy: CLLocationDirection?
        private var northReferenceIsTrue: Bool = false

        // Loop closure. Off by default: the position-proximity trigger below cannot
        // distinguish a real loop from two passages that merely run close together,
        // and a false closure silently deforms an otherwise good survey. Turn on
        // only when you know the traverse actually closes.
        private var loopClosureEnabled: Bool = false
        private var lastClosureResidual: Float?

        // Session / lifecycle
        private var isSessionActive: Bool = true
        private var lastUpdateTime: TimeInterval = 0
        private var lastAutosaveTime: TimeInterval = 0
        private var isWritingAutosave: Bool = false
        private var autosaveURL: URL?
        private let exportQueue = DispatchQueue(label: "cave-mapper.ply-export", qos: .utility)
        private var idleTimerEnforcer: Timer?
        private var lifecycleObservers: [NSObjectProtocol] = []

        var stopButton: UIButton?
        var northButton: UIButton?

        // Live point cloud overlay (CPU heavy, off by default)
        private var liveVisualization: Bool = false
        private var featurePointAnchor = AnchorEntity()
        private var featurePointEntities: [UInt64: ModelEntity] = [:]
        private var featurePointOrder: [UInt64] = []

        /// Loaded once and cloned per marker. `Entity.loadModel` hits the disk and
        /// parses USDZ; doing that every 30 cm stalls the main thread and starves
        /// the tracker.
        private var arrowTemplate: ModelEntity?

        private var markerAnchors: [AnchorEntity] = []


        // MARK: Setup / teardown

        func setup(arView: ARView) {
            self.arView = arView
            UIApplication.shared.isIdleTimerDisabled = true

            idleTimerEnforcer?.invalidate()
            idleTimerEnforcer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                UIApplication.shared.isIdleTimerDisabled = true
            }

            locationManager.requestWhenInUseAuthorization()
            locationManager.delegate = self
            locationManager.headingFilter = 1
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }

            arView.scene.addAnchor(featurePointAnchor)

            arrowTemplate = loadArrowTemplate()

            let center = NotificationCenter.default
            lifecycleObservers.append(
                center.addObserver(forName: UIApplication.willResignActiveNotification,
                                   object: nil, queue: .main) { [weak self] _ in
                    // A backgrounded session may come back with a different world
                    // origin. Get what we have onto disk before that can happen.
                    self?.autosave(force: true)
                }
            )
        }

        deinit {
            idleTimerEnforcer?.invalidate()
            lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
            locationManager.stopUpdatingHeading()
            UIApplication.shared.isIdleTimerDisabled = false
        }

        private func loadArrowTemplate() -> ModelEntity? {
            guard let entity = try? Entity.loadModel(named: "cave_arrow.usdz") else {
                print("❌ Failed to load cave_arrow.usdz")
                return nil
            }
            let glowingYellow = UnlitMaterial(color: .yellow)
            applyMaterialRecursively(to: entity, material: glowingYellow)
            entity.scale = SIMD3<Float>(repeating: 0.001)
            return entity
        }

        private func applyMaterialRecursively(to entity: Entity, material: RealityKit.Material) {
            if let model = entity as? ModelEntity {
                model.model?.materials = [material]
            }
            for child in entity.children {
                applyMaterialRecursively(to: child, material: material)
            }
        }


        // MARK: ARSessionDelegate

        func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
            return true
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.isTrackingUsable = false
                self?.needsNewSegment = true
                self?.autosave(force: true)
                self?.presentAlert(title: "Tracking Failed",
                                   message: "\(error.localizedDescription)\n\nData captured so far has been saved.")
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            isTrackingUsable = false
            needsNewSegment = true
            autosave(force: true)
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            // ARKit may or may not relocalize into the original world frame. Until
            // it reports .normal again we record nothing, and whatever comes next
            // starts a fresh segment so a re-origined frame cannot be silently
            // spliced onto the existing path.
            isTrackingUsable = false
            needsNewSegment = true
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let usable: Bool
            switch camera.trackingState {
            case .normal:
                usable = true
            case .notAvailable, .limited:
                usable = false
            }

            if isTrackingUsable && !usable {
                trackingGapCount += 1
                needsNewSegment = true
            }
            isTrackingUsable = usable

            updateTrackingStateLabel(camera.trackingState)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard isSessionActive else { return }

            let t = frame.timestamp
            guard t - lastUpdateTime >= Tuning.updateInterval else { return }
            lastUpdateTime = t

            lastCameraTransform = frame.camera.transform

            // Everything below writes survey data. Only ever do that while ARKit
            // reports full tracking — poses under .limited drift and jump, and
            // those jumps used to be integrated straight into the map.
            guard case .normal = frame.camera.trackingState else {
                autosave(force: false, now: t)
                return
            }

            let cameraPosition = SIMD3<Float>(frame.camera.transform.columns.3.x,
                                              frame.camera.transform.columns.3.y,
                                              frame.camera.transform.columns.3.z)

            if let raw = frame.rawFeaturePoints {
                accumulateFeatures(raw, cameraPosition: cameraPosition)
                if liveVisualization {
                    visualizeFeaturePoints(raw, cameraPosition: cameraPosition)
                }
            }

            placeMarker(at: cameraPosition, timestamp: t)
            autosave(force: false, now: t)
        }


        // MARK: Feature accumulation

        private func accumulateFeatures(_ cloud: ARPointCloud, cameraPosition: SIMD3<Float>) {
            let maxRange2 = Tuning.maxFeatureRange * Tuning.maxFeatureRange
            let pathIndex = max(0, pathPoints.count - 1)

            for (i, id) in cloud.identifiers.enumerated() {
                let point = cloud.points[i]
                if simd_length_squared(point - cameraPosition) > maxRange2 { continue }

                if var existing = featureObservations[id] {
                    // ARKit refines a feature's position as it gathers views, so the
                    // most recent estimate is the best one.
                    existing.position = point
                    existing.count += 1
                    existing.lastPathIndex = pathIndex
                    featureObservations[id] = existing
                } else {
                    featureObservations[id] = FeatureObservation(position: point,
                                                                 count: 1,
                                                                 lastPathIndex: pathIndex)
                }
            }

            if featureObservations.count > Tuning.featureBudget {
                pruneWeakFeatures()
            }
        }

        /// Drop points we have only ever seen once. They are overwhelmingly noise,
        /// and they would be filtered at export time anyway.
        private func pruneWeakFeatures() {
            let before = featureObservations.count
            featureObservations = featureObservations.filter { $0.value.count > 1 }
            print("🧹 Pruned \(before - featureObservations.count) single-observation features")
        }


        // MARK: Path building

        private func placeMarker(at position: SIMD3<Float>, timestamp: TimeInterval) {
            if originY == nil { originY = position.y }

            // Reject implausible motion. After a tracking gap or a relocalization
            // ARKit can teleport the camera; that displacement is not travel.
            if let previous = previousPosition, let previousTime = previousAcceptedTime {
                let displacement = simd_length(position - previous)
                let dt = Float(max(timestamp - previousTime, 1e-3))
                if displacement / dt > Tuning.maxPlausibleSpeed {
                    rejectedJumpCount += 1
                    needsNewSegment = true
                    previousPosition = position
                    previousAcceptedTime = timestamp
                    updateTrackingDetailLabels()
                    return
                }
            }

            if let previous = previousPosition,
               !needsNewSegment,
               simd_distance(position, previous) < Tuning.markerSpacing {
                return
            }

            guard let arView = arView else { return }

            let startingNewSegment = needsNewSegment
            if startingNewSegment {
                currentSegment += 1
                needsNewSegment = false
            }

            let headingInfo = preferredHeading()
            let headingValue = headingInfo.value ?? -1

            // Accumulate travel. The previous implementation dropped any segment
            // whose direction differed from the last by more than ~66°, which threw
            // away the length of every sharp corner in the cave. Jitter while
            // stationary is already excluded by the markerSpacing gate above.
            var connectToPrevious = false
            if let previous = previousPosition, !startingNewSegment {
                totalDistance += simd_length(position - previous)
                connectToPrevious = true
            }

            let depth = originY.map { -(position.y - $0) } ?? 0

            pathPoints.append(PathPoint(position: position,
                                        distance: totalDistance,
                                        heading: headingValue,
                                        depth: depth,
                                        drift: 0.0,
                                        segment: currentSegment))

            addMarkerEntity(at: position,
                            connectToPrevious: connectToPrevious,
                            previous: previousPosition,
                            in: arView)

            previousPosition = position
            previousAcceptedTime = timestamp

            if loopClosureEnabled {
                _ = checkForLoopClosure(at: position)
            }

            updateLabel()
            updateDepthLabel()
        }

        private func addMarkerEntity(at position: SIMD3<Float>,
                                     connectToPrevious: Bool,
                                     previous: SIMD3<Float>?,
                                     in arView: ARView) {
            let anchor = AnchorEntity(world: position)

            if let template = arrowTemplate {
                let arrow = template.clone(recursive: true)
                var direction = SIMD3<Float>(0, 0, -1)
                if let previous = previous {
                    let delta = previous - position
                    if simd_length(delta) > 1e-4 {
                        direction = simd_normalize(delta)
                    }
                }
                arrow.look(at: position + direction, from: position, relativeTo: nil)
                arrow.position = SIMD3<Float>(0, 0.015, 0)
                anchor.addChild(arrow)
            }

            if connectToPrevious, let previous = previous {
                let line = generateLine(from: .zero, to: position - previous)
                previousAnchor?.addChild(line)
            }

            arView.scene.addAnchor(anchor)
            markerAnchors.append(anchor)
            previousAnchor = anchor

            // Keep the live scene bounded. Thousands of anchors tank the frame rate,
            // and a starved renderer degrades tracking — an accuracy problem, not
            // just a smoothness one. The path data itself is untouched.
            while markerAnchors.count > Tuning.maxRenderedMarkers {
                let oldest = markerAnchors.removeFirst()
                arView.scene.removeAnchor(oldest)
            }
        }

        private func generateLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> ModelEntity {
            let vector = end - start
            let distance = simd_length(vector)
            let container = ModelEntity()
            container.position = (start + end) / 2

            guard distance > 1e-5 else { return container }

            let cylinder = MeshResource.generateCylinder(height: distance, radius: 0.001)
            let entity = ModelEntity(mesh: cylinder, materials: [UnlitMaterial(color: .yellow)])

            // Rotate the cylinder's +Y axis onto the segment direction. When the
            // segment is vertical — every pitch and every climb — the naive cross
            // product is zero and normalizing it produces NaN, which used to corrupt
            // the entity's transform. Fall back to an explicit axis in that case.
            let up = SIMD3<Float>(0, 1, 0)
            let direction = vector / distance
            let dot = min(max(simd_dot(direction, up), -1), 1)
            if dot < 1 - 1e-6 {
                let axis = simd_cross(up, direction)
                let axisLength = simd_length(axis)
                if axisLength > 1e-6 {
                    entity.transform.rotation = simd_quatf(angle: acos(dot), axis: axis / axisLength)
                } else {
                    // Antiparallel: any axis perpendicular to up will do.
                    entity.transform.rotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
                }
            }

            container.addChild(entity)
            return container
        }


        // MARK: Loop closure

        /// Experimental. See `loopClosureEnabled`.
        private func checkForLoopClosure(at currentPosition: SIMD3<Float>) -> Bool {
            guard pathPoints.count > 20 else { return false }

            let searchRadius: Float = 0.5
            var bestMatchIndex: Int?
            var bestDistance = Float.greatestFiniteMagnitude

            for i in 0..<(pathPoints.count - 20) {
                // Only a point on the same tracking segment is comparable; positions
                // across a tracking gap may not share a coordinate frame.
                guard pathPoints[i].segment == currentSegment else { continue }
                let d = simd_distance(pathPoints[i].position, currentPosition)
                if d < searchRadius && d < bestDistance {
                    bestDistance = d
                    bestMatchIndex = i
                }
            }

            guard let matchIndex = bestMatchIndex else { return false }

            let matchedPosition = pathPoints[matchIndex].position
            let residual = simd_distance(matchedPosition, currentPosition)
            print("🔁 Loop closure at index \(matchIndex), residual \(residual) m")

            applyClosureCorrection(from: matchIndex, matchedPosition: matchedPosition, currentPosition: currentPosition)
            lastClosureResidual = residual
            showLoopClosureIndicator(at: currentPosition)
            updateClosureLabel()

            return true
        }

        /// Distributes the closure residual over the drifted stretch as a single
        /// monotonic ramp from `matchIndex` to the end of the path.
        ///
        /// The previous implementation ran two independent 0→1 ramps that met at the
        /// midpoint, so the midpoint received the full correction while its immediate
        /// neighbour received none — tearing the path apart at the seam. On a path of
        /// 1 m segments with a 2 m correction, the seam segment stretched to 2.9 m.
        private func applyClosureCorrection(from matchIndex: Int,
                                            matchedPosition: SIMD3<Float>,
                                            currentPosition: SIMD3<Float>) {
            let endIndex = pathPoints.count - 1
            guard endIndex > matchIndex else { return }

            let rawCorrection = matchedPosition - currentPosition
            let maxCorrectionLength: Float = 2.0
            let length = simd_length(rawCorrection)
            let correction = length > maxCorrectionLength
                ? simd_normalize(rawCorrection) * maxCorrectionLength
                : rawCorrection

            let span = Float(endIndex - matchIndex)
            for i in matchIndex...endIndex {
                let t = Float(i - matchIndex) / span
                let applied = correction * t
                pathPoints[i].position += applied
                pathPoints[i].drift = simd_length(applied)
            }

            // The wall cloud has to move with the centerline, or closure pulls the
            // two apart. Each feature rides the ramp of the path point it was last
            // seen from.
            for (id, observation) in featureObservations where observation.lastPathIndex >= matchIndex {
                let t = Float(min(observation.lastPathIndex, endIndex) - matchIndex) / span
                featureObservations[id]?.position += correction * t
            }

            // Travelled distance changes when the geometry does.
            recomputeCumulativeDistance()
            previousPosition = pathPoints[endIndex].position

            // Note: markers already committed to the RealityKit scene are not
            // retro-corrected. The live overlay drifts from the exported data after
            // a closure; the export is the authoritative result.
        }

        private func recomputeCumulativeDistance() {
            var running: Float = 0
            for i in pathPoints.indices {
                if i > 0 && pathPoints[i].segment == pathPoints[i - 1].segment {
                    running += simd_distance(pathPoints[i].position, pathPoints[i - 1].position)
                }
                pathPoints[i].distance = running
            }
            totalDistance = running
        }

        private func showLoopClosureIndicator(at position: SIMD3<Float>) {
            guard let arView = arView else { return }
            let sphere = MeshResource.generateSphere(radius: 0.03)
            let entity = ModelEntity(mesh: sphere, materials: [UnlitMaterial(color: .cyan)])
            let anchor = AnchorEntity(world: position)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }


        // MARK: North calibration

        /// Freezes the rotation between the ARKit yaw origin (arbitrary, since we
        /// align to gravity only) and the compass, so the exported survey carries a
        /// real bearing.
        ///
        /// The offset is recorded in the PLY header rather than baked into the
        /// coordinates: if it turns out to be wrong, one header line can be edited
        /// after the trip without re-deriving the point cloud.
        ///
        /// NOTE — verify on device before trusting the sign. `CLHeading` is reported
        /// relative to the device axis implied by `headingOrientation`, and the phone
        /// is held near the singular attitude for a portrait compass reading. Point
        /// the camera along a passage of known bearing, tap SET N, and check the
        /// value against a hand compass.
        @objc func calibrateNorth() {
            guard let heading = currentHeading else {
                presentAlert(title: "No Compass", message: "No heading available yet.")
                return
            }
            guard heading.headingAccuracy >= 0,
                  heading.headingAccuracy <= Tuning.headingAccuracyLimit else {
                presentAlert(title: "Compass Not Ready",
                             message: String(format: "Heading accuracy is ±%.0f°. Move the phone in a figure-eight and try again.",
                                             heading.headingAccuracy))
                return
            }
            guard let transform = lastCameraTransform,
                  let cameraAzimuth = arkitAzimuthDegrees(of: cameraForward(from: transform)) else {
                presentAlert(title: "No Tracking", message: "Point the camera along the passage and try again.")
                return
            }

            let info = preferredHeading()
            let compass = info.value ?? heading.magneticHeading
            northOffsetDegrees = normalizedDegrees(compass - cameraAzimuth)
            northOffsetAccuracy = heading.headingAccuracy
            northReferenceIsTrue = info.isTrue

            updateNorthLabel()
            presentAlert(title: "North Set",
                         message: String(format: "Offset %.0f° (±%.0f°, %@).\nCheck against a hand compass before you rely on it.",
                                         northOffsetDegrees ?? 0,
                                         heading.headingAccuracy,
                                         northReferenceIsTrue ? "true" : "magnetic"))
        }

        /// The camera looks down its own -Z, so world-space forward is the negated
        /// third column of the transform.
        private func cameraForward(from transform: simd_float4x4) -> SIMD3<Float> {
            SIMD3<Float>(-transform.columns.2.x, -transform.columns.2.y, -transform.columns.2.z)
        }

        /// Azimuth of a world vector in the ARKit frame, degrees clockwise from -Z.
        /// Returns nil when the vector is (near) vertical and has no bearing.
        private func arkitAzimuthDegrees(of vector: SIMD3<Float>) -> Double? {
            let horizontal = SIMD2<Float>(vector.x, vector.z)
            guard simd_length(horizontal) > 1e-3 else { return nil }
            let radians = atan2(Double(vector.x), Double(-vector.z))
            return normalizedDegrees(radians * 180.0 / .pi)
        }

        private func normalizedDegrees(_ value: Double) -> Double {
            let wrapped = value.truncatingRemainder(dividingBy: 360)
            return wrapped < 0 ? wrapped + 360 : wrapped
        }


        // MARK: Heading

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            currentHeading = newHeading
            updateHeadingLabel()
        }

        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
            if let h = currentHeading {
                return h.headingAccuracy < 0 || h.headingAccuracy > 15
            }
            return true
        }

        private func preferredHeading() -> (value: Double?, isTrue: Bool, accuracy: CLLocationDirection?) {
            guard let h = currentHeading else { return (nil, false, nil) }
            if h.headingAccuracy >= 0, h.trueHeading >= 0 {
                return (h.trueHeading, true, h.headingAccuracy)
            }
            let accuracy = h.headingAccuracy >= 0 ? h.headingAccuracy : nil
            return (h.magneticHeading, false, accuracy)
        }


        // MARK: Labels

        private func label(_ tag: Int) -> UILabel? {
            arView?.viewWithTag(tag) as? UILabel
        }

        private func updateLabel() {
            label(101)?.text = String(format: "Distance: %.2f m", totalDistance)
        }

        private func updateDepthLabel() {
            guard let label = label(102) else { return }
            // Positive is below the session origin, which is the survey convention.
            let current = pathPoints.last?.depth ?? 0
            let deepest = pathPoints.map(\.depth).max() ?? 0
            label.text = String(format: "Depth: %.2f m (max %.2f)", current, deepest)
        }

        private func updateTrackingStateLabel(_ trackingState: ARCamera.TrackingState) {
            guard let label = label(103) else { return }

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

            label.text = text + trackingSuffix()
            label.textColor = color
        }

        private func updateTrackingDetailLabels() {
            guard let label = label(103), let text = label.text else { return }
            let base = text.components(separatedBy: "  ").first ?? text
            label.text = base + trackingSuffix()
        }

        private func trackingSuffix() -> String {
            guard trackingGapCount > 0 || rejectedJumpCount > 0 else { return "" }
            return String(format: "  gaps:%d jumps:%d", trackingGapCount, rejectedJumpCount)
        }

        /// Reports the residual of the last loop closure — an actual measurement of
        /// accumulated error. The old "drift" readout showed
        /// `travelled − straight-line`, which is just how much the passage bends and
        /// turned red on every perfectly good curving survey.
        private func updateClosureLabel() {
            guard let label = label(104) else { return }
            guard let residual = lastClosureResidual else {
                label.text = loopClosureEnabled ? "Closure: none yet" : "Closure: off"
                label.textColor = .white
                return
            }
            label.text = String(format: "Closure: %.2f m", residual)
            if residual < 0.2 {
                label.textColor = .green
            } else if residual < 0.5 {
                label.textColor = .orange
            } else {
                label.textColor = .red
            }
        }

        private func updateHeadingLabel() {
            guard let label = label(105) else { return }
            let info = preferredHeading()
            guard let value = info.value else {
                label.text = "Heading: --"
                label.textColor = .white
                return
            }
            let suffix = info.isTrue ? "T" : "M"
            guard let accuracy = info.accuracy else {
                label.text = String(format: "Heading: %.0f° (unknown) %@", value, suffix)
                label.textColor = .red
                return
            }
            label.text = String(format: "Heading: %.0f° (±%.0f°) %@", value, accuracy, suffix)
            if accuracy <= 5 {
                label.textColor = .green
            } else if accuracy <= 15 {
                label.textColor = .orange
            } else {
                label.textColor = .red
            }
        }

        private func updateNorthLabel() {
            guard let label = label(106) else { return }
            guard let offset = northOffsetDegrees else {
                label.text = "North: not set"
                label.textColor = .orange
                return
            }
            label.text = String(format: "North: %.0f° ±%.0f° %@",
                                offset,
                                northOffsetAccuracy ?? -1,
                                northReferenceIsTrue ? "T" : "M")
            label.textColor = .green
        }


        // MARK: Export

        @objc func stopSession() {
            if isSessionActive {
                isSessionActive = false
                stopButton?.isEnabled = false
                stopButton?.setTitle("…", for: .normal)

                export { [weak self] result in
                    guard let self = self else { return }
                    self.stopButton?.isEnabled = true
                    self.stopButton?.setTitle("EXIT", for: .normal)
                    switch result {
                    case .success(let summary):
                        // A dive or a trip cannot be repeated. Never let a failed
                        // write disappear into a console log.
                        self.deleteAutosave()
                        self.presentAlert(title: "Survey Saved", message: summary)
                    case .failure(let error):
                        self.presentAlert(title: "SAVE FAILED",
                                          message: "\(error.localizedDescription)\n\nDo not exit — an autosave may still exist in Files › On My iPhone › cave-mapper.")
                    }
                }
            } else {
                // Stop the camera before tearing the view down.
                arView?.session.pause()
                UIApplication.shared.isIdleTimerDisabled = false
                arView?.parentViewController()?.dismiss(animated: true)
            }
        }

        private func export(completion: @escaping (Result<String, Error>) -> Void) {
            let snapshot = makeSnapshot()

            exportQueue.async {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let name = "pointcloud_\(formatter.string(from: Date())).ply"

                do {
                    let url = try Self.writePLY(snapshot, fileName: name)
                    let summary = """
                    \(name)

                    Centerline points: \(snapshot.path.count)
                    Wall points: \(snapshot.features.count)
                    Length: \(String(format: "%.1f", snapshot.totalDistance)) m
                    Tracking gaps: \(snapshot.trackingGaps)

                    Files › On My iPhone › cave-mapper
                    """
                    print("✅ Saved PLY to \(url.path)")
                    DispatchQueue.main.async { completion(.success(summary)) }
                } catch {
                    print("❌ PLY export failed: \(error)")
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        /// Immutable copy of everything the writer needs, so export runs off the
        /// main thread without racing the capture loop.
        private struct Snapshot {
            var path: [PathPoint]
            var features: [SIMD3<Float>]
            var comments: [Int: String]
            var totalDistance: Float
            var trackingGaps: Int
            var northOffset: Double?
            var northAccuracy: CLLocationDirection?
            var northIsTrue: Bool
        }

        private func makeSnapshot() -> Snapshot {
            // Comments are keyed by path index, so dropping a point has to renumber
            // them in the same pass or every annotation after the gap would attach
            // itself to the wrong station.
            var path: [PathPoint] = []
            var comments: [Int: String] = [:]
            path.reserveCapacity(pathPoints.count)
            for (originalIndex, point) in pathPoints.enumerated() {
                guard Self.isPlausible(point.position) else { continue }
                if let text = commentsByPathIndex[originalIndex] {
                    comments[path.count] = text
                }
                path.append(point)
            }

            return Snapshot(path: path,
                     features: filteredFeaturePoints(),
                     comments: comments,
                     totalDistance: totalDistance,
                     trackingGaps: trackingGapCount,
                     northOffset: northOffsetDegrees,
                     northAccuracy: northOffsetAccuracy,
                     northIsTrue: northReferenceIsTrue)
        }

        /// A non-finite or absurd coordinate would either trap in the `Int32`
        /// conversion used for voxel keys or land in the file as the literal text
        /// "nan", which makes the whole PLY unreadable. Either way the survey would
        /// be lost at the moment it is written, so such points are dropped.
        private static func isPlausible(_ p: SIMD3<Float>) -> Bool {
            let limit: Float = 100_000
            return p.x.isFinite && p.y.isFinite && p.z.isFinite
                && abs(p.x) < limit && abs(p.y) < limit && abs(p.z) < limit
        }

        /// Applies the observation-count filter and collapses the survivors onto a
        /// voxel grid. Raw ARKit features include a great many transient points that
        /// were never real geometry; exporting them makes the wall cloud noisier and
        /// the file far larger for no gain.
        private func filteredFeaturePoints() -> [SIMD3<Float>] {
            let voxel = Tuning.featureVoxelSize
            var occupied = Set<SIMD3<Int32>>()
            var result: [SIMD3<Float>] = []
            result.reserveCapacity(featureObservations.count / 2)

            for observation in featureObservations.values
            where observation.count >= Tuning.minFeatureObservations
                && Self.isPlausible(observation.position) {
                let key = SIMD3<Int32>(Int32(floor(observation.position.x / voxel)),
                                       Int32(floor(observation.position.y / voxel)),
                                       Int32(floor(observation.position.z / voxel)))
                if occupied.insert(key).inserted {
                    result.append(observation.position)
                }
            }
            return result
        }

        private static func writePLY(_ snapshot: Snapshot, fileName: String) throws -> URL {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "cave-mapper", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Documents folder unavailable"])
            }
            let url = docs.appendingPathComponent(fileName)

            guard let stream = OutputStream(url: url, append: false) else {
                throw NSError(domain: "cave-mapper", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not open \(url.lastPathComponent) for writing"])
            }
            stream.open()
            defer { stream.close() }

            let sortedComments = snapshot.comments.sorted { $0.key < $1.key }
            var commentIDByPathIndex: [Int: Int] = [:]
            for (id, pair) in sortedComments.enumerated() {
                commentIDByPathIndex[pair.key] = id
            }

            var header = """
            ply
            format ascii 1.0
            comment generated by CaveDiveMap VIO
            comment world_alignment gravity
            comment vertical_axis y
            comment depth_sign positive_down
            comment bearing_convention atan2(x,-z)_degrees_plus_north_offset

            """

            if let offset = snapshot.northOffset {
                header += "comment north_offset_deg \(String(format: "%.2f", offset))\n"
                header += "comment north_offset_accuracy_deg \(String(format: "%.1f", snapshot.northAccuracy ?? -1))\n"
                header += "comment north_reference \(snapshot.northIsTrue ? "true" : "magnetic")\n"
            }
            header += "comment total_distance_m \(String(format: "%.3f", snapshot.totalDistance))\n"
            header += "comment tracking_gaps \(snapshot.trackingGaps)\n"

            for (id, pair) in sortedComments.enumerated() {
                header += "comment annotation id=\(id) vertex_index=\(pair.key) text=\(sanitizeForPLYComment(pair.value))\n"
            }

            header += """
            element vertex \(snapshot.path.count + snapshot.features.count)
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            property float depth
            property float heading
            property int comment_id
            property int segment
            end_header

            """

            // The previous writer emitted a blank line before end_header whenever a
            // comment existed, which is not valid PLY: plyfile, CloudCompare, MeshLab
            // and Open3D all refuse the file. Only the in-app parser tolerated it,
            // so the breakage was invisible on the phone.
            var buffer = header
            buffer.reserveCapacity(1 << 16)
            var bufferedRows = 0
            let rowsPerFlush = 2048

            // Row counting rather than `buffer.utf8.count`: measuring the string's
            // length is O(n), so checking it after every row would make the whole
            // export quadratic in the size of the cloud.
            func flushIfNeeded(force: Bool = false) throws {
                guard force || bufferedRows >= rowsPerFlush else { return }
                try write(buffer, to: stream)
                buffer.removeAll(keepingCapacity: true)
                bufferedRows = 0
            }

            // Integers go through interpolation rather than %d: Swift's Int is
            // 64-bit and %d expects a 32-bit value in the varargs ABI.
            for (index, point) in snapshot.path.enumerated() {
                let commentID = commentIDByPathIndex[index] ?? -1
                buffer += String(format: "%.4f %.4f %.4f 255 255 0 %.2f %.0f ",
                                 point.position.x, point.position.y, point.position.z,
                                 point.depth, point.heading)
                buffer += "\(commentID) \(point.segment)\n"
                bufferedRows += 1
                try flushIfNeeded()
            }

            for feature in snapshot.features {
                buffer += String(format: "%.4f %.4f %.4f 0 255 255 -1.0 -1 -1 -1\n",
                                 feature.x, feature.y, feature.z)
                bufferedRows += 1
                try flushIfNeeded()
            }

            try flushIfNeeded(force: true)
            return url
        }

        /// `OutputStream.write` may accept fewer bytes than offered; the previous
        /// code assumed a single full write, which silently truncates large files.
        private static func write(_ string: String, to stream: OutputStream) throws {
            let bytes = Array(string.utf8)
            var offset = 0
            while offset < bytes.count {
                let written = bytes.withUnsafeBufferPointer { buffer -> Int in
                    stream.write(buffer.baseAddress! + offset, maxLength: bytes.count - offset)
                }
                guard written > 0 else {
                    throw stream.streamError ?? NSError(domain: "cave-mapper", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Write failed (disk full?)"])
                }
                offset += written
            }
        }

        /// PLY headers must be single-line ASCII, but simply discarding everything
        /// else loses real content: a comment written in Cyrillic would reduce to
        /// an empty string and then vanish entirely, because the reader skips
        /// annotations with no text.
        ///
        /// Percent-encoding keeps the header ASCII while preserving the comment
        /// exactly. Encoding spaces too means the value is a single whitespace-free
        /// token, so the reader cannot mis-split it either.
        private static func sanitizeForPLYComment(_ s: String) -> String {
            let flattened = s.replacingOccurrences(of: "\n", with: " ")
                             .replacingOccurrences(of: "\r", with: " ")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return flattened.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }


        // MARK: Autosave

        /// Periodic dump so a crash, a battery pull or a mis-tap costs at most one
        /// interval of survey rather than the whole trip.
        private func autosave(force: Bool, now: TimeInterval = 0) {
            if !force {
                guard now - lastAutosaveTime >= Tuning.autosaveInterval else { return }
            }
            // The interval only advances once a write is actually started, so a
            // skipped attempt does not silently consume the slot and stretch the
            // real autosave gap to twice the interval.
            guard !isWritingAutosave, !pathPoints.isEmpty else { return }
            if !force { lastAutosaveTime = now }

            isWritingAutosave = true
            let snapshot = makeSnapshot()
            exportQueue.async { [weak self] in
                let url = try? Self.writePLY(snapshot, fileName: "autosave_current.ply")
                DispatchQueue.main.async {
                    self?.autosaveURL = url
                    self?.isWritingAutosave = false
                }
            }
        }

        private func deleteAutosave() {
            guard let url = autosaveURL else { return }
            try? FileManager.default.removeItem(at: url)
            autosaveURL = nil
        }


        // MARK: Comments

        @objc func promptForComment() {
            guard let vc = arView?.parentViewController() else { return }
            guard !pathPoints.isEmpty else {
                presentAlert(title: "Nothing to Annotate", message: "No path points recorded yet.")
                return
            }

            let alert = UIAlertController(title: "Add Comment",
                                          message: "Will attach to last path point (#\(pathPoints.count - 1)).",
                                          preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "Your comment"
                tf.autocapitalizationType = .sentences
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                guard let self = self else { return }
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return }
                self.addComment(text)
            })
            vc.safePresent(alert)
        }

        private func addComment(_ text: String) {
            let index = pathPoints.count - 1
            commentsByPathIndex[index] = text

            if let arView = arView, let position = pathPoints.last?.position {
                let sphere = MeshResource.generateSphere(radius: 0.02)
                let entity = ModelEntity(mesh: sphere, materials: [UnlitMaterial(color: .magenta)])
                let anchor = AnchorEntity(world: position)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
            }
            print("📝 Comment attached to path point \(index): \(text)")
        }

        private func presentAlert(title: String, message: String) {
            guard let vc = arView?.parentViewController() else { return }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.safePresent(alert)
        }


        // MARK: Reset

        @objc func resetSession() {
            guard let arView = arView else { return }
            arView.scene.anchors.removeAll()

            pathPoints.removeAll()
            markerAnchors.removeAll()
            previousPosition = nil
            previousAcceptedTime = nil
            previousAnchor = nil
            totalDistance = 0.0
            originY = nil
            currentSegment = 0
            needsNewSegment = true
            trackingGapCount = 0
            rejectedJumpCount = 0
            lastClosureResidual = nil
            commentsByPathIndex.removeAll()

            // This used to be left behind, so the next survey exported the previous
            // one's wall points in a coordinate frame that no longer existed.
            featureObservations.removeAll()

            featurePointEntities.values.forEach { $0.removeFromParent() }
            featurePointEntities.removeAll()
            featurePointOrder.removeAll()
            featurePointAnchor = AnchorEntity()
            arView.scene.addAnchor(featurePointAnchor)

            isSessionActive = true
            updateLabel()
            updateDepthLabel()
            updateClosureLabel()
        }


        // MARK: Live feature overlay (optional)

        private func visualizeFeaturePoints(_ cloud: ARPointCloud, cameraPosition: SIMD3<Float>) {
            let samplingRate = 10
            let maxRenderedPoints = 2_000
            let keepRadius: Float = 10.0

            for (i, id) in cloud.identifiers.enumerated() {
                guard i % samplingRate == 0, featurePointEntities[id] == nil else { continue }

                let point = cloud.points[i]
                if simd_distance(point, cameraPosition) > keepRadius { continue }

                let entity = ModelEntity(mesh: .generateBox(size: 0.003),
                                         materials: [UnlitMaterial(color: .cyan)])
                entity.position = point
                featurePointAnchor.addChild(entity)
                featurePointEntities[id] = entity
                featurePointOrder.append(id)
            }

            // Evict oldest-first. The old loop evaluated a live `count` inside a
            // snapshot iteration and removed points in hash order, so which points
            // survived was arbitrary and varied run to run.
            while featurePointOrder.count > maxRenderedPoints {
                let id = featurePointOrder.removeFirst()
                featurePointEntities.removeValue(forKey: id)?.removeFromParent()
            }
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
