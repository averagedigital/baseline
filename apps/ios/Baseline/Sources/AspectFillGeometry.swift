import CoreGraphics
import AthleteNutrition

enum AspectFillGeometry {
    static func displayRect(normalizedVisionRect: NormalizedFoodRect, sourceSize: CGSize, previewSize: CGSize, mirrored: Bool) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, previewSize.width > 0, previewSize.height > 0 else { return .zero }
        let sourceRect = CGRect(x: normalizedVisionRect.x * sourceSize.width, y: (1 - normalizedVisionRect.y - normalizedVisionRect.height) * sourceSize.height, width: normalizedVisionRect.width * sourceSize.width, height: normalizedVisionRect.height * sourceSize.height)
        let scale = max(previewSize.width / sourceSize.width, previewSize.height / sourceSize.height)
        let scaled = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        var rect = CGRect(x: sourceRect.minX * scale - (scaled.width - previewSize.width) / 2, y: sourceRect.minY * scale - (scaled.height - previewSize.height) / 2, width: sourceRect.width * scale, height: sourceRect.height * scale)
        if mirrored { rect.origin.x = previewSize.width - rect.maxX }
        return rect
    }
}
