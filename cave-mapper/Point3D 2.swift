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
    /// Tracking segment. Points in different segments were captured either side of
    /// a tracking loss and must not be joined by a line.
    var segment: Int = 0
    var vertexIndex: Int = 0
}

struct LoadedPLY {
    var points: [Point3D]
    /// comment text keyed by vertex_index (as written in the PLY header)
    var commentsByVertexIndex: [Int: String]
    /// Degrees to add to an in-cloud azimuth to obtain a compass bearing.
    /// Nil when the surveyor never tapped SET N, in which case the cloud has no
    /// north reference at all and any bearing derived from it is meaningless.
    var northOffsetDeg: Double? = nil
    var northAccuracyDeg: Double? = nil
    var northReference: String? = nil
}

struct LabelPoint {
    var point: CGPoint
    var text: String
}

/// Yellow vertices are the survey centerline; everything else is wall.
private func isCenterline(_ p: Point3D) -> Bool {
    p.color.x > 0.8 && p.color.y > 0.8 && p.color.z < 0.3
}

// MARK: - Main View

struct PlyVisualizerView: View {
    // Keep original 3D data so we can reproject dynamically
    @State private var allPoints3D: [Point3D] = []
    @State private var centerline3D: [Point3D] = []
    @State private var commentsByVertexIndex: [Int: String] = [:]

    @State private var northOffsetDeg: Double? = nil
    @State private var northAccuracyDeg: Double? = nil
    @State private var northReference: String? = nil

    // Plan view is always drawn north-up (when north is known), so it needs no
    // rotation control. The slider below chooses the profile's section azimuth,
    // which is what a surveyor actually wants to vary.
    @State private var planCenterline: [[CGPoint]] = []   // (east, north)
    @State private var planWalls: [CGPoint] = []
    @State private var labelsPlan: [LabelPoint] = []

    @State private var profileCenterline: [[CGPoint]] = [] // (along-section, height)
    @State private var profileWalls: [CGPoint] = []
    @State private var labelsProfile: [LabelPoint] = []

    /// Compass bearing of the vertical section drawn in the profile view.
    @State private var sectionAzimuth: Double = 0

    /// Straight-line bearing from the first centerline point to the last.
    @State private var trendBearing: Double = 0

    @State private var totalDistance: Double = 0
    @State private var maxDepth: Double = 0
    @State private var maxHeight: Double = 0

    @State private var isImporterPresented = false
    @State private var isExporting = false
    @State private var pendingShareURL: URL? = nil
    @State private var loadError: String? = nil

    @State private var mode3D: Bool = false
    @State private var tunnelOpacity: CGFloat = 0.4

    private var hasNorth: Bool { northOffsetDeg != nil }

    var body: some View {
        VStack {
            Toggle(isOn: $mode3D) {
                Text("3D Mode")
            }
            .padding(.bottom, 8)

            if mode3D {
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

                statsRow
                controlsRow
            } else {
                ZoomableView {
                    ProjectionView(
                        points: planWalls,
                        centerlineSegments: planCenterline,
                        labels: labelsPlan,
                        showVerticalScale: true,
                        showHorizontalScale: true,
                        axisUnitsSuffix: " m"
                    )
                }
                .frame(height: 200)
                .padding()
                Text(hasNorth ? "Plan View (north up)" : "Plan View (north not set)")
                    .font(.footnote)
                    .foregroundColor(hasNorth ? .secondary : .orange)

                ZoomableView {
                    ProjectionView(
                        points: profileWalls,
                        centerlineSegments: profileCenterline,
                        labels: labelsProfile,
                        showVerticalScale: true,
                        showHorizontalScale: true,
                        axisUnitsSuffix: " m"
                    )
                }
                .frame(height: 200)
                .padding()
                Text("Profile (section on \(Int(sectionAzimuth))°)")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Text(String(format: "Section azimuth: %.0f°", sectionAzimuth))
                    Slider(
                        value: $sectionAzimuth,
                        in: 0...359,
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { reproject() }
                        }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

                statsRow
                controlsRow
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
                if let url = urls.first { loadPLY(from: url) }
            case .failure(let error):
                loadError = error.localizedDescription
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
        .alert("Could not load file",
               isPresented: Binding(get: { loadError != nil },
                                    set: { if !$0 { loadError = nil } })) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            CompassView2(trendBearing: .degrees(trendBearing), northKnown: hasNorth)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Length: %.1f m", totalDistance))
                Text(String(format: "Depth: %.1f m   Height: +%.1f m", maxDepth, maxHeight))
                if hasNorth {
                    Text(String(format: "Trend: %.0f° %@%@",
                                trendBearing,
                                (northReference ?? "magnetic") == "true" ? "T" : "M",
                                (northAccuracyDeg ?? -1) >= 0
                                    ? String(format: " ±%.0f°", northAccuracyDeg ?? 0) : ""))
                } else {
                    Text("Trend: no north reference")
                        .foregroundColor(.orange)
                }
            }
            .font(.footnote)
            .padding(.vertical, 4)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            Button("Load PLY") { isImporterPresented = true }
            Button {
                exportPDFAndShare()
            } label: {
                if isExporting { ProgressView() } else { Text("Export PDF") }
            }
            .disabled(isExporting)
        }
    }

