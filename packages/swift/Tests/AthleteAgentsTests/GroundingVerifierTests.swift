import AthleteAgents
import AthleteCore
import Foundation
import Testing

private let evidenceID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
private let artifactID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!

@Test("Verifier принимает документ с существующими доказательствами")
func acceptsGroundedDocument() {
    let document = makeDocument(
        markdown: "Выполнено 4 подхода [calc:\(artifactID.uuidString)]. Сессия сохранена [ev:\(evidenceID.uuidString)]."
    )

    let report = GroundingVerifier().verify(
        document: document,
        evidenceIDs: [evidenceID],
        artifactIDs: [artifactID],
        staleArtifactIDs: []
    )

    #expect(report.status == .verified)
    #expect(report.issues.isEmpty)
}

@Test("Verifier отклоняет отсутствующую evidence-ссылку")
func rejectsMissingEvidence() {
    let document = makeDocument(markdown: "Сессия сохранена [ev:\(evidenceID.uuidString)].")

    let report = GroundingVerifier().verify(
        document: document,
        evidenceIDs: [],
        artifactIDs: [],
        staleArtifactIDs: []
    )

    #expect(report.status == .rejected)
    #expect(report.issues == [.missingEvidence(evidenceID)])
}

@Test("Verifier отклоняет точное число без artifact")
func rejectsUngroundedNumber() {
    let document = makeDocument(markdown: "Выполнено 4 рабочих подхода.")

    let report = GroundingVerifier().verify(
        document: document,
        evidenceIDs: [],
        artifactIDs: [],
        staleArtifactIDs: []
    )

    #expect(report.status == .rejected)
    #expect(report.issues == [.exactNumberWithoutArtifact(line: 1)])
}

@Test("Verifier помечает документ со stale artifact")
func marksStaleArtifact() {
    let document = makeDocument(markdown: "Выполнено 4 подхода [calc:\(artifactID.uuidString)].")

    let report = GroundingVerifier().verify(
        document: document,
        evidenceIDs: [],
        artifactIDs: [artifactID],
        staleArtifactIDs: [artifactID]
    )

    #expect(report.status == .stale)
    #expect(report.issues == [.staleArtifact(artifactID)])
}

private func makeDocument(markdown: String) -> MemoryDocument {
    MemoryDocument(
        id: UUID(),
        kind: .weekly,
        scope: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 604_800),
        revision: 1,
        createdAt: Date(timeIntervalSince1970: 604_800),
        supersedes: nil,
        basedOn: [],
        modelID: "mock",
        providerID: "mock",
        promptVersion: "state-builder-v1",
        inputDigest: "sha256:input",
        verificationStatus: .needsReview,
        markdown: markdown
    )
}
