//
//  TunnelMappingARViewContainer.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 1.04.25.
//


import SwiftUI
import RealityKit
import ARKit
import CoreLocation

struct TunnelMappingARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .none
        arView.session.run(config)

        context.coordinator.setup(arView: arView)
        arView.session.delegate = context.coordinator

        // Add UI label
        let label = UILabel()
        label.textColor = .white
        label.numberOfLines = 3
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 101
        arView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: arView.topAnchor, constant: 40),
            label.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20)
        ])

        // Add export button
        let exportButton = UIButton(type: .system)
        exportButton.setTitle("Export", for: .normal)
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        exportButton.layer.cornerRadius = 8
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.addTarget(context.coordinator, action: #selector(Coordinator.exportTapped), for: .touchUpInside)
        arView.addSubview(exportButton)

        NSLayoutConstraint.activate([
            exportButton.topAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.topAnchor, constant: 10),
            exportButton.trailingAnchor.constraint(equalTo: arView.trailingAnchor, constant: -20),
            exportButton.widthAnchor.constraint(equalToConstant: 80),
            exportButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Add reset button (bottom center like camera shutter)
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("⭯", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 28)
        resetButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        resetButton.layer.cornerRadius = 35
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addTarget(context.coordinator, action: #selector(Coordinator.resetSession), for: .touchUpInside)
        arView.addSubview(resetButton)

        NSLayoutConstraint.activate([
            resetButton.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
            resetButton.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            resetButton.widthAnchor.constraint(equalToConstant: 70),
            resetButton.heightAnchor.constraint(equalToConstant: 70)
        ])

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSessionDelegate, CLLocationManagerDelegate {
        private var arView: ARView?
        private var previousPosition: SIMD3<Float>?
        private var totalDistance: Float = 0.0
        private var pathPoints: [(position: SIMD3<Float>, distance: Float, heading: Double)] = []
        private let locationManager = CLLocationManager()
        private var currentHeading: CLHeading?
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.3

        func setup(arView: ARView) {
            self.arView = arView
            locationManager.delegate = self
            locationManager.headingFilter = 5
            locationManager.startUpdatingHeading()
            locationManager.requestWhenInUseAuthorization()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            currentHeading = newHeading
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let currentTime = frame.timestamp
            guard currentTime - lastUpdateTime >= updateInterval else { return }
            lastUpdateTime = currentTime

            let transform = frame.camera.transform
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

            DispatchQueue.main.async {
                self.placeMarker(at: position)
            }
        }

        func placeMarker(at position: SIMD3<Float>) {
            guard let arView = arView else { return }

            let sphere = MeshResource.generateSphere(radius: 0.005)
            var material = SimpleMaterial()
            material.color = .init(tint: .red, texture: nil)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = [0, 0, 0]

            let anchor = AnchorEntity(world: position)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            var segmentDistance: Float = 0.0
            if let previous = previousPosition {
                segmentDistance = simd_length(position - previous)
                guard segmentDistance > 0.01 else { return }

                let lineEntity = generateLine(from: previous, to: position)
                let lineAnchor = AnchorEntity(world: previous)
                lineAnchor.addChild(lineEntity)
                arView.scene.addAnchor(lineAnchor)

                totalDistance += segmentDistance
            }

            let heading = currentHeading?.magneticHeading ?? -1
            pathPoints.append((position: position, distance: totalDistance, heading: heading))

            updateLabel()
            previousPosition = position
        }

        func updateLabel() {
            guard let arView = arView,
                  let label = arView.viewWithTag(101) as? UILabel else { return }
            let distanceStr = String(format: "Distance: %.2f m", totalDistance)
            let headingStr = currentHeading != nil ? String(format: "Heading: %.0f°", currentHeading!.magneticHeading) : "Heading: --"
            label.text = "\(distanceStr)\n\(headingStr)\nTap with two fingers to export"
        }

        func generateLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> ModelEntity {
            let vector = end - start
            let distance = simd_length(vector)
            let midPoint = (start + end) / 2

            let cylinder = MeshResource.generateCylinder(height: distance, radius: 0.001)
            var material = SimpleMaterial()
            material.color = .init(tint: .green, texture: nil)

            let entity = ModelEntity(mesh: cylinder, materials: [material])
            entity.position = [0, 0, 0]

            let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), vector))
            let angle = acos(simd_dot(simd_normalize(vector), SIMD3<Float>(0, 1, 0)))
            if angle.isFinite {
                entity.transform.rotation = simd_quatf(angle: angle, axis: axis)
            }

            let container = ModelEntity()
            container.position = midPoint
            container.addChild(entity)

            return container
        }

        // Export path as CSV
        func exportPath() -> URL? {
            var csvString = "POINT_NUMBER,DISTANCE,HEADING\n"
            for (index, point) in pathPoints.enumerated() {
                let line = "\(index + 1),\(String(format: "%.2f", point.distance)),\(String(format: "%.1f", point.heading))\n"
                csvString.append(contentsOf: line)
            }

            let filename = FileManager.default.temporaryDirectory.appendingPathComponent("tunnel_path.csv")
            do {
                try csvString.write(to: filename, atomically: true, encoding: .utf8)
                return filename
            } catch {
                print("Failed to export CSV: \(error)")
                return nil
            }
        }

        @objc func resetSession() {
            guard let arView = arView else { return }
            arView.scene.anchors.removeAll()
            previousPosition = nil
            totalDistance = 0.0
            pathPoints.removeAll()
            updateLabel()
        }

        @objc func exportTapped() {
            guard let url = exportPath(), let arView = arView else { return }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let rootVC = arView.window?.rootViewController {
                rootVC.present(vc, animated: true)
            }
        }
    }
}
