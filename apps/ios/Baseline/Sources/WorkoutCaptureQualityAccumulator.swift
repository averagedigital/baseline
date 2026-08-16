import AthleteSensors

struct WorkoutCaptureQualityAccumulator: Sendable {
    var ambiguousFrameCount = 0
    var identityDiscontinuityCount = 0
    var warmupFrameCount = 0
    var rejectedMotionFrameCount = 0

    mutating func record(frame: PoseFrame, metrics: MotionMetrics) {
        guard frame.trackingState != .lost || frame.exclusionReason != .noSubject else { return }
        if frame.trackingState == .multiplePeople || frame.exclusionReason == .ambiguousSubjects { ambiguousFrameCount += 1 }
        if frame.exclusionReason == .identityDiscontinuity { identityDiscontinuityCount += 1 }
        if metrics.exclusionReason == .warmup { warmupFrameCount += 1 }
        if frame.trackID != nil,
           !metrics.isValid,
           metrics.exclusionReason != .warmup,
           frame.exclusionReason != .ambiguousSubjects,
           frame.exclusionReason != .identityDiscontinuity {
            rejectedMotionFrameCount += 1
        }
    }
}
