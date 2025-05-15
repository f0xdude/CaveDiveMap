import SwiftUI
import SceneKit
import CoreMotion
import UIKit

struct ThreeDCaveMapView: View {
    @State private var mapData: [SavedData] = []
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var initialSetupDone = false
    
    // Camera control state
    @State private var cameraDistance: Float = 10.0
    @State private var cameraAngleX: Float = 0.0
    @State private var cameraAngleY: Float = 0.0
    
    // Gesture state variables
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var zoomScale: CGFloat = 1.0
    
    @StateObject private var motionDetector = MotionDetector()
    @Environment(\.presentationMode) var presentationMode
    
    // Conversion factor to scale your measured distances to 3D space
    private let conversionFactor: Float = 0.5
    
    private var maxDepth: Double {
        mapData.map { $0.depth }.max() ?? 0
    }
    
    var body: some View {
        ZStack {
            SceneView(
                scene: scene,
                pointOfView: cameraNode,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .background(Color.black)
            .onAppear {
                loadMapData()
                setupScene()
                motionDetector.doubleTapDetected = {
                    self.presentationMode.wrappedValue.dismiss()
                }
                motionDetector.startDetection()
            }
            .onDisappear {
                motionDetector.stopDetection()
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        cameraAngleY += Float(value.translation.width) * 0.01
                        cameraAngleX += Float(value.translation.height) * 0.01
                        updateCameraPosition()
                    }
            )
            .gesture(
                MagnificationGesture()
                    .updating($zoomScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        cameraDistance = max(5.0, min(cameraDistance / Float(value), 50.0))
                        updateCameraPosition()
                    }
            )
            
            // Overlay export share buttons at the bottom left
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
                Button(action: { resetCamera() }) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 50, height: 50)
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            
            // Legend overlay
            VStack(alignment: .leading, spacing: 8) {
                Text("3D Cave Map")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.bottom, 4)
                
                HStack {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Text("Start Point").foregroundColor(.white)
                }
                
                HStack {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text("End Point").foregroundColor(.white)
                }
                
                HStack {
                    Rectangle().fill(Color.blue).frame(width: 10, height: 10)
                    Text("Guide Line").foregroundColor(.white)
                }
                
                HStack {
                    Rectangle().fill(Color.brown.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Cave Walls").foregroundColor(.white)
                }
                
                // New row for max depth
                HStack {
                    Text("Max Depth:")
                        .foregroundColor(.white)
                    Text("\(maxDepth, specifier: "%.1f") m")
                        .foregroundColor(.white)
                }
            
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .navigationTitle("3D Cave Map")
        .onChange(of: dragOffset) { oldValue, newValue in
            let tempAngleY = cameraAngleY + Float(newValue.width) * 0.01
            let tempAngleX = cameraAngleX + Float(newValue.height) * 0.01
            updateCameraPosition(angleX: tempAngleX, angleY: tempAngleY, distance: cameraDistance)
        }
        .onChange(of: zoomScale) { oldValue, newValue in
            let tempDistance = cameraDistance / Float(newValue)
            updateCameraPosition(angleX: cameraAngleX, angleY: cameraAngleY, distance: tempDistance)
        }
    }
    
    private func setupScene() {
        // Create a new scene
        scene = SCNScene()
        scene.background.contents = UIColor.black
        
        // Set up the camera
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 500
        scene.rootNode.addChildNode(cameraNode)
        
        // Set initial camera position
        cameraDistance = 20.0
        cameraAngleX = Float.pi / 6  // Slightly looking down
        cameraAngleY = Float.pi / 4  // Slightly rotated
        updateCameraPosition()
        
        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.5, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        // Add directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.color = UIColor(white: 0.8, alpha: 1.0)
        directionalLight.eulerAngles = SCNVector3(x: -Float.pi / 3, y: Float.pi / 4, z: 0)
        scene.rootNode.addChildNode(directionalLight)
        
        // Add a second directional light from another angle for better illumination
        let secondaryLight = SCNNode()
        secondaryLight.light = SCNLight()
        secondaryLight.light?.type = .directional
        secondaryLight.light?.color = UIColor(white: 0.6, alpha: 1.0)
        secondaryLight.eulerAngles = SCNVector3(x: Float.pi / 4, y: -Float.pi / 3, z: 0)
        scene.rootNode.addChildNode(secondaryLight)
        
        // Create 3D representation of the cave
        createCaveModel()
    }
    
    private func updateCameraPosition(angleX: Float? = nil, angleY: Float? = nil, distance: Float? = nil) {
        let x = angleX ?? cameraAngleX
        let y = angleY ?? cameraAngleY
        let dist = distance ?? cameraDistance
        
        let position = SCNVector3(
            x: dist * sin(y) * cos(x),
            y: dist * sin(x),
            z: dist * cos(y) * cos(x)
        )
        
        cameraNode.position = position
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }
    
    private func resetCamera() {
        cameraDistance = 20.0
        cameraAngleX = Float.pi / 6
        cameraAngleY = Float.pi / 4
        updateCameraPosition()
    }
    
    private func createCaveModel() {
        guard !mapData.isEmpty else { return }
        
        let manualData = mapData.filter { $0.rtype == "manual" }
        guard !manualData.isEmpty else { return }
        
        // Create a node to hold all cave geometry
        let caveNode = SCNNode()
        scene.rootNode.addChildNode(caveNode)
        
        // Create the center path (guide line)
        createCenterPath(parentNode: caveNode, manualData: manualData)
        
        // Create the cave walls with improved smoothing and intersection handling
        createSmoothCaveWalls(parentNode: caveNode, manualData: manualData)
        
        // Add start and end markers
        if let firstPoint = manualData.first, let lastPoint = manualData.last {
            addMarker(at: convertToVector3(firstPoint), color: .green, size: 0.3, parentNode: caveNode, label: "Start")
            addMarker(at: convertToVector3(lastPoint), color: .red, size: 0.3, parentNode: caveNode, label: "End")
        }
    }
    
    
    private func createCenterPath(parentNode: SCNNode, manualData: [SavedData]) {
        // Pre-process the path to create a smoother centerline with Catmull-Rom spline
        var smoothedPathPoints: [SCNVector3] = []
        let splineSegments = 3 // Number of points to generate between each original point
        
        // Convert all manual data points to 3D vectors
        var originalPoints: [SCNVector3] = []
        for point in manualData {
            originalPoints.append(convertToVector3(point))
        }
        
        // Add the first point
        smoothedPathPoints.append(originalPoints[0])
        
        // Generate spline points between each pair of original points
        for i in 0..<(originalPoints.count - 1) {
            let p0 = i > 0 ? originalPoints[i-1] : originalPoints[i]
            let p1 = originalPoints[i]
            let p2 = originalPoints[i+1]
            let p3 = i < originalPoints.count - 2 ? originalPoints[i+2] :
                    SCNVector3(p2.x + (p2.x - p1.x), p2.y + (p2.y - p1.y), p2.z + (p2.z - p1.z))
            
            // Generate points along the Catmull-Rom spline
            for j in 1...splineSegments {
                let t = Float(j) / Float(splineSegments + 1)
                let point = catmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                smoothedPathPoints.append(point)
            }
            
            // Add the end point of this segment (except for the last segment)
            if i < originalPoints.count - 2 {
                smoothedPathPoints.append(p2)
            }
        }
        
        // Add the last point
        smoothedPathPoints.append(originalPoints.last!)
        
        // Create a path using cylinders between each point
        for i in 0..<smoothedPathPoints.count-1 {
            let startPoint = smoothedPathPoints[i]
            let endPoint = smoothedPathPoints[i+1]
            
            // Create a cylinder between points
            let cylinder = createCylinder(from: startPoint, to: endPoint, radius: 0.05, color: .blue)
            parentNode.addChildNode(cylinder)
            
            // Add a small sphere at each junction
            if i % (splineSegments + 1) == 0 {
                let sphere = SCNNode(geometry: SCNSphere(radius: 0.1))
                sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
                sphere.position = startPoint
                parentNode.addChildNode(sphere)
                
                // Find the corresponding original data point
                let originalIndex = i / (splineSegments + 1)
                if originalIndex < manualData.count {
                    // Add depth label
                    let depthLabel = createTextNode(
                        text: String(format: "Depth: %.1fm", manualData[originalIndex].depth),
                        color: .white,
                        size: 0.2
                    )
                    depthLabel.position = SCNVector3(
                        startPoint.x,
                        startPoint.y + 0.3,
                        startPoint.z
                    )
                    depthLabel.constraints = [SCNBillboardConstraint()]
                    parentNode.addChildNode(depthLabel)
                }
            }
        }
        
        // Add the final point
        if let lastPoint = smoothedPathPoints.last {
            let sphere = SCNNode(geometry: SCNSphere(radius: 0.1))
            sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
            sphere.position = lastPoint
            parentNode.addChildNode(sphere)
            
            // Add depth label for last point
            if let lastData = manualData.last {
                let depthLabel = createTextNode(
                    text: String(format: "Depth: %.1fm", lastData.depth),
                    color: .white,
                    size: 0.2
                )
                depthLabel.position = SCNVector3(
                    lastPoint.x,
                    lastPoint.y + 0.3,
                    lastPoint.z
                )
                depthLabel.constraints = [SCNBillboardConstraint()]
                parentNode.addChildNode(depthLabel)
            }
        }
    }
    
    private func createSmoothCaveWalls(parentNode: SCNNode, manualData: [SavedData]) {
        guard manualData.count >= 2 else { return }
        
        // Create arrays to hold the cross-section points for each measurement
        var crossSections: [[SCNVector3]] = []
        
        // Number of points to use for each cross-section (more points = smoother circle)
        let crossSectionPointCount = 24 // Increased for smoother walls
        
        // Pre-process the path to create a smoother centerline with Catmull-Rom spline
        var smoothedPathPoints: [SCNVector3] = []
        let splineSegments = 3 // Number of points to generate between each original point
        
        // Convert all manual data points to 3D vectors
        var originalPoints: [SCNVector3] = []
        var originalData: [SavedData] = []
        
        for point in manualData {
            originalPoints.append(convertToVector3(point))
            originalData.append(point)
        }
        
        // Add the first point
        smoothedPathPoints.append(originalPoints[0])
        
        // Generate spline points between each pair of original points
        for i in 0..<(originalPoints.count - 1) {
            let p0 = i > 0 ? originalPoints[i-1] : originalPoints[i]
            let p1 = originalPoints[i]
            let p2 = originalPoints[i+1]
            let p3 = i < originalPoints.count - 2 ? originalPoints[i+2] :
                    SCNVector3(p2.x + (p2.x - p1.x), p2.y + (p2.y - p1.y), p2.z + (p2.z - p1.z))
            
            // Generate points along the Catmull-Rom spline
            for j in 1...splineSegments {
                let t = Float(j) / Float(splineSegments + 1)
                let point = catmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                smoothedPathPoints.append(point)
            }
            
            // Add the end point of this segment (except for the last segment)
            if i < originalPoints.count - 2 {
                smoothedPathPoints.append(p2)
            }
        }
        
        // Add the last point
        smoothedPathPoints.append(originalPoints.last!)
        
        // Calculate tangents for the smoothed path
        var smoothedPathTangents: [SCNVector3] = []
        for i in 0..<smoothedPathPoints.count {
            let prev = i > 0 ? smoothedPathPoints[i-1] : smoothedPathPoints[i]
            let next = i < smoothedPathPoints.count - 1 ? smoothedPathPoints[i+1] : smoothedPathPoints[i]
            
            let tangent = SCNVector3(
                next.x - prev.x,
                next.y - prev.y,
                next.z - prev.z
            )
            smoothedPathTangents.append(SCNVector3Normalize(tangent))
        }
        
        // Generate cross-sections for each point on the smoothed path
        for i in 0..<smoothedPathPoints.count {
            let basePoint = smoothedPathPoints[i]
            let tangent = smoothedPathTangents[i]
            
            // Calculate the right vector (perpendicular to tangent, in horizontal plane)
            let up = SCNVector3(0, 1, 0)
            let rightVector = SCNVector3CrossProduct(up, tangent)
            let normalizedRight = SCNVector3Normalize(rightVector)
            
            // Find the closest original data point to get measurements
            var closestIndex = 0
            var minDistance = Float.greatestFiniteMagnitude
            
            for j in 0..<originalPoints.count {
                let originalPoint = originalPoints[j]
                let distance = SCNVector3Distance(basePoint, originalPoint)
                
                if distance < minDistance {
                    minDistance = distance
                    closestIndex = j
                }
            }
            
            let point = originalData[closestIndex]
            
            // Scale the measurements
            let leftDist = Float(point.left) * conversionFactor
            let rightDist = Float(point.right) * conversionFactor
            let upDist = Float(point.up) * conversionFactor
            let downDist = Float(point.down) * conversionFactor
            
            // Create a cross-section with multiple points to form a smoother shape
            var sectionPoints: [SCNVector3] = []
            
            for j in 0..<crossSectionPointCount {
                let angle = Float(j) * (2 * Float.pi / Float(crossSectionPointCount))
                
                // Use a smoother elliptical function for cross-section shape
                // This creates a more natural cave-like shape
                let horizontalScale = mix(rightDist, leftDist, 0.5 + 0.5 * sin(angle))
                let verticalScale = mix(upDist, downDist, 0.5 + 0.5 * sin(angle + Float.pi / 2))
                
                // Add some natural variation to the cave walls
                let variation = Float(1.0 + 0.05 * sin(angle * 4 + Float(i) * 0.2))
                
                // Calculate the point position with a smoother profile
                let x = horizontalScale * cos(angle) * variation
                let y = verticalScale * sin(angle) * variation
                
                // Calculate the binormal vector (perpendicular to both tangent and right vector)
                let binormal = SCNVector3CrossProduct(tangent, normalizedRight)
                let normalizedBinormal = SCNVector3Normalize(binormal)
                
                // Transform to world coordinates using the frame defined by tangent, right, and binormal
                let pointPosition = SCNVector3(
                    basePoint.x + normalizedRight.x * x + normalizedBinormal.x * y,
                    basePoint.y + normalizedRight.y * x + normalizedBinormal.y * y,
                    basePoint.z + normalizedRight.z * x + normalizedBinormal.z * y
                )
                
                sectionPoints.append(pointPosition)
            }
            
            crossSections.append(sectionPoints)
        }
        
        // Create a smooth cave tunnel by connecting adjacent cross-sections
        for i in 0..<(crossSections.count - 1) {
            connectCrossSections(crossSections[i], crossSections[i+1], parentNode)
        }
    }
    
    // Helper function to calculate a point on a Catmull-Rom spline
    private func catmullRomPoint(p0: SCNVector3, p1: SCNVector3, p2: SCNVector3, p3: SCNVector3, t: Float) -> SCNVector3 {
        let t2 = t * t
        let t3 = t2 * t
        
        let b1 = 0.5 * (-t3 + 2*t2 - t)
        let b2 = 0.5 * (3*t3 - 5*t2 + 2)
        let b3 = 0.5 * (-3*t3 + 4*t2 + t)
        let b4 = 0.5 * (t3 - t2)
        
        return SCNVector3(
            b1 * p0.x + b2 * p1.x + b3 * p2.x + b4 * p3.x,
            b1 * p0.y + b2 * p1.y + b3 * p2.y + b4 * p3.y,
            b1 * p0.z + b2 * p1.z + b3 * p2.z + b4 * p3.z
        )
    }
    
    // Improved function to connect cross-sections with smoother transitions
    private func connectCrossSections(_ section1: [SCNVector3], _ section2: [SCNVector3], _ parentNode: SCNNode) {
        guard section1.count == section2.count else { return }
        
        let pointCount = section1.count
        
        // Create triangles to connect the two cross-sections
        for i in 0..<pointCount {
            let i1 = i
            let i2 = (i + 1) % pointCount
            
            let v1 = section1[i1]
            let v2 = section1[i2]
            let v3 = section2[i2]
            let v4 = section2[i1]
            
            // Create two triangles to form a quad
            createTriangle(vertices: [v1, v2, v3], parentNode: parentNode)
            createTriangle(vertices: [v1, v3, v4], parentNode: parentNode)
        }
    }
    
    // Enhanced triangle creation with improved materials for a more natural look
    private func createTriangle(vertices: [SCNVector3], parentNode: SCNNode) {
        let indices: [Int32] = [0, 1, 2]
        
        let source = SCNGeometrySource(vertices: vertices)
        
        // Calculate normals for better lighting
        let normals = calculateNormals(vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        
        // Add texture coordinates for more realistic materials
        let texCoords: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0.5, y: 1)
        ]
        // Fixed: Use textureCoordinates instead of texcoords
        let texCoordSource = SCNGeometrySource(textureCoordinates: texCoords)
        
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        let geometry = SCNGeometry(sources: [source, normalSource, texCoordSource], elements: [element])
        
        // Create a more realistic cave wall material
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.brown.withAlphaComponent(0.7)
        material.specular.contents = UIColor.white
        material.shininess = 0.2
        material.roughness.contents = NSNumber(value: 0.9)
        material.isDoubleSided = true
        
        // Add subtle noise texture for more natural cave walls
        // In a real app, you would use an actual texture image
        let noiseImage = generateNoiseTexture(width: 256, height: 256)
        material.normal.contents = noiseImage
        material.normal.intensity = 0.3
        
        geometry.materials = [material]
        
        let node = SCNNode(geometry: geometry)
        parentNode.addChildNode(node)
    }
    
