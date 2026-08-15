import AthleteNutrition
import SwiftUI

struct FoodDetectionOverlay: View {
    let objects: [TrackedFoodObject]
    let sourceSize: CGSize
    let isMirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            ForEach(objects) { object in
                let rect = AspectFillGeometry.displayRect(normalizedVisionRect: object.boundingBox, sourceSize: sourceSize, previewSize: proxy.size, mirrored: isMirrored)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 1.5)
                    Text("\(object.label) · \(Int((object.confidence * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(.white.opacity(0.92), in: Capsule())
                        .offset(y: -24)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
