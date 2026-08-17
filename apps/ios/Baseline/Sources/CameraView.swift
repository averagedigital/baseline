@preconcurrency import AVFoundation
import AthleteSensors
import AthleteStore
import AthleteNutrition
import Observation
import SwiftUI

struct MotionIntensityHistory: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let timestamp: TimeInterval
        let value: Double?
    }

    private(set) var points: [Point] = []
    let windowDuration: TimeInterval

    init(windowDuration: TimeInterval = 12) {
        self.windowDuration = max(1, windowDuration)
    }

    mutating func append(_ value: Double?, at timestamp: TimeInterval) {
        points.append(Point(timestamp: timestamp, value: value.map { min(max($0, 0), 1) }))
        let cutoff = timestamp - windowDuration
        points.removeAll { $0.timestamp < cutoff }
    }

    mutating func reset() {
        points.removeAll(keepingCapacity: true)
    }
}

enum FoodScanPhase: Equatable, Sendable {
    case watching
    case analyzing
    case noFood
    case unavailable

    var label: String {
        switch self {
        case .watching: "Камера следит за тарелкой"
        case .analyzing: "Определяю продукты"
        case .noFood: "Еда не подтверждена"
        case .unavailable: "Анализ питания недоступен"
        }
    }
}

struct SessionSummaryViewData: Equatable, Sendable {
    let evidenceID: UUID
    let endedAt: Date
    let activeMinutes: Double
    let restMinutes: Double
    let setCount: Int
    let trackingCoverage: Double
}

struct PendingSessionFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let feedbackEventID: UUID
    let evidenceID: UUID
    let summary: SessionSummaryViewData
}

@MainActor
@Observable
final class CameraModel {
    var samples: [PoseSample] = []
    var boundingBox: NormalizedPoseRect?
    var trackingState: PoseTrackingState = .lost
    var metricExclusionReason: PoseMetricExclusionReason = .noSubject
    var currentMetrics: MotionMetrics = .invalid(.noSubject)
    var intensityHistory = MotionIntensityHistory()
    var isCameraRunning = false
    var isWorkoutRecording = false
    var cameraPosition: CaptureCameraPosition = .front
    var foodScanEnabled = true
    var foodPhase: FoodScanPhase = .watching
    var foodDetectorAvailability: FoodObjectDetector.Availability = .modelMissing
    var nutritionAvailability: NutritionAvailability = .databaseMissing
    var foodObjects: [TrackedFoodObject] = []
    var foodSourceSize: CGSize = .zero
    var foodDetailsByLabel: [String: LocalFoodItem] = [:]
    var latestFood: LocalFoodAnalysis?
    var localHome: LocalHome?
    var lastSession: SessionSummaryViewData?
    var pendingFeedback: PendingSessionFeedback?
    var errorMessage: String?
    var liveSetCount = 0
    var recordingElapsed: TimeInterval = 0

    let pipeline: CameraPipeline
    let localServices: LocalDeviceServices

    private let store: AthleteStore?
    private var intensityEstimator = MotionIntensityEstimator()
    private var sessionStartedAt: Date?
    private var activityWindows: [ActivityWindow] = []
    private var lastFrameTimestamp: TimeInterval?
    private var lastLiveSummaryAt: TimeInterval = -.infinity
    private var foodRequestInFlight = false
    private var captureQuality = WorkoutCaptureQualityAccumulator()

