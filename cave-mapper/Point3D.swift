import SwiftUI
import simd
import UniformTypeIdentifiers

struct Point3D {
    var x: Float
    var y: Float
    var z: Float
    var color: SIMD3<Float>
}

struct ContentView: View {
    @State private var wallPoints: [CGPoint] = []
    @State private var centerlinePoints: [CGPoint] = []
    @State private var alphaShape: [CGPoint] = []
    @State private var angleDegrees: Double = 0
    
    var body: some View {
        VStack {
            ProjectionView(wallPoints: wallPoints, centerlinePoints: centerlinePoints, alphaShape: alphaShape)
                .frame(height: 400)
                .padding()
            CompassView(angleDegrees: angleDegrees)
                .padding()
            Button("Load PLY") {
                loadPLY()
            }
        }
        .padding()
    }

    func loadPLY() {
        guard let url = Bundle.main.url(forResource: "point", withExtension: "ply") else { return }
        let points = loadPLYPoints(from: url)

        let yellowMask = points.filter { $0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3 }
        let wall = points.filter { !($0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3) }

        let centerlineProj = yellowMask.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
        let wallProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.z)) }

        centerlinePoints = centerlineProj
        wallPoints = wallProj
        alphaShape = convexHull(wallProj)

        if let start = centerlineProj.first, let end = centerlineProj.last {
            let dx = end.x - start.x
            let dy = end.y - start.y
            angleDegrees = (atan2(dx, dy) * 180.0 / .pi).truncatingRemainder(dividingBy: 360)
            if angleDegrees < 0 { angleDegrees += 360 }
        }
    }

    func loadPLYPoints(from fileURL: URL) -> [Point3D] {
        var points: [Point3D] = []
        guard let content = try? String(contentsOf: fileURL) else { return [] }
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

    func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var hull: [CGPoint] = []

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        for p in sorted {
            while hull.count >= 2 && cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 {
                hull.removeLast()
            }
            hull.append(p)
        }

        let t = hull.count + 1
        for p in sorted.reversed() {
            while hull.count >= t && cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 {
                hull.removeLast()
            }
            hull.append(p)
        }

        hull.removeLast()
        return hull
    }
}

struct ProjectionView: View {
    var wallPoints: [CGPoint]
    var centerlinePoints: [CGPoint]
    var alphaShape: [CGPoint]

    var body: some View {
        Canvas { context, size in
            for point in wallPoints {
                let rect = CGRect(x: point.x, y: size.height - point.y, width: 1, height: 1)
                context.fill(Path(ellipseIn: rect), with: .color(.gray))
            }

            if !centerlinePoints.isEmpty {
                var path = Path()
                path.move(to: CGPoint(x: centerlinePoints[0].x, y: size.height - centerlinePoints[0].y))
                for pt in centerlinePoints.dropFirst() {
                    path.addLine(to: CGPoint(x: pt.x, y: size.height - pt.y))
                }
                context.stroke(path, with: .color(.yellow), lineWidth: 1)
            }

            if !alphaShape.isEmpty {
                var poly = Path()
                poly.move(to: CGPoint(x: alphaShape[0].x, y: size.height - alphaShape[0].y))
                for pt in alphaShape.dropFirst() {
                    poly.addLine(to: CGPoint(x: pt.x, y: size.height - pt.y))
                }
                poly.closeSubpath()
                context.stroke(poly, with: .color(.blue), lineWidth: 1)
            }
        }
    }
}

struct CompassView: View {
    var angleDegrees: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray, lineWidth: 1)
            Arrow()
                .rotationEffect(.degrees(angleDegrees))
                .fill(Color.red)
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
