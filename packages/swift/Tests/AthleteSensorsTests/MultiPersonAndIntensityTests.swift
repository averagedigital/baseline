import AthleteSensors
import Foundation
import XCTest

private let allJoints = PoseJoint.allCases

private func candidate(
    centerX: Double,
    centerY: Double = 0.5,
    width: Double = 0.26,
    height: Double = 0.62,
    confidence: Double = 0.9,
    poseOffset: Double = 0,
    appearance: AppearanceSignature? = nil
) -> PoseCandidate {
    let rect = NormalizedPoseRect(
        x: centerX - width / 2,
        y: centerY - height / 2,
        width: width,
        height: height
    )
    let samples = allJoints.enumerated().map { index, joint in
        let column = Double(index % 4) / 3
        let row = Double(index / 4) / 3
        return PoseSample(
            joint: joint,
            point: NormalizedPosePoint(
                x: rect.x + rect.width * (0.2 + 0.6 * column) + poseOffset,
                y: rect.y + rect.height * (0.12 + 0.76 * row),
                confidence: confidence
            )
        )
    }
    return PoseCandidate(samples: samples, boundingBox: rect, averageConfidence: confidence, appearanceSignature: appearance)
}

final class AthleteSensorsTests: XCTestCase {
func testExplicitLockSelectsUserWithoutAcquisitionDelay() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 5))
    let selected = candidate(centerX: 0.75)
    tracker.lock(candidate: selected)

    let result = tracker.update(candidates: [candidate(centerX: 0.25), selected])

    XCTAssertNotNil(result.trackID)
    XCTAssertEqual(result.candidate?.boundingBox.center.x, selected.boundingBox.center.x)
    XCTAssertTrue(result.isMetricEligible)
}

func testKeepsIdentityWhenVisionOrderingChanges() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2))
    let user0 = candidate(centerX: 0.48)
    let stranger0 = candidate(centerX: 0.82, width: 0.18)

    _ = tracker.update(candidates: [user0, stranger0])
    let acquired = tracker.update(candidates: [stranger0, user0])
    let trackID = acquired.trackID
    XCTAssertNotNil(trackID)

    let user1 = candidate(centerX: 0.50)
    let stranger1 = candidate(centerX: 0.78, width: 0.18)
    let next = tracker.update(candidates: [stranger1, user1])

    XCTAssertEqual(next.trackID, trackID)
    XCTAssertEqual(next.candidate?.boundingBox.center.x, user1.boundingBox.center.x)
    XCTAssertTrue(next.isMetricEligible)
}

func testRejectsAmbiguousCrossing() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2, ambiguityMargin: 0.2))
    let user = candidate(centerX: 0.46)
    _ = tracker.update(candidates: [user])
    let acquired = tracker.update(candidates: [candidate(centerX: 0.47)])
    let id = acquired.trackID

    let crossingA = candidate(centerX: 0.50, poseOffset: 0.005)
    let crossingB = candidate(centerX: 0.51, poseOffset: -0.005)
    let ambiguous = tracker.update(candidates: [crossingB, crossingA])

    XCTAssertEqual(ambiguous.trackID, id)
    XCTAssertTrue(!ambiguous.isMetricEligible)
    XCTAssertEqual(ambiguous.trackingState, .multiplePeople)
    XCTAssertEqual(ambiguous.exclusionReason, .ambiguousSubjects)
}

func testCloseAppearanceKeepsSameTrack() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2))
    let first = candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0.1, 0.2, 0.3]))
    _ = tracker.update(candidates: [first])
    let acquired = tracker.update(candidates: [candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0.11, 0.2, 0.3]))])
    XCTAssertNotNil(acquired.trackID)
    let next = tracker.update(candidates: [candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0.12, 0.2, 0.3]))])
    XCTAssertEqual(next.trackID, acquired.trackID)
    XCTAssertNotEqual(next.exclusionReason, .identityDiscontinuity)
}

func testFarAppearanceRejectsIdentity() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2))
    let first = candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0, 0, 0]))
    _ = tracker.update(candidates: [first])
    let acquired = tracker.update(candidates: [candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0, 0, 0]))])
    XCTAssertNotNil(acquired.trackID)
    let next = tracker.update(candidates: [candidate(centerX: 0.5, appearance: AppearanceSignature(values: [1, 1, 1]))])
    XCTAssertEqual(next.exclusionReason, .identityDiscontinuity)
    XCTAssertFalse(next.isMetricEligible)
}

func testMissingAppearanceUsesGeometryFallback() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2))
    _ = tracker.update(candidates: [candidate(centerX: 0.5, appearance: AppearanceSignature(values: [0, 0, 0]))])
    let acquired = tracker.update(candidates: [candidate(centerX: 0.5)])
    XCTAssertNotNil(acquired.trackID)
    let next = tracker.update(candidates: [candidate(centerX: 0.51)])
    XCTAssertEqual(next.trackID, acquired.trackID)
}

func testDoesNotColdSwitchToDistantPerson() {
    var tracker = PrimarySubjectTracker(configuration: .init(acquisitionFrames: 2, maximumHoldFrames: 2))
    _ = tracker.update(candidates: [candidate(centerX: 0.35)])
    let acquired = tracker.update(candidates: [candidate(centerX: 0.36)])
    let id = acquired.trackID

    for _ in 0..<8 {
        let result = tracker.update(candidates: [candidate(centerX: 0.88, width: 0.16)])
        XCTAssertEqual(result.trackID, id)
        XCTAssertTrue(!result.isMetricEligible)
        XCTAssertEqual(result.exclusionReason, .identityDiscontinuity)
    }
}

