import Foundation

public struct MotionIntensityConfiguration: Equatable, Sendable {
    public let minimumJointConfidence: Double
    public let minimumCommonJoints: Int
    public let maximumFrameGap: TimeInterval
    public let movingJointSpeedThreshold: Double
    public let velocityReference: Double
    public let boundingBoxMotionReference: Double
    public let warmupFrames: Int
    public let robustWindowSize: Int
    public let robustMADMultiplier: Double
    public let maximumIntensity: Double
    public let oneEuroMinimumCutoff: Double
    public let oneEuroBeta: Double
    public let oneEuroDerivativeCutoff: Double

    public init(
        minimumJointConfidence: Double = 0.3,
        minimumCommonJoints: Int = 6,
        maximumFrameGap: TimeInterval = 0.25,
        movingJointSpeedThreshold: Double = 0.55,
        velocityReference: Double = 2.4,
        boundingBoxMotionReference: Double = 1.5,
        warmupFrames: Int = 6,
        robustWindowSize: Int = 31,
        robustMADMultiplier: Double = 3.5,
        maximumIntensity: Double = 0.92,
        oneEuroMinimumCutoff: Double = 1.0,
        oneEuroBeta: Double = 0.025,
        oneEuroDerivativeCutoff: Double = 1.0
    ) {
        self.minimumJointConfidence = min(max(minimumJointConfidence, 0), 1)
        self.minimumCommonJoints = max(1, minimumCommonJoints)
        self.maximumFrameGap = max(1.0 / 240, maximumFrameGap)
        self.movingJointSpeedThreshold = max(0.01, movingJointSpeedThreshold)
        self.velocityReference = max(0.01, velocityReference)
        self.boundingBoxMotionReference = max(0.01, boundingBoxMotionReference)
        self.warmupFrames = max(0, warmupFrames)
        self.robustWindowSize = max(5, robustWindowSize)
        self.robustMADMultiplier = max(0, robustMADMultiplier)
        self.maximumIntensity = min(max(maximumIntensity, 0.05), 1)
        self.oneEuroMinimumCutoff = max(0.001, oneEuroMinimumCutoff)
        self.oneEuroBeta = max(0, oneEuroBeta)
        self.oneEuroDerivativeCutoff = max(0.001, oneEuroDerivativeCutoff)
    }
}

public struct MotionMetrics: Equatable, Sendable {
    public let intensity: Double
    public let normalizedJointVelocity: Double
    public let movingJointFraction: Double
    public let boundingBoxMotion: Double
    public let segmentationMotionScore: Double
    public let acceptedJointCount: Int
    public let isValid: Bool
    public let exclusionReason: PoseMetricExclusionReason

    public init(
        intensity: Double,
        normalizedJointVelocity: Double,
        movingJointFraction: Double,
        boundingBoxMotion: Double,
        segmentationMotionScore: Double = 0,
        acceptedJointCount: Int,
        isValid: Bool,
        exclusionReason: PoseMetricExclusionReason
    ) {
        self.intensity = intensity
        self.normalizedJointVelocity = normalizedJointVelocity
        self.movingJointFraction = movingJointFraction
        self.boundingBoxMotion = boundingBoxMotion
        self.segmentationMotionScore = min(max(segmentationMotionScore, 0), 1)
        self.acceptedJointCount = acceptedJointCount
        self.isValid = isValid
        self.exclusionReason = exclusionReason
    }

    public static func invalid(_ reason: PoseMetricExclusionReason) -> MotionMetrics {
        MotionMetrics(
            intensity: 0,
            normalizedJointVelocity: 0,
            movingJointFraction: 0,
            boundingBoxMotion: 0,
            acceptedJointCount: 0,
            isValid: false,
            exclusionReason: reason
        )
    }
}

public struct MotionIntensityEstimator: Sendable {
    private let configuration: MotionIntensityConfiguration
    private var previousPoints: [PoseJoint: NormalizedPosePoint] = [:]
    private var previousBoundingBox: NormalizedPoseRect?
    private var previousTimestamp: TimeInterval?
    private var previousTrackID: UUID?
    private var validFrameCount = 0
    private var intensityWindow: [Double] = []
    private var velocityWindow: [Double] = []
    private var movingFractionWindow: [Double] = []
    private var filter: OneEuroFilter
    private var segmentationFilter = LowPassFilter()

