import AthleteSensors
import AthleteStore
import Foundation
import Testing

@Test("Поток активности закрывает компактную session evidence в AthleteStore")
func persistsSessionEvidenceFromActivityStream() async throws {
    let store = try AthleteStore.inMemory()
    let interval = DateInterval(
        start: Date(timeIntervalSince1970: 1_000),
        duration: 6
    )
    let summary = try ActivitySegmenter(configuration: .test).segment([
        .tracked(duration: 2, velocity: 0.8, movingFraction: 0.7),
        .tracked(duration: 2, velocity: 0.1, movingFraction: 0.1),
        .tracked(duration: 2, velocity: 0.8, movingFraction: 0.7),
    ])

    let session = SessionEvidenceBuilder().make(interval: interval, summary: summary)
    let envelope = try session.envelope(ingestedAt: interval.end)

    try await store.appendEvidence(envelope, payload: session)

    #expect(try await store.evidence(id: envelope.id) == envelope)
    #expect(try await store.payload(for: envelope.id, as: SessionEvidence.self) == session)
    #expect(session.setCount == 2)
    #expect(session.trackingCoverage == 1)
}

@Test("Debrief сохраняет только явные user-reported значения")
func extractsExplicitNarrativeClaims() throws {
    let narrative = try UserNarrativeBuilder().make(
        text: "Присед 100 кг на 5, RPE 8.",
        sessionEvidenceID: UUID()
    )

    #expect(narrative.claims.map(\.kind) == [.exercise, .loadKilograms, .repetitions, .rpe])
    #expect(narrative.clarificationQuestion == nil)
}

@Test("Пустой debrief не создаёт evidence")
func rejectsEmptyNarrative() {
    #expect(throws: UserNarrativeError.emptyText) {
        try UserNarrativeBuilder().make(text: "  \n ", sessionEvidenceID: UUID())
    }
}

@Test("Неоднозначный debrief не превращается в подтверждённый факт")
func leavesAmbiguousNarrativeUnresolved() throws {
    let narrative = try UserNarrativeBuilder().make(text: "100 на 5", sessionEvidenceID: UUID())

    #expect(narrative.claims.isEmpty)
    #expect(narrative.clarificationQuestion == "К какому упражнению и весу относились 100 на 5?")
}

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

@Test("1.2 секунды подготовки не становятся активным блоком")
func rejectsLongPreparation() throws {
    let summary = try ActivitySegmenter(configuration: .test).segment(
        Array(repeating: ActivityWindow(duration: 0.2, normalizedJointVelocity: 0.8, movingJointFraction: 0.8, boundingBoxMotion: 0, trackingAvailable: true), count: 6)
        + Array(repeating: ActivityWindow(duration: 0.4, normalizedJointVelocity: 0.1, movingJointFraction: 0.1, boundingBoxMotion: 0, trackingAvailable: true), count: 5)
    )
    #expect(summary.setCount == 0)
}

@Test("2.5 секунды устойчивой артикуляции становятся одним активным блоком")
func acceptsSustainedActivity() throws {
    let summary = try ActivitySegmenter(configuration: .test).segment(
        Array(repeating: ActivityWindow(duration: 0.5, normalizedJointVelocity: 0.8, movingJointFraction: 0.8, boundingBoxMotion: 0, trackingAvailable: true), count: 5)
        + Array(repeating: ActivityWindow(duration: 0.5, normalizedJointVelocity: 0.1, movingJointFraction: 0.1, boundingBoxMotion: 0, trackingAvailable: true), count: 4)
    )
    #expect(summary.setCount == 1)
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
