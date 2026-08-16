import CoreML
import Foundation
import Testing
import AthleteCore
import AthleteNutrition
import AthleteSensors
import AthleteStore
@testable import Baseline

@Test("История интенсивности ограничена временем, а не числом кадров")
func boundsIntensityByTimeWindow() {
    var history = MotionIntensityHistory(windowDuration: 3)
    history.append(0.1, at: 0)
    history.append(0.4, at: 1)
    history.append(nil, at: 2)
    history.append(4, at: 4.1)

    #expect(history.points.count == 2)
    #expect(history.points.map(\.timestamp) == [2, 4.1])
    #expect(history.points.last?.value == 1)
    #expect(history.points.first?.value == nil)
}

@Test("Положение камеры переключается между фронтальным и задним")
func togglesCameraPosition() {
    #expect(CaptureCameraPosition.front.toggled == .back)
    #expect(CaptureCameraPosition.back.toggled == .front)
}

@Test("Продукт имеет ровно две основные вкладки")
func hasExactlyTwoProductTabs() {
    #expect(AppTab.allCases == [.camera, .chat])
}

@MainActor
@Test("Тренировка запускается автоматически без отдельного пользовательского шага")
func startsWorkoutWithoutManualInput() {
    let model = CameraModel(store: nil, localServices: LocalDeviceServices(store: nil))

    model.startWorkout()

    #expect(model.isWorkoutRecording)
}

@Test("Food bbox показывает распознанное и доступные калории")
func formatsFoodOverlayWithCalories() {
    let nutrition = LocalFoodItem(
        name: "Рис",
        estimatedGrams: nil,
        gramsLow: nil,
        gramsHigh: nil,
        labelConfidence: 0.91,
        portionConfidence: nil,
        fdcID: nil,
        kcalPer100g: 130,
        nutrientSource: "nutrition.sqlite",
        caloriesLow: nil,
        caloriesHigh: nil
    )

    #expect(FoodOverlayText.make(label: "rice", confidence: 0.91, nutrition: nutrition) == "Рис · 91% · 130 ккал/100 г")
}

@Test("Нулевая интенсивность остаётся видимой внутри графика")
func keepsRestingIntensityInsideChartBounds() {
    #expect(MotionIntensityChartGeometry.y(for: 0, height: 58) == 57)
}

@Test("Кофе доступен через класс cup из bundled nutrition database")
func resolvesCupAsCoffee() async throws {
    let services = LocalDeviceServices(store: nil)

    let result = try await services.analyzeFood(
        detections: [FoodDetection(label: "cup", confidence: 0.9, boundingBox: .init(x: 0, y: 0, width: 1, height: 1))],
        capturedAt: Date()
    )

    #expect(result.items.first?.name == "Кофе")
    #expect(result.items.first?.kcalPer100g == 1)
}

@Test("Food detector отбрасывает не-пищевые COCO классы")
func filtersNonFoodCocoLabels() {
    #expect(FoodLabelPolicy.isSupported("cup"))
    #expect(FoodLabelPolicy.isSupported("pizza"))
    #expect(!FoodLabelPolicy.isSupported("person"))
    #expect(!FoodLabelPolicy.isSupported("chair"))
}

@Test("В анализ калорий попадают только food-классы, даже если debug показывает все bbox")
func keepsDebugObjectsOutOfNutritionAnalysis() {
    let detections = [
        FoodDetection(label: "person", confidence: 0.95, boundingBox: .init(x: 0, y: 0, width: 1, height: 1)),
        FoodDetection(label: "cup", confidence: 0.8, boundingBox: .init(x: 0, y: 0, width: 1, height: 1)),
    ]

    #expect(FoodLabelPolicy.analysisDetections(detections).map(\.label) == ["cup"])
}

@Test("Модель и база питания доступны из app bundle")
func bundlesFoodRuntimeAssets() async {
    #expect(FoodObjectDetector(bundle: .main).availability == .available)
    #expect(await LocalDeviceServices(store: nil).nutritionAvailability() == .available)
}

@Test("В bundle используется полная YOLOv3 FP16, а не Tiny")
func bundlesFullYoloModel() throws {
    let url = try #require(Bundle.main.url(forResource: "FoodDetector", withExtension: "mlmodelc"))
    let model = try MLModel(contentsOf: url)
    let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]

    #expect(metadata?["com.apple.developer.machine-learning.models.name"] == "YOLOv3FP16.mlmodel")
}

