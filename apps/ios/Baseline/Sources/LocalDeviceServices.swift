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
    let recommendationIsPersonalized: Bool; let recommendationConfidence: Double
    let predictedDifficulty: Double?; let difficultyConfidence: Double
    let recommendationExposureID: UUID?
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
        let latestFood = try await store.recentFoodObservations(limit: 1).first.flatMap { observation in
            try? JSONDecoder().decode(LocalLatestFood.self, from: observation.payload)
        }
        let state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        guard let evidence else {
            return LocalHome(latestSession: session, latestFood: latestFood, suggestedAction: CoachingAction.consistency.rawValue, recommendationIsPersonalized: false, recommendationConfidence: 0, predictedDifficulty: nil, difficultyConfidence: state.difficulty.dataConfidence, recommendationExposureID: nil)
        }
        let features = try await PersonalizationFeatureBuilder(store: store).features(for: evidence.id)
        let recommendation = state.bandit.choose(features: features)
        let prediction = state.difficulty.predict(features: features)
        var exposureID: UUID?
        if recommendation.personalized {
            let exposure = RecommendationExposure(action: recommendation.action, features: features, contextDigest: evidence.contentDigest)
            try await store.saveRecommendationExposure(StoredRecommendationExposure(id: exposure.id, payload: JSONEncoder().encode(exposure), createdAt: exposure.createdAt))
            exposureID = exposure.id
        }
        return LocalHome(latestSession: session, latestFood: latestFood, suggestedAction: recommendation.action.rawValue, recommendationIsPersonalized: recommendation.personalized, recommendationConfidence: recommendation.confidence, predictedDifficulty: prediction, difficultyConfidence: state.difficulty.dataConfidence, recommendationExposureID: exposureID)
    }

    func uploadEvidence<Payload: Encodable & Sendable>(envelope: EvidenceEnvelope, payload: Payload) async throws { guard let store else { throw LocalStorageError.unavailable }; try await store.appendEvidence(envelope, payload: payload) }

    func analyzeFood(detections: [FoodDetection], capturedAt: Date) async throws -> LocalFoodAnalysis { throw FoodDetectorUnavailableError.nutritionDatabaseMissing }

    func chat(threadID: UUID?, message: String) async throws -> LocalChatResponse { throw LocalCoachError.unavailable }

    func sendSessionRPE(eventID: UUID, value: Double, sourceEvidenceID: UUID, note: String) async throws -> LocalFeedbackResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard try await store.evidence(id: sourceEvidenceID) != nil else { throw AthleteStoreError.invalidIdentifier(sourceEvidenceID.uuidString) }
        if try await store.hasFeedbackEvent(id: eventID) {
            let state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
            return LocalFeedbackResponse(stored: false, personalizationSamples: state.difficulty.samples)
        }
        let state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        var model = state.difficulty
        let features = try await PersonalizationFeatureBuilder(store: store).features(for: sourceEvidenceID)
        model.update(features: features, rpe: value)
        let event = StoredFeedbackEvent(id: eventID, kind: "session.rpe", payload: LocalFeedbackPayload(sourceEvidenceID: sourceEvidenceID, rpe: value, note: note))
        _ = try await store.insertFeedbackEvent(event)
        try await store.savePersonalizationState(PersonalizationState(difficulty: model, bandit: state.bandit), at: Date())
        let narrative = SessionRPEEvidence(sessionEvidenceID: sourceEvidenceID, rpe: value, note: note.isEmpty ? nil : note)
        let narrativeEnvelope = try narrative.envelope()
        if try await store.hasEvidence(kind: "user.narrative.v1", derivedFrom: sourceEvidenceID) == false { try await store.appendEvidence(narrativeEnvelope, payload: narrative) }
        return LocalFeedbackResponse(stored: true, personalizationSamples: model.samples)
    }

    func sendRecommendationReward(feedbackContextID: UUID, reward: Double, context: PersonalizationContext) async throws -> LocalFeedbackResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard let stored = try await store.recommendationExposure(id: feedbackContextID) else { throw AthleteStoreError.invalidIdentifier(feedbackContextID.uuidString) }
        let exposure = try JSONDecoder().decode(RecommendationExposure.self, from: stored.payload)
        guard try await store.markRecommendationExposureRewarded(id: feedbackContextID, reward: reward) else { throw LocalStorageError.duplicate }
        var state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        guard let features = PersonalizationFeatures(values: exposure.featureVector, version: exposure.featureVersion) else { throw LocalStorageError.invalidExposure }
        state.bandit.update(action: exposure.action, features: features, reward: reward)
        try await store.savePersonalizationState(state, at: Date())
        return LocalFeedbackResponse(stored: true, personalizationSamples: state.bandit.totalExplicitRewards)
    }
    func dismissFood(observationID: UUID) async throws { guard let store else { throw LocalStorageError.unavailable }; try await store.dismissFoodObservation(id: observationID) }
}

enum LocalStorageError: LocalizedError { case unavailable; case duplicate; case invalidExposure; var errorDescription: String? { switch self { case .unavailable: "Локальное хранилище недоступно."; case .duplicate: "Оценка этого совета уже сохранена."; case .invalidExposure: "Некорректный snapshot рекомендации." } } }
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
