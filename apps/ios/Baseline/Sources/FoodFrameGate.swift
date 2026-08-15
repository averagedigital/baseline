import Foundation
import AthleteNutrition

struct FoodFrameGate: Sendable {
    private let evaluationInterval: TimeInterval
    private let uploadCooldown: TimeInterval
    private let requiredPositiveFrames: Int
    private var lastEvaluationAt: TimeInterval = -.infinity
    private var lastUploadAt: TimeInterval = -.infinity
    private var positiveFrames = 0

    init(
        evaluationInterval: TimeInterval = 0.2,
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
        observations: [FoodDetection],
        at timestamp: TimeInterval
    ) -> Bool {
        let isPositive = observations.prefix(12).contains { $0.confidence >= 0.45 }
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
}