    public init(configuration: MotionIntensityConfiguration = .init()) {
        self.configuration = configuration
        filter = OneEuroFilter(
            minimumCutoff: configuration.oneEuroMinimumCutoff,
            beta: configuration.oneEuroBeta,
            derivativeCutoff: configuration.oneEuroDerivativeCutoff
        )
    }

    public mutating func reset() {
        previousPoints.removeAll(keepingCapacity: true)
        previousBoundingBox = nil
        previousTimestamp = nil
        previousTrackID = nil
        validFrameCount = 0
        intensityWindow.removeAll(keepingCapacity: true)
        velocityWindow.removeAll(keepingCapacity: true)
        movingFractionWindow.removeAll(keepingCapacity: true)
        filter.reset()
        segmentationFilter.reset()
    }

    public mutating func update(frame: PoseFrame) -> MotionMetrics {
        guard let trackID = frame.trackID else {
            resetTemporalState()
            return .invalid(frame.exclusionReason == .none ? .noSubject : frame.exclusionReason)
        }
        if let previousTrackID, previousTrackID != trackID {
            reset()
            self.previousTrackID = trackID
            seed(with: frame)
            return .invalid(.identityDiscontinuity)
        }
        previousTrackID = trackID

        guard frame.isMetricEligible, let boundingBox = frame.boundingBox else {
            resetTemporalState(keepTrackID: true)
            return .invalid(frame.exclusionReason == .none ? .lowConfidence : frame.exclusionReason)
        }
        guard let previousTimestamp, let previousBoundingBox else {
            seed(with: frame)
            return .invalid(.warmup)
        }

        let dt = frame.capturedAt - previousTimestamp
        guard dt > 0, dt <= configuration.maximumFrameGap else {
            seed(with: frame)
            validFrameCount = 0
            filter.reset()
            return .invalid(.warmup)
        }

        let current = Dictionary(uniqueKeysWithValues: frame.samples.map { ($0.joint, $0.point) })
        let bodyScale = max(max(boundingBox.diagonal, previousBoundingBox.diagonal), 0.12)
        let translationX = boundingBox.center.x - previousBoundingBox.center.x
        let translationY = boundingBox.center.y - previousBoundingBox.center.y
        var jointSpeeds: [Double] = []
        for joint in PoseJoint.allCases {
            guard let point = current[joint], let previous = previousPoints[joint],
                  point.confidence >= configuration.minimumJointConfidence,
                  previous.confidence >= configuration.minimumJointConfidence else { continue }
            // Remove whole-body camera-plane translation. Walking into position or a
            // small camera movement must not look like internal exercise articulation.
            let localDeltaX = point.x - previous.x - translationX
            let localDeltaY = point.y - previous.y - translationY
            jointSpeeds.append(hypot(localDeltaX, localDeltaY) / bodyScale / dt)
        }

        guard jointSpeeds.count >= configuration.minimumCommonJoints else {
            seed(with: frame)
            validFrameCount = 0
            return .invalid(.lowConfidence)
        }

        let velocity = median(jointSpeeds)
        let movingFraction = Double(jointSpeeds.filter { $0 >= configuration.movingJointSpeedThreshold }.count)
            / Double(jointSpeeds.count)
        let centerSpeed = hypot(
            boundingBox.center.x - previousBoundingBox.center.x,
            boundingBox.center.y - previousBoundingBox.center.y
        ) / bodyScale / dt
        let areaRatio = max(boundingBox.area, 0.0001) / max(previousBoundingBox.area, 0.0001)
        let scaleSpeed = abs(log(areaRatio)) / dt
        let boxMotionRaw = centerSpeed + 0.18 * scaleSpeed

        let normalizedVelocity = clamp(velocity / configuration.velocityReference)
        let normalizedBoxMotion = clamp(boxMotionRaw / configuration.boundingBoxMotionReference)
        let rawIntensity = clamp(
            0.74 * normalizedVelocity
                + 0.22 * movingFraction
                + 0.04 * normalizedBoxMotion
        )
        let clipped = robustClip(rawIntensity, window: intensityWindow, hardMaximum: configuration.maximumIntensity)
        let filtered = min(
            filter.update(value: clipped, timestamp: frame.capturedAt),
            configuration.maximumIntensity
        )
        let robustVelocity = robustClip(normalizedVelocity, window: velocityWindow, hardMaximum: 1)
        let robustMovingFraction = robustClip(movingFraction, window: movingFractionWindow, hardMaximum: 1)
        let rawSegmentation = min(max(0.65 * robustVelocity + 0.35 * robustMovingFraction, 0), 1)
        let segmentationScore = segmentationFilter.update(value: rawSegmentation, alpha: 0.35)

        append(rawIntensity, to: &intensityWindow)
        append(normalizedVelocity, to: &velocityWindow)
        append(movingFraction, to: &movingFractionWindow)
        validFrameCount += 1
        seed(with: frame)

        guard validFrameCount > configuration.warmupFrames else {
            return MotionMetrics(
                intensity: 0,
                normalizedJointVelocity: normalizedVelocity,
                movingJointFraction: movingFraction,
                boundingBoxMotion: normalizedBoxMotion,
                segmentationMotionScore: 0,
                acceptedJointCount: jointSpeeds.count,
                isValid: false,
                exclusionReason: .warmup
            )
        }

        return MotionMetrics(
            intensity: filtered,
            normalizedJointVelocity: normalizedVelocity,
            movingJointFraction: movingFraction,
            boundingBoxMotion: normalizedBoxMotion,
            segmentationMotionScore: segmentationScore,
            acceptedJointCount: jointSpeeds.count,
            isValid: true,
            exclusionReason: .none
        )
    }

