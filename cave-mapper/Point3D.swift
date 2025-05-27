import SwiftUI
import simd
import UniformTypeIdentifiers
import CoreGraphics
import GameplayKit



struct Point3D {
    var x: Float
    var y: Float
    var z: Float
    var color: SIMD3<Float>
}




struct PlyVisualizerView: View {
    @State private var centerlinePoints: [CGPoint] = []
    @State private var topAlphaShape: [CGPoint] = []
    @State private var sideAlphaShape: [CGPoint] = []
    @State private var angleDegrees: Double = 0
    @State private var isImporterPresented = false
    @State private var wallTopPoints: [CGPoint] = []
    @State private var wallSidePoints: [CGPoint] = []
    // Alpha shape parameters
    let alpha: CGFloat = 20.0 // tune this to control shape "tightness"
    

    var body: some View {
        VStack {
            ZoomableView {
                ProjectionView(
                    wallPoints: wallTopPoints,
                    centerlinePoints: centerlinePoints,
                    alphaShape: topAlphaShape
                )
            }
            .frame(height: 250)
            .padding()
            Text("Top View (X-Z)")

            ZoomableView {
                ProjectionView(
                    wallPoints: wallSidePoints,
                    centerlinePoints: [], // or use a proper side projection if needed
                    alphaShape: sideAlphaShape
                )

            }
            .frame(height: 250)
            .padding()
            Text("Side View (X-Y)")

            CompassView2(mapRotation: .degrees(angleDegrees))
                .padding()

            Button("Load PLY") {
                isImporterPresented = true
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadPLY(from: url)
                }
            case .failure(let error):
                print("Failed to import file: \(error.localizedDescription)")
            }
        }
    }
    
    func downsample(points: [CGPoint], step: Int) -> [CGPoint] {
        guard step > 0 else { return points }
        return points.enumerated().compactMap { index, pt in
            index % step == 0 ? pt : nil
        }
    }

    func filterByDistanceToCenterline(walls: [CGPoint], centerline: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        guard !centerline.isEmpty else { return walls }

        return walls.filter { wallPt in
            let minDist = centerline.map { distance($0, wallPt) }.min() ?? .infinity
            return minDist > minDistance
        }
    }


    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let points = loadPLYPoints(from: url)

            let yellowMask = points.filter { $0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3 }
            let wall = points.filter { !($0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3) }

            let centerlineProj = yellowMask.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallTopProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallSideProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.y)) }

            let downsampledTop = downsample(points: wallTopProj, step: 5)
            let downsampledSide = downsample(points: wallSideProj, step: 5)

            let topAlpha = alphaShape(points: downsampledTop, alpha: 5.0)
            let sideAlpha = alphaShape(points: downsampledSide, alpha: 5.0)

            
            print("Top alpha shape count: \(topAlpha.count)")
            print("First few points:", topAlpha.prefix(5))

            let start = centerlineProj.first
            let end = centerlineProj.last
            let angle: Double = {
                guard let s = start, let e = end else { return 0 }
                let dx = e.x - s.x
                let dy = e.y - s.y
                var angle = atan2(dx, dy) * 180.0 / .pi
                if angle < 0 { angle += 360 }
                return angle
            }()

            
            
            // Switch back to main thread to update UI
            DispatchQueue.main.async {
                centerlinePoints = centerlineProj
                wallTopPoints = wallTopProj
                wallSidePoints = wallSideProj
                topAlphaShape = topAlpha
                sideAlphaShape = sideAlpha
                angleDegrees = angle
            }
        }
    }

    
    

    func loadPLYPoints(from fileURL: URL) -> [Point3D] {
        var points: [Point3D] = []
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n")
        var headerEnded = false
        var vertexCount = 0

        for line in lines {
            if !headerEnded {
                if line.starts(with: "element vertex") {
                    let parts = line.split(separator: " ")
                    vertexCount = Int(parts.last ?? "0") ?? 0
                }
                if line == "end_header" {
                    headerEnded = true
                }
                continue
            }
            if vertexCount > 0 && points.count < vertexCount {
                let parts = line.split(separator: " ").map { Float($0) ?? 0 }
                if parts.count >= 6 {
                    let point = Point3D(
                        x: parts[0], y: parts[1], z: parts[2],
                        color: SIMD3<Float>(parts[3] / 255, parts[4] / 255, parts[5] / 255)
                    )
                    points.append(point)
                }
            }
        }
        return points
    }

    
    func alphaShape(points: [CGPoint], alpha: CGFloat) -> [CGPoint] {
        guard points.count > 3 else { return points }

        // Dynamically compute bounds for mesh graph
        let minX = points.map { Float($0.x) }.min() ?? 0
        let maxX = points.map { Float($0.x) }.max() ?? 1
        let minY = points.map { Float($0.y) }.min() ?? 0
        let maxY = points.map { Float($0.y) }.max() ?? 1

        // Setup mesh graph with expanded bounds
        let margin: Float = 10.0
        let graph = GKMeshGraph<GKGraphNode2D>(
            bufferRadius: 0,
            minCoordinate: vector_float2(minX - margin, minY - margin),
            maxCoordinate: vector_float2(maxX + margin, maxY + margin)
        )

        let nodes = points.map {
            GKGraphNode2D(point: vector_float2(Float($0.x), Float($0.y)))
        }

        graph.add(nodes)
        graph.triangulate()

        var edges: [(CGPoint, CGPoint)] = []

        for node in nodes {
            for connected in node.connectedNodes {
                guard let to = connected as? GKGraphNode2D else { continue }

                let fromPt = CGPoint(x: CGFloat(node.position.x), y: CGFloat(node.position.y))
                let toPt = CGPoint(x: CGFloat(to.position.x), y: CGFloat(to.position.y))

                if distance(fromPt, toPt) < alpha {
                    edges.append((fromPt, toPt))
                }
            }
        }

        print("Alpha shape edge count: \(edges.count)")

        return traceBoundary(from: edges)
    }



    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    func traceBoundary(from edges: [(CGPoint, CGPoint)]) -> [CGPoint] {
        guard !edges.isEmpty else { return [] }

        var adjacency: [CGPoint: Set<CGPoint>] = [:]
        for (a, b) in edges {
            adjacency[a, default: []].insert(b)
            adjacency[b, default: []].insert(a)
        }

        var visited: Set<CGPoint> = []
        var boundary: [CGPoint] = []
        var current = edges.first!.0

        boundary.append(current)
        visited.insert(current)

        while true {
            guard let next = adjacency[current]?.first(where: { !visited.contains($0) }) else {
                break
            }
            current = next
            boundary.append(current)
            visited.insert(current)

            // Stop if we're back at the start
            if current == boundary.first {
                break
            }
        }

        return boundary
    }

    
    

    
    
    
}

