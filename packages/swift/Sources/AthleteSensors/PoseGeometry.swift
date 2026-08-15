import Foundation

public enum PoseJoint: String, Codable, Hashable, Sendable, CaseIterable {
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

public struct NormalizedPoseRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { width * height }
    public var diagonal: Double { hypot(width, height) }
    public var center: NormalizedPosePoint {
        NormalizedPosePoint(x: x + width / 2, y: y + height / 2, confidence: 1)
    }

    public func intersectionOverUnion(with other: NormalizedPoseRect) -> Double {
        let intersectionWidth = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let intersectionHeight = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        let intersection = intersectionWidth * intersectionHeight
        let union = area + other.area - intersection
        return union > 0 ? intersection / union : 0
    }
}

public struct PoseCandidate: Equatable, Sendable {
    public let samples: [PoseSample]
    public let boundingBox: NormalizedPoseRect
    public let averageConfidence: Double
    public let appearanceSignature: AppearanceSignature?

    public init(samples: [PoseSample], boundingBox: NormalizedPoseRect, averageConfidence: Double, appearanceSignature: AppearanceSignature? = nil) {
        self.samples = samples
        self.boundingBox = boundingBox
        self.averageConfidence = averageConfidence
        self.appearanceSignature = appearanceSignature
    }