    private mutating func seed(with frame: PoseFrame) {
        previousPoints = Dictionary(uniqueKeysWithValues: frame.samples.map { ($0.joint, $0.point) })
        previousBoundingBox = frame.boundingBox
        previousTimestamp = frame.capturedAt
    }

    private mutating func resetTemporalState(keepTrackID: Bool = false) {
        previousPoints.removeAll(keepingCapacity: true)
        previousBoundingBox = nil
        previousTimestamp = nil
        validFrameCount = 0
        intensityWindow.removeAll(keepingCapacity: true)
        velocityWindow.removeAll(keepingCapacity: true)
        movingFractionWindow.removeAll(keepingCapacity: true)
        filter.reset()
        segmentationFilter.reset()
        if !keepTrackID { previousTrackID = nil }
    }

    private func robustClip(_ value: Double, window: [Double], hardMaximum: Double) -> Double {
        guard window.count >= 7 else { return min(value, hardMaximum) }
        let center = median(window)
        let absoluteDeviations = window.map { abs($0 - center) }
        let mad = median(absoluteDeviations) * 1.4826
        let allowance = max(0.06, configuration.robustMADMultiplier * mad)
        return min(min(value, center + allowance), hardMaximum)
    }

    private func append(_ value: Double, to window: inout [Double]) {
        window.append(value)
        if window.count > configuration.robustWindowSize { window.removeFirst(window.count - configuration.robustWindowSize) }
    }
}

private struct LowPassFilter: Sendable {
    private var state: Double?

    mutating func update(value: Double, alpha: Double) -> Double {
        guard let state else {
            self.state = value
            return value
        }
        let next = alpha * value + (1 - alpha) * state
        self.state = next
        return next
    }

    mutating func reset() {
        state = nil
    }
}

private struct OneEuroFilter: Sendable {
    let minimumCutoff: Double
    let beta: Double
    let derivativeCutoff: Double

    init(minimumCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minimumCutoff = minimumCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }
    private var previousRawValue: Double?
    private var previousTimestamp: TimeInterval?
    private var valueFilter = LowPassFilter()
    private var derivativeFilter = LowPassFilter()

    mutating func update(value: Double, timestamp: TimeInterval) -> Double {
        guard let previousTimestamp, let previousRawValue else {
            self.previousTimestamp = timestamp
            self.previousRawValue = value
            return valueFilter.update(value: value, alpha: 1)
        }
        let dt = max(timestamp - previousTimestamp, 1.0 / 240)
        let derivative = (value - previousRawValue) / dt
        let filteredDerivative = derivativeFilter.update(
            value: derivative,
            alpha: smoothingFactor(dt: dt, cutoff: derivativeCutoff)
        )
        let cutoff = minimumCutoff + beta * abs(filteredDerivative)
        let filtered = valueFilter.update(value: value, alpha: smoothingFactor(dt: dt, cutoff: cutoff))
        self.previousTimestamp = timestamp
        self.previousRawValue = value
        return filtered
    }

    mutating func reset() {
        previousRawValue = nil
        previousTimestamp = nil
        valueFilter.reset()
        derivativeFilter.reset()
    }

    private func smoothingFactor(dt: TimeInterval, cutoff: Double) -> Double {
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + timeConstant / dt)
    }
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
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
