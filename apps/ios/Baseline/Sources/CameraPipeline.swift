@preconcurrency import AVFoundation
import AthleteSensors
import ImageIO
import Vision

final class CameraPipeline: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    var onFrame: (@Sendable (PoseFrame) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "org.averagedigital.baseline.camera")
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanBodyPoseRequest()
    private var smoother = PoseSmoother(alpha: 0.25)
    private var isConfigured = false

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if !isConfigured {
                        try configure()
                        isConfigured = true
                    }
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraPipelineError.backCameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraPipelineError.inputRejected
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw CameraPipelineError.outputRejected
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.isVideoMirrored = false
        }
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            ).perform([request])
            let observations = request.results ?? []
            guard let observation = observations.first else {
                onFrame?(PoseFrame(samples: [], trackingState: .lost))
                return
            }
            let points = try observation.recognizedPoints(.all)
            let samples = jointMap.compactMap { joint, visionJoint -> PoseSample? in
                guard let point = points[visionJoint], point.confidence > 0.2 else { return nil }
                let sample = PoseSample(
                    joint: joint,
                    point: NormalizedPosePoint(
                        x: point.location.x,
                        y: point.location.y,
                        confidence: Double(point.confidence)
                    )
                )
                return smoother.smooth(sample)
            }
            let confidence = samples.isEmpty
                ? 0
                : samples.reduce(0) { $0 + $1.point.confidence } / Double(samples.count)
            let state = TrackingQualityClassifier().classify(
                sampleCount: samples.count,
                averageConfidence: confidence,
                subjectCount: observations.count
            )
            let geometry = CameraGeometry(isMirrored: false)
            onFrame?(PoseFrame(
                samples: samples.map(geometry.displaySample),
                trackingState: state
            ))
        } catch {
            onError?(error.localizedDescription)
        }
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

enum CameraPipelineError: LocalizedError {
    case backCameraUnavailable
    case inputRejected
    case outputRejected

    var errorDescription: String? {
        switch self {
        case .backCameraUnavailable: "Задняя камера недоступна."
        case .inputRejected: "Не удалось подключить вход камеры."
        case .outputRejected: "Не удалось подключить поток камеры."
        }
    }
}
