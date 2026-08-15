import Foundation

public struct FoodDetection: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let label: String
    public let confidence: Double
    public let boundingBox: NormalizedFoodRect

    public init(id: UUID = UUID(), label: String, confidence: Double, boundingBox: NormalizedFoodRect) {
        self.id = id; self.label = label; self.confidence = confidence; self.boundingBox = boundingBox
    }
}

public struct NormalizedFoodRect: Codable, Equatable, Sendable {
    public let x: Double; public let y: Double; public let width: Double; public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = max(0, width); self.height = max(0, height)
    }
}

public struct NutritionItem: Codable, Equatable, Sendable {
    public let canonicalName: String; public let aliases: [String]; public let kcalPer100g: Double
    public init(canonicalName: String, aliases: [String] = [], kcalPer100g: Double) {
        self.canonicalName = canonicalName; self.aliases = aliases; self.kcalPer100g = kcalPer100g
    }
}

public struct MealCalories: Equatable, Sendable {
    public let low: Double; public let high: Double
}

public struct NutritionDatabase: Sendable {
    public let items: [NutritionItem]
    public init(items: [NutritionItem]) { self.items = items }

    public func match(_ label: String) -> NutritionItem? {
        let normalized = Self.normalize(label)
        return items.first { item in
            ([item.canonicalName] + item.aliases).contains { Self.normalize($0) == normalized }
        } ?? items.first { item in
            let tokens = Set(normalized.split(separator: " "))
            return !tokens.isEmpty && tokens.isSubset(of: Set(Self.normalize(item.canonicalName).split(separator: " ")))
        }
    }

    public func calories(for item: NutritionItem, gramsLow: Double?, gramsHigh: Double?) -> MealCalories? {
        guard let gramsLow, let gramsHigh, gramsLow >= 0, gramsHigh >= gramsLow else { return nil }
        return MealCalories(low: gramsLow * item.kcalPer100g / 100, high: gramsHigh * item.kcalPer100g / 100)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
}

public protocol FoodObjectDetecting: Sendable {
    func detect(frame: FoodDetectionFrame) async throws -> [FoodDetection]
}

public struct FoodDetectionFrame: Sendable {
    public let timestamp: TimeInterval
    public init(timestamp: TimeInterval) { self.timestamp = timestamp }
}

public struct FoodDetectionTracker: Sendable {
    public let minimumConfidence: Double
    public let minimumHits: Int
    public let maximumMisses: Int
    private var tracks: [UUID: TrackedFoodObject] = [:]
    public init(minimumConfidence: Double = 0.45, minimumHits: Int = 2, maximumMisses: Int = 3) { self.minimumConfidence = minimumConfidence; self.minimumHits = minimumHits; self.maximumMisses = maximumMisses }

    public mutating func update(_ detections: [FoodDetection], at timestamp: TimeInterval) -> [TrackedFoodObject] {
        var matched = Set<UUID>()
        for detection in detections where detection.confidence >= minimumConfidence {
            let candidate = tracks.values.filter { !matched.contains($0.id) && $0.label == detection.label && $0.boundingBox.iou(with: detection.boundingBox) >= 0.1 }.min { $0.boundingBox.centerDistance(to: detection.boundingBox) < $1.boundingBox.centerDistance(to: detection.boundingBox) }
            if let candidate {
                var track = candidate; matched.insert(track.id); track.boundingBox = track.boundingBox.ema(with: detection.boundingBox, alpha: 0.35); track.confidence = 0.65 * track.confidence + 0.35 * detection.confidence; track.hitCount += 1; track.missCount = 0; track.lastSeenAt = timestamp; tracks[track.id] = track
            } else {
                let track = TrackedFoodObject(id: detection.id, label: detection.label, confidence: detection.confidence, boundingBox: detection.boundingBox, hitCount: 1, missCount: 0, firstSeenAt: timestamp, lastSeenAt: timestamp); tracks[track.id] = track
            }
        }
        for id in tracks.keys where !matched.contains(id) { tracks[id]?.missCount += 1 }
        tracks = tracks.filter { $0.value.missCount <= maximumMisses }
        return tracks.values.filter { $0.hitCount >= minimumHits }.sorted { $0.confidence > $1.confidence }.prefix(5).map { $0 }
    }
}

public struct TrackedFoodObject: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID; public var label: String; public var confidence: Double; public var boundingBox: NormalizedFoodRect
    public var hitCount: Int; public var missCount: Int; public let firstSeenAt: TimeInterval; public var lastSeenAt: TimeInterval
}

private extension NormalizedFoodRect {
    var center: (Double, Double) { (x + width / 2, y + height / 2) }
    func centerDistance(to other: NormalizedFoodRect) -> Double { hypot(center.0 - other.center.0, center.1 - other.center.1) }
    func iou(with other: NormalizedFoodRect) -> Double { let w = max(0, min(x + width, other.x + other.width) - max(x, other.x)); let h = max(0, min(y + height, other.y + other.height) - max(y, other.y)); let intersection = w * h; return intersection / max(width * height + other.width * other.height - intersection, 0.0001) }
    func ema(with other: NormalizedFoodRect, alpha: Double) -> NormalizedFoodRect { NormalizedFoodRect(x: x + alpha * (other.x - x), y: y + alpha * (other.y - y), width: width + alpha * (other.width - width), height: height + alpha * (other.height - height)) }
}
