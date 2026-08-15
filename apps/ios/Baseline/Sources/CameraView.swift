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
    let context: PersonalizationContext
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
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
            }
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
        guard let latestFood, latestFood.containsFood else { return nil }
        return "≈ \(Int(latestFood.caloriesLow.rounded()))–\(Int(latestFood.caloriesHigh.rounded())) ккал"
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

    func setFoodScanEnabled(_ enabled: Bool) {
        foodScanEnabled = enabled
        pipeline.setFoodScanEnabled(enabled)
        if enabled {
            foodPhase = .watching
        } else {
            latestFood = nil
        }
    }

    func startWorkout() {
        guard !isWorkoutRecording else { return }
        isWorkoutRecording = true
        sessionStartedAt = Date()
        activityWindows = []
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
                captureQuality: SessionCaptureQuality(trackingGapCount: summary.segments.filter { $0.state == .trackingGap }.count),
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
            let context = PersonalizationContext(
                activeMinutes: summary.activeTime / 60,
                setCount: summary.setCount,
                workRestRatio: summary.activeTime / max(summary.restTime, 60),
                trackingCoverage: summary.coverage,
                sevenDayActiveMinutes: summary.activeTime / 60,
                hoursSincePreviousSession: 72,
                recentFoodKcalMidpoint: latestFood.map { ($0.caloriesLow + $0.caloriesHigh) / 2 } ?? 0
            )
            pendingFeedback = PendingSessionFeedback(
                feedbackEventID: UUID(),
                evidenceID: envelope.id,
                context: context,
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
                    items: food.items
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

struct CameraCard: View {
    let model: CameraModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(
                    session: model.pipeline.session,
                    isMirrored: model.cameraPosition == .front
                )
                PoseOverlay(
                    samples: model.samples,
                    boundingBox: model.boundingBox,
                    state: model.trackingState
                )

                VStack {
                    HStack {
                        TrackingStatusPill(
                            label: model.trackingLabel,
                            tone: model.trackingTone,
                            pulses: model.trackingState == .stable && model.isCameraRunning
                        )
                        Spacer()
                        cameraControls
                    }
                    Spacer()
                    if model.trackingState == .multiplePeople
                        || model.metricExclusionReason == .identityDiscontinuity {
                        Button("Зафиксировать меня заново") {
                            model.resetSubjectLock()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BaselineTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.94), in: Capsule())
                        .transition(.opacity)
                    }
                }
                .padding(12)
            }
            .frame(height: 360)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            ))

            liveDock
                .padding(16)
        }
        .baselineCard(radius: 20)
        .animation(reduceMotion ? nil : BaselineTheme.standardAnimation, value: model.trackingState)
    }

    private var cameraControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.switchCamera() }
            } label: {
                Image(systemName: "camera.rotate")
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.94), in: Circle())
            }
            .foregroundStyle(BaselineTheme.ink)
            .accessibilityLabel("Переключить камеру")
        }
    }

    private var liveDock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Интенсивность")
                        .font(.caption)
                        .foregroundStyle(BaselineTheme.secondary)
                    Text(model.currentMetrics.isValid
                        ? String(format: "%.0f%%", model.currentMetrics.intensity * 100)
                        : "—")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                MotionIntensityChart(history: model.intensityHistory)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Активные блоки")
                        .font(.caption)
                        .foregroundStyle(BaselineTheme.secondary)
                    Text("\(model.liveSetCount)")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }

            Button {
                Task {
                    if model.isWorkoutRecording {
                        await model.stopWorkout()
                    } else {
                        model.startWorkout()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: model.isWorkoutRecording ? "stop.fill" : "play.fill")
                    Text(model.isWorkoutRecording
                        ? "Завершить · \(duration(model.recordingElapsed))"
                        : "Начать тренировку")
                }
            }
            .buttonStyle(BaselinePrimaryButtonStyle())
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct LatestFoodCard: View {
    let model: CameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Питание", systemImage: "fork.knife")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if model.foodPhase == .analyzing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(model.foodScanEnabled ? "Авто" : "Выкл.")
                        .font(.caption)
                        .foregroundStyle(BaselineTheme.secondary)
                }
            }

            if let calories = model.latestFoodCalories {
                Text(model.latestFoodTitle)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(calories)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Не еда") {
                        Task { await model.dismissLatestFood() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BaselineTheme.danger)
                }
                Text("Диапазон, а не точное число: порция оценивается по одному RGB-кадру.")
                    .font(.caption)
                    .foregroundStyle(BaselineTheme.secondary)
            } else {
                Text(model.latestFoodTitle)
                    .font(.system(size: 15, weight: .medium))
                Text("Изображения камеры обрабатываются в памяти и не сохраняются.")
                    .font(.caption)
                    .foregroundStyle(BaselineTheme.secondary)
            }
        }
        .padding(18)
        .baselineCard()
    }
}

struct HomeInsightCard: View {
    let model: CameraModel
    let openCoach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Сейчас")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if let confidence = model.localHome?.recommendationConfidence, model.localHome?.recommendationIsPersonalized == true, confidence > 0 {
                    Text("персонализация \(Int((confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(BaselineTheme.secondary)
                }
            }

            Text(insightTitle)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if let session = model.lastSession {
                Text("Последняя тренировка: \(session.setCount) активных блоков, \(Int(session.activeMinutes.rounded())) мин активности, покрытие \(Int((session.trackingCoverage * 100).rounded()))%.")
                    .font(.subheadline)
                    .foregroundStyle(BaselineTheme.secondary)
            } else {
                Text("После первой сохранённой тренировки здесь появится один приоритетный вывод.")
                    .font(.subheadline)
                    .foregroundStyle(BaselineTheme.secondary)
            }

            Button("Открыть Coach") {
                openCoach()
            }
            .buttonStyle(BaselineSecondaryButtonStyle())
        }
        .padding(18)
        .baselineCard()
    }

    private var insightTitle: String {
        switch model.localHome?.suggestedAction {
        case "technique": "Сфокусироваться на технике"
        case "load": "Сверить рабочую нагрузку"
        case "recovery": "Проверить восстановление"
        case "nutrition": "Уточнить питание вокруг тренировки"
        case "consistency": "Сохранить ритм тренировок"
        default: "Собрать первую надёжную базовую линию"
        }
    }
}

private struct TrackingStatusPill: View {
    let label: String
    let tone: Color
    let pulses: Bool
    @State private var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
                .opacity(pulses && highlighted ? 0.45 : 1)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(BaselineTheme.ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.94), in: Capsule())
        .onAppear {
            guard pulses, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                highlighted = true
            }
        }
        .onChange(of: pulses) { _, value in
            highlighted = false
            guard value, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                highlighted = true
            }
        }
    }
}

private struct MotionIntensityChart: View {
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
                let y = size.height * (1 - CGFloat(value))
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

private struct CameraPreview: UIViewRepresentable {
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

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct PoseOverlay: View {
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