struct ProjectionView: View {
    var wallPoints: [CGPoint]
    var centerlinePoints: [CGPoint]
    var alphaShape: [CGPoint]

    var body: some View {
        Canvas { context, size in
            let bounds = wallPoints + centerlinePoints + alphaShape
            guard !bounds.isEmpty else { return }
            let minX = bounds.map { $0.x }.min() ?? 0
            let maxX = bounds.map { $0.x }.max() ?? 1
            let minY = bounds.map { $0.y }.min() ?? 0
            let maxY = bounds.map { $0.y }.max() ?? 1

            let scaleX = size.width / (maxX - minX)
            let scaleY = size.height / (maxY - minY)
            let scale = min(scaleX, scaleY)

            let offset = CGPoint(x: -minX * scale, y: -minY * scale)

            for pt in alphaShape {
                let p = transform(pt)
                let rect = CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(.red))
            }

            print("Canvas size: \(size)")
            print("wallPoints bounds: \(minX) to \(maxX), \(minY) to \(maxY)")
            print("Scale: \(scale), Offset: \(offset)")

            
            func transform(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale + offset.x,
                        y: size.height - (point.y * scale + offset.y))
            }

            for point in wallPoints {
                let p = transform(point)
                let rect = CGRect(x: p.x, y: p.y, width: 1, height: 1)
                context.fill(Path(ellipseIn: rect), with: .color(.gray))
            }

            if !centerlinePoints.isEmpty {
                var path = Path()
                path.move(to: transform(centerlinePoints[0]))
                for pt in centerlinePoints.dropFirst() {
                    path.addLine(to: transform(pt))
                }
                context.stroke(path, with: .color(.yellow), lineWidth: 1)
            }

            if !alphaShape.isEmpty {
                var poly = Path()
                poly.move(to: transform(alphaShape[0]))
                for pt in alphaShape.dropFirst() {
                    poly.addLine(to: transform(pt))
                }
                poly.closeSubpath()
                context.stroke(poly, with: .color(.blue), lineWidth: 1)
            }
        }
    }
}

struct ZoomableView<Content: View>: View {
    @GestureState private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var content: () -> Content

    var body: some View {
        content()
            .scaleEffect(scale)
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture().updating($scale) { value, state, _ in
                        state = value
                    },
                    DragGesture().updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
                )
            )
    }
}

struct CompassView2: View {
    var mapRotation: Angle

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray, lineWidth: 1)
            Arrow()
                .rotationEffect(mapRotation)
                .foregroundColor(.red)
            Text("N")
                .offset(y: -30)
                .foregroundColor(.red)
        }
        .frame(width: 100, height: 100)
    }
}

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLines([
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY * 0.6),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
        path.closeSubpath()
        return path
    }
}
