import Foundation
import Testing
@testable import AthleteCore

@Test("MemoryDocument хранит свободный Markdown и зависимости")
func memoryDocumentKeepsMarkdownAndDependencies() {
    let evidenceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let artifactID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let document = MemoryDocument(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        kind: .weekly,
        scope: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 604_800),
        revision: 1,
        createdAt: Date(timeIntervalSince1970: 604_800),
        supersedes: nil,
        basedOn: [.evidence(evidenceID), .artifact(artifactID)],
        modelID: "mock",
        providerID: "mock",
        promptVersion: "state-builder-v1",
        inputDigest: "sha256:input",
        verificationStatus: .verified,
        markdown: "# Что изменилось\n\nВыполнено 4 подхода [calc:\(artifactID.uuidString)]."
    )

    #expect(document.markdown.hasPrefix("# Что изменилось"))
    #expect(document.basedOn == [.evidence(evidenceID), .artifact(artifactID)])
    #expect(document.verificationStatus == .verified)
}
