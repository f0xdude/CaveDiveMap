import SwiftUI
import SceneKit

// MARK: - SCNVector3 Helpers

extension SCNVector3 {
    static func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
    
    static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }
    
    static func *(lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
    
    func length() -> Float {
        sqrt(x*x + y*y + z*z)
    }
    
    func normalized() -> SCNVector3 {
        let len = length()
        return len > 0 ? self * (1/len) : self
    }
    
    func cross(_ vec: SCNVector3) -> SCNVector3 {
        SCNVector3(
            y * vec.z - z * vec.y,
            z * vec.x - x * vec.z,
            x * vec.y - y * vec.x
        )
    }
}
  
// MARK: - 3D Tunnel View

/// A SwiftUI view that builds a 3D SceneKit scene showing an extruded tunnel
struct ThreeDMapView: View {
    @State private var mapData: [SavedData] = [] // your saved survey data
    
    // A conversion factor to scale your measurements to SceneKit units
    private let conversionFactor: CGFloat = 20.0
    
    var body: some View {
        SceneView(
            scene: buildScene(),
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .onAppear {
            loadMapData()
        }
    }
    
    /// Build the SceneKit scene
    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        
        // Add a camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 10, z: 30)
        scene.rootNode.addChildNode(cameraNode)
        
        // Create and add the tunnel geometry node
        if let tunnelGeometry = createTunnelGeometry() {
            let tunnelNode = SCNNode(geometry: tunnelGeometry)
            scene.rootNode.addChildNode(tunnelNode)
        }
        
        return scene
    }
    
    /// Build the tunnel geometry from your survey data.
    /// This example uses only the "manual" survey points.
    private func createTunnelGeometry() -> SCNGeometry? {
        // Filter for manual survey shots (which have the cross-section measurements)
        let manualData = mapData.filter { $0.rtype == "manual" }
        guard manualData.count > 1 else { return nil }
        
        // Compute the 3D centerline positions.
        // Here we assume the tunnel is mostly horizontal (y = 0 or based on depth if you wish)
        var centerPositions: [SCNVector3] = []
        var currentPosition = SCNVector3Zero
        centerPositions.append(currentPosition)
        for data in manualData.dropFirst() {
            // Convert heading to radians (using your conversion: (90 - heading))
            let angle = (90.0 - data.heading) * Double.pi / 180.0
            // Compute horizontal delta (x, z). You can incorporate vertical change from data.depth if needed.
            let dx = data.distance * Double(conversionFactor) * cos(angle)
            let dz = data.distance * Double(conversionFactor) * sin(angle)
            // For this example we ignore vertical change along the centerline:
            currentPosition = currentPosition + SCNVector3(Float(dx), 0, Float(dz))
            centerPositions.append(currentPosition)
        }
        
        // Build cross–sections at each manual point.
        // Each cross-section is defined by 4 corners: leftUp, rightUp, rightDown, leftDown.
        // In SceneKit we take "up" as (0,1,0).
        var crossSections: [[SCNVector3]] = []
        for (i, data) in manualData.enumerated() {
            let center = centerPositions[i]
            
            // Determine the forward direction.
            // Use the vector to the next center (or previous if at the end)
            var forward = SCNVector3(0, 0, 1)
            if i < centerPositions.count - 1 {
                forward = (centerPositions[i+1] - center).normalized()
            } else if i > 0 {
                forward = (center - centerPositions[i-1]).normalized()
            }
            let globalUp = SCNVector3(0, 1, 0)
            var rightVec = forward.cross(globalUp).normalized()
            if rightVec.length() == 0 {
                rightVec = SCNVector3(1, 0, 0)
            }
            
            // Compute the cross-section corners.
            // Note: We use the cross-section measurements (left, right, up, down)
            // to offset from the center position.
            let left = Float(data.left)
            let right = Float(data.right)
            let upVal = Float(data.up)
            let down = Float(data.down)
            
            let leftUp = center + (rightVec * (-left)) + (globalUp * upVal)
            let rightUp = center + (rightVec * right) + (globalUp * upVal)
            let rightDown = center + (rightVec * right) - (globalUp * down)
            let leftDown = center + (rightVec * (-left)) - (globalUp * down)
            crossSections.append([leftUp, rightUp, rightDown, leftDown])
        }
        
        // Now create the mesh by connecting adjacent cross–sections.
        // We build one set of vertices per section and then create quads (as triangles) for the walls.
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        let sectionCount = crossSections.count
        let vertsPerSection = 4
        
        // Add vertices for every section.
        for section in crossSections {
            vertices.append(contentsOf: section)
        }
        
        // For every adjacent pair of sections, create faces for ceiling, floor, left wall, and right wall.
        for i in 0..<(sectionCount - 1) {
            let base = i * vertsPerSection
            let nextBase = (i + 1) * vertsPerSection
            
            // Ceiling face (between leftUp [0] and rightUp [1])
            indices.append(contentsOf: [
                Int32(base + 0), Int32(nextBase + 0), Int32(nextBase + 1),
                Int32(base + 0), Int32(nextBase + 1), Int32(base + 1)
            ])
            
            // Floor face (between leftDown [3] and rightDown [2])
            indices.append(contentsOf: [
                Int32(base + 3), Int32(nextBase + 3), Int32(nextBase + 2),
                Int32(base + 3), Int32(nextBase + 2), Int32(base + 2)
            ])
            
            // Left wall (connecting leftUp [0] to leftDown [3])
            indices.append(contentsOf: [
                Int32(base + 0), Int32(nextBase + 0), Int32(nextBase + 3),
                Int32(base + 0), Int32(nextBase + 3), Int32(base + 3)
            ])
            
            // Right wall (connecting rightUp [1] to rightDown [2])
            indices.append(contentsOf: [
                Int32(base + 1), Int32(nextBase + 1), Int32(nextBase + 2),
                Int32(base + 1), Int32(nextBase + 2), Int32(base + 2)
            ])
        }
        
        // Create geometry sources and elements.
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.brown
        geometry.firstMaterial?.isDoubleSided = true
        
        return geometry
    }
    
    /// Load your survey data (this is just a placeholder).
    private func loadMapData() {
        mapData = DataManager.loadSavedData()
    }
}
