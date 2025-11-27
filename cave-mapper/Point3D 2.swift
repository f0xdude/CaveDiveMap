import SwiftUI
import simd
import UniformTypeIdentifiers
import CoreGraphics
import UIKit

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
    // Keep original 3D data so we can reproject dynamically
    @State private var allPoints3D: [Point3D] = []
    @State private var centerline3D: [Point3D] = []
    @State private var commentsByVertexIndex: [Int: String] = [:]

    // Separate centerlines for each projection (2D)
    @State private var centerlineTopPoints: [CGPoint] = []   // (x, z)
    @State private var centerlineSidePoints: [CGPoint] = []  // (x, y)

    @State private var wallTopPoints: [CGPoint] = []   // (x, z)
    @State private var wallSidePoints: [CGPoint] = []  // (x, y)

    @State private var labelsTop: [LabelPoint] = []    // (x, z)
    @State private var labelsSide: [LabelPoint] = []   // (x, y)

    // User-controlled rotation around Y (degrees)
    @State private var rotationYDegrees: Double = 0

    @State private var angleDegrees: Double = 0
    @State private var isImporterPresented = false
    @State private var isExporting = false
    @State private var pendingShareURL: URL? = nil

    // NEW: Toggle between 2D and 3D
    @State private var mode3D: Bool = false

    // Hard-coded opacity for tunnel mesh in 3D view (no UI)
    @State private var tunnelOpacity: CGFloat = 0.4
    
    var totalDistance: Double {
        guard centerlineTopPoints.count > 1 else { return 0 }
        return zip(centerlineTopPoints, centerlineTopPoints.dropFirst())
            .map { a, b in hypot(a.x - b.x, a.y - b.y) }
            .reduce(0, +)
    }

    var maxDepth: Double {
        guard !wallSidePoints.isEmpty else { return 0 }
        return Double(wallSidePoints.map { $0.y }.min() ?? 0)
    }

    var body: some View {
        VStack {
            // Toggle 2D/3D mode
            Toggle(isOn: $mode3D) {
                Text("3D Mode")
            }
            .padding(.bottom, 8)

            if mode3D {
                // 3D view
                PointCloud3DView(
                    points: allPoints3D,
                    centerline: centerline3D,
                    tubeRadius: 0.5,
                    tubeSides: 16,
                    showAxes: true,
                    showGrid: false,
                    buildTunnelMesh: true,
                    tunnelOpacity: $tunnelOpacity
                )
                .frame(height: 320)
                .padding(.horizontal)

                // Keep some stats visible under 3D
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

                // Export still available in 3D mode
                HStack(spacing: 16) {
                    Button("Load PLY") {
                        isImporterPresented = true
                    }
                    Button {
                        exportPDFAndShare()
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Export PDF")
                        }
                    }
                    .disabled(isExporting)
                }
            } else {
                // 2D projections (existing UI)
                // Top projection (X-Z)
                ZoomableView {
                    ProjectionView(
                        points: wallTopPoints,
                        centerlinePoints: centerlineTopPoints,
                        labels: labelsTop,
                        showVerticalScale: true,
                        showHorizontalScale: true,
                        axisUnitsSuffix: " m"
                    )
                }
                .frame(height: 200)
                .padding()
                Text("Top View (X-Z)")

                // Side projection (X-Y)
                ZoomableView {
                    ProjectionView(
                        points: wallSidePoints,
                        centerlinePoints: centerlineSidePoints, // (x’, y’)
                        labels: labelsSide,
                        showVerticalScale: true,
                        showHorizontalScale: true,
                        axisUnitsSuffix: " m"
                    )
                }
                .frame(height: 200)
                .padding()
                Text("Side View (X-Y)")

                // Rotation control for Y-axis (affects both views since we rotate the 3D data)
                VStack(spacing: 8) {
                    Text(String(format: "Rotate Y: %.0f°", rotationYDegrees))
                    Slider(
                        value: $rotationYDegrees,
                        in: -180...180,
                        step: 1,
                        onEditingChanged: { editing in
                            // Only reproject when the user finishes interacting with the slider
                            if !editing {
                                reproject(using: rotationYDegrees)
                            }
                        }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

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

                HStack(spacing: 16) {
                    Button("Load PLY") {
                        isImporterPresented = true
                    }
                    Button {
                        exportPDFAndShare()
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Export PDF")
                        }
                    }
                    .disabled(isExporting)
                }
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
        .onChange(of: isImporterPresented) { _, isPresented in
            if !isPresented, let url = pendingShareURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    presentShareSheet(with: url)
                    pendingShareURL = nil
                }
            }
        }
    }
    
    // MARK: - Load & Parse

    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadPLYPointsAndComments(from: url)
            let points = loaded.points
            let commentsByVertex = loaded.commentsByVertexIndex

            // Split centerline vs walls by color (yellow-ish)
            let isYellow: (Point3D) -> Bool = { p in
                p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
            }
            let centerline = points.filter(isYellow)

            DispatchQueue.main.async {
                // Keep originals for dynamic reprojection
                allPoints3D = points
                centerline3D = centerline
                commentsByVertexIndex = commentsByVertex

                // Initial projection using current rotation (0 by default)
                reproject(using: rotationYDegrees)
            }
        }
    }

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
                let comps = line.split(separator: " ")
                var vIndex: Int? = nil
                var textStart: String = ""
                for (idx, token) in comps.enumerated() {
                    if token.hasPrefix("vertex_index=") {
                        let val = token.replacingOccurrences(of: "vertex_index=", with: "")
                        vIndex = Int(val)
                    }
                    if token.hasPrefix("text=") {
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

        while headerEnded && readVertices < vertexCount && i < lines.count {
            let line = lines[i]
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { String($0) }

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

    // MARK: - Reprojection with Y rotation

    private func reproject(using rotationDegrees: Double) {
        let radians = rotationDegrees * .pi / 180.0
        let cosT = CGFloat(cos(radians))
        let sinT = CGFloat(sin(radians))

        // Rotate around Y: x' = x*cosT + z*sinT, z' = -x*sinT + z*cosT, y' = y
        func rotateY(_ p: Point3D) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
            let x = CGFloat(p.x)
            let y = CGFloat(p.y)
            let z = CGFloat(p.z)
            let xr = x * cosT + z * sinT
            let zr = -x * sinT + z * cosT
            return (xr, y, zr)
        }

        // Split walls vs centerline from originals
        let isYellow: (Point3D) -> Bool = { p in
            p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
        }
        let walls3D = allPoints3D.filter { !isYellow($0) }

        // Rotate and project
        let rotatedCenterline = centerline3D.map(rotateY)
        let rotatedWalls = walls3D.map(rotateY)

        let newCenterlineTop = rotatedCenterline.map { CGPoint(x: $0.x, y: $0.z) }   // (x’, z’)
        let newCenterlineSide = rotatedCenterline.map { CGPoint(x: $0.x, y: $0.y) }  // (x’, y’)

        let newWallTop = rotatedWalls.map { CGPoint(x: $0.x, y: $0.z) }              // (x’, z’)
        let newWallSide = rotatedWalls.map { CGPoint(x: $0.x, y: $0.y) }             // (x’, y’)

        // Labels from rotated centerline
        var newLabelsTop: [LabelPoint] = []
        var newLabelsSide: [LabelPoint] = []
        for p in centerline3D {
            if let text = commentsByVertexIndex[p.vertexIndex] {
                let pr = rotateY(p)
                newLabelsTop.append(LabelPoint(point: CGPoint(x: pr.x, y: pr.z), text: text))
                newLabelsSide.append(LabelPoint(point: CGPoint(x: pr.x, y: pr.y), text: text))
            }
        }

        // Heading angle based on rotated top centerline
        let newAngle: Double = {
            guard let s = newCenterlineTop.first, let e = newCenterlineTop.last else { return 0 }
            let dx = e.x - s.x
            let dy = e.y - s.y
            var angle = atan2(dx, dy) * 180.0 / .pi
            if angle < 0 { angle += 360 }
            return angle
        }()

        // Push to UI
        centerlineTopPoints = newCenterlineTop
        centerlineSidePoints = newCenterlineSide
        wallTopPoints = newWallTop
        wallSidePoints = newWallSide
        labelsTop = newLabelsTop
        labelsSide = newLabelsSide
        angleDegrees = newAngle
    }

    // MARK: - PDF Export (multi-page with stats on first page, readable background)

    private func exportPDFAndShare() {
        guard !centerlineTopPoints.isEmpty || !centerlineSidePoints.isEmpty else {
            print("Nothing to export yet.")
            return
        }
        isExporting = true

        // A4 portrait in points (72 dpi)
        let pageSize = CGSize(width: 595.2, height: 841.8)
        let pageBounds = CGRect(origin: .zero, size: pageSize)

        let pageBG = Color(white: 0.94)   // light gray page background
        let panelBG = Color(white: 0.90)  // slightly darker panel behind plots

        // Page 1: Stats
        let statsPage = VStack(alignment: .leading, spacing: 18) {
            Text("Point Cloud Map")
                .font(.title)
                .bold()

            HStack(spacing: 14) {
                CompassView2(mapRotation: .degrees(angleDegrees))
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Total Distance: %.1f m", totalDistance))
                    Text(String(format: "Max Depth: %.1f m", maxDepth))
                    Text(String(format: "Rotation Y: %.0f°", rotationYDegrees))
                }
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Details")
                .font(.headline)
                .padding(.top, 8)
            Text("Generated on \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("Generated by CaveDiveMapApp")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(28)
        .frame(width: pageSize.width, height: pageSize.height)
        .background(pageBG)

        // Page 2: Top View
        let topViewPage = VStack(alignment: .leading, spacing: 12) {
            Text("Top View (X–Z)")
                .font(.title2).bold()

            ZStack {
                panelBG
                    .cornerRadius(8)
                ProjectionView(
                    points: wallTopPoints,
                    centerlinePoints: centerlineTopPoints,
                    labels: labelsTop,
                    showVerticalScale: true,
                    showHorizontalScale: true,
                    axisUnitsSuffix: " m",
                    labelColor: .black
                )
                .padding(10)
            }
            .frame(height: pageSize.height - 120)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: pageSize.width, height: pageSize.height)
        .background(pageBG)

        // Page 3: Side View
        let sideViewPage = VStack(alignment: .leading, spacing: 12) {
            Text("Side View (X–Y)")
                .font(.title2).bold()

            ZStack {
                panelBG
                    .cornerRadius(8)
                ProjectionView(
                    points: wallSidePoints,
                    centerlinePoints: centerlineSidePoints,
                    labels: labelsSide,
                    showVerticalScale: true,
                    showHorizontalScale: true,
                    axisUnitsSuffix: " m",
                    labelColor: .black
                )
                .padding(10)
            }
            .frame(height: pageSize.height - 120)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: pageSize.width, height: pageSize.height)
        .background(pageBG)

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("MapExport-\(Int(Date().timeIntervalSince1970)).pdf")

        // Choose a target DPI for export. 300 dpi is typical for print quality.
        let targetPrintDPI: CGFloat = 300
        let pointsPerInch: CGFloat = 72
        // Render scale to achieve target DPI inside a 72-pt-per-inch PDF page.
        let renderScale = max(1.0, min(6.0, targetPrintDPI / pointsPerInch))

        // Render on main thread; ImageRenderer works with SwiftUI views (including Canvas)
        DispatchQueue.main.async {
            do {
                let data = renderer.pdfData { ctx in
                    // Page 1
                    ctx.beginPage()
                    if let cg = UIGraphicsGetCurrentContext() {
                        cg.interpolationQuality = .high
                    }
                    if let img = renderSwiftUIView(statsPage, size: pageSize, scale: renderScale) {
                        img.draw(in: pageBounds)
                    }

                    // Page 2
                    ctx.beginPage()
                    if let cg = UIGraphicsGetCurrentContext() {
                        cg.interpolationQuality = .high
                    }
                    if let img = renderSwiftUIView(topViewPage, size: pageSize, scale: renderScale) {
                        img.draw(in: pageBounds)
                    }

                    // Page 3
                    ctx.beginPage()
                    if let cg = UIGraphicsGetCurrentContext() {
                        cg.interpolationQuality = .high
                    }
                    if let img = renderSwiftUIView(sideViewPage, size: pageSize, scale: renderScale) {
                        img.draw(in: pageBounds)
                    }
                }
                try data.write(to: tmpURL, options: .atomic)
                self.isExporting = false
                self.presentShareSheet(with: tmpURL)
            } catch {
                self.isExporting = false
                print("Failed to create PDF: \(error)")
            }
        }
    }

    // Helper to render any SwiftUI view into a UIImage using ImageRenderer (iOS 16+)
    @MainActor
    private func renderSwiftUIView<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(size)
        renderer.scale = scale
        return renderer.uiImage
    }

    private func presentShareSheet(with url: URL) {
        guard let rootVC = topMostViewController() else {
            print("No root view controller to present share sheet.")
            return
        }
        if rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    presentShareSheet(with: url)
                }
            }
            return
        }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = rootVC.view
            pop.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 1, height: 1)
        }
        rootVC.present(activityVC, animated: true)
    }

    private func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - Drawing

