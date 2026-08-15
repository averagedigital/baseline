import Foundation

struct FoodLabelObservation: Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

struct FoodFrameGate: Sendable {
    private let evaluationInterval: TimeInterval
    private let uploadCooldown: TimeInterval
    private let requiredPositiveFrames: Int
    private var lastEvaluationAt: TimeInterval = -.infinity
    private var lastUploadAt: TimeInterval = -.infinity
    private var positiveFrames = 0

    init(
        evaluationInterval: TimeInterval = 1.5,
        uploadCooldown: TimeInterval = 20,
        requiredPositiveFrames: Int = 2
    ) {
        self.evaluationInterval = max(0.1, evaluationInterval)
        self.uploadCooldown = max(0, uploadCooldown)
        self.requiredPositiveFrames = max(1, requiredPositiveFrames)
    }

    mutating func shouldEvaluate(at timestamp: TimeInterval) -> Bool {
        guard timestamp - lastEvaluationAt >= evaluationInterval else { return false }
        lastEvaluationAt = timestamp
        return true
    }

    mutating func consume(
        observations: [FoodLabelObservation],
        at timestamp: TimeInterval
    ) -> Bool {
        let isPositive = observations.prefix(12).contains { observation in
            observation.confidence >= 0.10 && Self.foodKeywords.contains { keyword in
                observation.identifier.localizedCaseInsensitiveContains(keyword)
            }
        }
        positiveFrames = isPositive ? positiveFrames + 1 : 0
        guard positiveFrames >= requiredPositiveFrames,
              timestamp - lastUploadAt >= uploadCooldown else { return false }
        positiveFrames = 0
        lastUploadAt = timestamp
        return true
    }

    mutating func reset() {
        lastEvaluationAt = -.infinity
        lastUploadAt = -.infinity
        positiveFrames = 0
    }

    private static let foodKeywords = [
        "food", "dish", "plate", "meal", "breakfast", "lunch", "dinner",
        "salad", "rice", "pasta", "pizza", "sandwich", "bread", "soup",
        "fruit", "vegetable", "meat", "chicken", "fish", "dessert", "bowl",
    ]
}
