import SwiftUI

struct StickMapView: View {
    var points: [CGPoint]
    @ObservedObject var viewModel: MagnetometerViewModel

    var body: some View {
        VStack {
            // Distance display at the top of the view
            Text("Distance: \(viewModel.distanceInMeters, specifier: "%.2f") meters")
                .font(.title2)
                .padding()

            GeometryReader { geometry in
                let size = geometry.size

                // Calculate the bounds of the points
                let (minX, maxX, minY, maxY) = calculateBounds(points: points)
                let width = maxX - minX
                let height = maxY - minY

                // Calculate scale to fit all points within the view, adding some padding
                let scaleX = size.width / (width == 0 ? 1 : width * 1.2)
                let scaleY = size.height / (height == 0 ? 1 : height * 1.2)
                let scale = min(scaleX, scaleY)

                // Calculate offsets to center the path
                let offsetX = size.width / 2 - ((minX + maxX) / 2) * scale
                let offsetY = size.height / 2 - ((minY + maxY) / 2) * scale

                ZStack {
                    // Draw the path, with a 90-degree left rotation
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: CGPoint(
                            x: firstPoint.x * scale + offsetX,
                            y: size.height - (firstPoint.y * scale + offsetY)
                        ))

                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(
                                x: point.x * scale + offsetX,
                                y: size.height - (point.y * scale + offsetY)
                            ))
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    .rotationEffect(.degrees(-90)) // Rotate the entire path 90 degrees to the left
                    .frame(width: size.width, height: size.height)

                    
                }
            }
            
        }
    }

    func calculateBounds(points: [CGPoint]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return (minX, maxX, minY, maxY)
    }
}