@Test("Legacy session payload не блокирует облачный Coach")
func legacySessionDoesNotBlockCloudCoachContext() async throws {
    let store = try AthleteStore.inMemory()
    let evidenceID = UUID()
    let malformedV2 = EvidenceEnvelope(
        id: evidenceID,
        moduleID: "org.baseline.activity",
        moduleVersion: "legacy",
        kind: "activity.session.v2",
        observedFrom: Date(timeIntervalSince1970: 100),
        observedTo: Date(timeIntervalSince1970: 200),
        ingestedAt: Date(timeIntervalSince1970: 200),
        epistemicRole: .computed,
        provenance: Provenance(sourceID: "test", producerID: "test", producerVersion: "1", method: nil),
        privacyClass: .sensitiveLocal,
        payload: PayloadReference(mediaType: "application/json", schemaID: "activity.session", schemaVersion: "2", storageURI: "baseline://evidence/\(evidenceID.uuidString)"),
        derivedFrom: [],
        supersedes: nil,
        contentDigest: "sha256:test"
    )
    try await store.appendEvidence(malformedV2, payload: ["legacy_set_count": 3])

    let context = try await LocalDeviceServices(store: store).cloudCoachContext(threadID: nil, message: "Что нового?")

    #expect(context.contains("CURRENT USER REQUEST\nЧто нового?"))
}

@Test("Food bbox переводится из Vision bottom-left в aspect-fill preview")
func convertsFoodAspectFillGeometry() {
    let rect = AspectFillGeometry.displayRect(normalizedVisionRect: NormalizedFoodRect(x: 0.1, y: 0.25, width: 0.25, height: 0.25), sourceSize: CGSize(width: 4, height: 3), previewSize: CGSize(width: 16, height: 9), mirrored: false)
    let mirrored = AspectFillGeometry.displayRect(normalizedVisionRect: NormalizedFoodRect(x: 0.1, y: 0.25, width: 0.25, height: 0.25), sourceSize: CGSize(width: 4, height: 3), previewSize: CGSize(width: 16, height: 9), mirrored: true)
    #expect(rect.width == 4)
    #expect(rect.minY == mirrored.minY)
    #expect(rect.minX + mirrored.maxX == 16)
}

@Test("BBox geometry flips Vision Y and supports portrait aspect-fill")
func convertsVisionYAndPortraitAspectFill() {
    let bottom = AspectFillGeometry.displayRect(normalizedVisionRect: NormalizedFoodRect(x: 0, y: 0, width: 0.25, height: 0.25), sourceSize: CGSize(width: 16, height: 9), previewSize: CGSize(width: 9, height: 16), mirrored: false)
    let top = AspectFillGeometry.displayRect(normalizedVisionRect: NormalizedFoodRect(x: 0, y: 0.75, width: 0.25, height: 0.25), sourceSize: CGSize(width: 16, height: 9), previewSize: CGSize(width: 9, height: 16), mirrored: false)
    #expect(bottom.minY > top.minY)
    #expect(bottom.width > 0)
    #expect(bottom.height > 0)
}

@Test("Front preview mirrors bbox while back preview does not")
func mirrorsOnlyFrontCameraBBox() {
    let source = NormalizedFoodRect(x: 0.1, y: 0.2, width: 0.2, height: 0.2)
    let back = AspectFillGeometry.displayRect(normalizedVisionRect: source, sourceSize: CGSize(width: 4, height: 3), previewSize: CGSize(width: 16, height: 9), mirrored: false)
    let front = AspectFillGeometry.displayRect(normalizedVisionRect: source, sourceSize: CGSize(width: 4, height: 3), previewSize: CGSize(width: 16, height: 9), mirrored: true)
    #expect(back.minX != front.minX)
    #expect(abs(back.minX + front.maxX - 16) < 0.001)
}

@Test("Zero source or preview size yields no bbox")
func rejectsZeroGeometrySize() {
    let rect = NormalizedFoodRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    #expect(AspectFillGeometry.displayRect(normalizedVisionRect: rect, sourceSize: .zero, previewSize: CGSize(width: 100, height: 100), mirrored: false) == .zero)
    #expect(AspectFillGeometry.displayRect(normalizedVisionRect: rect, sourceSize: CGSize(width: 100, height: 100), previewSize: .zero, mirrored: false) == .zero)
}

@Test("Локальный gate не запускает классификацию чаще заданного интервала")
func throttlesFoodClassification() {
    var gate = FoodFrameGate(evaluationInterval: 1.5)

    let first = gate.shouldEvaluate(at: 0)
    let second = gate.shouldEvaluate(at: 0.7)
    let third = gate.shouldEvaluate(at: 1.5)
    #expect(first)
    #expect(!second)
    #expect(third)
}

@Test("Food gate требует два последовательных положительных кадра")
func requiresConsecutiveFoodSignals() {
    var gate = FoodFrameGate(evaluationInterval: 0.1, uploadCooldown: 20, requiredPositiveFrames: 2)
    let food = [FoodDetection(label: "plate of pasta", confidence: 0.8, boundingBox: NormalizedFoodRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))]

    let first = gate.consume(observations: food, at: 0)
    let second = gate.consume(observations: food, at: 1)
    let third = gate.consume(observations: food, at: 2)
    #expect(!first)
    #expect(second)
    #expect(!third)
}

