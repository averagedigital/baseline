import AthleteCore
import AthleteIntelligence
import AthleteNutrition
import AthletePersonalization
import AthleteSensors
import AthleteStore
import Foundation

struct LocalFoodItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(name)-\(kcalPer100g)" }
    let name: String; let estimatedGrams: Double?; let gramsLow: Double?; let gramsHigh: Double?
    let labelConfidence: Double; let portionConfidence: Double?; let fdcID: Int?; let kcalPer100g: Double
    let nutrientSource: String; let caloriesLow: Double?; let caloriesHigh: Double?
}
struct LocalFoodAnalysis: Codable, Equatable, Sendable {
    let containsFood: Bool; let stored: Bool; let duplicateOf: UUID?; let observationID: UUID?
    let confidence: Double; let caloriesLow: Double?; let caloriesHigh: Double?; let items: [LocalFoodItem]
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
struct LocalLatestFood: Codable, Equatable, Sendable { let id: UUID; let capturedAt: Date; let caloriesLow: Double?; let caloriesHigh: Double?; let items: [LocalFoodItem] }
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
struct LocalRecommendationRewardPayload: Codable, Sendable { let exposureID: UUID; let reward: Double }
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
        let latestFood = try await store.recentFoodObservations(limit: 20).first(where: { !$0.dismissed }).flatMap { observation in
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

    func analyzeFood(detections: [FoodDetection], capturedAt: Date) async throws -> LocalFoodAnalysis {
        guard let url = Bundle.main.url(forResource: "nutrition", withExtension: "sqlite") else { throw FoodDetectorUnavailableError.nutritionDatabaseMissing }
        let database = try NutritionDatabase(path: url.path)
        let items = detections.compactMap { detection -> LocalFoodItem? in
            guard let item = database.match(detection.label) else { return nil }
            return LocalFoodItem(name: item.canonicalName, estimatedGrams: nil, gramsLow: nil, gramsHigh: nil, labelConfidence: detection.confidence, portionConfidence: nil, fdcID: nil, kcalPer100g: item.kcalPer100g, nutrientSource: "nutrition.sqlite", caloriesLow: nil, caloriesHigh: nil)
        }
        guard !items.isEmpty else { return LocalFoodAnalysis(containsFood: false, stored: false, duplicateOf: nil, observationID: nil, confidence: 0, caloriesLow: nil, caloriesHigh: nil, items: []) }
        let observationID = UUID()
        let snapshot = LocalLatestFood(id: observationID, capturedAt: capturedAt, caloriesLow: nil, caloriesHigh: nil, items: items)
        try await store?.saveFoodObservation(StoredFoodObservation(id: observationID, payload: JSONEncoder().encode(snapshot), capturedAt: capturedAt))
        return LocalFoodAnalysis(containsFood: true, stored: true, duplicateOf: nil, observationID: observationID, confidence: items.map(\.labelConfidence).min() ?? 0, caloriesLow: nil, caloriesHigh: nil, items: items)
    }

    func chat(threadID: UUID?, message: String) async throws -> LocalChatResponse {
        guard let store else { throw LocalStorageError.unavailable }
        let generator = FoundationModelsCoachAdapter()
        guard generator.availability == .available else { throw LocalCoachError.unavailable }
        let thread: UUID
        if let threadID {
            guard try await store.chatThreads().contains(where: { $0.id == threadID }) else { throw AthleteStoreError.invalidIdentifier(threadID.uuidString) }
            thread = threadID
        } else {
            thread = try await store.createChat(title: String(message.prefix(48))).id
        }
        try await store.appendChatMessage(ChatHistoryMessage(threadID: thread, role: .user, text: message))
        let facts = try await coachFacts(store: store)
        let request = CoachGenerationRequest(prompt: message, facts: facts)
        var output: CoachOutput
        do {
            output = try await generator.generate(request: request)
            try GroundingValidator().validate(output, facts: facts)
        } catch {
            let repaired = try await generator.generate(request: CoachGenerationRequest(prompt: "Repair the previous JSON using only these facts. User request: \(message)", facts: facts))
            try GroundingValidator().validate(repaired, facts: facts)
            output = repaired
        }
        let answer = output.claims.map(\.text).joined(separator: "\n\n")
        try await store.appendChatMessage(ChatHistoryMessage(threadID: thread, role: .assistant, text: answer))
        let action = output.recommendationAction.flatMap(CoachingAction.init(rawValue:))
        var exposureID: UUID?
        if let action, let session = try await store.latestEvidence(kind: "activity.session.v2") {
            let features = try await PersonalizationFeatureBuilder(store: store).features(for: session.id)
            let exposure = RecommendationExposure(action: action, features: features, contextDigest: session.contentDigest)
            try await store.saveRecommendationExposure(StoredRecommendationExposure(id: exposure.id, payload: JSONEncoder().encode(exposure), createdAt: exposure.createdAt))
            exposureID = exposure.id
        }
        return LocalChatResponse(threadID: thread, answerMarkdown: answer, recommendationCategory: action?.rawValue ?? "none", evidenceIDs: facts.compactMap { UUID(uuidString: $0.id) }, foodIDs: [], contextDigest: "local", feedbackContextID: exposureID)
    }

    private func coachFacts(store: AthleteStore) async throws -> [GroundedFact] {
        guard let envelope = try await store.latestEvidence(kind: "activity.session.v2"), let session = try await store.payload(for: envelope.id, as: SessionEvidenceV2.self) else { return [] }
        var facts = CoachContextAssembler().assemble(session: SessionFacts(activeMinutes: session.activeTime / 60, activeBlocks: session.activeBlockCount, coverage: session.trackingCoverage), personalization: nil, food: nil).facts
        facts.append(contentsOf: [
            GroundedFact(id: envelope.id.uuidString, value: "session", numericValue: nil),
            GroundedFact(id: "rest_minutes", value: String(format: "%.1f", session.restTime / 60), numericValue: session.restTime / 60),
            GroundedFact(id: "tracking_gaps_minutes", value: String(format: "%.1f", session.trackingGapTime / 60), numericValue: session.trackingGapTime / 60),
            GroundedFact(id: "capture_quality", value: "ambiguous=\(session.captureQuality.ambiguousFrameCount), identity=\(session.captureQuality.identityDiscontinuityCount), warmup=\(session.captureQuality.warmupFrameCount)"),
        ])
        facts.append(GroundedFact(id: "timeline", value: session.segments.prefix(100).map { "\($0.state.rawValue) \($0.startOffset)-\($0.endOffset)" }.joined(separator: "; ")))
        return facts
    }

    func sendSessionRPE(eventID: UUID, value: Double, sourceEvidenceID: UUID, note: String) async throws -> LocalFeedbackResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard try await store.evidence(id: sourceEvidenceID) != nil else { throw AthleteStoreError.invalidIdentifier(sourceEvidenceID.uuidString) }
        let state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        var model = state.difficulty
        let features = try await PersonalizationFeatureBuilder(store: store).features(for: sourceEvidenceID)
        model.update(features: features, rpe: value)
        let narrative = SessionRPEEvidence(sessionEvidenceID: sourceEvidenceID, rpe: value, note: note.isEmpty ? nil : note)
        let narrativeEnvelope = try narrative.envelope()
        let stored = try await store.applySessionRPE(eventID: eventID, sourceEvidenceID: sourceEvidenceID, feedbackPayload: JSONEncoder().encode(LocalFeedbackPayload(sourceEvidenceID: sourceEvidenceID, rpe: value, note: note)), createdAt: Date(), statePayload: JSONEncoder().encode(PersonalizationState(difficulty: model, bandit: state.bandit)), narrativeEnvelope: narrativeEnvelope, narrativePayload: JSONEncoder().encode(narrative))
        return LocalFeedbackResponse(stored: stored, personalizationSamples: model.samples)
    }

    func sendRecommendationReward(feedbackContextID: UUID, reward: Double) async throws -> LocalFeedbackResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard let storedExposure = try await store.recommendationExposure(id: feedbackContextID) else { throw AthleteStoreError.invalidIdentifier(feedbackContextID.uuidString) }
        let exposure = try JSONDecoder().decode(RecommendationExposure.self, from: storedExposure.payload)
        var state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        guard let features = PersonalizationFeatures(values: exposure.featureVector, version: exposure.featureVersion) else { throw LocalStorageError.invalidExposure }
        state.bandit.update(action: exposure.action, features: features, reward: reward)
        let stored = try await store.applyRecommendationReward(exposureID: feedbackContextID, reward: reward, feedbackEventID: UUID(), feedbackPayload: JSONEncoder().encode(LocalRecommendationRewardPayload(exposureID: feedbackContextID, reward: reward)), createdAt: Date(), statePayload: JSONEncoder().encode(state))
        return LocalFeedbackResponse(stored: stored, personalizationSamples: state.bandit.totalExplicitRewards)
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
