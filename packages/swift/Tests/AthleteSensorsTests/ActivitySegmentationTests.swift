import AthleteSensors
import Foundation
import Testing

@Test("Activity segmentation выделяет подход с hysteresis")
func segmentsSetWithHysteresis() throws {
    let segmenter = ActivitySegmenter(configuration: .test)
    let summary = try segmenter.segment([
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
        .tracked(duration: 1, velocity: 0.5, movingFraction: 0.5),
        .tracked(duration: 1, velocity: 0.4, movingFraction: 0.4),
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
    ])

    #expect(summary.segments == [
        ActivitySegment(state: .rest, start: 0, end: 2),
        ActivitySegment(state: .active, start: 2, end: 5),
        ActivitySegment(state: .rest, start: 5, end: 7),
    ])
    #expect(summary.activeTime == 3)
    #expect(summary.restTime == 4)
    #expect(summary.setCount == 1)
    #expect(summary.coverage == 1)
}

@Test("Короткий tracking gap не делит один подход")
func mergesSetAcrossShortTrackingGap() throws {
    let segmenter = ActivitySegmenter(configuration: .test)
    let summary = try segmenter.segment([
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
        .gap(duration: 1),
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
    ])

    #expect(summary.segments == [
        ActivitySegment(state: .active, start: 0, end: 2),
        ActivitySegment(state: .trackingGap, start: 2, end: 3),
        ActivitySegment(state: .active, start: 3, end: 5),
    ])
    #expect(summary.setCount == 1)
    #expect(summary.trackingGapTime == 1)
    #expect(summary.coverage == 0.8)
}

@Test("Короткое движение не становится подходом")
func rejectsShortActivity() throws {
    let segmenter = ActivitySegmenter(configuration: .test)
    let summary = try segmenter.segment([
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
        .tracked(duration: 1, velocity: 0.8, movingFraction: 0.7),
        .tracked(duration: 1, velocity: 0.1, movingFraction: 0.1),
    ])

    #expect(summary.segments == [ActivitySegment(state: .rest, start: 0, end: 3)])
    #expect(summary.setCount == 0)
}

private extension ActivitySegmentationConfiguration {
    static let test = ActivitySegmentationConfiguration(
        enterVelocity: 0.6,
        exitVelocity: 0.3,
        enterMovingFraction: 0.6,
        exitMovingFraction: 0.3,
        enterBoundingBoxMotion: 0.6,
        exitBoundingBoxMotion: 0.3,
        minimumActiveDuration: 2,
        minimumRestDuration: 2,
        shortTrackingGapDuration: 1
    )
}

private extension ActivityWindow {
    static func tracked(
        duration: TimeInterval,
        velocity: Double,
        movingFraction: Double
    ) -> ActivityWindow {
        ActivityWindow(
            duration: duration,
            normalizedJointVelocity: velocity,
            movingJointFraction: movingFraction,
            boundingBoxMotion: 0,
            trackingAvailable: true
        )
    }

    static func gap(duration: TimeInterval) -> ActivityWindow {
        ActivityWindow(
            duration: duration,
            normalizedJointVelocity: 0,
            movingJointFraction: 0,
            boundingBoxMotion: 0,
            trackingAvailable: false
        )
    }
}
