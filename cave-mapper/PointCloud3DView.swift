import SwiftUI
import SceneKit

// Public SwiftUI view you can embed in your UI
struct PointCloud3DView: View {
    let points: [Point3D]
    let centerline: [Point3D]
    var tubeRadius: CGFloat = 0.5        // fallback/base radius in meters
    var tubeSides: Int = 14              // segments around the tube
    var showAxes: Bool = true
    var showGrid: Bool = false
    var buildTunnelMesh: Bool = true
    var useVariableRadius: Bool = true   // derive radius from wall distances

    @Binding var tunnelOpacity: CGFloat

    var body: some View {
        SceneKitContainer(points: points,
                          centerline: centerline,
                          tubeRadius: tubeRadius,
                          tubeSides: tubeSides,
                          showAxes: showAxes,
                          showGrid: showGrid,
                          buildTunnelMesh: buildTunnelMesh,
                          useVariableRadius: useVariableRadius,
                          tunnelOpacity: tunnelOpacity)
            .ignoresSafeArea(.all, edges: .bottom)
    }
}

private let tunnelNodeName = "tunnel"

// UIViewRepresentable wrapper around SCNView so we can use SceneKit in SwiftUI
private struct SceneKitContainer: UIViewRepresentable {
    let points: [Point3D]
    let centerline: [Point3D]
    let tubeRadius: CGFloat
    let tubeSides: Int
    let showAxes: Bool
    let showGrid: Bool
    let buildTunnelMesh: Bool
    let useVariableRadius: Bool
    let tunnelOpacity: CGFloat

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor.systemBackground
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 85
        view.antialiasingMode = .multisampling4X

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.resetCamera))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        context.coordinator.view = view
        view.scene = buildScene()
        context.coordinator.lastSignature = geometrySignature
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Rebuilding the whole scene on every SwiftUI update meant that dragging
        // the opacity slider re-triangulated the tunnel and re-uploaded the point
        // cloud on the main thread, once per frame of the drag.
        if context.coordinator.lastSignature != geometrySignature {
            uiView.scene = buildScene()
            context.coordinator.lastSignature = geometrySignature
            return
        }
        applyTunnelOpacity(to: uiView.scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var lastSignature: Int = 0

        @objc func resetCamera() {
            guard let cam = view?.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            cam.position = SCNVector3(0, 0, 10)
            cam.orientation = SCNQuaternion(0, 0, 0, 1)
            SCNTransaction.commit()
            view?.defaultCameraController.target = SCNVector3Zero
        }
    }

    /// Everything except opacity, which can be applied without rebuilding.
    private var geometrySignature: Int {
        var hasher = Hasher()
        hasher.combine(points.count)
        hasher.combine(centerline.count)
        hasher.combine(tubeRadius)
        hasher.combine(tubeSides)
        hasher.combine(showAxes)
        hasher.combine(showGrid)
        hasher.combine(buildTunnelMesh)
        hasher.combine(useVariableRadius)
        if let first = centerline.first { hasher.combine(first.x); hasher.combine(first.z) }
        if let last = centerline.last { hasher.combine(last.x); hasher.combine(last.z) }
        return hasher.finalize()
    }

    private func applyTunnelOpacity(to scene: SCNScene?) {
        guard let node = scene?.rootNode.childNode(withName: tunnelNodeName, recursively: true),
              let material = node.geometry?.firstMaterial else { return }
        let alpha = max(0.0, min(1.0, tunnelOpacity))
        material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(alpha)
        material.emission.contents = UIColor.systemTeal.withAlphaComponent(alpha * 0.4)
    }

    // MARK: - Scene construction

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 10_000
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = UIColor(white: 0.65, alpha: 1.0)
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        dir.light?.intensity = 800
        scene.rootNode.addChildNode(dir)

        if showGrid {
            scene.rootNode.addChildNode(makeGridNode(size: 50, step: 1))
        }
        if showAxes {
            scene.rootNode.addChildNode(makeAxesNode(length: 2.0, thickness: 0.02))
        }
        if let cloudNode = makePointCloudNode(points) {
            scene.rootNode.addChildNode(cloudNode)
        }
        if buildTunnelMesh,
           let tube = makeTunnelMeshNode(centerline: centerline,
                                         points: points,
                                         baseRadius: tubeRadius,
                                         sides: tubeSides,
                                         variableRadius: useVariableRadius,
                                         opacity: tunnelOpacity) {
            scene.rootNode.addChildNode(tube)
        }

        // Centre on the survey data. Using the root node's bounding box also folded
        // in the axes and the 50 m grid, pulling the camera away from the cave.
        if !points.isEmpty {
            var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for p in points {
                let v = SIMD3<Float>(p.x, p.y, p.z)
                minV = simd_min(minV, v)
                maxV = simd_max(maxV, v)
            }
            let centre = (minV + maxV) * 0.5
            scene.rootNode.position = SCNVector3(-centre.x, -centre.y, -centre.z)
        }

        return scene
    }

    // MARK: - Geometry builders

    private func makePointCloudNode(_ pts: [Point3D]) -> SCNNode? {
        guard !pts.isEmpty else { return nil }

        let positions = pts.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let colors = pts.map { $0.color }

        let posData = positions.withUnsafeBytes { Data($0) }
        let colData = colors.withUnsafeBytes { Data($0) }

        let positionSource = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let colorSource = SCNGeometrySource(
            data: colData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let indices = Array(0..<UInt32(positions.count))
        let indexData = indices.withUnsafeBytes { Data($0) }

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        let geom = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = true
        mat.readsFromDepthBuffer = true
        mat.diffuse.contents = UIColor.white
        geom.firstMaterial = mat

        geom.setValue(NSNumber(value: 3.0), forKey: "pointSize")
        geom.setValue(NSNumber(value: 1), forKey: "pointSizeAttenuation")

        return SCNNode(geometry: geom)
    }

    private func makeTunnelMeshNode(centerline: [Point3D],
                                    points: [Point3D],
                                    baseRadius: CGFloat,
                                    sides: Int,
                                    variableRadius: Bool,
                                    opacity: CGFloat) -> SCNNode? {
        guard centerline.count >= 2, sides >= 3 else { return nil }

        let wallPoints = points.filter { !isCenterlinePoint($0) }
        let wallPositions = wallPoints.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let grid = SpatialGrid(points: wallPositions, cellSize: 1.0)

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // A tracking gap means the two sides were never connected by a surveyed
        // passage, so each contiguous run gets its own tube rather than one tube
        // stretched across the void.
        for run in contiguousRuns(of: centerline) where run.count >= 2 {
            appendTube(for: run,
                       grid: grid,
                       wallPositions: wallPositions,
                       baseRadius: Float(baseRadius),
                       sides: sides,
                       variableRadius: variableRadius,
                       vertices: &vertices,
                       indices: &indices)
        }

        guard !indices.isEmpty else { return nil }

        let posData = vertices.withUnsafeBytes { Data($0) }
        let positionSource = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        let geom = SCNGeometry(sources: [positionSource], elements: [element])
        let alpha = max(0.0, min(1.0, opacity))
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.systemTeal.withAlphaComponent(alpha)
        m.emission.contents = UIColor.systemTeal.withAlphaComponent(alpha * 0.4)
        m.isDoubleSided = true
        m.lightingModel = .physicallyBased
        geom.firstMaterial = m

        let node = SCNNode(geometry: geom)
        node.name = tunnelNodeName
        return node
    }

    private func contiguousRuns(of centerline: [Point3D]) -> [[Point3D]] {
        var runs: [[Point3D]] = []
        var current: [Point3D] = []
        for p in centerline {
            if let last = current.last, last.segment != p.segment {
                runs.append(current)
                current = []
            }
            current.append(p)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private func appendTube(for run: [Point3D],
                            grid: SpatialGrid,
                            wallPositions: [SIMD3<Float>],
                            baseRadius: Float,
                            sides: Int,
                            variableRadius: Bool,
                            vertices: inout [SIMD3<Float>],
                            indices: inout [UInt32]) {
        let positions = run.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let tangents = (0..<positions.count).map { i -> SIMD3<Float> in
            let raw: SIMD3<Float>
            if i == 0 {
                raw = positions[1] - positions[0]
            } else if i == positions.count - 1 {
                raw = positions[i] - positions[i - 1]
            } else {
                raw = positions[i + 1] - positions[i - 1]
            }
            let length = simd_length(raw)
            return length > 1e-6 ? raw / length : SIMD3<Float>(0, 0, -1)
        }

        let radii = variableRadius
            ? crossSectionRadii(positions: positions, tangents: tangents,
                                grid: grid, wallPositions: wallPositions, fallback: baseRadius)
            : Array(repeating: baseRadius, count: positions.count)

        let firstVertex = UInt32(vertices.count)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let dTheta = Float.pi * 2 / Float(sides)

        for i in 0..<positions.count {
            let tangent = tangents[i]
            let refUp = abs(simd_dot(tangent, worldUp)) > 0.95 ? SIMD3<Float>(1, 0, 0) : worldUp
            let right = simd_normalize(simd_cross(tangent, refUp))
            let normal = simd_normalize(simd_cross(right, tangent))

            for s in 0..<sides {
                let theta = Float(s) * dTheta
                vertices.append(positions[i] + radii[i] * (cos(theta) * normal + sin(theta) * right))
            }
        }

        for i in 0..<(positions.count - 1) {
            let baseA = firstVertex + UInt32(i * sides)
            let baseB = firstVertex + UInt32((i + 1) * sides)
            for s in 0..<sides {
                let sNext = UInt32((s + 1) % sides)
                let s = UInt32(s)
                indices.append(contentsOf: [baseA + s, baseB + s, baseA + sNext])
                indices.append(contentsOf: [baseA + sNext, baseB + s, baseB + sNext])
            }
        }
    }

    // MARK: - Cross-section radius

    /// Estimates passage radius at each station from the wall points that lie in a
    /// thin slab perpendicular to the passage — which is what a cross-section is.
    ///
    /// The previous implementation scanned every wall point linearly for every
    /// station and stopped after the first 200 hits *in array order*, so the radius
    /// was a median over an arbitrary insertion-ordered subset rather than over the
    /// nearby geometry. It was also O(stations × walls) on the main thread.
    private func crossSectionRadii(positions: [SIMD3<Float>],
                                   tangents: [SIMD3<Float>],
                                   grid: SpatialGrid,
                                   wallPositions: [SIMD3<Float>],
                                   fallback: Float) -> [Float] {
        let searchRadius: Float = 5.0
        let slabHalfThickness: Float = 0.35
        let minSamples = 6
        let clampRange: (min: Float, max: Float) = (0.1, 5.0)
        let smoothWindow = 5

        guard !wallPositions.isEmpty else {
            return Array(repeating: fallback, count: positions.count)
        }

        var radii = [Float](repeating: fallback, count: positions.count)
        var radial: [Float] = []
        var nearby: [Float] = []

        for i in positions.indices {
            let centre = positions[i]
            let tangent = tangents[i]
            radial.removeAll(keepingCapacity: true)
            nearby.removeAll(keepingCapacity: true)

            grid.forEachNeighbour(of: centre, within: searchRadius) { index in
                let v = wallPositions[index] - centre
                let distance = simd_length(v)
                guard distance <= searchRadius else { return }
                nearby.append(distance)

                let along = simd_dot(v, tangent)
                guard abs(along) <= slabHalfThickness else { return }
                radial.append(simd_length(v - along * tangent))
            }

            // Prefer the cross-section slab; fall back to all nearby points, then to
            // the caller's default, so a sparse stretch still produces a tube.
            let samples = radial.count >= minSamples ? radial
                        : (nearby.count >= minSamples ? nearby : [])
            if samples.isEmpty {
                radii[i] = fallback
            } else {
                let sorted = samples.sorted()
                radii[i] = sorted[sorted.count / 2]
            }
            radii[i] = min(max(radii[i], clampRange.min), clampRange.max)
        }

        guard smoothWindow > 1, radii.count > 2 else { return radii }
        let half = smoothWindow / 2
        var smoothed = radii
        for i in radii.indices {
            let a = max(0, i - half)
            let b = min(radii.count - 1, i + half)
            smoothed[i] = radii[a...b].reduce(0, +) / Float(b - a + 1)
        }
        return smoothed
    }

    // MARK: - Helpers

    private func isCenterlinePoint(_ p: Point3D) -> Bool {
        p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
    }

    private func makeAxesNode(length: CGFloat, thickness: CGFloat) -> SCNNode {
        let node = SCNNode()

        func axis(_ color: UIColor, position: SCNVector3, euler: SCNVector3) -> SCNNode {
            let cylinder = SCNCylinder(radius: thickness, height: length)
            cylinder.firstMaterial?.diffuse.contents = color
            let child = SCNNode(geometry: cylinder)
            child.position = position
            child.eulerAngles = euler
            return child
        }

        node.addChildNode(axis(.red, position: SCNVector3(Float(length) / 2, 0, 0),
                               euler: SCNVector3(0, 0, Float.pi / 2)))
        node.addChildNode(axis(.green, position: SCNVector3(0, Float(length) / 2, 0),
                               euler: SCNVector3(0, 0, 0)))
        node.addChildNode(axis(.blue, position: SCNVector3(0, 0, Float(length) / 2),
                               euler: SCNVector3(Float.pi / 2, 0, 0)))
        return node
    }

    /// One geometry of line primitives rather than a few hundred SCNBox nodes.
    private func makeGridNode(size: CGFloat, step: CGFloat) -> SCNNode {
        let half = Float(size) / 2
        var vertices: [SIMD3<Float>] = []

        var i = -half
        while i <= half {
            vertices.append(SIMD3<Float>(-half, 0, i))
            vertices.append(SIMD3<Float>(half, 0, i))
            vertices.append(SIMD3<Float>(i, 0, -half))
            vertices.append(SIMD3<Float>(i, 0, half))
            i += Float(step)
        }

        let posData = vertices.withUnsafeBytes { Data($0) }
        let source = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride, dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride)

        let indices = Array(0..<UInt32(vertices.count))
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(data: indexData, primitiveType: .line,
                                         primitiveCount: indices.count / 2,
                                         bytesPerIndex: MemoryLayout<UInt32>.stride)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.secondaryLabel.withAlphaComponent(0.25)
        material.lightingModel = .constant
        geometry.firstMaterial = material

        return SCNNode(geometry: geometry)
    }
}

// MARK: - Spatial index

/// Uniform-grid hash over the wall cloud, so a station only tests points in its
/// own neighbourhood instead of the entire cloud.
private struct SpatialGrid {
    private let cellSize: Float
    private var cells: [SIMD3<Int32>: [Int]] = [:]

    init(points: [SIMD3<Float>], cellSize: Float) {
        self.cellSize = max(cellSize, 0.01)
        cells.reserveCapacity(points.count / 4 + 1)
        for (index, p) in points.enumerated() {
            cells[Self.key(for: p, cellSize: self.cellSize), default: []].append(index)
        }
    }

    private static func key(for p: SIMD3<Float>, cellSize: Float) -> SIMD3<Int32> {
        SIMD3<Int32>(Int32(floor(p.x / cellSize)),
                     Int32(floor(p.y / cellSize)),
                     Int32(floor(p.z / cellSize)))
    }

    func forEachNeighbour(of centre: SIMD3<Float>, within radius: Float, _ body: (Int) -> Void) {
        let span = Int32(ceil(radius / cellSize))
        let origin = Self.key(for: centre, cellSize: cellSize)
        for dx in -span...span {
            for dy in -span...span {
                for dz in -span...span {
                    let key = SIMD3<Int32>(origin.x + dx, origin.y + dy, origin.z + dz)
                    guard let bucket = cells[key] else { continue }
                    bucket.forEach(body)
                }
            }
        }
    }
}