struct ProjectionView: View {
    var points: [CGPoint]
    var centerlinePoints: [CGPoint]
    var labels: [LabelPoint] = []
    var showVerticalScale: Bool = false
    var showHorizontalScale: Bool = false
    var axisUnitsSuffix: String = " m"
    var labelColor: Color = .primary // default for on-screen; can override for PDF

    // Style
    private let axisColor = Color.gray.opacity(0.6)
    private let gridColor = Color.gray.opacity(0.25)

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let allPoints = points + centerlinePoints + labels.map { $0.point }
                guard !allPoints.isEmpty else { return }

                // Data bounds
                let minX = allPoints.map { $0.x }.min() ?? 0
                let maxX = allPoints.map { $0.x }.max() ?? 1
                let minY = allPoints.map { $0.y }.min() ?? 0
                let maxY = allPoints.map { $0.y }.max() ?? 1

                // Gutters for axes/labels (slightly larger to avoid clipping)
                let leftGutter: CGFloat = showVerticalScale ? 44 : 0
                let bottomGutter: CGFloat = showHorizontalScale ? 28 : 0

                // Compute scale to fit remaining drawable area
                let drawableWidth = max(1, size.width - leftGutter)
                let drawableHeight = max(1, size.height - bottomGutter)
                let scaleX = drawableWidth / max(0.0001, (maxX - minX))
                let scaleY = drawableHeight / max(0.0001, (maxY - minY))
                let scale = min(scaleX, scaleY)

