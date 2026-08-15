import AthleteSensors
import CoreImage
import CoreVideo

protocol AppearanceSignatureExtracting: Sendable {
    func signature(pixelBuffer: CVPixelBuffer, boundingBox: NormalizedPoseRect) -> AppearanceSignature?
}

struct AppearanceSignatureExtractor: @unchecked Sendable, AppearanceSignatureExtracting {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func signature(pixelBuffer: CVPixelBuffer, boundingBox: NormalizedPoseRect) -> AppearanceSignature? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let margin = 0.08
        let x = max(0, boundingBox.x - margin * boundingBox.width) * CGFloat(width)
        let y = max(0, boundingBox.y - margin * boundingBox.height) * CGFloat(height)
        let right = min(1, boundingBox.x + boundingBox.width * (1 + margin)) * CGFloat(width)
        let top = min(1, boundingBox.y + boundingBox.height * (1 + margin)) * CGFloat(height)
        let crop = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: CGRect(x: x, y: y, width: max(1, right - x), height: max(1, top - y)))
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let bitmap = CGContext(data: &pixels, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.interpolationQuality = .low
        guard let image = context.createCGImage(crop, from: crop.extent) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        var descriptor = [Double](repeating: 0, count: 48)
        for row in 0..<32 { for column in 0..<32 {
            let region = (row / 16) * 2 + column / 16
            let offset = (row * 32 + column) * 4
            for channel in 0..<3 { descriptor[region * 12 + channel * 4 + min(3, Int(pixels[offset + channel]) / 64)] += 1 }
        }}
        let norm = sqrt(descriptor.reduce(0) { $0 + $1 * $1 })
        return AppearanceSignature(values: descriptor.map { Float($0 / max(norm, 0.0001)) })
    }
}
