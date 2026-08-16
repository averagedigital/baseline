import AthleteCore
import AthleteIntelligence
import AthleteNutrition
import AthletePersonalization
import AthleteSensors
import AthleteStore
import Foundation

struct LocalFoodItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(name)-\(labelConfidence)" }
    let name: String; let estimatedGrams: Double?; let gramsLow: Double?; let gramsHigh: Double?
    let labelConfidence: Double; let portionConfidence: Double?; let fdcID: Int?; let kcalPer100g: Double?
    let nutrientSource: String?; let caloriesLow: Double?; let caloriesHigh: Double?
}
enum NutritionAvailability: Equatable, Sendable { case available, databaseMissing, invalid }

private struct ContextResettingCoachGenerator: CoachGenerating {
    let adapter: FoundationModelsCoachAdapter

    func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        do {
            return try await adapter.generate(request: request)
        } catch let error as CoachGenerationError where error == .contextWindowExceeded {
            await adapter.reset(threadID: request.threadID ?? UUID())
            let compact = CoachGenerationRequest(
                prompt: request.prompt,
                facts: request.facts,
                conversation: Array(request.conversation.suffix(8)),
                threadID: request.threadID
            )
            return try await adapter.generate(request: compact)
        }
    }
}

private actor SerialMutationQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
struct PersistedFoodItem: Codable, Equatable, Sendable {
    let name: String; let estimatedGrams: Double?; let gramsLow: Double?; let gramsHigh: Double?
    let labelConfidence: Double; let portionConfidence: Double?; let fdcID: Int?; let kcalPer100g: Double?
    let nutrientSource: String?; let caloriesLow: Double?; let caloriesHigh: Double?
}
struct PersistedFoodObservation: Codable, Equatable, Sendable {
    let id: UUID; let capturedAt: Date; let items: [PersistedFoodItem]; let caloriesLow: Double?; let caloriesHigh: Double?
    var localItems: [LocalFoodItem] { items.map { LocalFoodItem(name: $0.name, estimatedGrams: $0.estimatedGrams, gramsLow: $0.gramsLow, gramsHigh: $0.gramsHigh, labelConfidence: $0.labelConfidence, portionConfidence: $0.portionConfidence, fdcID: $0.fdcID, kcalPer100g: $0.kcalPer100g, nutrientSource: $0.nutrientSource, caloriesLow: $0.caloriesLow, caloriesHigh: $0.caloriesHigh) } }
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
typealias LocalLatestFood = PersistedFoodObservation
struct LocalHome: Codable, Equatable, Sendable {
    let latestSession: LocalLatestSession?; let latestFood: LocalLatestFood?; let suggestedAction: String
    let recommendationIsPersonalized: Bool; let recommendationConfidence: Double
    let predictedDifficulty: Double?; let difficultyConfidence: Double
    let recommendationExposureID: UUID?
}
struct LocalFeedbackPayload: Codable, Sendable { let sourceEvidenceID: UUID; let rpe: Double; let note: String }
struct LocalRecommendationRewardPayload: Codable, Sendable { let exposureID: UUID; let reward: Double }
enum LocalCoachError: LocalizedError { case unavailable, unsupportedLocale, contextWindowExceeded, refused, invalidResponse, failed
    var errorDescription: String? { switch self { case .unavailable: "Локальная языковая модель недоступна на этом устройстве."; case .unsupportedLocale: "Язык запроса не поддерживается локальной моделью."; case .contextWindowExceeded: "Контекст Coach слишком большой."; case .refused: "Локальная модель не смогла ответить на этот запрос."; case .invalidResponse: "Не удалось подтвердить ответ данными тренировки."; case .failed: "Не удалось получить ответ Coach." } }
}

actor LocalDeviceServices {
    private let store: AthleteStore?
    private var nutritionDatabase: NutritionDatabase?
    private var nutritionAvailabilityState: NutritionAvailability?
    private let coachGenerator = FoundationModelsCoachAdapter()
    private let personalizationMutations = SerialMutationQueue()

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
            let existing = try await store.recentRecommendationExposures(limit: 20).compactMap { stored -> (StoredRecommendationExposure, RecommendationExposure)? in
                guard let value = try? JSONDecoder().decode(RecommendationExposure.self, from: stored.payload) else { return nil }
                return (stored, value)
            }.first { $0.0.rewardedAt == nil && $0.1.contextDigest == evidence.contentDigest && $0.1.action == recommendation.action }?.0
            if let existing { exposureID = existing.id } else {
                let exposure = RecommendationExposure(action: recommendation.action, features: features, contextDigest: evidence.contentDigest)
                try await store.saveRecommendationExposure(StoredRecommendationExposure(id: exposure.id, payload: JSONEncoder().encode(exposure), createdAt: exposure.createdAt))
                exposureID = exposure.id
            }
        }
        return LocalHome(latestSession: session, latestFood: latestFood, suggestedAction: recommendation.action.rawValue, recommendationIsPersonalized: recommendation.personalized, recommendationConfidence: recommendation.confidence, predictedDifficulty: prediction, difficultyConfidence: state.difficulty.dataConfidence, recommendationExposureID: exposureID)
    }

    func uploadEvidence<Payload: Encodable & Sendable>(envelope: EvidenceEnvelope, payload: Payload) async throws { guard let store else { throw LocalStorageError.unavailable }; try await store.appendEvidence(envelope, payload: payload) }

    func mostRecentChat() async throws -> (ChatThread, [ChatHistoryMessage])? {
        guard let store, let thread = try await store.chatThreads().first else { return nil }
        return (thread, try await store.chatMessages(threadID: thread.id))
    }

    func analyzeFood(detections: [FoodDetection], capturedAt: Date) async throws -> LocalFoodAnalysis {
        ensureNutritionDatabase()
        let items = detections.compactMap { detection -> LocalFoodItem? in
            let item = nutritionDatabase?.match(detection.label)
            return LocalFoodItem(name: item?.canonicalName ?? detection.label, estimatedGrams: nil, gramsLow: nil, gramsHigh: nil, labelConfidence: detection.confidence, portionConfidence: nil, fdcID: nil, kcalPer100g: item?.kcalPer100g, nutrientSource: item == nil ? nil : "nutrition.sqlite", caloriesLow: nil, caloriesHigh: nil)
        }
        guard !items.isEmpty else { return LocalFoodAnalysis(containsFood: false, stored: false, duplicateOf: nil, observationID: nil, confidence: 0, caloriesLow: nil, caloriesHigh: nil, items: []) }
        let observationID = UUID()
        let snapshot = PersistedFoodObservation(id: observationID, capturedAt: capturedAt, items: items.map { PersistedFoodItem(name: $0.name, estimatedGrams: $0.estimatedGrams, gramsLow: $0.gramsLow, gramsHigh: $0.gramsHigh, labelConfidence: $0.labelConfidence, portionConfidence: $0.portionConfidence, fdcID: $0.fdcID, kcalPer100g: $0.kcalPer100g, nutrientSource: $0.nutrientSource, caloriesLow: $0.caloriesLow, caloriesHigh: $0.caloriesHigh) }, caloriesLow: nil, caloriesHigh: nil)
        try await store?.saveFoodObservation(StoredFoodObservation(id: observationID, payload: JSONEncoder().encode(snapshot), capturedAt: capturedAt))
        return LocalFoodAnalysis(containsFood: true, stored: true, duplicateOf: nil, observationID: observationID, confidence: items.map(\.labelConfidence).min() ?? 0, caloriesLow: nil, caloriesHigh: nil, items: items)
    }

    func nutritionAvailability() -> NutritionAvailability {
        ensureNutritionDatabase()
        return nutritionAvailabilityState ?? .databaseMissing
    }

    private func ensureNutritionDatabase() {
        guard nutritionDatabase == nil, nutritionAvailabilityState == nil else { return }
        guard let url = Bundle.main.url(forResource: "nutrition", withExtension: "sqlite") else {
            nutritionAvailabilityState = .databaseMissing
            return
        }
        do {
            nutritionDatabase = try NutritionDatabase(path: url.path)
            nutritionAvailabilityState = .available
        } catch {
            nutritionAvailabilityState = .invalid
        }
    }

    func chat(threadID: UUID?, message: String) async throws -> LocalChatResponse {
        guard let store else { throw LocalStorageError.unavailable }
        guard case .available = coachGenerator.availability else { throw LocalCoachError.unavailable }
        let thread: UUID
        if let threadID {
            guard try await store.chatThreads().contains(where: { $0.id == threadID }) else { throw AthleteStoreError.invalidIdentifier(threadID.uuidString) }
            thread = threadID
        } else {
            thread = try await store.createChat(title: String(message.prefix(48))).id
        }
        try await store.appendChatMessage(ChatHistoryMessage(threadID: thread, role: .user, text: message))
        let facts = try await coachFacts(store: store)
        let history = try await store.chatMessages(threadID: thread).suffix(12).dropLast().map { CoachConversationTurn(role: $0.role == .user ? .user : .assistant, text: $0.text) }
        let request = CoachGenerationRequest(prompt: message, facts: facts, conversation: Array(history), threadID: thread)
        let generator = ContextResettingCoachGenerator(adapter: coachGenerator)
        let output: CoachOutput
        do { output = try await CoachOrchestrator(generator: generator).generate(request: request) }
        catch is GroundingError { throw LocalCoachError.invalidResponse }
        catch { throw mapCoachError(error) }
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
        return LocalChatResponse(threadID: thread, answerMarkdown: answer, recommendationCategory: action?.rawValue ?? "none", evidenceIDs: Array(Set(facts.compactMap { $0.sourceEvidenceID })), foodIDs: Array(Set(facts.compactMap { $0.sourceFoodObservationID })), contextDigest: "local", feedbackContextID: exposureID)
    }

    private func mapCoachError(_ error: Error) -> LocalCoachError {
        switch error {
        case let error as LocalCoachError: return error
        case CoachGenerationError.unsupportedLocale: return .unsupportedLocale
        case CoachGenerationError.contextWindowExceeded: return .contextWindowExceeded
        case CoachGenerationError.refused: return .refused
        case CoachGenerationError.unavailable: return .unavailable
        default: return .failed
        }
    }

    private func coachFacts(store: AthleteStore) async throws -> [GroundedFact] {
        guard let envelope = try await store.latestEvidence(kind: "activity.session.v2"), let session = try await store.payload(for: envelope.id, as: SessionEvidenceV2.self) else { return [] }
        var facts: [GroundedFact] = [
            .text("session:\(envelope.id.uuidString):observed_from", ISO8601DateFormatter().string(from: session.observedFrom), sourceEvidenceID: envelope.id),
            .text("session:\(envelope.id.uuidString):observed_to", ISO8601DateFormatter().string(from: session.observedTo), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):duration_minutes", session.observedTo.timeIntervalSince(session.observedFrom) / 60, sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):active_minutes", session.activeTime / 60, sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):rest_minutes", session.restTime / 60, sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):tracking_gap_minutes", session.trackingGapTime / 60, sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):active_block_count", Double(session.activeBlockCount), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):tracking_coverage", session.trackingCoverage, sourceEvidenceID: envelope.id),
            .text("session:\(envelope.id.uuidString):algorithm_version", session.algorithmVersion, sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):capture:ambiguous_frame_count", Double(session.captureQuality.ambiguousFrameCount), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):capture:identity_discontinuity_count", Double(session.captureQuality.identityDiscontinuityCount), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):capture:warmup_frame_count", Double(session.captureQuality.warmupFrameCount), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):capture:rejected_motion_frame_count", Double(session.captureQuality.rejectedMotionFrameCount), sourceEvidenceID: envelope.id),
            .number("session:\(envelope.id.uuidString):capture:tracking_gap_count", Double(session.captureQuality.trackingGapCount), sourceEvidenceID: envelope.id),
            .text("session:\(envelope.id.uuidString):timeline", session.segments.prefix(80).map { "\($0.state.rawValue) \($0.startOffset)-\($0.endOffset)" }.joined(separator: "; "), sourceEvidenceID: envelope.id),
        ]
        for recent in try await store.evidenceEnvelopes(kind: "activity.session.v2", limit: 5) {
            guard recent.id != envelope.id, let value = try await store.payload(for: recent.id, as: SessionEvidenceV2.self) else { continue }
            let prefix = "recent_session:\(recent.id.uuidString)"
            facts += [.text("\(prefix):date", ISO8601DateFormatter().string(from: value.observedTo), sourceEvidenceID: recent.id), .number("\(prefix):active_minutes", value.activeTime / 60, sourceEvidenceID: recent.id), .number("\(prefix):rest_minutes", value.restTime / 60, sourceEvidenceID: recent.id), .number("\(prefix):active_blocks", Double(value.activeBlockCount), sourceEvidenceID: recent.id), .number("\(prefix):coverage", value.trackingCoverage, sourceEvidenceID: recent.id)]
        }
        for narrative in try await store.evidenceEnvelopes(kind: "user.narrative.v1", limit: 10) {
            guard let source = narrative.derivedFrom.first, let rpe = try await store.payload(for: narrative.id, as: SessionRPEEvidence.self) else { continue }
            facts += [.number("session:\(source.uuidString):rpe", rpe.rpe, sourceEvidenceID: source), .text("session:\(source.uuidString):rpe_note", rpe.note ?? "", sourceEvidenceID: source)]
        }
        for observation in try await store.recentFoodObservations(limit: 5) where !observation.dismissed {
            guard let food = try? JSONDecoder().decode(PersistedFoodObservation.self, from: observation.payload) else { continue }
            facts.append(.text("food:\(food.id.uuidString):names", food.items.map { $0.name }.joined(separator: ", "), sourceFoodObservationID: food.id))
            facts.append(.text("food:\(food.id.uuidString):label_confidence", food.items.map { String(format: "%.2f", $0.labelConfidence) }.joined(separator: ", "), sourceFoodObservationID: food.id))
            facts.append(.boolean("food:\(food.id.uuidString):portion_available", food.items.contains { $0.estimatedGrams != nil || ($0.gramsLow != nil && $0.gramsHigh != nil) }, sourceFoodObservationID: food.id))
            if let low = food.caloriesLow, let high = food.caloriesHigh { facts += [.number("food:\(food.id.uuidString):kcal_low", low, sourceFoodObservationID: food.id), .number("food:\(food.id.uuidString):kcal_high", high, sourceFoodObservationID: food.id)] }
        }
        let state = try await store.loadPersonalizationState(as: PersonalizationState.self) ?? PersonalizationState()
        facts += [.number("personalization:difficulty_sample_count", Double(state.difficulty.samples)), .number("personalization:difficulty_confidence", state.difficulty.dataConfidence), .number("personalization:explicit_reward_count", Double(state.bandit.totalExplicitRewards)), .boolean("personalization:recommendation_personalized", state.bandit.totalExplicitRewards >= 5)]
        if let prediction = state.difficulty.predict(features: try await PersonalizationFeatureBuilder(store: store).features(for: envelope.id)) { facts.append(.number("personalization:predicted_difficulty", prediction)) }
        assert(Set(facts.map(\.id)).count == facts.count)
        return facts
    }

    func sendSessionRPE(eventID: UUID, value: Double, sourceEvidenceID: UUID, note: String) async throws -> LocalFeedbackResponse {
        try await personalizationMutations.run { [self] in
            try await performSessionRPE(eventID: eventID, value: value, sourceEvidenceID: sourceEvidenceID, note: note)
        }
    }

    private func performSessionRPE(eventID: UUID, value: Double, sourceEvidenceID: UUID, note: String) async throws -> LocalFeedbackResponse {
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
        try await personalizationMutations.run { [self] in
            try await performRecommendationReward(feedbackContextID: feedbackContextID, reward: reward)
        }
    }

    private func performRecommendationReward(feedbackContextID: UUID, reward: Double) async throws -> LocalFeedbackResponse {
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