private func frame(
    samples: [PoseSample],
    rect: NormalizedPoseRect,
    id: UUID,
    time: TimeInterval,
    eligible: Bool = true,
    reason: PoseMetricExclusionReason = .none
) -> PoseFrame {
    PoseFrame(
        samples: samples,
        boundingBox: rect,
        trackID: id,
        capturedAt: time,
        trackingState: .stable,
        isMetricEligible: eligible,
        exclusionReason: reason
    )
}

func testClipsIdentityLikeIntensitySpike() {
    let config = MotionIntensityConfiguration(warmupFrames: 0, robustWindowSize: 15, maximumIntensity: 0.8)
    var estimator = MotionIntensityEstimator(configuration: config)
    let id = UUID()
    var time: TimeInterval = 0
    let base = candidate(centerX: 0.5)
    _ = estimator.update(frame: frame(samples: base.samples, rect: base.boundingBox, id: id, time: time))

    var regular: MotionMetrics = .invalid(.warmup)
    for step in 1...12 {
        time += 1.0 / 30
        let current = candidate(centerX: 0.5 + Double(step) * 0.0008)
        regular = estimator.update(frame: frame(samples: current.samples, rect: current.boundingBox, id: id, time: time))
    }
    XCTAssertTrue(regular.isValid)

    time += 1.0 / 30
    let jumped = candidate(centerX: 0.72)
    let spike = estimator.update(frame: frame(samples: jumped.samples, rect: jumped.boundingBox, id: id, time: time))

    XCTAssertTrue(spike.isValid)
    XCTAssertTrue(spike.intensity <= 0.8)
    XCTAssertTrue(spike.intensity < 0.5)
}

func testResetsIntensityOnTrackChange() {
    var estimator = MotionIntensityEstimator(configuration: .init(warmupFrames: 0))
    let first = candidate(centerX: 0.3)
    let second = candidate(centerX: 0.8)
    let id1 = UUID()
    let id2 = UUID()

    _ = estimator.update(frame: frame(samples: first.samples, rect: first.boundingBox, id: id1, time: 0))
    let changed = estimator.update(frame: frame(samples: second.samples, rect: second.boundingBox, id: id2, time: 1.0 / 30))

    XCTAssertTrue(!changed.isValid)
    XCTAssertEqual(changed.intensity, 0)
    XCTAssertEqual(changed.exclusionReason, .identityDiscontinuity)
}

func testRejectsPreparationBurst() throws {
    let configuration = ActivitySegmentationConfiguration(
        enterVelocity: 0.55,
        exitVelocity: 0.25,
        enterMovingFraction: 0.55,
        exitMovingFraction: 0.25,
        enterBoundingBoxMotion: 0.55,
        exitBoundingBoxMotion: 0.25,
        minimumActiveDuration: 1.5,
        minimumRestDuration: 1.0,
        shortTrackingGapDuration: 1.0,
        enterConfirmationDuration: 0.6,
        exitConfirmationDuration: 0.6
    )
    let segmenter = ActivitySegmenter(configuration: configuration)
    let windows = [
        ActivityWindow(duration: 1, normalizedJointVelocity: 0.1, movingJointFraction: 0.1, boundingBoxMotion: 0, trackingAvailable: true),
        ActivityWindow(duration: 0.35, normalizedJointVelocity: 0.9, movingJointFraction: 0.8, boundingBoxMotion: 0.8, trackingAvailable: true),
        ActivityWindow(duration: 1, normalizedJointVelocity: 0.1, movingJointFraction: 0.1, boundingBoxMotion: 0, trackingAvailable: true),
    ]

    let summary = try segmenter.segment(windows)
    XCTAssertEqual(summary.setCount, 0)
    XCTAssertEqual(summary.activeTime, 0)
}

func testWholeBodyTranslationDoesNotBecomeExerciseIntensity() {
    var estimator = MotionIntensityEstimator(configuration: .init(warmupFrames: 0, maximumIntensity: 0.92))
    let id = UUID()
    let first = candidate(centerX: 0.35)
    _ = estimator.update(frame: frame(samples: first.samples, rect: first.boundingBox, id: id, time: 0))

    let translated = candidate(centerX: 0.37)
    let metrics = estimator.update(
        frame: frame(samples: translated.samples, rect: translated.boundingBox, id: id, time: 1.0 / 30)
    )

    XCTAssertTrue(metrics.isValid)
    XCTAssertLessThan(metrics.normalizedJointVelocity, 0.05)
    XCTAssertLessThan(metrics.intensity, 0.12)
}

func testBoxMotionAloneCannotStartCameraActivity() throws {
    let configuration = ActivitySegmentationConfiguration(
        enterVelocity: 0.4,
        exitVelocity: 0.15,
        enterMovingFraction: 0.4,
        exitMovingFraction: 0.15,
        enterBoundingBoxMotion: 0.3,
        exitBoundingBoxMotion: 0.15,
        minimumActiveDuration: 1.0,
        minimumRestDuration: 0.5,
        shortTrackingGapDuration: 1.0,
        enterConfirmationDuration: 0.5,
        exitConfirmationDuration: 0.5,
        boundingBoxCanEnterActivity: false
    )
    let windows = [
        ActivityWindow(duration: 1.0, normalizedJointVelocity: 0.02, movingJointFraction: 0.02, boundingBoxMotion: 0.9, trackingAvailable: true),
        ActivityWindow(duration: 1.0, normalizedJointVelocity: 0.02, movingJointFraction: 0.02, boundingBoxMotion: 0.9, trackingAvailable: true),
    ]

    let summary = try ActivitySegmenter(configuration: configuration).segment(windows)
    XCTAssertEqual(summary.setCount, 0)
    XCTAssertEqual(summary.activeTime, 0)
}

}