    // MARK: - Load & Parse

    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Security-scoped access is required for files picked outside the app
            // sandbox; without it the read silently returns nothing.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let loaded = Self.loadPLYPointsAndComments(from: url)

            DispatchQueue.main.async {
                guard !loaded.points.isEmpty else {
                    loadError = "No vertices found. Is this a CaveDiveMap PLY?"
                    return
                }
                allPoints3D = loaded.points
                centerline3D = loaded.points.filter(isCenterline)
                commentsByVertexIndex = loaded.commentsByVertexIndex
                northOffsetDeg = loaded.northOffsetDeg
                northAccuracyDeg = loaded.northAccuracyDeg
                northReference = loaded.northReference

                computeStats()
                // Default the section to run along the passage, which is the view a
                // surveyor almost always wants first.
                sectionAzimuth = trendBearing.rounded()
                reproject()
            }
        }
    }

    /// Memory-maps the file and walks it a line at a time. The previous version
    /// read the whole file into a String and then split it into an array of
    /// substrings, which for a large cloud meant several multiples of the file
    /// size resident at once.
    static func loadPLYPointsAndComments(from fileURL: URL) -> LoadedPLY {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return LoadedPLY(points: [], commentsByVertexIndex: [:])
        }

        var points: [Point3D] = []
        var commentsByVertexIndex: [Int: String] = [:]
        var northOffsetDeg: Double? = nil
        var northAccuracyDeg: Double? = nil
        var northReference: String? = nil

        var headerEnded = false
        var vertexCount = 0
        var readVertices = 0

        func handleHeaderLine(_ line: String) {
            if line == "end_header" {
                headerEnded = true
                return
            }
            if line.hasPrefix("element vertex"),
               let last = line.split(separator: " ").last,
               let n = Int(last) {
                vertexCount = n
                return
            }
            guard line.hasPrefix("comment ") else { return }
            let body = String(line.dropFirst("comment ".count))
            let tokens = body.split(separator: " ").map(String.init)
            guard let key = tokens.first else { return }

            switch key {
            case "north_offset_deg":
                northOffsetDeg = tokens.count > 1 ? Double(tokens[1]) : nil
            case "north_offset_accuracy_deg":
                northAccuracyDeg = tokens.count > 1 ? Double(tokens[1]) : nil
            case "north_reference":
                northReference = tokens.count > 1 ? tokens[1] : nil
            case "annotation":
                var vertexIndex: Int? = nil
                for (i, token) in tokens.enumerated() {
                    if token.hasPrefix("vertex_index=") {
                        vertexIndex = Int(token.dropFirst("vertex_index=".count))
                    }
                    if token.hasPrefix("text=") {
                        // Only the prefix is stripped; `replacingOccurrences` used to
                        // remove every "text=" occurring inside the comment itself.
                        let joined = tokens[i...].joined(separator: " ")
                        let raw = String(joined.dropFirst("text=".count))
                        // The writer percent-encodes so non-ASCII comments survive a
                        // header that has to stay ASCII. Older files were written
                        // literally, and decode to themselves.
                        let text = raw.removingPercentEncoding ?? raw
                        if let vi = vertexIndex, !text.isEmpty {
                            commentsByVertexIndex[vi] = text
                        }
                        return
                    }
                }
            default:
                break
            }
        }

        func handleVertexLine(_ line: String) {
            guard readVertices < vertexCount else { return }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 6 else { return }

            let x = Float(parts[0]) ?? 0
            let y = Float(parts[1]) ?? 0
            let z = Float(parts[2]) ?? 0
            let r = Float(parts[3]) ?? 0
            let g = Float(parts[4]) ?? 0
            let b = Float(parts[5]) ?? 0

            var depth: Float? = nil
            var heading: Float? = nil
            var commentID: Int? = nil
            var segment = 0
            if parts.count >= 8 {
                depth = Float(parts[6])
                heading = Float(parts[7])
            }
            if parts.count >= 9 { commentID = Int(parts[8]) }
            if parts.count >= 10 { segment = Int(parts[9]) ?? 0 }

            points.append(Point3D(x: x, y: y, z: z,
                                  color: SIMD3<Float>(r / 255.0, g / 255.0, b / 255.0),
                                  depth: depth, heading: heading, commentID: commentID,
                                  segment: segment, vertexIndex: readVertices))
            readVertices += 1
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lineStart = 0

            func emit(_ start: Int, _ end: Int) {
                var end = end
                if end > start, bytes[end - 1] == 0x0D { end -= 1 }   // strip CR
                guard end > start else { return }
                let slice = UnsafeBufferPointer(rebasing: bytes[start..<end])
                guard let line = String(bytes: slice, encoding: .utf8) else { return }
                if headerEnded { handleVertexLine(line) } else { handleHeaderLine(line) }
            }

            for i in 0..<bytes.count where bytes[i] == 0x0A {
                emit(lineStart, i)
                lineStart = i + 1
            }
            if lineStart < bytes.count { emit(lineStart, bytes.count) }
        }

        return LoadedPLY(points: points,
                         commentsByVertexIndex: commentsByVertexIndex,
                         northOffsetDeg: northOffsetDeg,
                         northAccuracyDeg: northAccuracyDeg,
                         northReference: northReference)
    }

    // MARK: - Geometry

    /// Converts a cloud point to horizontal east/north metres.
    /// `bearing = atan2(x, -z) + northOffset`, and (E, N) = r·(sin bearing, cos bearing).
    private func eastNorth(_ p: Point3D) -> (e: CGFloat, n: CGFloat) {
        let theta = (northOffsetDeg ?? 0) * .pi / 180.0
        let cosT = CGFloat(cos(theta)), sinT = CGFloat(sin(theta))
        let x = CGFloat(p.x), z = CGFloat(p.z)
        return (x * cosT - z * sinT, -z * cosT - x * sinT)
    }

    private func computeStats() {
        guard let first = centerline3D.first else {
            totalDistance = 0; maxDepth = 0; maxHeight = 0; trendBearing = 0
            return
        }

        // Full 3D length. Summing the top projection, as before, silently discarded
        // every metre of vertical travel on a sloping passage.
        var length: Double = 0
        for (a, b) in zip(centerline3D, centerline3D.dropFirst()) where a.segment == b.segment {
            let d = SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)
            length += Double(simd_length(d))
        }
        totalDistance = length

        let originY = first.y
        let ys = allPoints3D.map { Double($0.y - originY) }
        maxDepth = -(ys.min() ?? 0)      // positive below the start
        maxHeight = max(0, ys.max() ?? 0)

        if let last = centerline3D.last {
            let a = eastNorth(first), b = eastNorth(last)
            var bearing = atan2(Double(b.e - a.e), Double(b.n - a.n)) * 180.0 / .pi
            if bearing < 0 { bearing += 360 }
            trendBearing = bearing
        }
    }

    private func reproject() {
        let azimuth = sectionAzimuth * .pi / 180.0
        let sinAz = CGFloat(sin(azimuth)), cosAz = CGFloat(cos(azimuth))
        let originY = CGFloat(centerline3D.first?.y ?? 0)

        // Distance along the chosen vertical section.
        func alongSection(_ en: (e: CGFloat, n: CGFloat)) -> CGFloat {
            en.e * sinAz + en.n * cosAz
        }

        let walls = allPoints3D.filter { !isCenterline($0) }

        var newPlanWalls: [CGPoint] = []
        var newProfileWalls: [CGPoint] = []
        newPlanWalls.reserveCapacity(walls.count)
        newProfileWalls.reserveCapacity(walls.count)
        for p in walls {
            let en = eastNorth(p)
            newPlanWalls.append(CGPoint(x: en.e, y: en.n))
            newProfileWalls.append(CGPoint(x: alongSection(en), y: CGFloat(p.y) - originY))
        }

        // Break the centerline wherever tracking was lost, so the drawing never
        // implies travel across a gap that was never surveyed.
        var newPlanCenterline: [[CGPoint]] = []
        var newProfileCenterline: [[CGPoint]] = []
        var planRun: [CGPoint] = []
        var profileRun: [CGPoint] = []
        var currentSegment: Int? = nil

        for p in centerline3D {
            if let segment = currentSegment, segment != p.segment {
                if planRun.count > 1 { newPlanCenterline.append(planRun) }
                if profileRun.count > 1 { newProfileCenterline.append(profileRun) }
                planRun.removeAll()
                profileRun.removeAll()
            }
            currentSegment = p.segment
            let en = eastNorth(p)
            planRun.append(CGPoint(x: en.e, y: en.n))
            profileRun.append(CGPoint(x: alongSection(en), y: CGFloat(p.y) - originY))
        }
        if planRun.count > 1 { newPlanCenterline.append(planRun) }
        if profileRun.count > 1 { newProfileCenterline.append(profileRun) }

        var newLabelsPlan: [LabelPoint] = []
        var newLabelsProfile: [LabelPoint] = []
        for p in centerline3D {
            guard let text = commentsByVertexIndex[p.vertexIndex] else { continue }
            let en = eastNorth(p)
            newLabelsPlan.append(LabelPoint(point: CGPoint(x: en.e, y: en.n), text: text))
            newLabelsProfile.append(LabelPoint(
                point: CGPoint(x: alongSection(en), y: CGFloat(p.y) - originY), text: text))
        }

        planWalls = newPlanWalls
        planCenterline = newPlanCenterline
        labelsPlan = newLabelsPlan
        profileWalls = newProfileWalls
        profileCenterline = newProfileCenterline
        labelsProfile = newLabelsProfile
    }

    // MARK: - PDF Export

    private func exportPDFAndShare() {
        guard !planCenterline.isEmpty || !profileCenterline.isEmpty else {
            loadError = "Nothing to export yet — load a PLY first."
            return
        }
        isExporting = true

        let pageSize = CGSize(width: 595.2, height: 841.8)
        let pageBounds = CGRect(origin: .zero, size: pageSize)

        let pageBG = Color(white: 0.94)
        let panelBG = Color(white: 0.90)

        let statsPage = VStack(alignment: .leading, spacing: 18) {
            Text("Cave Survey")
                .font(.title)
                .bold()

            HStack(spacing: 14) {
                CompassView2(trendBearing: .degrees(trendBearing), northKnown: hasNorth)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Length: %.1f m", totalDistance))
                    Text(String(format: "Depth: %.1f m", maxDepth))
                    Text(String(format: "Height: +%.1f m", maxHeight))
                    if hasNorth {
                        Text(String(format: "Trend: %.0f° (%@)", trendBearing,
                                    northReference ?? "magnetic"))
                    } else {
                        Text("Trend: no north reference recorded")
                    }
                    Text(String(format: "Section azimuth: %.0f°", sectionAzimuth))
                }
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !hasNorth {
                Text("⚠️ This survey carries no north reference. The plan view "
                     + "orientation is arbitrary and must not be used for bearings.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Text("Generated on \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("Generated by CaveDiveMap")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(28)
        .frame(width: pageSize.width, height: pageSize.height)
        .background(pageBG)

        func plotPage(title: String, walls: [CGPoint],
                      centerline: [[CGPoint]], labels: [LabelPoint]) -> AnyView {
            AnyView(VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2).bold()
                ZStack {
                    panelBG.cornerRadius(8)
                    ProjectionView(
                        points: walls,
                        centerlineSegments: centerline,
                        labels: labels,
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
            .background(pageBG))
        }

        let planPage = plotPage(title: hasNorth ? "Plan View (north up)" : "Plan View (north not set)",
                                walls: planWalls, centerline: planCenterline, labels: labelsPlan)
        let profilePage = plotPage(title: String(format: "Profile (section on %.0f°)", sectionAzimuth),
                                   walls: profileWalls, centerline: profileCenterline, labels: labelsProfile)

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapExport-\(Int(Date().timeIntervalSince1970)).pdf")

        let renderScale = max(1.0, min(6.0, 300.0 / 72.0))

        DispatchQueue.main.async {
            do {
                let data = renderer.pdfData { ctx in
                    for page in [AnyView(statsPage), planPage, profilePage] {
                        ctx.beginPage()
                        UIGraphicsGetCurrentContext()?.interpolationQuality = .high
                        if let img = renderSwiftUIView(page, size: pageSize, scale: renderScale) {
                            img.draw(in: pageBounds)
                        }
                    }
                }
                try data.write(to: tmpURL, options: .atomic)
                self.isExporting = false
                self.presentShareSheet(with: tmpURL)
            } catch {
                self.isExporting = false
                self.loadError = "Failed to create PDF: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func renderSwiftUIView<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(size)
        renderer.scale = scale
        return renderer.uiImage
    }

    private func presentShareSheet(with url: URL) {
        guard let rootVC = topMostViewController() else { return }
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
    /// One polyline per tracking segment; they are drawn separately so a tracking
    /// gap never appears as a surveyed leg.
    var centerlineSegments: [[CGPoint]]
    var labels: [LabelPoint] = []
    var showVerticalScale: Bool = false
    var showHorizontalScale: Bool = false
    var axisUnitsSuffix: String = " m"
    var labelColor: Color = .primary

    private let axisColor = Color.gray.opacity(0.6)
    private let gridColor = Color.gray.opacity(0.25)

    var body: some View {
        Canvas { context, size in
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude

            func extend(_ p: CGPoint) {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            points.forEach(extend)
            centerlineSegments.forEach { $0.forEach(extend) }
            labels.forEach { extend($0.point) }
            guard minX <= maxX else { return }

            let leftGutter: CGFloat = showVerticalScale ? 44 : 0
            let bottomGutter: CGFloat = showHorizontalScale ? 28 : 0

            let drawableWidth = max(1, size.width - leftGutter)
            let drawableHeight = max(1, size.height - bottomGutter)
            // A single scale for both axes keeps the drawing to true proportions —
            // a map with different horizontal and vertical scales is not a map.
            let scale = min(drawableWidth / max(0.0001, maxX - minX),
                            drawableHeight / max(0.0001, maxY - minY))

            func transform(_ point: CGPoint) -> CGPoint {
                CGPoint(x: leftGutter + (point.x - minX) * scale,
                        y: (size.height - bottomGutter) - (point.y - minY) * scale)
            }

            let targetPxPerTick: CGFloat = 80
            let stepX = niceStep(range: maxX - minX, pixelSpan: drawableWidth, targetPx: targetPxPerTick)
            let stepY = niceStep(range: maxY - minY, pixelSpan: drawableHeight, targetPx: targetPxPerTick)

            if showVerticalScale {
                drawVerticalScale(context: &context, size: size, minY: minY, maxY: maxY,
                                  scale: scale, leftGutter: leftGutter,
                                  bottomGutter: bottomGutter, units: axisUnitsSuffix, step: stepY)
            }
            if showHorizontalScale {
                drawHorizontalScale(context: &context, size: size, minX: minX, maxX: maxX,
                                    scale: scale, leftGutter: leftGutter,
                                    bottomGutter: bottomGutter, units: axisUnitsSuffix, step: stepX)
            }

            // Walls, as a single accumulated path rather than one fill call per
            // point — a cloud of 100k points was 100k separate draw calls.
            var wallPath = Path()
            for point in points {
                let p = transform(point)
                wallPath.addRect(CGRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            context.fill(wallPath, with: .color(.gray))

            for segment in centerlineSegments where segment.count > 1 {
                var path = Path()
                path.move(to: transform(segment[0]))
                for pt in segment.dropFirst() { path.addLine(to: transform(pt)) }
                context.stroke(path, with: .color(.yellow), lineWidth: 1)
            }

            let resolvedLabelColor = resolveLabelColor()
            for label in labels {
                let p = transform(label.point)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                             with: .color(.white))
                context.draw(Text(label.text)
                                .font(.system(size: 10))
                                .foregroundColor(resolvedLabelColor),
                             at: CGPoint(x: p.x + 6, y: p.y - 6), anchor: .topLeading)
            }
        }
    }

    private func resolveLabelColor() -> Color {
        if labelColor == .black { return .black }
        if labelColor == .white { return .white }
        if labelColor == .secondary { return Color(UIColor.secondaryLabel) }
        return Color(UIColor.label)
    }

    // MARK: - Axes

    private func drawVerticalScale(context: inout GraphicsContext, size: CGSize,
                                   minY: CGFloat, maxY: CGFloat, scale: CGFloat,
                                   leftGutter: CGFloat, bottomGutter: CGFloat,
                                   units: String, step: CGFloat) {
        guard maxY > minY, step > 0 else { return }

        let fontSize = clamp(step * scale * 0.45, min: 7, max: 12)
        let labelFont = Font.system(size: fontSize)

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: leftGutter - 1, y: 0))
        axisPath.addLine(to: CGPoint(x: leftGutter - 1, y: size.height - bottomGutter))
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)

        var yValue = ceil(minY / step) * step
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

            context.draw(Text(String(format: "%.0f%@", yValue, units))
                            .font(labelFont).foregroundColor(.secondary),
                         at: CGPoint(x: leftGutter - 10, y: yCanvas), anchor: .trailing)
            yValue += step
        }
    }

    private func drawHorizontalScale(context: inout GraphicsContext, size: CGSize,
                                     minX: CGFloat, maxX: CGFloat, scale: CGFloat,
                                     leftGutter: CGFloat, bottomGutter: CGFloat,
                                     units: String, step: CGFloat) {
        guard maxX > minX, step > 0 else { return }

        let fontSize = clamp(step * scale * 0.45, min: 7, max: 12)
        let labelFont = Font.system(size: fontSize)

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: leftGutter - 1, y: size.height - bottomGutter + 1))
        axisPath.addLine(to: CGPoint(x: size.width, y: size.height - bottomGutter + 1))
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)

        var xValue = ceil(minX / step) * step
        while xValue <= maxX + 0.0001 {
            let xCanvas = leftGutter + ((xValue - minX) * scale)

            var tick = Path()
            tick.move(to: CGPoint(x: xCanvas, y: size.height - bottomGutter + 1))
            tick.addLine(to: CGPoint(x: xCanvas, y: size.height - bottomGutter + 6))
            context.stroke(tick, with: .color(axisColor), lineWidth: 1)

            context.draw(Text(String(format: "%.0f%@", xValue, units))
                            .font(labelFont).foregroundColor(.secondary),
                         at: CGPoint(x: xCanvas, y: size.height - bottomGutter + 12), anchor: .top)
            xValue += step
        }
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }

    private func niceStep(range: CGFloat, pixelSpan: CGFloat, targetPx: CGFloat) -> CGFloat {
        guard range.isFinite, range > 0, pixelSpan > 0, targetPx > 0 else { return 1 }
        let rawStep = range / Swift.max(1.0, pixelSpan / targetPx)
        let base = pow(10.0, floor(log10(rawStep)))
        let fraction = rawStep / base

        let niceFraction: CGFloat
        if fraction <= 1.0 { niceFraction = 1.0 }
        else if fraction <= 2.0 { niceFraction = 2.0 }
        else if fraction <= 5.0 { niceFraction = 5.0 }
        else { niceFraction = 10.0 }

        return niceFraction * base
    }
}

// MARK: - Zooming & Compass

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
                        .onEnded { value in
                            // Keep the view recoverable: unbounded zoom-out used to
                            // shrink the map to an unfindable dot.
                            currentScale = min(max(currentScale * value, 0.25), 20)
                        },
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation { currentScale = 1.0; offset = .zero }
            }
    }
}

/// North is fixed at the top — the plan view is drawn north-up — and the red
/// needle shows the survey's overall trend. Previously the needle was rotated by
/// the map rotation while "N" stayed put, which made the two disagree.
struct CompassView2: View {
    var trendBearing: Angle
    var northKnown: Bool = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray, lineWidth: 1)
            Arrow()
                .rotationEffect(trendBearing)
                .foregroundColor(northKnown ? .red : .gray)
            Text("N")
                .font(.caption2)
                .offset(y: -30)
                .foregroundColor(northKnown ? .red : .gray)
            if !northKnown {
                Text("?")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .offset(y: 18)
            }
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
