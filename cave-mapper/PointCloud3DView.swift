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

    // NEW: external control over tunnel opacity (0.0 ... 1.0)
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
        view.scene = buildScene()
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 85
        view.antialiasingMode = .multisampling4X

        // Double tap to reset camera
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.resetCamera))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Rebuild the scene when inputs change (including opacity)
        uiView.scene = buildScene()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
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

    // MARK: - Scene construction

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 10_000
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)

        // Lights
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = UIColor(white: 0.65, alpha: 1.0)
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/4, 0)
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

        // Frame to data center for better camera defaults
        let (minV, maxV) = scene.rootNode.boundingBox
        let center = SCNVector3((minV.x + maxV.x) * 0.5,
                                (minV.y + maxV.y) * 0.5,
                                (minV.z + maxV.z) * 0.5)
        scene.rootNode.position = SCNVector3(-center.x, -center.y, -center.z)

        return scene
    }

    // MARK: - Geometry builders

    // Efficient point cloud: single geometry with positions + per-vertex color
    private func makePointCloudNode(_ pts: [Point3D]) -> SCNNode? {
        guard !pts.isEmpty else { return nil }

        let positions = pts.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let colors = pts.map { $0.color } // already 0..1

        // SceneKit geometry sources
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

        // Indices for points 0..N-1
        let indices = Array(0..<positions.count).map { UInt32($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        let geom = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        // Point size hint (may require shader modifiers for full control on all devices)
        let mat = SCNMaterial()
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = true
        mat.readsFromDepthBuffer = true
        mat.diffuse.contents = UIColor.white
        geom.firstMaterial = mat

        // Best-effort point size controls (not guaranteed on all GPUs)
        geom.setValue(NSNumber(value: 3.0), forKey: "pointSize")
        geom.setValue(NSNumber(value: 1), forKey: "pointSizeAttenuation")

        let node = SCNNode(geometry: geom)
        return node
    }

    // Variable-radius tube mesh along centerline: sweep a circle with per-ring radius
    private func makeTunnelMeshNode(centerline: [Point3D],
                                    points: [Point3D],
                                    baseRadius: CGFloat,
                                    sides: Int,
                                    variableRadius: Bool,
                                    opacity: CGFloat) -> SCNNode? {
        guard centerline.count >= 2, sides >= 3 else { return nil }

        // Split walls vs centerline (yellow-ish are centerline)
        let isYellow: (Point3D) -> Bool = { p in
            p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
        }
        let wallPoints = points.filter { !isYellow($0) }

        // Compute per-ring radii from wall distances
        let radii: [Float]
        if variableRadius {
            radii = computeVariableRadii(centerline: centerline,
                                         wallPoints: wallPoints,
                                         fallback: Float(baseRadius),
                                         searchRadius: 5.0,
                                         minNeighbors: 10,
                                         maxNeighbors: 200,
                                         clamp: (min: 0.1, max: 5.0),
                                         smoothWindow: 5)
        } else {
            radii = Array(repeating: Float(baseRadius), count: centerline.count)
        }

        // Build rings
        var ringVertices: [[SIMD3<Float>]] = []
        ringVertices.reserveCapacity(centerline.count)

        let worldUp = SIMD3<Float>(0, 1, 0)
        let twoPi = Float.pi * 2
        let dTheta = twoPi / Float(sides)

        for i in 0..<centerline.count {
            let p = SIMD3<Float>(centerline[i].x, centerline[i].y, centerline[i].z)

            // Tangent direction
            let tangent: SIMD3<Float> = {
                if i == 0 {
                    let next = SIMD3<Float>(centerline[i+1].x, centerline[i+1].y, centerline[i+1].z)
                    return simd_normalize(next - p)
                } else if i == centerline.count - 1 {
                    let prev = SIMD3<Float>(centerline[i-1].x, centerline[i-1].y, centerline[i-1].z)
                    return simd_normalize(p - prev)
                } else {
                    let prev = SIMD3<Float>(centerline[i-1].x, centerline[i-1].y, centerline[i-1].z)
                    let next = SIMD3<Float>(centerline[i+1].x, centerline[i+1].y, centerline[i+1].z)
                    return simd_normalize(next - prev)
                }
            }()

            let refUp: SIMD3<Float> = abs(simd_dot(tangent, worldUp)) > 0.95 ? SIMD3<Float>(1, 0, 0) : worldUp
            let right = simd_normalize(simd_cross(tangent, refUp))
            let normal = simd_normalize(simd_cross(right, tangent))

            let r = radii[i]
            var ring: [SIMD3<Float>] = []
            ring.reserveCapacity(sides)

            for s in 0..<sides {
                let theta = Float(s) * dTheta
                let dir = cos(theta) * normal + sin(theta) * right
                let v = p + r * dir
                ring.append(v)
            }
            ringVertices.append(ring)
        }

        // Flatten vertices
        let vertices: [SIMD3<Float>] = ringVertices.flatMap { $0 }

        // Build indices for triangle strips between consecutive rings
        var indices: [UInt32] = []
        indices.reserveCapacity((centerline.count - 1) * sides * 6)

        let ringCount = centerline.count
        for i in 0..<(ringCount - 1) {
            let baseA = i * sides
            let baseB = (i + 1) * sides
            for s in 0..<sides {
                let sNext = (s + 1) % sides

                let a0 = UInt32(baseA + s)
                let a1 = UInt32(baseA + sNext)
                let b0 = UInt32(baseB + s)
                let b1 = UInt32(baseB + sNext)

                // Two triangles per quad
                indices.append(contentsOf: [a0, b0, a1])
                indices.append(contentsOf: [a1, b0, b1])
            }
        }

        // Geometry sources
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

        return SCNNode(geometry: geom)
    }

    // MARK: - Variable radius computation

    private func computeVariableRadii(centerline: [Point3D],
                                      wallPoints: [Point3D],
                                      fallback: Float,
                                      searchRadius: Float,
                                      minNeighbors: Int,
                                      maxNeighbors: Int,
                                      clamp: (min: Float, max: Float),
                                      smoothWindow: Int) -> [Float] {
        guard !centerline.isEmpty else { return [] }
        if wallPoints.isEmpty {
            return Array(repeating: fallback, count: centerline.count)
        }

        // Precompute wall positions
        let wallPos: [SIMD3<Float>] = wallPoints.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let sr2 = searchRadius * searchRadius

        var radii = [Float](repeating: fallback, count: centerline.count)

        for (i, c) in centerline.enumerated() {
            let cpos = SIMD3<Float>(c.x, c.y, c.z)

            // Gather neighbors within radius, early exit when enough found
            var dists: [Float] = []
            dists.reserveCapacity(min(maxNeighbors, 256))

            for p in wallPos {
                let d2 = simd_length_squared(p - cpos)
                if d2 <= sr2 {
                    dists.append(sqrt(d2))
                    if dists.count >= maxNeighbors { break }
                }
            }

            let r: Float
            if dists.count >= minNeighbors {
                dists.sort()
                // Median
                let mid = dists.count / 2
                r = dists[mid]
            } else if !dists.isEmpty {
                // Average if few
                r = dists.reduce(0, +) / Float(dists.count)
            } else {
                r = fallback
            }

            radii[i] = max(clamp.min, min(clamp.max, r))
        }

        // Smooth with moving average
        if smoothWindow > 1, radii.count > 2 {
            let half = smoothWindow / 2
            var smoothed = radii
            for i in 0..<radii.count {
                var sum: Float = 0
                var count: Int = 0
                let a = max(0, i - half)
                let b = min(radii.count - 1, i + half)
                for j in a...b {
                    sum += radii[j]
                    count += 1
                }
                smoothed[i] = sum / Float(count)
            }
            radii = smoothed
        }

        return radii
    }

    // MARK: - Helpers

    private func makeAxesNode(length: CGFloat, thickness: CGFloat) -> SCNNode {
        let node = SCNNode()

        let x = SCNCylinder(radius: thickness, height: length)
        x.firstMaterial?.diffuse.contents = UIColor.red
        let xNode = SCNNode(geometry: x)
        xNode.position = SCNVector3(length/2, 0, 0)
        xNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.addChildNode(xNode)

        let y = SCNCylinder(radius: thickness, height: length)
        y.firstMaterial?.diffuse.contents = UIColor.green
        let yNode = SCNNode(geometry: y)
        yNode.position = SCNVector3(0, length/2, 0)
        node.addChildNode(yNode)

        let z = SCNCylinder(radius: thickness, height: length)
        z.firstMaterial?.diffuse.contents = UIColor.blue
        let zNode = SCNNode(geometry: z)
        zNode.position = SCNVector3(0, 0, length/2)
        zNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.addChildNode(zNode)

        return node
    }

    private func makeGridNode(size: CGFloat, step: CGFloat) -> SCNNode {
        let parent = SCNNode()
        let half = size / 2

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.secondaryLabel.withAlphaComponent(0.25)
        material.isDoubleSided = true
        material.lightingModel = .constant

        // Build many thin lines along X and Z on Y=0 plane
        var i = -half
        while i <= half {
            // Line parallel to X (vary Z)
            let geomX = SCNBox(width: size, height: 0.001, length: 0.001, chamferRadius: 0)
            geomX.firstMaterial = material
            let nodeX = SCNNode(geometry: geomX)
            nodeX.position = SCNVector3(0, 0, Float(i))
            parent.addChildNode(nodeX)

            // Line parallel to Z (vary X)
            let geomZ = SCNBox(width: 0.001, height: 0.001, length: size, chamferRadius: 0)
            geomZ.firstMaterial = material
            let nodeZ = SCNNode(geometry: geomZ)
            nodeZ.position = SCNVector3(Float(i), 0, 0)
            parent.addChildNode(nodeZ)

            i += step
        }
        return parent
    }
}

// MARK: - Small math helpers

// Unary negation for SCNVector3
prefix func - (v: SCNVector3) -> SCNVector3 {
    SCNVector3(-v.x, -v.y, -v.z)
}

private extension SCNVector3 {
    static func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(a.x * s, a.y * s, a.z * s) }
}

private extension SIMD3 where Scalar == Float {
    static func + (a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> { SIMD3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> { SIMD3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: SIMD3<Float>, s: Float) -> SIMD3<Float> { SIMD3(a.x * s, a.y * s, a.z * s) }
}
