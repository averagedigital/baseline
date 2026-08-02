import Foundation

public struct ActivitySegmentationConfiguration: Equatable, Sendable {
    public let enterVelocity: Double
    public let exitVelocity: Double
    public let enterMovingFraction: Double
    public let exitMovingFraction: Double
    public let enterBoundingBoxMotion: Double
    public let exitBoundingBoxMotion: Double
    public let minimumActiveDuration: TimeInterval
    public let minimumRestDuration: TimeInterval
    public let shortTrackingGapDuration: TimeInterval

    public init(
        enterVelocity: Double,
        exitVelocity: Double,
        enterMovingFraction: Double,
        exitMovingFraction: Double,
        enterBoundingBoxMotion: Double,
        exitBoundingBoxMotion: Double,
        minimumActiveDuration: TimeInterval,
        minimumRestDuration: TimeInterval,
        shortTrackingGapDuration: TimeInterval
    ) {
        self.enterVelocity = enterVelocity
        self.exitVelocity = exitVelocity
        self.enterMovingFraction = enterMovingFraction
        self.exitMovingFraction = exitMovingFraction
        self.enterBoundingBoxMotion = enterBoundingBoxMotion
        self.exitBoundingBoxMotion = exitBoundingBoxMotion
        self.minimumActiveDuration = minimumActiveDuration
        self.minimumRestDuration = minimumRestDuration
        self.shortTrackingGapDuration = shortTrackingGapDuration
    }
}

public struct ActivityWindow: Equatable, Sendable {
    public let duration: TimeInterval
    public let normalizedJointVelocity: Double
    public let movingJointFraction: Double
    public let boundingBoxMotion: Double
    public let trackingAvailable: Bool

    public init(
        duration: TimeInterval,
        normalizedJointVelocity: Double,
        movingJointFraction: Double,
        boundingBoxMotion: Double,
        trackingAvailable: Bool
    ) {
        self.duration = duration
        self.normalizedJointVelocity = normalizedJointVelocity
        self.movingJointFraction = movingJointFraction
        self.boundingBoxMotion = boundingBoxMotion
        self.trackingAvailable = trackingAvailable
    }
}

public enum ActivitySegmentState: String, Codable, Equatable, Sendable {
    case active
    case rest
    case trackingGap
}

public struct ActivitySegment: Equatable, Sendable {
    public let state: ActivitySegmentState
    public let start: TimeInterval
    public let end: TimeInterval

    public init(state: ActivitySegmentState, start: TimeInterval, end: TimeInterval) {
        self.state = state
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

public struct ActivitySummary: Equatable, Sendable {
    public let segments: [ActivitySegment]
    public let activeTime: TimeInterval
    public let restTime: TimeInterval
    public let trackingGapTime: TimeInterval
    public let setCount: Int
    public let coverage: Double
}

public enum ActivitySegmentationError: Error, Equatable, Sendable {
    case invalidDuration(index: Int)
}

public struct ActivitySegmenter: Sendable {
    private let configuration: ActivitySegmentationConfiguration

    public init(configuration: ActivitySegmentationConfiguration) {
        self.configuration = configuration
    }

    public func segment(_ windows: [ActivityWindow]) throws -> ActivitySummary {
        for (index, window) in windows.enumerated() where window.duration < 0 {
            throw ActivitySegmentationError.invalidDuration(index: index)
        }

        var motionState = ActivitySegmentState.rest
        var offset: TimeInterval = 0
        var segments: [ActivitySegment] = []

        for window in windows where window.duration > 0 {
            let state: ActivitySegmentState
            if !window.trackingAvailable {
                state = .trackingGap
            } else {
                switch motionState {
                case .rest, .trackingGap:
                    if entersActive(window) { motionState = .active }
                case .active:
                    if exitsActive(window) { motionState = .rest }
                }
                state = motionState
            }
            append(state: state, duration: window.duration, offset: &offset, to: &segments)
        }

        segments = normalize(segments)
        let activeTime = duration(of: .active, in: segments)
        let restTime = duration(of: .rest, in: segments)
        let trackingGapTime = duration(of: .trackingGap, in: segments)
        let total = activeTime + restTime + trackingGapTime

        return ActivitySummary(
            segments: segments,
            activeTime: activeTime,
            restTime: restTime,
            trackingGapTime: trackingGapTime,
            setCount: countSets(in: segments),
            coverage: total == 0 ? 0 : (activeTime + restTime) / total
        )
    }

    private func entersActive(_ window: ActivityWindow) -> Bool {
        window.normalizedJointVelocity >= configuration.enterVelocity
            || window.movingJointFraction >= configuration.enterMovingFraction
            || window.boundingBoxMotion >= configuration.enterBoundingBoxMotion
    }

    private func exitsActive(_ window: ActivityWindow) -> Bool {
        window.normalizedJointVelocity <= configuration.exitVelocity
            && window.movingJointFraction <= configuration.exitMovingFraction
            && window.boundingBoxMotion <= configuration.exitBoundingBoxMotion
    }

    private func normalize(_ source: [ActivitySegment]) -> [ActivitySegment] {
        let withoutShortActivity = source.map { segment in
            guard segment.state == .active,
                  segment.duration < configuration.minimumActiveDuration else { return segment }
            return ActivitySegment(state: .rest, start: segment.start, end: segment.end)
        }
        let merged = mergeAdjacent(withoutShortActivity)
        let withoutShortRest = merged.enumerated().map { index, segment in
            guard segment.state == .rest,
                  segment.duration < configuration.minimumRestDuration,
                  index > 0,
                  index < merged.count - 1,
                  merged[index - 1].state == .active,
                  merged[index + 1].state == .active else { return segment }
            return ActivitySegment(state: .active, start: segment.start, end: segment.end)
        }
        return mergeAdjacent(withoutShortRest)
    }

    private func mergeAdjacent(_ source: [ActivitySegment]) -> [ActivitySegment] {
        var result: [ActivitySegment] = []
        for segment in source {
            if let last = result.last, last.state == segment.state {
                result[result.count - 1] = ActivitySegment(
                    state: last.state,
                    start: last.start,
                    end: segment.end
                )
            } else {
                result.append(segment)
            }
        }
        return result
    }

    private func countSets(in segments: [ActivitySegment]) -> Int {
        var count = 0
        var continuesSet = false
        for segment in segments {
            switch segment.state {
            case .active:
                if !continuesSet { count += 1 }
                continuesSet = true
            case .rest:
                continuesSet = false
            case .trackingGap:
                if segment.duration > configuration.shortTrackingGapDuration {
                    continuesSet = false
                }
            }
        }
        return count
    }

    private func duration(of state: ActivitySegmentState, in segments: [ActivitySegment]) -> TimeInterval {
        segments.filter { $0.state == state }.reduce(0) { $0 + $1.duration }
    }

    private func append(
        state: ActivitySegmentState,
        duration: TimeInterval,
        offset: inout TimeInterval,
        to segments: inout [ActivitySegment]
    ) {
        let end = offset + duration
        if let last = segments.last, last.state == state {
            segments[segments.count - 1] = ActivitySegment(state: state, start: last.start, end: end)
        } else {
            segments.append(ActivitySegment(state: state, start: offset, end: end))
        }
        offset = end
    }
}
