import AthleteCore
import CryptoKit
import Foundation

public struct SessionActivitySegment: Codable, Equatable, Sendable {
    public let state: ActivitySegmentState
    public let startOffset: TimeInterval
    public let endOffset: TimeInterval

    public init(state: ActivitySegmentState, startOffset: TimeInterval, endOffset: TimeInterval) {
        self.state = state
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct SessionEvidence: Codable, Equatable, Sendable {
    public let observedFrom: Date
    public let observedTo: Date
    public let trackingCoverage: Double
    public let activeTime: TimeInterval
    public let restTime: TimeInterval
    public let trackingGapTime: TimeInterval
    public let setCount: Int
    public let segments: [SessionActivitySegment]
    public let algorithmVersion: String

    public func envelope(id: UUID = UUID(), ingestedAt: Date = Date()) throws -> EvidenceEnvelope {
        let payload = try JSONEncoder().encode(self)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return EvidenceEnvelope(
            id: id,
            moduleID: "org.baseline.activity",
            moduleVersion: algorithmVersion,
            kind: "activity.session.v1",
            observedFrom: observedFrom,
            observedTo: observedTo,
            ingestedAt: ingestedAt,
            epistemicRole: .computed,
            provenance: Provenance(
                sourceID: "vision-body-pose",
                producerID: "activity-segmentation",
                producerVersion: algorithmVersion,
                method: "active-rest-set-segmentation"
            ),
            privacyClass: .sensitiveLocal,
            payload: PayloadReference(
                mediaType: "application/json",
                schemaID: "activity.session",
                schemaVersion: "1",
                storageURI: "baseline://evidence/\(id.uuidString)"
            ),
            derivedFrom: [],
            supersedes: nil,
            contentDigest: "sha256:\(digest)"
        )
    }
}

public struct SessionCaptureQuality: Codable, Equatable, Sendable {
    public let ambiguousFrameCount: Int; public let identityDiscontinuityCount: Int
    public let warmupFrameCount: Int; public let rejectedMotionFrameCount: Int; public let trackingGapCount: Int
    public init(ambiguousFrameCount: Int = 0, identityDiscontinuityCount: Int = 0, warmupFrameCount: Int = 0, rejectedMotionFrameCount: Int = 0, trackingGapCount: Int = 0) {
        self.ambiguousFrameCount = ambiguousFrameCount; self.identityDiscontinuityCount = identityDiscontinuityCount; self.warmupFrameCount = warmupFrameCount; self.rejectedMotionFrameCount = rejectedMotionFrameCount; self.trackingGapCount = trackingGapCount
    }
}

public struct SessionEvidenceV2: Codable, Equatable, Sendable {
    public let observedFrom: Date; public let observedTo: Date; public let trackingCoverage: Double
    public let activeTime: TimeInterval; public let restTime: TimeInterval; public let trackingGapTime: TimeInterval
    public let activeBlockCount: Int; public let confirmedSetCount: Int?; public let segments: [SessionActivitySegment]
    public let captureQuality: SessionCaptureQuality; public let algorithmVersion: String
    public init(observedFrom: Date, observedTo: Date, trackingCoverage: Double, activeTime: TimeInterval, restTime: TimeInterval, trackingGapTime: TimeInterval, activeBlockCount: Int, confirmedSetCount: Int? = nil, segments: [SessionActivitySegment], captureQuality: SessionCaptureQuality, algorithmVersion: String) {
        self.observedFrom = observedFrom; self.observedTo = observedTo; self.trackingCoverage = trackingCoverage; self.activeTime = activeTime; self.restTime = restTime; self.trackingGapTime = trackingGapTime; self.activeBlockCount = activeBlockCount; self.confirmedSetCount = confirmedSetCount; self.segments = segments; self.captureQuality = captureQuality; self.algorithmVersion = algorithmVersion
    }
    public func envelope(id: UUID = UUID(), ingestedAt: Date = Date()) throws -> EvidenceEnvelope {
        let data = try JSONEncoder().encode(self); let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return EvidenceEnvelope(id: id, moduleID: "org.baseline.activity", moduleVersion: algorithmVersion, kind: "activity.session.v2", observedFrom: observedFrom, observedTo: observedTo, ingestedAt: ingestedAt, epistemicRole: .computed, provenance: Provenance(sourceID: "vision-body-pose", producerID: "activity-segmentation", producerVersion: algorithmVersion, method: "robust-active-rest-segmentation"), privacyClass: .sensitiveLocal, payload: PayloadReference(mediaType: "application/json", schemaID: "activity.session", schemaVersion: "2", storageURI: "baseline://evidence/\(id.uuidString)"), derivedFrom: [], supersedes: nil, contentDigest: "sha256:\(digest)")
    }
}

public struct SessionEvidenceBuilder: Sendable {
    public let algorithmVersion: String

    public init(algorithmVersion: String = "activity-segmentation-v1") {
        self.algorithmVersion = algorithmVersion
    }

    public func make(interval: DateInterval, summary: ActivitySummary) -> SessionEvidence {
        SessionEvidence(
            observedFrom: interval.start,
            observedTo: interval.end,
            trackingCoverage: summary.coverage,
            activeTime: summary.activeTime,
            restTime: summary.restTime,
            trackingGapTime: summary.trackingGapTime,
            setCount: summary.setCount,
            segments: summary.segments.map {
                SessionActivitySegment(state: $0.state, startOffset: $0.start, endOffset: $0.end)
            },
            algorithmVersion: algorithmVersion
        )
    }
}