                // Offsets so min bounds align with drawable rect origin
                let offset = CGPoint(
                    x: leftGutter + (-minX * scale),
                    y: -minY * scale
                )

                func transform(_ point: CGPoint) -> CGPoint {
                    // Flip Y for SwiftUI coordinate system and account for bottom gutter
                    CGPoint(
                        x: point.x * scale + offset.x,
                        y: (size.height - bottomGutter) - (point.y * scale + offset.y)
                    )
                }

                // Dynamic “nice” tick steps based on span and drawable pixels
                let targetPxPerTick: CGFloat = 80
                let stepX = niceStep(range: maxX - minX, pixelSpan: drawableWidth, targetPx: targetPxPerTick)
                let stepY = niceStep(range: maxY - minY, pixelSpan: drawableHeight, targetPx: targetPxPerTick)

                if showVerticalScale {
                    drawVerticalScale(context: &context,
                                      size: size,
                                      minY: minY,
                                      maxY: maxY,
                                      scale: scale,
                                      leftGutter: leftGutter,
                                      bottomGutter: bottomGutter,
                                      units: axisUnitsSuffix,
                                      step: stepY)
                }
                if showHorizontalScale {
                    drawHorizontalScale(context: &context,
                                        size: size,
                                        minX: minX,
                                        maxX: maxX,
                                        scale: scale,
                                        leftGutter: leftGutter,
                                        bottomGutter: bottomGutter,
                                        units: axisUnitsSuffix,
                                        step: stepX)
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
                    let dotRect = CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dotRect), with: .color(.white))

                    // Resolve SwiftUI Color to a concrete color for reliable rendering
                    let uiColor: UIColor
                    if labelColor == .black {
                        uiColor = .black
                    } else if labelColor == .white {
                        uiColor = .white
                    } else if labelColor == .secondary {
                        uiColor = UIColor.secondaryLabel
                    } else if labelColor == .primary {
                        uiColor = UIColor.label
                    } else {
                        uiColor = .black
                    }

                    // Use Text (supported by GraphicsContext.draw)
                    let textView = Text(label.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color(uiColor))

                    context.draw(textView, at: CGPoint(x: p.x + 6, y: p.y - 6), anchor: .topLeading)
                }
            }
        }
    }

    // MARK: - Axes (dynamic step)

    private func drawVerticalScale(context: inout GraphicsContext,
                                   size: CGSize,
                                   minY: CGFloat,
                                   maxY: CGFloat,
                                   scale: CGFloat,
                                   leftGutter: CGFloat,
                                   bottomGutter: CGFloat,
                                   units: String,
                                   step: CGFloat) {
        guard maxY > minY, step > 0 else { return }

        let pxPerStep = step * scale
        let fontSize = clamp(pxPerStep * 0.45, min: 7, max: 12)
        let labelFont = Font.system(size: fontSize)

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: leftGutter - 1, y: 0))
        axisPath.addLine(to: CGPoint(x: leftGutter - 1, y: size.height - bottomGutter))
        // Use axisColor to maintain consistency
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)

        let start = ceil(minY / step) * step
        var yValue = start
        while yValue <= maxY + 0.0001 {
            let yCanvas = (size.height - bottomGutter) - ((yValue - minY) * scale)

            var grid = Path()
            grid.move(to: CGPoint(x: leftGutter - 1, y: yCanvas))
            grid.addLine(to: CGPoint(x: size.width, y: yCanvas))
            context.stroke(grid, with: .color(gridColor), lineWidth: 0.5)

            var tick = Path()
            tick.move(to: CGPoint(x: leftGutter - 8, y: yCanvas))
            tick.addLine(to: CGPoint(x: leftGutter - 1, y: yCanvas))
            context.stroke(tick, with: .color(axisColor), lineWidth: 1)

            let labelText = Text(String(format: "%.0f%@", yValue, units))
                .font(labelFont)
                .foregroundColor(.secondary)
            context.draw(labelText, at: CGPoint(x: leftGutter - 10, y: yCanvas), anchor: .trailing)

            yValue += step
        }
    }

    private func drawHorizontalScale(context: inout GraphicsContext,
                                     size: CGSize,
                                     minX: CGFloat,
                                     maxX: CGFloat,
                                     scale: CGFloat,
                                     leftGutter: CGFloat,
                                     bottomGutter: CGFloat,
                                     units: String,
                                     step: CGFloat) {
        guard maxX > minX, step > 0 else { return }

        let pxPerStep = step * scale
        let fontSize = clamp(pxPerStep * 0.45, min: 7, max: 12)
        let labelFont = Font.system(size: fontSize)

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: leftGutter - 1, y: size.height - bottomGutter + 1))
        axisPath.addLine(to: CGPoint(x: size.width, y: size.height - bottomGutter + 1))
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)

        let start = ceil(minX / step) * step
        var xValue = start
        while xValue <= maxX + 0.0001 {
            let xCanvas = leftGutter + ((xValue - minX) * scale)

            var tick = Path()
            tick.move(to: CGPoint(x: xCanvas, y: size.height - bottomGutter + 1))
            tick.addLine(to: CGPoint(x: xCanvas, y: size.height - bottomGutter + 6))
            context.stroke(tick, with: .color(axisColor), lineWidth: 1)

            let labelText = Text(String(format: "%.0f%@", xValue, units))
                .font(labelFont)
                .foregroundColor(.secondary)
            context.draw(labelText, at: CGPoint(x: xCanvas, y: size.height - bottomGutter + 12), anchor: .top)

            xValue += step
        }
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if value < min { return min }
        if value > max { return max }
        return value
    }

    private func niceStep(range: CGFloat, pixelSpan: CGFloat, targetPx: CGFloat) -> CGFloat {
        guard range.isFinite, range > 0, pixelSpan > 0, targetPx > 0 else { return 1 }
        let desiredTicks = max(1.0, pixelSpan / targetPx)
        let rawStep = range / desiredTicks
        let exponent = floor(log10(rawStep))
        let base = pow(10.0, exponent)
        let fraction = rawStep / base

        let niceFraction: CGFloat
        if fraction <= 1.0 { niceFraction = 1.0 }
        else if fraction <= 2.0 { niceFraction = 2.0 }
        else if fraction <= 5.0 { niceFraction = 5.0 }
        else { niceFraction = 10.0 }

        return niceFraction * base
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