    init(
        pipeline: CameraPipeline = CameraPipeline(),
        store: AthleteStore? = nil,
        localServices: LocalDeviceServices? = nil
    ) {
        self.pipeline = pipeline
        let resolvedStore: AthleteStore?
        if let store {
            resolvedStore = store
        } else {
            do {
                resolvedStore = try StoreFactory.open()
            } catch {
                resolvedStore = nil
                errorMessage = "Не удалось открыть локальное хранилище."
            }
        }
        self.store = resolvedStore
        self.localServices = localServices ?? LocalDeviceServices(store: resolvedStore)

        pipeline.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.consume(frame)
            }
        }
        pipeline.onFoodCandidate = { [weak self] detections, capturedAt in
            Task { @MainActor in
                await self?.analyzeFood(detections: detections, capturedAt: capturedAt)
            }
        }
        pipeline.onFoodObjects = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.foodObjects = result.objects
                self.foodSourceSize = result.sourceSize
            }
        }
        pipeline.onFoodAvailability = { [weak self] availability in
            Task { @MainActor in
                guard let self else { return }
                self.foodDetectorAvailability = availability
                if availability != .available { self.foodPhase = .unavailable }
            }
        }
        pipeline.onIdentitySample = { [weak self] values, quality in
            Task {
                do { try await self?.localServices.updateIdentityGallery(embedding: values, quality: quality) }
                catch { await MainActor.run { self?.errorMessage = "Не удалось сохранить персональный identity prototype." } }
            }
        }
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.nutritionAvailability = await self.localServices.nutritionAvailability()
        }
    }

    var trackingLabel: String {
        switch trackingState {
        case .acquiring: "Фиксирую спортсмена"
        case .stable: "Слежение стабильно"
        case .degraded: "Часть суставов не видна"
        case .lost where metricExclusionReason == .identityDiscontinuity: "Спортсмен потерян — метрики на паузе"
        case .lost: "Тело не найдено"
        case .multiplePeople: "Пересечение людей — метрики на паузе"
        }
    }

    var trackingTone: Color {
        switch trackingState {
        case .stable: BaselineTheme.success
        case .acquiring, .degraded, .multiplePeople: BaselineTheme.warning
        case .lost: BaselineTheme.danger
        }
    }

    var latestFoodTitle: String {
        guard let latestFood, !latestFood.items.isEmpty else { return foodPhase.label }
        return latestFood.items.prefix(3).map(\.name).joined(separator: ", ")
    }

    var latestFoodCalories: String? {
        guard let latestFood, latestFood.containsFood, let low = latestFood.caloriesLow, let high = latestFood.caloriesHigh else { return nil }
        return "≈ \(Int(low.rounded()))–\(Int(high.rounded())) ккал"
    }

    func startCamera() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }
        guard granted else {
            errorMessage = "Нет доступа к камере."
            return
        }
        do {
            try await pipeline.start()
            isCameraRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        pipeline.stop()
        isCameraRunning = false
        intensityEstimator.reset()
        intensityHistory.reset()
    }

    func switchCamera() async {
        let target = cameraPosition.toggled
        do {
            try await pipeline.switchCamera(to: target)
            cameraPosition = target
            resetRealtimeMetrics()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetSubjectLock() {
        pipeline.resetSubjectLock()
        resetRealtimeMetrics()
    }

    func lockSubject(at point: CGPoint) {
        pipeline.lockSubject(at: point)
        resetRealtimeMetrics()
    }

    func setFoodScanEnabled(_ enabled: Bool) {
        foodScanEnabled = enabled
        pipeline.setFoodScanEnabled(enabled)
        if enabled {
            foodPhase = .watching
        } else {
            latestFood = nil
            foodObjects = []
            foodDetailsByLabel = [:]
        }
    }

    func startWorkout() {
        guard !isWorkoutRecording else { return }
        isWorkoutRecording = true
        sessionStartedAt = Date()
        activityWindows = []
        captureQuality = WorkoutCaptureQualityAccumulator()
        lastFrameTimestamp = nil
        lastLiveSummaryAt = -.infinity
        liveSetCount = 0
        recordingElapsed = 0
        intensityEstimator.reset()
        intensityHistory.reset()
        errorMessage = nil
    }

    func stopWorkout() async {
        guard isWorkoutRecording else { return }
        isWorkoutRecording = false
        guard let startedAt = sessionStartedAt else { return }
        sessionStartedAt = nil
        let windows = activityWindows
        activityWindows = []
        lastFrameTimestamp = nil
        recordingElapsed = 0

        guard !windows.isEmpty else {
            liveSetCount = 0
            return
        }

        do {
            let summary = try ActivitySegmenter(configuration: .cameraV2).segment(windows)
            let endedAt = Date()
            let interval = DateInterval(start: startedAt, end: endedAt)
            let session = SessionEvidenceV2(
                observedFrom: interval.start,
                observedTo: interval.end,
                trackingCoverage: summary.coverage,
                activeTime: summary.activeTime,
                restTime: summary.restTime,
                trackingGapTime: summary.trackingGapTime,
                activeBlockCount: summary.setCount,
                confirmedSetCount: nil,
                segments: summary.segments.map { SessionActivitySegment(state: $0.state, startOffset: $0.start, endOffset: $0.end) },
                captureQuality: SessionCaptureQuality(ambiguousFrameCount: captureQuality.ambiguousFrameCount, identityDiscontinuityCount: captureQuality.identityDiscontinuityCount, warmupFrameCount: captureQuality.warmupFrameCount, rejectedMotionFrameCount: captureQuality.rejectedMotionFrameCount, trackingGapCount: summary.segments.filter { $0.state == .trackingGap }.count),
                algorithmVersion: "activity-segmentation-v2"
            )
            let envelope = try session.envelope(ingestedAt: endedAt)

            if let store {
                try await store.appendEvidence(envelope, payload: session)
            }

            let viewData = SessionSummaryViewData(
                evidenceID: envelope.id,
                endedAt: endedAt,
                activeMinutes: summary.activeTime / 60,
                restMinutes: summary.restTime / 60,
                setCount: summary.setCount,
                trackingCoverage: summary.coverage
            )
            lastSession = viewData
            liveSetCount = summary.setCount
            pendingFeedback = PendingSessionFeedback(
                feedbackEventID: UUID(),
                evidenceID: envelope.id,
                summary: viewData
            )
            await refreshHome()
        } catch {
            errorMessage = "Не удалось сохранить тренировку: \(error.localizedDescription)"
        }
    }

    func submitRPE(_ value: Double, note: String, for feedback: PendingSessionFeedback) async -> Bool {
        do {
            _ = try await localServices.sendSessionRPE(
                eventID: feedback.feedbackEventID,
                value: value,
                sourceEvidenceID: feedback.evidenceID,
                note: note
            )
            pendingFeedback = nil
            await refreshHome()
            return true
        } catch {
            errorMessage = "Не удалось сохранить RPE: \(error.localizedDescription)"
            return false
        }
    }

    func refreshHome() async {
        do {
            let value = try await localServices.home()
            localHome = value
            if let session = value.latestSession,
               lastSession == nil || session.observedTo > (lastSession?.endedAt ?? .distantPast) {
                lastSession = SessionSummaryViewData(
                    evidenceID: session.id,
                    endedAt: session.observedTo,
                    activeMinutes: (session.activeTime ?? 0) / 60,
                    restMinutes: (session.restTime ?? 0) / 60,
                    setCount: session.setCount ?? 0,
                    trackingCoverage: session.trackingCoverage ?? 0
                )
            }
            if let food = value.latestFood {
                latestFood = LocalFoodAnalysis(
                    containsFood: true,
                    stored: true,
                    duplicateOf: nil,
                    observationID: food.id,
                    confidence: food.items.map(\.labelConfidence).min() ?? 0,
                    caloriesLow: food.caloriesLow,
                    caloriesHigh: food.caloriesHigh,
                    items: food.localItems
                )
            }
        } catch {
            // The camera and local evidence must keep working without a network connection.
        }
    }

    func dismissLatestFood() async {
        guard let observationID = latestFood?.observationID else {
            latestFood = nil
            return
        }
        do {
            try await localServices.dismissFood(observationID: observationID)
            latestFood = nil
            foodPhase = .watching
            await refreshHome()
        } catch {
            errorMessage = "Не удалось исправить запись о еде: \(error.localizedDescription)"
        }
    }

    private func consume(_ frame: PoseFrame) {
        samples = frame.samples
        boundingBox = frame.boundingBox
        trackingState = frame.trackingState
        metricExclusionReason = frame.exclusionReason

        let metrics = intensityEstimator.update(frame: frame)
        currentMetrics = metrics
        if isWorkoutRecording { captureQuality.record(frame: frame, metrics: metrics) }
        intensityHistory.append(metrics.isValid ? metrics.intensity : nil, at: frame.capturedAt)
        recordActivity(frame: frame, metrics: metrics)
    }

    private func recordActivity(frame: PoseFrame, metrics: MotionMetrics) {
        guard isWorkoutRecording else { return }
        if let sessionStartedAt {
            recordingElapsed = Date().timeIntervalSince(sessionStartedAt)
        }
        defer { lastFrameTimestamp = frame.capturedAt }
        guard let previousTimestamp = lastFrameTimestamp else { return }
        let duration = frame.capturedAt - previousTimestamp
        guard duration > 0, duration <= 2 else { return }

        activityWindows.append(ActivityWindow(
            duration: duration,
            normalizedJointVelocity: metrics.isValid ? metrics.normalizedJointVelocity : 0,
            movingJointFraction: metrics.isValid ? metrics.movingJointFraction : 0,
            boundingBoxMotion: metrics.isValid ? metrics.boundingBoxMotion : 0,
            motionScore: metrics.isValid ? metrics.segmentationMotionScore : 0,
            trackingAvailable: metrics.isValid
        ))

        if frame.capturedAt - lastLiveSummaryAt >= 0.75 {
            lastLiveSummaryAt = frame.capturedAt
            if let summary = try? ActivitySegmenter(configuration: .cameraV2).segment(activityWindows) {
                liveSetCount = summary.setCount
            }
        }
    }

    private func analyzeFood(detections: [FoodDetection], capturedAt: Date) async {
        guard foodScanEnabled, !foodRequestInFlight else { return }
        foodRequestInFlight = true
        foodPhase = .analyzing
        defer { foodRequestInFlight = false }
        do {
            let result = try await localServices.analyzeFood(detections: detections, capturedAt: capturedAt)
            if result.containsFood {
                var details: [String: LocalFoodItem] = [:]
                for (detection, item) in zip(detections, result.items) {
                    details[detection.label] = item
                }
                foodDetailsByLabel = details
                latestFood = result
                foodPhase = .watching
                await refreshHome()
            } else {
                foodPhase = .noFood
                try? await Task.sleep(for: .seconds(2))
                if foodScanEnabled { foodPhase = .watching }
            }
        } catch {
            foodPhase = .unavailable
        }
    }

    private func resetRealtimeMetrics() {
        samples = []
        boundingBox = nil
        trackingState = .acquiring
        metricExclusionReason = .acquiringSubject
        currentMetrics = .invalid(.warmup)
        intensityEstimator.reset()
        intensityHistory.reset()
        lastFrameTimestamp = nil
    }
}

private extension ActivitySegmentationConfiguration {
    static let cameraV2 = ActivitySegmentationConfiguration(
        enterVelocity: 0.36,
        exitVelocity: 0.16,
        enterMovingFraction: 0.42,
        exitMovingFraction: 0.20,
        enterBoundingBoxMotion: 0.42,
        exitBoundingBoxMotion: 0.18,
        minimumActiveDuration: 1.5,
        minimumRestDuration: 1.0,
        shortTrackingGapDuration: 1.0,
        enterConfirmationDuration: 0.8,
        exitConfirmationDuration: 0.7,
        boundingBoxCanEnterActivity: false
    )
}

struct MotionIntensityChart: View {
    let history: MotionIntensityHistory

    var body: some View {
        Canvas { context, size in
            guard history.points.count > 1,
                  let firstTime = history.points.first?.timestamp,
                  let lastTime = history.points.last?.timestamp else { return }
            let span = max(lastTime - firstTime, 0.001)
            var path = Path()
            var hasOpenSegment = false
            for point in history.points {
                guard let value = point.value else {
                    hasOpenSegment = false
                    continue
                }
                let x = CGFloat((point.timestamp - firstTime) / span) * size.width
                let y = MotionIntensityChartGeometry.y(for: value, height: size.height)
                if hasOpenSegment {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    hasOpenSegment = true
                }
            }
            context.stroke(path, with: .color(BaselineTheme.accent), lineWidth: 2)
        }
        .accessibilityLabel("Интенсивность за последние двенадцать секунд")
    }
}

enum MotionIntensityChartGeometry {
    static func y(for value: Double, height: CGFloat) -> CGFloat {
        guard height > 1 else { return 0 }
        return min(max(height * (1 - CGFloat(value)), 1), height - 1)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        updateMirroring(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        updateMirroring(uiView.previewLayer)
    }

    private func updateMirroring(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct PoseOverlay: View {
    let samples: [PoseSample]
    let boundingBox: NormalizedPoseRect?
    let state: PoseTrackingState

    var body: some View {
        Canvas { context, size in
            let points = Dictionary(uniqueKeysWithValues: samples.map {
                ($0.joint, CGPoint(x: $0.point.x * size.width, y: $0.point.y * size.height))
            })
            for (startJoint, endJoint) in bones {
                guard let start = points[startJoint], let end = points[endJoint] else { continue }
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(tone), lineWidth: 3)
            }
            for point in points.values {
                let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: rect), with: .color(tone))
            }
            if let boundingBox {
                let rect = CGRect(
                    x: boundingBox.x * size.width,
                    y: boundingBox.y * size.height,
                    width: boundingBox.width * size.width,
                    height: boundingBox.height * size.height
                )
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 12),
                    with: .color(tone.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var tone: Color {
        switch state {
        case .stable: BaselineTheme.accent
        case .acquiring, .degraded, .multiplePeople: Color.orange
        case .lost: Color.clear
        }
    }

    private var bones: [(PoseJoint, PoseJoint)] {
        [
            (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.neck, .root), (.root, .leftHip), (.root, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        ]
    }
}
