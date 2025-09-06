import SwiftUI
import simd
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - Data Models

struct Point3D {
    var x: Float
    var y: Float
    var z: Float
    var color: SIMD3<Float>
    // Optional extras from our PLY:
    var depth: Float? = nil
    var heading: Float? = nil
    var commentID: Int? = nil
    var vertexIndex: Int = 0
}

struct LoadedPLY {
    var points: [Point3D]
    /// comment text keyed by vertex_index (as written in the PLY header)
    var commentsByVertexIndex: [Int: String]
}

struct LabelPoint {
    var point: CGPoint
    var text: String
}

// MARK: - Main View

struct PlyVisualizerView: View {
    @State private var centerlinePoints: [CGPoint] = []
    @State private var wallTopPoints: [CGPoint] = []
    @State private var wallSidePoints: [CGPoint] = []

    @State private var labelsTop: [LabelPoint] = []
    @State private var labelsSide: [LabelPoint] = []

    @State private var angleDegrees: Double = 0
    @State private var isImporterPresented = false
    
    var totalDistance: Double {
        guard centerlinePoints.count > 1 else { return 0 }
        return zip(centerlinePoints, centerlinePoints.dropFirst())
            .map { a, b in hypot(a.x - b.x, a.y - b.y) }
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
                    centerlinePoints: centerlinePoints,
                    labels: labelsTop
                )
            }
            .frame(height: 200)
            .padding()
            Text("Top View (X-Z)")

            ZoomableView {
                ProjectionView(
                    points: wallSidePoints,
                    centerlinePoints: [], // optional in side view
                    labels: labelsSide
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

    // MARK: - Load & Parse

    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadPLYPointsAndComments(from: url)
            let points = loaded.points
            let commentsByVertex = loaded.commentsByVertexIndex

            // Identify path (yellow) vs wall/feature
            let isYellow: (Point3D) -> Bool = { p in
                p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
            }
            let centerline = points.filter(isYellow)
            let wall = points.filter { !isYellow($0) }

            // Projections
            let centerlineProj = centerline.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallTopProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.z)) }
            let wallSideProj = wall.map { CGPoint(x: Double($0.x), y: Double($0.y)) }

            // Labels next to corresponding path vertices
            var topLabels: [LabelPoint] = []
            var sideLabels: [LabelPoint] = []
            for p in centerline {
                if let text = commentsByVertex[p.vertexIndex] {
                    topLabels.append(LabelPoint(point: CGPoint(x: Double(p.x), y: Double(p.z)), text: text))
                    sideLabels.append(LabelPoint(point: CGPoint(x: Double(p.x), y: Double(p.y)), text: text))
                }
            }

            // Map orientation angle
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
                labelsTop = topLabels
                labelsSide = sideLabels
                angleDegrees = angle
            }
        }
    }

    /// Parse PLY with our custom header comments and comment_id property.
    func loadPLYPointsAndComments(from fileURL: URL) -> LoadedPLY {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return LoadedPLY(points: [], commentsByVertexIndex: [:])
        }
        var points: [Point3D] = []
        var commentsByVertexIndex: [Int: String] = [:]

        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
        var headerEnded = false
        var vertexCount = 0
        var readVertices = 0

        // Parse header + collect comment annotations
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line == "end_header" {
                headerEnded = true
                i += 1
                break
            }
            if line.hasPrefix("element vertex") {
                let parts = line.split(separator: " ")
                if let last = parts.last, let n = Int(last) {
                    vertexCount = n
                }
            }
            if line.hasPrefix("comment annotation") {
                // Expected: comment annotation id=XX vertex_index=YY text=...
                // Extract vertex_index and text
                let comps = line.split(separator: " ")
                var vIndex: Int? = nil
                var textStart: String = ""
                for (idx, token) in comps.enumerated() {
                    if token.hasPrefix("vertex_index=") {
                        let val = token.replacingOccurrences(of: "vertex_index=", with: "")
                        vIndex = Int(val)
                    }
                    if token.hasPrefix("text=") {
                        // The rest of the line (including spaces) after "text="
                        let joined = comps[idx...].joined(separator: " ")
                        textStart = joined.replacingOccurrences(of: "text=", with: "")
                        break
                    }
                }
                if let vi = vIndex, !textStart.isEmpty {
                    commentsByVertexIndex[vi] = textStart
                }
            }
            i += 1
        }

        // Parse vertices
        while headerEnded && readVertices < vertexCount && i < lines.count {
            let line = lines[i]
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String($0) }

            // We expect at least x y z r g b; may also have depth heading comment_id
            guard parts.count >= 6 else { i += 1; continue }
            let x = Float(parts[0]) ?? 0
            let y = Float(parts[1]) ?? 0
            let z = Float(parts[2]) ?? 0
            let r = Float(parts[3]) ?? 0
            let g = Float(parts[4]) ?? 0
            let b = Float(parts[5]) ?? 0

            var depth: Float? = nil
            var heading: Float? = nil
            var commentID: Int? = nil
            if parts.count >= 8 {
                depth = Float(parts[6])
                heading = Float(parts[7])
            }
            if parts.count >= 9 {
                commentID = Int(parts[8])
            }

            let p = Point3D(
                x: x, y: y, z: z,
                color: SIMD3<Float>(r/255.0, g/255.0, b/255.0),
                depth: depth, heading: heading, commentID: commentID,
                vertexIndex: readVertices
            )
            points.append(p)

            readVertices += 1
            i += 1
        }

        return LoadedPLY(points: points, commentsByVertexIndex: commentsByVertexIndex)
    }
}

