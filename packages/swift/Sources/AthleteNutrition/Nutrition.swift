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
    public init(minimumConfidence: Double = 0.45) { self.minimumConfidence = minimumConfidence }

    public func stable(_ detections: [FoodDetection]) -> [FoodDetection] {
        detections.filter { $0.confidence >= minimumConfidence }.prefix(5).map { $0 }
    }
}