    public init?(samples: [PoseSample], minimumConfidence: Double = 0.2) {
        let accepted = samples.filter { $0.point.confidence >= minimumConfidence }
        guard accepted.count >= 5 else { return nil }
        let xs = accepted.map(\.point.x)
        let ys = accepted.map(\.point.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        let confidence = accepted.reduce(0) { $0 + $1.point.confidence } / Double(accepted.count)
        self.init(
            samples: accepted,
            boundingBox: NormalizedPoseRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            averageConfidence: confidence
        )
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

    public func displayRect(for rect: NormalizedPoseRect) -> NormalizedPoseRect {
        NormalizedPoseRect(
            x: isMirrored ? 1 - rect.maxX : rect.x,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

public struct PoseSmoother: Sendable {
    private let alpha: Double
    private var previousPoints: [PoseJoint: NormalizedPosePoint] = [:]

    public init(alpha: Double) {
        self.alpha = min(max(alpha, 0), 1)
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

    public mutating func reset() {
        previousPoints.removeAll(keepingCapacity: true)
    }
}

public enum PoseTrackingState: String, Codable, Equatable, Sendable {
    case acquiring
    case stable
    case degraded
    case lost
    case multiplePeople
}

public enum PoseMetricExclusionReason: String, Codable, Equatable, Sendable {
    case none
    case noSubject
    case acquiringSubject
    case ambiguousSubjects
    case identityDiscontinuity
    case lowConfidence
    case warmup
}

public struct TrackingQualityClassifier: Sendable {
    public init() {}

    public func classify(sampleCount: Int, averageConfidence: Double, subjectCount: Int) -> PoseTrackingState {
        if subjectCount > 1 { return .multiplePeople }
        if sampleCount >= 10, averageConfidence >= 0.45 { return .stable }
        if sampleCount >= 5, averageConfidence >= 0.25 { return .degraded }
        return .lost
    }

    public func classifyLocked(sampleCount: Int, averageConfidence: Double) -> PoseTrackingState {
        if sampleCount >= 10, averageConfidence >= 0.45 { return .stable }
        if sampleCount >= 5, averageConfidence >= 0.25 { return .degraded }
        return .lost
    }
}

public struct PoseFrame: Equatable, Sendable {
    public let samples: [PoseSample]
    public let boundingBox: NormalizedPoseRect?
    public let trackID: UUID?
    public let capturedAt: TimeInterval
    public let trackingState: PoseTrackingState
    public let isMetricEligible: Bool
    public let exclusionReason: PoseMetricExclusionReason

    public init(
        samples: [PoseSample],
        boundingBox: NormalizedPoseRect? = nil,
        trackID: UUID? = nil,
        capturedAt: TimeInterval = 0,
        trackingState: PoseTrackingState,
        isMetricEligible: Bool = false,
        exclusionReason: PoseMetricExclusionReason = .noSubject
    ) {
        self.samples = samples
        self.boundingBox = boundingBox
        self.trackID = trackID
        self.capturedAt = capturedAt
        self.trackingState = trackingState
        self.isMetricEligible = isMetricEligible
        self.exclusionReason = exclusionReason
    }
}

public struct PrimarySubjectTrackerConfiguration: Equatable, Sendable {
    public let acquisitionFrames: Int
    public let ambiguityMargin: Double
    public let minimumContinuityScore: Double
    public let maximumCenterDistance: Double
    public let maximumPoseDistance: Double
    public let maximumHoldFrames: Int
    public let appearanceDistanceGate: Double

    public init(
        acquisitionFrames: Int = 5,
        ambiguityMargin: Double = 0.12,
        minimumContinuityScore: Double = 0.42,
        maximumCenterDistance: Double = 1.25,
        maximumPoseDistance: Double = 0.8,
        maximumHoldFrames: Int = 18
        , appearanceDistanceGate: Double = 0.45
    ) {
        self.acquisitionFrames = max(1, acquisitionFrames)
        self.ambiguityMargin = max(0, ambiguityMargin)
        self.minimumContinuityScore = min(max(minimumContinuityScore, 0), 1)
        self.maximumCenterDistance = max(0.1, maximumCenterDistance)
        self.maximumPoseDistance = max(0.1, maximumPoseDistance)
        self.maximumHoldFrames = max(1, maximumHoldFrames)
        self.appearanceDistanceGate = max(0, appearanceDistanceGate)
    }
}

public struct SubjectTrackingResult: Equatable, Sendable {
    public let candidate: PoseCandidate?
    public let trackID: UUID?
    public let trackingState: PoseTrackingState
    public let isMetricEligible: Bool
    public let exclusionReason: PoseMetricExclusionReason

    public init(
        candidate: PoseCandidate?,
        trackID: UUID?,
        trackingState: PoseTrackingState,
        isMetricEligible: Bool,
        exclusionReason: PoseMetricExclusionReason
    ) {
        self.candidate = candidate
        self.trackID = trackID
        self.trackingState = trackingState
        self.isMetricEligible = isMetricEligible
        self.exclusionReason = exclusionReason
    }
}

public struct PrimarySubjectTracker: Sendable {
    private let configuration: PrimarySubjectTrackerConfiguration
    private var activeTrackID: UUID?
    private var lastCandidate: PoseCandidate?
    private var pendingCandidate: PoseCandidate?
    private var pendingFrames = 0
    private var holdFrames = 0
    private let appearanceComparator: any AppearanceComparing

    public init(configuration: PrimarySubjectTrackerConfiguration = .init(), appearanceComparator: any AppearanceComparing = EuclideanAppearanceComparator()) {
        self.configuration = configuration
        self.appearanceComparator = appearanceComparator
    }

    public mutating func reset() {
        activeTrackID = nil
        lastCandidate = nil
        pendingCandidate = nil
        pendingFrames = 0
        holdFrames = 0
    }

    public mutating func update(candidates: [PoseCandidate]) -> SubjectTrackingResult {
        guard !candidates.isEmpty else {
            return holdOrLose(reason: .noSubject)
        }
        guard let lastCandidate, let activeTrackID else {
            return acquire(from: candidates)
        }

        let ranked = candidates.compactMap { candidate -> (candidate: PoseCandidate, score: Double)? in
            guard passesHardGate(candidate, against: lastCandidate) else { return nil }
            return (candidate, continuityScore(candidate, against: lastCandidate))
        }.sorted { $0.score > $1.score }

        guard let best = ranked.first, best.score >= configuration.minimumContinuityScore else {
            return holdOrLose(reason: .identityDiscontinuity)
        }
        if ranked.count > 1, best.score - ranked[1].score < configuration.ambiguityMargin {
            return holdOrLose(reason: .ambiguousSubjects)
        }

        self.lastCandidate = best.candidate
        holdFrames = 0
        let quality = TrackingQualityClassifier().classifyLocked(
            sampleCount: best.candidate.samples.count,
            averageConfidence: best.candidate.averageConfidence
        )
        let eligible = quality == .stable || quality == .degraded
        return SubjectTrackingResult(
            candidate: best.candidate,
            trackID: activeTrackID,
            trackingState: quality,
            isMetricEligible: eligible,
            exclusionReason: eligible ? .none : .lowConfidence
        )
    }

    private mutating func acquire(from candidates: [PoseCandidate]) -> SubjectTrackingResult {
        let ranked = candidates.map { ($0, acquisitionScore($0)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else {
            return SubjectTrackingResult(
                candidate: nil,
                trackID: nil,
                trackingState: .lost,
                isMetricEligible: false,
                exclusionReason: .noSubject
            )
        }
        if ranked.count > 1, best.1 - ranked[1].1 < configuration.ambiguityMargin / 2 {
            pendingCandidate = nil
            pendingFrames = 0
            return SubjectTrackingResult(
                candidate: best.0,
                trackID: nil,
                trackingState: .multiplePeople,
                isMetricEligible: false,
                exclusionReason: .ambiguousSubjects
            )
        }

        if let pendingCandidate, passesHardGate(best.0, against: pendingCandidate),
           continuityScore(best.0, against: pendingCandidate) >= configuration.minimumContinuityScore {
            self.pendingCandidate = best.0
            pendingFrames += 1
        } else {
            pendingCandidate = best.0
            pendingFrames = 1
        }

        guard pendingFrames >= configuration.acquisitionFrames else {
            return SubjectTrackingResult(
                candidate: best.0,
                trackID: nil,
                trackingState: .acquiring,
                isMetricEligible: false,
                exclusionReason: .acquiringSubject
            )
        }

        let id = UUID()
        activeTrackID = id
        lastCandidate = best.0
        pendingCandidate = nil
        pendingFrames = 0
        holdFrames = 0
        let quality = TrackingQualityClassifier().classifyLocked(
            sampleCount: best.0.samples.count,
            averageConfidence: best.0.averageConfidence
        )
        return SubjectTrackingResult(
            candidate: best.0,
            trackID: id,
            trackingState: quality,
            isMetricEligible: quality == .stable || quality == .degraded,
            exclusionReason: quality == .lost ? .lowConfidence : .none
        )
    }

    private mutating func holdOrLose(reason: PoseMetricExclusionReason) -> SubjectTrackingResult {
        guard let lastCandidate, let activeTrackID else {
            pendingCandidate = nil
            pendingFrames = 0
            return SubjectTrackingResult(
                candidate: nil,
                trackID: nil,
                trackingState: .lost,
                isMetricEligible: false,
                exclusionReason: reason
            )
        }
        holdFrames += 1
        let state: PoseTrackingState = reason == .ambiguousSubjects ? .multiplePeople : .lost
        if holdFrames > configuration.maximumHoldFrames {
            // Keep the identity lock and the last location. A distant person must never become
            // the active subject automatically; the UI can explicitly call reset().
            holdFrames = configuration.maximumHoldFrames
        }
        return SubjectTrackingResult(
            candidate: lastCandidate,
            trackID: activeTrackID,
            trackingState: state,
            isMetricEligible: false,
            exclusionReason: reason
        )
    }

    private func acquisitionScore(_ candidate: PoseCandidate) -> Double {
        let center = candidate.boundingBox.center
        let centerDistance = hypot(center.x - 0.5, center.y - 0.5) / hypot(0.5, 0.5)
        let centerScore = 1 - min(centerDistance, 1)
        let sizeScore = min(candidate.boundingBox.area / 0.35, 1)
        return 0.48 * centerScore + 0.32 * sizeScore + 0.20 * candidate.averageConfidence
    }

    private func passesHardGate(_ candidate: PoseCandidate, against previous: PoseCandidate) -> Bool {
        let scale = max(max(candidate.boundingBox.diagonal, previous.boundingBox.diagonal), 0.12)
        let centerDistance = hypot(
            candidate.boundingBox.center.x - previous.boundingBox.center.x,
            candidate.boundingBox.center.y - previous.boundingBox.center.y
        ) / scale
        let iou = candidate.boundingBox.intersectionOverUnion(with: previous.boundingBox)
        if centerDistance > configuration.maximumCenterDistance, iou < 0.05 { return false }
        if let distance = poseDistance(candidate, previous), distance > configuration.maximumPoseDistance {
            return false
        }
        if let lhs = candidate.appearanceSignature, let rhs = previous.appearanceSignature,
           appearanceComparator.distance(lhs, rhs) > configuration.appearanceDistanceGate { return false }
        return true
    }

    private func continuityScore(_ candidate: PoseCandidate, against previous: PoseCandidate) -> Double {
        let scale = max(max(candidate.boundingBox.diagonal, previous.boundingBox.diagonal), 0.12)
        let centerDistance = hypot(
            candidate.boundingBox.center.x - previous.boundingBox.center.x,
            candidate.boundingBox.center.y - previous.boundingBox.center.y
        ) / scale
        let centerScore = 1 - min(centerDistance / configuration.maximumCenterDistance, 1)
        let iou = candidate.boundingBox.intersectionOverUnion(with: previous.boundingBox)
        let poseScore: Double
        if let distance = poseDistance(candidate, previous) {
            poseScore = 1 - min(distance / configuration.maximumPoseDistance, 1)
        } else {
            poseScore = 0.45
        }
        let appearanceScore: Double
        if let lhs = candidate.appearanceSignature, let rhs = previous.appearanceSignature {
            appearanceScore = 1 - min(appearanceComparator.distance(lhs, rhs) / max(configuration.appearanceDistanceGate, 0.001), 1)
        } else { appearanceScore = 0.5 }
        return 0.30 * iou + 0.22 * centerScore + 0.28 * poseScore + 0.10 * candidate.averageConfidence + 0.10 * appearanceScore
    }

    private func poseDistance(_ left: PoseCandidate, _ right: PoseCandidate) -> Double? {
        let leftPoints = Dictionary(uniqueKeysWithValues: left.samples.map { ($0.joint, $0.point) })
        let rightPoints = Dictionary(uniqueKeysWithValues: right.samples.map { ($0.joint, $0.point) })
        let scale = max(max(left.boundingBox.diagonal, right.boundingBox.diagonal), 0.12)
        var distances: [Double] = []
        for joint in PoseJoint.allCases {
            guard let lhs = leftPoints[joint], let rhs = rightPoints[joint],
                  lhs.confidence >= 0.25, rhs.confidence >= 0.25 else { continue }
            distances.append(hypot(lhs.x - rhs.x, lhs.y - rhs.y) / scale)
        }
        guard distances.count >= 5 else { return nil }
        return median(distances)
    }
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
