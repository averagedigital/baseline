@preconcurrency import AVFoundation
import AthleteSensors
import CoreImage
import ImageIO
import UIKit
import Vision

enum CaptureCameraPosition: Sendable, Equatable {
    case front
    case back

    var toggled: Self { self == .front ? .back : .front }

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: .front
        case .back: .back
        }
    }
}

final class CameraPipeline: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    var onFrame: (@Sendable (PoseFrame) -> Void)?
    var onFoodCandidate: (@Sendable (Data, Date) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "org.averagedigital.baseline.camera", qos: .userInitiated)
    private let foodQueue = DispatchQueue(label: "org.averagedigital.baseline.food-gate", qos: .utility)
    private let output = AVCaptureVideoDataOutput()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var tracker = PrimarySubjectTracker()
    private var smoother = PoseSmoother(alpha: 0.24)
    private var foodGate = FoodFrameGate()
    private var isConfigured = false
    private var cameraInput: AVCaptureDeviceInput?
    private var cameraPosition: CaptureCameraPosition = .front
    private var lastPoseTimestamp: TimeInterval = -.infinity
    private var smoothedTrackID: UUID?
    private var lastDisplaySamples: [PoseSample] = []
    private var lastDisplayBox: NormalizedPoseRect?
    private var foodScanEnabled = true
    private var foodClassificationInFlight = false

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if !isConfigured {
                        try configure()
                        isConfigured = true
                    }
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setFoodScanEnabled(_ enabled: Bool) {
        queue.async { [self] in
            foodScanEnabled = enabled
            if !enabled { foodGate.reset() }
        }
    }

    func resetSubjectLock() {
        queue.async { [self] in resetTrackingState() }
    }

    func switchCamera(to position: CaptureCameraPosition) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard isConfigured else {
                        cameraPosition = position
                        continuation.resume()
                        return
                    }
                    try replaceCameraInput(with: position)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        try addCameraInput(position: cameraPosition)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraPipelineError.outputRejected }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            connection.isVideoMirrored = false
        }
    }

    private func addCameraInput(position: CaptureCameraPosition) throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position.avPosition
        ) else { throw CameraPipelineError.cameraUnavailable(position) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraPipelineError.inputRejected }
        session.addInput(input)
        cameraInput = input
        cameraPosition = position
    }

    private func replaceCameraInput(with position: CaptureCameraPosition) throws {
        guard position != cameraPosition else { return }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position.avPosition
        ) else { throw CameraPipelineError.cameraUnavailable(position) }
        let newInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let cameraInput { session.removeInput(cameraInput) }
        guard session.canAddInput(newInput) else {
            if let cameraInput, session.canAddInput(cameraInput) { session.addInput(cameraInput) }
            throw CameraPipelineError.inputRejected
        }
        session.addInput(newInput)
        cameraInput = newInput
        cameraPosition = position
        resetTrackingState()
        foodGate.reset()
    }

    private func resetTrackingState() {
        tracker.reset()
        smoother.reset()
        smoothedTrackID = nil
        lastDisplaySamples = []
        lastDisplayBox = nil
        lastPoseTimestamp = -.infinity
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp.isFinite else { return }

        if timestamp - lastPoseTimestamp >= 1.0 / 15.0 {
            lastPoseTimestamp = timestamp
            processPose(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
        if foodScanEnabled, !foodClassificationInFlight, foodGate.shouldEvaluate(at: timestamp) {
            foodClassificationInFlight = true
            processFoodGate(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func processPose(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                .perform([bodyRequest])
            let candidates = try (bodyRequest.results ?? []).compactMap { try makeCandidate($0) }
            let result = tracker.update(candidates: candidates)
            let geometry = CameraGeometry(isMirrored: cameraPosition == .front)

            var displaySamples: [PoseSample] = []
            var displayBox: NormalizedPoseRect?
            if let candidate = result.candidate {
                if result.isMetricEligible {
                    if smoothedTrackID != result.trackID {
                        smoother.reset()
                        smoothedTrackID = result.trackID
                    }
                    let smoothed = candidate.samples.map { smoother.smooth($0) }
                    displaySamples = smoothed.map(geometry.displaySample)
                    if let smoothedCandidate = PoseCandidate(samples: smoothed) {
                        displayBox = geometry.displayRect(for: smoothedCandidate.boundingBox)
                    } else {
                        displayBox = geometry.displayRect(for: candidate.boundingBox)
                    }
                    lastDisplaySamples = displaySamples
                    lastDisplayBox = displayBox
                } else if result.trackingState == .acquiring {
                    displaySamples = candidate.samples.map(geometry.displaySample)
                    displayBox = geometry.displayRect(for: candidate.boundingBox)
                } else {
                    displaySamples = lastDisplaySamples
                    displayBox = lastDisplayBox
                }
            }

            onFrame?(PoseFrame(
                samples: displaySamples,
                boundingBox: displayBox,
                trackID: result.trackID,
                capturedAt: timestamp,
                trackingState: result.trackingState,
                isMetricEligible: result.isMetricEligible,
                exclusionReason: result.exclusionReason
            ))
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func processFoodGate(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let box = PixelBufferBox(pixelBuffer)
        foodQueue.async { [weak self] in
            guard let self else { return }
            let labels: [FoodLabelObservation]
            do {
                let request = VNClassifyImageRequest()
                try VNImageRequestHandler(cvPixelBuffer: box.value, orientation: .up, options: [:])
                    .perform([request])
                labels = (request.results ?? []).map {
                    FoodLabelObservation(identifier: $0.identifier, confidence: Double($0.confidence))
                }
            } catch {
                labels = []
            }

            self.queue.async { [weak self] in
                guard let self else { return }
                self.foodClassificationInFlight = false
                guard self.foodScanEnabled, self.foodGate.consume(observations: labels, at: timestamp) else {
                    return
                }
                self.foodQueue.async { [weak self] in
                    guard let self, let jpeg = self.makeJPEG(pixelBuffer: box.value) else { return }
                    self.onFoodCandidate?(jpeg, Date())
                }
            }
        }
    }

    private func makeCandidate(_ observation: VNHumanBodyPoseObservation) throws -> PoseCandidate? {
        let points = try observation.recognizedPoints(.all)
        let samples = jointMap.compactMap { joint, visionJoint -> PoseSample? in
            guard let point = points[visionJoint], point.confidence > 0.2 else { return nil }
            return PoseSample(
                joint: joint,
                point: NormalizedPosePoint(
                    x: point.location.x,
                    y: point.location.y,
                    confidence: Double(point.confidence)
                )
            )
        }
        return PoseCandidate(samples: samples)
    }

    private func makeJPEG(pixelBuffer: CVPixelBuffer) -> Data? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(source, from: source.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        let maximumDimension: CGFloat = 768
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.72)
    }

    private var jointMap: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] {
        [
            (.nose, .nose), (.neck, .neck), (.root, .root),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip),
            (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        ]
    }
}


private final class PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer

    init(_ value: CVPixelBuffer) {
        self.value = value
    }
}

enum CameraPipelineError: LocalizedError {
    case cameraUnavailable(CaptureCameraPosition)
    case inputRejected
    case outputRejected

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable(.front): "Фронтальная камера недоступна."
        case .cameraUnavailable(.back): "Задняя камера недоступна."
        case .inputRejected: "Не удалось подключить вход камеры."
        case .outputRejected: "Не удалось подключить поток камеры."
        }
    }
}