    // Generate a simple procedural noise texture for cave walls
    private func generateNoiseTexture(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        
        let context = UIGraphicsGetCurrentContext()!
        
        // Fill with base color
        context.setFillColor(UIColor.darkGray.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Add noise
        for _ in 0..<1000 {
            let x = CGFloat.random(in: 0..<size.width)
            let y = CGFloat.random(in: 0..<size.height)
            let radius = CGFloat.random(in: 1..<3)
            let alpha = CGFloat.random(in: 0.1..<0.3)
            
            context.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    private func calculateNormals(_ vertices: [SCNVector3]) -> [SCNVector3] {
        guard vertices.count >= 3 else { return [SCNVector3](repeating: SCNVector3(0, 1, 0), count: vertices.count) }
        
        // Calculate the normal for the triangle
        let v1 = vertices[0]
        let v2 = vertices[1]
        let v3 = vertices[2]
        
        let edge1 = SCNVector3(v2.x - v1.x, v2.y - v1.y, v2.z - v1.z)
        let edge2 = SCNVector3(v3.x - v1.x, v3.y - v1.y, v3.z - v1.z)
        
        let normal = SCNVector3CrossProduct(edge1, edge2)
        let normalizedNormal = SCNVector3Normalize(normal)
        
        // Return the same normal for all vertices
        return [normalizedNormal, normalizedNormal, normalizedNormal]
    }
    
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a * (1 - t) + b * t
    }
    
    private func convertToVector3(_ point: SavedData) -> SCNVector3 {
        // Convert from distance/heading/depth to 3D coordinates
        let distance = Float(point.distance) * conversionFactor
        let heading = Float(point.heading) * Float.pi / 180.0
        let depth = Float(point.depth) * conversionFactor
        
        // X and Z form the horizontal plane, Y is depth (negative because depth increases downward)
        return SCNVector3(
            distance * sin(heading),
            -depth,  // Negative because depth increases downward
            distance * cos(heading)
        )
    }
    
    private func createCylinder(from startPoint: SCNVector3, to endPoint: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
        let height = CGFloat(SCNVector3Distance(startPoint, endPoint))
        let cylinder = SCNCylinder(radius: radius, height: height)
        cylinder.firstMaterial?.diffuse.contents = color
        
        let node = SCNNode(geometry: cylinder)
        
        // Position and orient the cylinder to connect the two points
        positionNodeBetweenPoints(node, from: startPoint, to: endPoint)
        
        return node
    }
    
    private func positionNodeBetweenPoints(_ node: SCNNode, from startPoint: SCNVector3, to endPoint: SCNVector3) {
        // Position at the midpoint
        node.position = SCNVector3(
            (startPoint.x + endPoint.x) / 2,
            (startPoint.y + endPoint.y) / 2,
            (startPoint.z + endPoint.z) / 2
        )
        
        // Calculate the direction vector
        let direction = SCNVector3(
            endPoint.x - startPoint.x,
            endPoint.y - startPoint.y,
            endPoint.z - startPoint.z
        )
        
        // Calculate the rotation to align with the direction
        // Default cylinder orientation is along the y-axis
        let yAxis = SCNVector3(0, 1, 0)
        let angle = Float(acos(SCNVector3DotProduct(SCNVector3Normalize(direction), yAxis)))
        
        if angle != 0 {
            let rotationAxis = SCNVector3CrossProduct(yAxis, SCNVector3Normalize(direction))
            if SCNVector3Length(rotationAxis) > 0.000001 {
                node.rotation = SCNVector4(
                    rotationAxis.x,
                    rotationAxis.y,
                    rotationAxis.z,
                    angle
                )
            }
        }
    }
    
    private func addMarker(at position: SCNVector3, color: UIColor, size: CGFloat, parentNode: SCNNode, label: String) {
        // Create a sphere for the marker
        let sphere = SCNSphere(radius: size)
        sphere.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: sphere)
        node.position = position
        parentNode.addChildNode(node)
        
        // Add a text label
        let textNode = createTextNode(text: label, color: color, size: size * 0.8)
        textNode.position = SCNVector3(position.x, position.y + Float(size) * 1.5, position.z)
        textNode.constraints = [SCNBillboardConstraint()]
        parentNode.addChildNode(textNode)
    }
    
    private func createTextNode(text: String, color: UIColor, size: CGFloat) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0)
        textGeometry.font = UIFont.systemFont(ofSize: 1)
        
