import SwiftUI
import SceneKit

// Public SwiftUI view you can embed in your UI
struct PointCloud3DView: View {
    let points: [Point3D]
    let centerline: [Point3D]
    var tubeRadius: CGFloat = 0.5        // meters
    var tubeSides: Int = 14              // segments around the tube
    var showAxes: Bool = true
    var showGrid: Bool = false
    var buildTunnelMesh: Bool = true

    var body: some View {
        SceneKitContainer(points: points,
                          centerline: centerline,
                          tubeRadius: tubeRadius,
                          tubeSides: tubeSides,
                          showAxes: showAxes,
                          showGrid: showGrid,
                          buildTunnelMesh: buildTunnelMesh)
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
        // If you need to rebuild on changes, do it here:
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
        dir.eulerAngles = SCNVector3(-.pi/3, .pi/4, 0)
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

        if buildTunnelMesh, let tube = makeTunnelMeshNode(centerline: centerline,
                                                          radius: tubeRadius,
                                                          sides: tubeSides) {
            scene.rootNode.addChildNode(tube)
        }

        // Frame to data center for better camera defaults
        if let bounds = scene.rootNode.boundingBoxIfValid {
            let center = (bounds.min + bounds.max) * 0.5
            scene.rootNode.position = -center
        }

        return scene
    }

    // MARK: - Geometry builders

    // Efficient point cloud: single geometry with positions + per-vertex color
    private func makePointCloudNode(_ pts: [Point3D]) -> SCNNode? {
        guard !pts.isEmpty else { return nil }

        let positions = pts.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let colors = pts.map { $0.color } // already 0..1

        // SceneKit geometry sources
        let posData = Data(bytes: positions, count: MemoryLayout<SIMD3<Float>>.stride * positions.count)
        let colData = Data(bytes: colors, count: MemoryLayout<SIMD3<Float>>.stride * colors.count)

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
        var indices = Array(0..<positions.count).map { UInt32($0) }
        let indexData = Data(bytes: &indices, count: MemoryLayout<UInt32>.stride * indices.count)

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        let geom = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        // Point size (SceneKit pointSize is in pixels; enable pointSizeAttenuation for distance scaling)
        geom.firstMaterial = {
            let m = SCNMaterial()
            m.isDoubleSided = true
            m.lightingModel = .constant
            m.writesToDepthBuffer = true
            m.readsFromDepthBuffer = true
            // Enable per-vertex color
            m.diffuse.contents = UIColor.white
            return m
        }()

        // SceneKit has a material property for point size through shader modifiers or geometry property
        // Use a simple approach: set geometry pointSize via key
        geom.setValue(NSNumber(value: 3.0), forKey: "pointSize")
        geom.setValue(NSNumber(value: 1), forKey: "pointSizeAttenuation")

        let node = SCNNode(geometry: geom)
        return node
    }

    // Tube mesh along centerline: sweep a circle along the path
    private func makeTunnelMeshNode(centerline: [Point3D], radius: CGFloat, sides: Int) -> SCNNode? {
        guard centerline.count >= 2, sides >= 3 else { return nil }

        // Build rings
        var ringVertices: [[SIMD3<Float>]] = []
        ringVertices.reserveCapacity(centerline.count)

        // A simple, robust frame: use world up as reference and compute right/normal
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

            // If tangent is nearly parallel to worldUp, choose another up to avoid instability
            let refUp: SIMD3<Float> = abs(simd_dot(tangent, worldUp)) > 0.95 ? SIMD3<Float>(1, 0, 0) : worldUp

            let right = simd_normalize(simd_cross(tangent, refUp))
            let normal = simd_normalize(simd_cross(right, tangent))

            var ring: [SIMD3<Float>] = []
            ring.reserveCapacity(sides)

            for s in 0..<sides {
                let theta = Float(s) * dTheta
                let dir = cos(theta) * normal + sin(theta) * right
                let v = p + Float(radius) * dir
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
        let posData = Data(bytes: vertices, count: MemoryLayout<SIMD3<Float>>.stride * vertices.count)
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

        let indexData = Data(bytes: indices, count: MemoryLayout<UInt32>.stride * indices.count)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        let geom = SCNGeometry(sources: [positionSource], elements: [element])
        geom.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.35)
            m.emission.contents = UIColor.systemTeal.withAlphaComponent(0.15)
            m.isDoubleSided = true
            m.lightingModel = .physicallyBased
            return m
        }()

        return SCNNode(geometry: geom)
    }

    // MARK: - Helpers

    private func makeAxesNode(length: CGFloat, thickness: CGFloat) -> SCNNode {
        let node = SCNNode()

        let x = SCNCylinder(radius: thickness, height: length)
        x.firstMaterial?.diffuse.contents = UIColor.red
        let xNode = SCNNode(geometry: x)
        xNode.position = SCNVector3(length/2, 0, 0)
        xNode.eulerAngles = SCNVector3(0, 0, .pi/2)
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
        zNode.eulerAngles = SCNVector3(.pi/2, 0, 0)
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
        for i in stride(from: -half, through: half, by: step) {
            // Line parallel to X (vary Z)
            let geomX = SCNBox(width: size, height: 0.001, length: 0.001, chamferRadius: 0)
            geomX.firstMaterial = material
            let nodeX = SCNNode(geometry: geomX)
            nodeX.position = SCNVector3(0, 0, i)
            parent.addChildNode(nodeX)

            // Line parallel to Z (vary X)
            let geomZ = SCNBox(width: 0.001, height: 0.001, length: size, chamferRadius: 0)
            geomZ.firstMaterial = material
            let nodeZ = SCNNode(geometry: geomZ)
            nodeZ.position = SCNVector3(i, 0, 0)
            parent.addChildNode(nodeZ)
        }
        return parent
    }
}

// MARK: - Small math helpers

private extension (min: SCNVector3, max: SCNVector3) {
    static func + (lhs: (min: SCNVector3, max: SCNVector3), rhs: (min: SCNVector3, max: SCNVector3)) -> (min: SCNVector3, max: SCNVector3) {
        return (lhs.min + rhs.min, lhs.max + rhs.max)
    }
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

private extension SCNNode {
    var boundingBoxIfValid: (min: SCNVector3, max: SCNVector3)? {
        var minV = SCNVector3Zero
        var maxV = SCNVector3Zero
        let ok = getBoundingBoxMin(&minV, max: &maxV)
        return ok ? (minV, maxV) : nil
    }
}