@Test("Food gate resets after a miss and respects upload cooldown")
func resetsFoodSignalsAndCooldown() {
    var gate = FoodFrameGate(evaluationInterval: 0.1, uploadCooldown: 20, requiredPositiveFrames: 2)
    let food = [FoodDetection(label: "apple", confidence: 0.8, boundingBox: NormalizedFoodRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))]
    let first = gate.consume(observations: food, at: 0)
    let miss = gate.consume(observations: [], at: 1)
    let third = gate.consume(observations: food, at: 2)
    let upload = gate.consume(observations: food, at: 3)
    let cooldownOne = gate.consume(observations: food, at: 4)
    let cooldownTwo = gate.consume(observations: food, at: 5)
    #expect(!first)
    #expect(!miss)
    #expect(!third)
    #expect(upload)
    #expect(!cooldownOne)
    #expect(!cooldownTwo)
}

@Test("Ответ питания декодируется как диапазон, а не одно точное число")
func decodesFoodRange() throws {
    let data = Data(
        #"{"contains_food":true,"stored":true,"duplicate_of":null,"observation_id":"00000000-0000-0000-0000-000000000001","confidence":0.82,"calories_low":410.0,"calories_high":650.0,"items":[]}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let value = try decoder.decode(LocalFoodAnalysis.self, from: data)

    #expect(value.containsFood)
    #expect(value.caloriesLow == 410)
    #expect(value.caloriesHigh == 650)
    #expect(value.caloriesLow! < value.caloriesHigh!)
}

@Test("RPE feedback сохраняет ссылку на конкретную session evidence")
func feedbackDraftKeepsEvidenceIdentity() {
    let evidenceID = UUID()
    let summary = SessionSummaryViewData(
        evidenceID: evidenceID,
        endedAt: Date(timeIntervalSince1970: 1_800_000_000),
        activeMinutes: 30,
        restMinutes: 20,
        setCount: 8,
        trackingCoverage: 0.9
    )

    let feedback = PendingSessionFeedback(
        feedbackEventID: UUID(),
        evidenceID: evidenceID,
        summary: summary
    )

    #expect(feedback.evidenceID == evidenceID)
    #expect(feedback.summary.evidenceID == evidenceID)
}

@Test("Совет декодируется с одноразовым feedback context")
func decodesRecommendationFeedbackContext() throws {
    let data = Data(
        #"{"threadID":"00000000-0000-0000-0000-000000000001","answerMarkdown":"Отдых приоритетнее [model:personalization-v1]","recommendationCategory":"recovery","evidenceIDs":[],"foodIDs":[],"contextDigest":"sha256:test","feedbackContextID":"00000000-0000-0000-0000-000000000002"}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let value = try decoder.decode(LocalChatResponse.self, from: data)

    #expect(value.recommendationCategory == "recovery")
    #expect(value.feedbackContextID == UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
}

@Test("Capture quality не считает warmup rejected motion")
func captureQualityWarmupIsNotMotionRejection() {
    var accumulator = WorkoutCaptureQualityAccumulator()
    accumulator.record(
        frame: PoseFrame(samples: [], trackingState: .stable, isMetricEligible: false, exclusionReason: .none),
        metrics: .invalid(.warmup)
    )
    #expect(accumulator.warmupFrameCount == 1)
    #expect(accumulator.rejectedMotionFrameCount == 0)
}

@Test("Capture quality отдельно считает ambiguity и identity discontinuity")
func captureQualityIdentityCategories() {
    var accumulator = WorkoutCaptureQualityAccumulator()
    accumulator.record(frame: PoseFrame(samples: [], trackID: UUID(), trackingState: .multiplePeople, exclusionReason: .ambiguousSubjects), metrics: .invalid(.ambiguousSubjects))
    accumulator.record(frame: PoseFrame(samples: [], trackID: UUID(), trackingState: .lost, exclusionReason: .identityDiscontinuity), metrics: .invalid(.identityDiscontinuity))
    #expect(accumulator.ambiguousFrameCount == 1)
    #expect(accumulator.identityDiscontinuityCount == 1)
    #expect(accumulator.rejectedMotionFrameCount == 0)
}

@Test("Capture quality считает low confidence tracked frame rejected motion")
func captureQualityRejectedMotion() {
    var accumulator = WorkoutCaptureQualityAccumulator()
    accumulator.record(frame: PoseFrame(samples: [], trackID: UUID(), trackingState: .degraded, exclusionReason: .none), metrics: .invalid(.lowConfidence))
    #expect(accumulator.rejectedMotionFrameCount == 1)
}