        // Use white for depth labels if the color is black (for better visibility on dark background)
        let textColor = color == .black ? UIColor.white : color
        textGeometry.firstMaterial?.diffuse.contents = textColor
        
        let textNode = SCNNode(geometry: textGeometry)
        
        // Scale the text to the desired size
        let scale = size / 1.0
        textNode.scale = SCNVector3(scale, scale, scale)
        
        // Center the text
        let (min, max) = textGeometry.boundingBox
        let width = max.x - min.x
        textNode.pivot = SCNMatrix4MakeTranslation(width/2, 0, 0)
        
        return textNode
    }
    
    private func loadMapData() {
        mapData = DataManager.loadSavedData()
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

// MARK: - Vector Math Helpers

func SCNVector3Distance(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
    let dx = v2.x - v1.x
    let dy = v2.y - v1.y
    let dz = v2.z - v1.z
    return sqrt(dx*dx + dy*dy + dz*dz)
}

func SCNVector3Length(_ v: SCNVector3) -> Float {
    return sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
}

func SCNVector3Normalize(_ v: SCNVector3) -> SCNVector3 {
    let length = SCNVector3Length(v)
    if length == 0 {
        return SCNVector3(0, 0, 0)
    }
    return SCNVector3(v.x / length, v.y / length, v.z / length)
}

func SCNVector3DotProduct(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
    return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
}

func SCNVector3CrossProduct(_ v1: SCNVector3, _ v2: SCNVector3) -> SCNVector3 {
    return SCNVector3(
        v1.y * v2.z - v1.z * v2.y,
        v1.z * v2.x - v1.x * v2.z,
        v1.x * v2.y - v1.y * v2.x
    )
}
