import AthleteNutrition
import SwiftUI

struct FoodDetectionOverlay: View {
    let objects: [TrackedFoodObject]
    let sourceSize: CGSize
    let isMirrored: Bool
    let nutritionByLabel: [String: LocalFoodItem]

    var body: some View {
        GeometryReader { proxy in
            ForEach(objects) { object in
                let rect = AspectFillGeometry.displayRect(normalizedVisionRect: object.boundingBox, sourceSize: sourceSize, previewSize: proxy.size, mirrored: isMirrored)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 1.5)
                    Text(FoodOverlayText.make(
                        label: object.label,
                        confidence: object.confidence,
                        nutrition: nutritionByLabel[object.label]
                    ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

enum FoodOverlayText {
    static func make(label: String, confidence: Double, nutrition: LocalFoodItem?) -> String {
        var parts = [nutrition?.name ?? label, "\(Int((confidence * 100).rounded()))%"]
        if let low = nutrition?.caloriesLow, let high = nutrition?.caloriesHigh {
            parts.append("\(Int(low.rounded()))–\(Int(high.rounded())) ккал")
        } else if let kcalPer100g = nutrition?.kcalPer100g {
            parts.append("\(Int(kcalPer100g.rounded())) ккал/100 г")
        }
        return parts.joined(separator: " · ")
    }
}
