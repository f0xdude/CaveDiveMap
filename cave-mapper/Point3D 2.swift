import SwiftUI
import simd
import UniformTypeIdentifiers
import CoreGraphics

struct Point3D {
    var x: Float
    var y: Float
    var z: Float
    var color: SIMD3<Float>
}

struct PlyVisualizerView: View {
    @State private var centerlinePoints: [CGPoint] = []
    @State private var wallTopPoints: [CGPoint] = []
    @State private var wallSidePoints: [CGPoint] = []
    @State private var angleDegrees: Double = 0
    @State private var isImporterPresented = false
    
    var totalDistance: Double {
        guard centerlinePoints.count > 1 else { return 0 }
        return zip(centerlinePoints, centerlinePoints.dropFirst())
            .map { a, b in
                hypot(a.x - b.x, a.y - b.y)
            }
            .reduce(0, +)
    }

    var maxDepth: Double {
        guard !wallSidePoints.isEmpty else { return 0 }
        return Double(wallSidePoints.map { $0.y }.min() ?? 0)
    }


    var body: some View {
        VStack {
            ZoomableView {
                ProjectionView(
                    points: wallTopPoints,
                    centerlinePoints: centerlinePoints
                )
            }
            .frame(height: 200)
            .padding()
            Text("Top View (X-Z)")

            ZoomableView {
                ProjectionView(
                    points: wallSidePoints,
                    centerlinePoints: [] // optional side centerline
                )
            }
            .frame(height: 200)
            .padding()
            Text("Side View (X-Y)")

            HStack(spacing: 20) {
                CompassView2(mapRotation: .degrees(angleDegrees))
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Total Distance: %.1f m", totalDistance))
                    Text(String(format: "Max Depth: %.1f m", maxDepth))
                }
                .font(.footnote)
                .padding(.vertical, 4)
            }

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

    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let points = loadPLYPoints(from: url)

            let yellowMask = points.filter { $0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3 }
            let wall = points.filter { !($0.color.x > 0.8 && $0.color.y > 0.8 && $0.color.z < 0.3) }

            let centerlineProj = yellowMask.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallTopProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallSideProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.y)) }

            let angle: Double = {
                guard let s = centerlineProj.first, let e = centerlineProj.last else { return 0 }
                let dx = e.x - s.x
                let dy = e.y - s.y
                var angle = atan2(dx, dy) * 180.0 / .pi
                if angle < 0 { angle += 360 }
                return angle
            }()

            DispatchQueue.main.async {
                centerlinePoints = centerlineProj
                wallTopPoints = wallTopProj
                wallSidePoints = wallSideProj
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
}

struct ProjectionView: View {
    var points: [CGPoint]
    var centerlinePoints: [CGPoint]

    var body: some View {
        Canvas { context, size in
            let allPoints = points + centerlinePoints
            guard !allPoints.isEmpty else { return }

            let minX = allPoints.map { $0.x }.min() ?? 0
            let maxX = allPoints.map { $0.x }.max() ?? 1
            let minY = allPoints.map { $0.y }.min() ?? 0
            let maxY = allPoints.map { $0.y }.max() ?? 1

            let scaleX = size.width / (maxX - minX)
            let scaleY = size.height / (maxY - minY)
            let scale = min(scaleX, scaleY)

            let offset = CGPoint(x: -minX * scale, y: -minY * scale)

            func transform(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale + offset.x,
                        y: size.height - (point.y * scale + offset.y))
            }

            for point in points {
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
        }
    }
}

struct ZoomableView<Content: View>: View {
    @State private var currentScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var content: () -> Content

    var body: some View {
        content()
            .scaleEffect(currentScale * gestureScale)
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            currentScale *= value
                        },
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
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
        .frame(width: 50, height: 50)
    }
}

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let leftBase = CGPoint(x: rect.midX - rect.width * 0.2, y: rect.maxY)
        let centerNotch = CGPoint(x: rect.midX, y: rect.height * 0.45)
        let rightBase = CGPoint(x: rect.midX + rect.width * 0.2, y: rect.maxY)

        path.move(to: tip)
        path.addLine(to: rightBase)
        path.addLine(to: centerNotch)
        path.addLine(to: leftBase)
        path.closeSubpath()

        return path
    }
}