// MARK: - Drawing

struct ProjectionView: View {
    var points: [CGPoint]
    var centerlinePoints: [CGPoint]
    var labels: [LabelPoint] = []

    var body: some View {
        Canvas { context, size in
            let allPoints = points + centerlinePoints + labels.map { $0.point }
            guard !allPoints.isEmpty else { return }

            let minX = allPoints.map { $0.x }.min() ?? 0
            let maxX = allPoints.map { $0.x }.max() ?? 1
            let minY = allPoints.map { $0.y }.min() ?? 0
            let maxY = allPoints.map { $0.y }.max() ?? 1

            let scaleX = size.width / max(0.0001, (maxX - minX))
            let scaleY = size.height / max(0.0001, (maxY - minY))
            let scale = min(scaleX, scaleY)

            let offset = CGPoint(x: -minX * scale, y: -minY * scale)

            func transform(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale + offset.x,
                        y: size.height - (point.y * scale + offset.y))
            }

            // Walls
            for point in points {
                let p = transform(point)
                let rect = CGRect(x: p.x, y: p.y, width: 1, height: 1)
                context.fill(Path(ellipseIn: rect), with: .color(.gray))
            }

            // Centerline
            if !centerlinePoints.isEmpty {
                var path = Path()
                path.move(to: transform(centerlinePoints[0]))
                for pt in centerlinePoints.dropFirst() {
                    path.addLine(to: transform(pt))
                }
                context.stroke(path, with: .color(.yellow), lineWidth: 1)
            }

            // Labels next to path points
            for label in labels {
                let p = transform(label.point)

                // small dot at the labeled vertex
                let dotRect = CGRect(x: p.x-1.5, y: p.y-1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: dotRect), with: .color(.white))

                // text a bit to the right/up
                let text = Text(label.text).font(.system(size: 10, weight: .regular, design: .default))
                context.draw(text, at: CGPoint(x: p.x + 6, y: p.y - 6), anchor: .topLeading)
            }
        }
    }
}

// MARK: - Zooming & Compass (unchanged)

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
                        .updating($gestureScale) { value, state, _ in state = value }
                        .onEnded { value in currentScale *= value },
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in state = value.translation }
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
