public enum PoseJoint: String, Codable, Hashable, Sendable {
    case nose
    case neck
    case root
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

public struct NormalizedPosePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct PoseSample: Codable, Equatable, Sendable {
    public let joint: PoseJoint
    public let point: NormalizedPosePoint

    public init(joint: PoseJoint, point: NormalizedPosePoint) {
        self.joint = joint
        self.point = point
    }
}

public struct CameraGeometry: Sendable {
    public let isMirrored: Bool

    public init(isMirrored: Bool) {
        self.isMirrored = isMirrored
    }

    public func displayPoint(for point: NormalizedPosePoint) -> NormalizedPosePoint {
        NormalizedPosePoint(
            x: isMirrored ? 1 - point.x : point.x,
            y: 1 - point.y,
            confidence: point.confidence
        )
    }

    public func displaySample(for sample: PoseSample) -> PoseSample {
        PoseSample(joint: sample.joint, point: displayPoint(for: sample.point))
    }
}

public struct PoseSmoother: Sendable {
    private let alpha: Double
    private var previousPoints: [PoseJoint: NormalizedPosePoint] = [:]

    public init(alpha: Double) {
        self.alpha = alpha
    }

    public mutating func smooth(_ sample: PoseSample) -> PoseSample {
        guard let previous = previousPoints[sample.joint] else {
            previousPoints[sample.joint] = sample.point
            return sample
        }
        let point = NormalizedPosePoint(
            x: previous.x + alpha * (sample.point.x - previous.x),
            y: previous.y + alpha * (sample.point.y - previous.y),
            confidence: sample.point.confidence
        )
        previousPoints[sample.joint] = point
        return PoseSample(joint: sample.joint, point: point)
    }
}
