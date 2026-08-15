import Foundation
import Testing
@testable import Baseline

@Test("История интенсивности ограничена временем, а не числом кадров")
func boundsIntensityByTimeWindow() {
    var history = MotionIntensityHistory(windowDuration: 3)
    history.append(0.1, at: 0)
    history.append(0.4, at: 1)
    history.append(nil, at: 2)
    history.append(4, at: 4.1)

    #expect(history.points.count == 3)
    #expect(history.points.map(\.timestamp) == [1, 2, 4.1])
    #expect(history.points.last?.value == 1)
    #expect(history.points[1].value == nil)
}

@Test("Положение камеры переключается между фронтальным и задним")
func togglesCameraPosition() {
    #expect(CaptureCameraPosition.front.toggled == .back)
    #expect(CaptureCameraPosition.back.toggled == .front)
}

@Test("Локальный gate не запускает классификацию чаще заданного интервала")
func throttlesFoodClassification() {
    var gate = FoodFrameGate(evaluationInterval: 1.5)

    #expect(gate.shouldEvaluate(at: 0))
    #expect(!gate.shouldEvaluate(at: 0.7))
    #expect(gate.shouldEvaluate(at: 1.5))
}

@Test("Food gate требует два последовательных положительных кадра")
func requiresConsecutiveFoodSignals() {
    var gate = FoodFrameGate(evaluationInterval: 0.1, uploadCooldown: 20, requiredPositiveFrames: 2)
    let food = [FoodLabelObservation(identifier: "plate of pasta", confidence: 0.8)]

    #expect(!gate.consume(observations: food, at: 0))
    #expect(gate.consume(observations: food, at: 1))
    #expect(!gate.consume(observations: food, at: 2))
}

@Test("Ответ питания декодируется как диапазон, а не одно точное число")
func decodesFoodRange() throws {
    let data = Data(
        #"{"contains_food":true,"stored":true,"duplicate_of":null,"observation_id":"00000000-0000-0000-0000-000000000001","confidence":0.82,"calories_low":410.0,"calories_high":650.0,"items":[]}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let value = try decoder.decode(BackendFoodAnalysis.self, from: data)

    #expect(value.containsFood)
    #expect(value.caloriesLow == 410)
    #expect(value.caloriesHigh == 650)
    #expect(value.caloriesLow < value.caloriesHigh)
}

@Test("RPE feedback сохраняет ссылку на конкретную session evidence")
func feedbackDraftKeepsEvidenceIdentity() {
    let evidenceID = UUID()
    let context = PersonalizationContext(
        activeMinutes: 30,
        setCount: 8,
        workRestRatio: 1.5,
        trackingCoverage: 0.9,
        sevenDayActiveMinutes: 90,
        hoursSincePreviousSession: 48,
        recentFoodKcalMidpoint: 500
    )
    let summary = SessionSummaryViewData(
        evidenceID: evidenceID,
        endedAt: Date(timeIntervalSince1970: 1_800_000_000),
        activeMinutes: 30,
        restMinutes: 20,
        setCount: 8,
        trackingCoverage: 0.9
    )

    let feedback = PendingSessionFeedback(
        evidenceID: evidenceID,
        context: context,
        summary: summary
    )

    #expect(feedback.evidenceID == evidenceID)
    #expect(feedback.summary.evidenceID == evidenceID)
}

@Test("Совет декодируется с одноразовым feedback context")
func decodesRecommendationFeedbackContext() throws {
    let data = Data(
        #"{"thread_id":"00000000-0000-0000-0000-000000000001","answer_markdown":"Отдых приоритетнее [model:personalization-v1]","recommendation_category":"recovery","evidence_ids":[],"food_ids":[],"context_digest":"sha256:test","feedback_context_id":"00000000-0000-0000-0000-000000000002"}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let value = try decoder.decode(BackendChatResponse.self, from: data)

    #expect(value.recommendationCategory == "recovery")
    #expect(value.feedbackContextID == UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
}
