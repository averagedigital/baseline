import AthleteCore
import AthletePersonalization
import Foundation

struct LocalFoodItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(name)-\(estimatedGrams)" }
    let name: String
    let estimatedGrams: Double
    let gramsLow: Double
    let gramsHigh: Double
    let labelConfidence: Double
    let portionConfidence: Double
    let fdcID: Int?
    let kcalPer100g: Double
    let nutrientSource: String
    let caloriesLow: Double
    let caloriesHigh: Double
}

struct LocalFoodAnalysis: Codable, Equatable, Sendable {
    let containsFood: Bool
    let stored: Bool
    let duplicateOf: UUID?
    let observationID: UUID?
    let confidence: Double
    let caloriesLow: Double
    let caloriesHigh: Double
    let items: [LocalFoodItem]
}

struct LocalChatResponse: Codable, Equatable, Sendable {
    let threadID: UUID
    let answerMarkdown: String
    let recommendationCategory: String
    let evidenceIDs: [UUID]
    let foodIDs: [UUID]
    let contextDigest: String
    let feedbackContextID: UUID?

}

struct LocalFeedbackResponse: Codable, Equatable, Sendable {
    let stored: Bool
    let personalizationSamples: Int
}

struct LocalLatestSession: Codable, Equatable, Sendable {
    let id: UUID; let observedTo: Date; let trackingCoverage: Double?
    let activeTime: Double?; let restTime: Double?; let trackingGapTime: Double?; let setCount: Int?
}

struct LocalLatestFood: Codable, Equatable, Sendable {
    let id: UUID; let capturedAt: Date; let caloriesLow: Double; let caloriesHigh: Double; let items: [LocalFoodItem]
}

struct LocalHome: Codable, Equatable, Sendable {
    let latestSession: LocalLatestSession?
    let latestFood: LocalLatestFood?
    let suggestedAction: String
    let predictedDifficulty: Double?
    let predictionConfidence: Double
}

struct PersonalizationContext: Codable, Equatable, Sendable {
    let activeMinutes: Double; let setCount: Int; let workRestRatio: Double; let trackingCoverage: Double
    let sevenDayActiveMinutes: Double; let hoursSincePreviousSession: Double; let recentFoodKcalMidpoint: Double
}

actor LocalDeviceServices {
    private var latestSession: LocalLatestSession?
    private var latestFood: LocalLatestFood?
    private var difficulty = LocalDifficultyModel()
    private var threadID = UUID()

    func home() -> LocalHome {
        LocalHome(latestSession: latestSession, latestFood: latestFood, suggestedAction: "recovery", predictedDifficulty: difficulty.prediction, predictionConfidence: difficulty.prediction == nil ? 0 : 0.6)
    }

    func uploadEvidence<Payload: Encodable & Sendable>(envelope: EvidenceEnvelope, payload: Payload) {
        latestSession = LocalLatestSession(id: envelope.id, observedTo: envelope.observedTo, trackingCoverage: nil, activeTime: nil, restTime: nil, trackingGapTime: nil, setCount: nil)
    }

    func analyzeFood(jpeg: Data, capturedAt: Date) async throws -> LocalFoodAnalysis {
        // The optional CoreML detector owns real labels. No image bytes are retained here.
        LocalFoodAnalysis(containsFood: false, stored: false, duplicateOf: nil, observationID: nil, confidence: 0, caloriesLow: 0, caloriesHigh: 0, items: [])
    }

    func chat(threadID: UUID?, message: String) -> LocalChatResponse {
        self.threadID = threadID ?? self.threadID
        return LocalChatResponse(threadID: self.threadID, answerMarkdown: "Локальный Coach пока доступен только при наличии системной on-device языковой модели. Измерения и история продолжают работать локально.", recommendationCategory: "none", evidenceIDs: [], foodIDs: [], contextDigest: "local", feedbackContextID: nil)
    }

    func sendSessionRPE(value: Double, sourceEvidenceID: UUID, note: String, context: PersonalizationContext) -> LocalFeedbackResponse {
        let features = PersonalizationFeatures(activeMinutes: context.activeMinutes, setCount: Double(context.setCount), trackingCoverage: context.trackingCoverage, workRestRatio: context.workRestRatio, recentActiveMinutes: context.sevenDayActiveMinutes, hoursSincePrevious: context.hoursSincePreviousSession)
        difficulty.update(features: features, rpe: value)
        return LocalFeedbackResponse(stored: true, personalizationSamples: difficulty.samples)
    }

    func sendRecommendationReward(feedbackContextID: UUID, reward: Double, context: PersonalizationContext) -> LocalFeedbackResponse {
        LocalFeedbackResponse(stored: true, personalizationSamples: difficulty.samples)
    }

    func dismissFood(observationID: UUID) { latestFood = nil }
}
