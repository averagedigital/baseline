import Foundation
import Testing
@testable import AthleteCore

@Test("EvidenceEnvelope сохраняет доказательное происхождение")
func evidenceEnvelopeRoundTrip() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let envelope = EvidenceEnvelope(
        id: id,
        moduleID: "org.baseline.strength-load",
        moduleVersion: "0.1.0",
        kind: "strength.set.v1",
        observedFrom: Date(timeIntervalSince1970: 100),
        observedTo: Date(timeIntervalSince1970: 110),
        ingestedAt: Date(timeIntervalSince1970: 120),
        epistemicRole: .userReported,
        provenance: Provenance(
            sourceID: "user-debrief",
            producerID: "strength-load",
            producerVersion: "0.1.0",
            method: "confirmed-text"
        ),
        privacyClass: .sensitiveLocal,
        payload: PayloadReference(
            mediaType: "application/json",
            schemaID: "strength.set",
            schemaVersion: "1",
            storageURI: "baseline://payloads/set-1"
        ),
        derivedFrom: [],
        supersedes: nil,
        contentDigest: "sha256:test"
    )

    let encoded = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(EvidenceEnvelope.self, from: encoded)

    #expect(decoded == envelope)
    #expect(decoded.epistemicRole == .userReported)
    #expect(decoded.provenance.sourceID == "user-debrief")
}

@Test("Исправление создаёт новое событие, не меняя исходное")
func correctionSupersedesOriginalEvidence() {
    let originalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let correction = UserCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        evidenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        supersedes: originalID,
        createdAt: Date(timeIntervalSince1970: 200),
        reason: "Исправлен вес подхода"
    )

    #expect(correction.supersedes == originalID)
    #expect(correction.evidenceID != originalID)
}
