import AthleteCore
import AthleteNutrition
import AthletePersonalization
import AthleteSensors
import AthleteStore
import Foundation

struct LocalFoodItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(name)-\(estimatedGrams)" }
    let name: String; let estimatedGrams: Double; let gramsLow: Double; let gramsHigh: Double
    let labelConfidence: Double; let portionConfidence: Double; let fdcID: Int?; let kcalPer100g: Double
    let nutrientSource: String; let caloriesLow: Double; let caloriesHigh: Double
}
struct LocalFoodAnalysis: Codable, Equatable, Sendable {
    let containsFood: Bool; let stored: Bool; let duplicateOf: UUID?; let observationID: UUID?
    let confidence: Double; let caloriesLow: Double; let caloriesHigh: Double; let items: [LocalFoodItem]
}
struct LocalChatResponse: Codable, Equatable, Sendable {
    let threadID: UUID; let answerMarkdown: String; let recommendationCategory: String
    let evidenceIDs: [UUID]; let foodIDs: [UUID]; let contextDigest: String; let feedbackContextID: UUID?
}
struct LocalFeedbackResponse: Codable, Equatable, Sendable { let stored: Bool; let personalizationSamples: Int }
struct LocalLatestSession: Codable, Equatable, Sendable {
    let id: UUID; let observedTo: Date; let trackingCoverage: Double?; let activeTime: Double?
    let restTime: Double?; let trackingGapTime: Double?; let setCount: Int?
}
struct LocalLatestFood: Codable, Equatable, Sendable { let id: UUID; let capturedAt: Date; let caloriesLow: Double; let caloriesHigh: Double; let items: [LocalFoodItem] }
struct LocalHome: Codable, Equatable, Sendable {
    let latestSession: LocalLatestSession?; let latestFood: LocalLatestFood?; let suggestedAction: String
    let predictedDifficulty: Double?; let predictionConfidence: Double
}
struct PersonalizationContext: Codable, Equatable, Sendable {
    let activeMinutes: Double; let setCount: Int; let workRestRatio: Double; let trackingCoverage: Double
    let sevenDayActiveMinutes: Double; let hoursSincePreviousSession: Double; let recentFoodKcalMidpoint: Double
}
struct LocalFeedbackPayload: Codable, Sendable { let sourceEvidenceID: UUID; let rpe: Double; let note: String }
enum LocalCoachError: LocalizedError { case unavailable; var errorDescription: String? { "Локальная языковая модель недоступна на этом устройстве." } }

actor LocalDeviceServices {
    private let store: AthleteStore?

    init(store: AthleteStore? = nil) {
        if let store { self.store = store }
        else { self.store = nil }
    }

    func home() async throws -> LocalHome {
        guard let store else { throw LocalStorageError.unavailable }
        let evidence = try await store.latestEvidence(kind: "activity.session.v2")
        let session: LocalLatestSession?
        if let evidence, let payload = try await store.payload(for: evidence.id, as: SessionEvidenceV2.self) {
            session = LocalLatestSession(id: evidence.id, observedTo: payload.observedTo, trackingCoverage: payload.trackingCoverage, activeTime: payload.activeTime, restTime: payload.restTime, trackingGapTime: payload.trackingGapTime, setCount: payload.activeBlockCount)
        } else { session = nil }
        let state = try await store.loadPersonalizationState(as: DifficultyRegressionState.self)
        return LocalHome(latestSession: session, latestFood: nil, suggestedAction: "consistency", predictedDifficulty: nil, predictionConfidence: state.map { min(Double($0.sampleCount) / 20, 1) } ?? 0)
    }

    func uploadEvidence<Payload: Encodable & Sendable>(envelope: EvidenceEnvelope, payload: Payload) async throws { guard let store else { throw LocalStorageError.unavailable }; try await store.appendEvidence(envelope, payload: payload) }

    func analyzeFood(detections: [FoodDetection], capturedAt: Date) async throws -> LocalFoodAnalysis { throw FoodDetectorUnavailableError.nutritionDatabaseMissing }

    func chat(threadID: UUID?, message: String) async throws -> LocalChatResponse { throw LocalCoachError.unavailable }

    func sendSessionRPE(value: Double, sourceEvidenceID: UUID, note: String, context: PersonalizationContext) async throws -> LocalFeedbackResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard try await store.evidence(id: sourceEvidenceID) != nil else { throw AthleteStoreError.invalidIdentifier(sourceEvidenceID.uuidString) }
        var model = try await store.loadPersonalizationState(as: LocalDifficultyModel.self) ?? LocalDifficultyModel()
        let payload = try await store.payload(for: sourceEvidenceID, as: SessionEvidenceV2.self)
        let activeMinutes = (payload?.activeTime ?? context.activeMinutes * 60) / 60
        let restMinutes = (payload?.restTime ?? context.activeMinutes / max(context.workRestRatio, 0.01)) / 60
        let features = PersonalizationFeatures(activeMinutes: activeMinutes, setCount: Double(payload?.activeBlockCount ?? context.setCount), trackingCoverage: payload?.trackingCoverage ?? context.trackingCoverage, workRestRatio: activeMinutes / max(restMinutes, 1), recentActiveMinutes: context.sevenDayActiveMinutes, hoursSincePrevious: context.hoursSincePreviousSession, nutritionSignal: context.recentFoodKcalMidpoint)
        model.update(features: features, rpe: value)
        let event = StoredFeedbackEvent(id: UUID(), kind: "session.rpe", payload: LocalFeedbackPayload(sourceEvidenceID: sourceEvidenceID, rpe: value, note: note))
        _ = try await store.insertFeedbackEvent(event)
        try await store.savePersonalizationState(model, at: Date())
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let narrative = try UserNarrativeBuilder().make(text: note, sessionEvidenceID: sourceEvidenceID)
            let narrativeEnvelope = try narrative.envelope()
            try await store.appendEvidence(narrativeEnvelope, payload: narrative)
        }
        return LocalFeedbackResponse(stored: true, personalizationSamples: model.samples)
    }

    func sendRecommendationReward(feedbackContextID: UUID, reward: Double, context: PersonalizationContext) async throws -> LocalFeedbackResponse { throw LocalCoachError.unavailable }
    func dismissFood(observationID: UUID) async throws { guard let store else { throw LocalStorageError.unavailable }; try await store.dismissFoodObservation(id: observationID) }
}

enum LocalStorageError: LocalizedError { case unavailable; var errorDescription: String? { "Локальное хранилище недоступно." } }
enum FoodDetectorUnavailableError: LocalizedError {
    case modelMissing
    case nutritionDatabaseMissing
    var errorDescription: String? {
        switch self {
        case .modelMissing: "Food detection unavailable: model asset missing."
        case .nutritionDatabaseMissing: "Food analysis unavailable: local nutrition database asset missing."
        }
    }
}
