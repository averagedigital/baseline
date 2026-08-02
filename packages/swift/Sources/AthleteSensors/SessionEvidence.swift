import AthleteCore
import CryptoKit
import Foundation

public struct SessionActivitySegment: Codable, Equatable, Sendable {
    public let state: ActivitySegmentState
    public let startOffset: TimeInterval
    public let endOffset: TimeInterval
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
