import AthleteCore
import AthleteStore
import Foundation

public struct SessionMemoryBuilder: Sendable {
    private let store: AthleteStore
    private let provider: any LLMProvider

    public init(store: AthleteStore, provider: any LLMProvider) {
        self.store = store
        self.provider = provider
    }

    public func build(for evidenceID: UUID) async throws -> MemoryDocument {
        guard let evidence = try await store.evidence(id: evidenceID) else {
            throw SessionMemoryBuilderError.evidenceNotFound(evidenceID)
        }
        let document = try await StateBuilderAgent(provider: provider).build(StateBuilderInput(
            kind: .session,
            scope: DateInterval(start: evidence.observedFrom, end: evidence.observedTo),
            revision: 1,
            supersedes: nil,
            evidenceIDs: [evidence.id],
            artifactIDs: [],
            staleArtifactIDs: [],
            inputDigest: evidence.contentDigest,
            context: """
            Данные сессии доступны локально.
            Evidence: [ev:\(evidence.id.uuidString)]
            Источник: \(evidence.moduleID) \(evidence.moduleVersion)
            Интервал: \(evidence.observedFrom.timeIntervalSince1970)-\(evidence.observedTo.timeIntervalSince1970)
            """,
            promptVersion: "state-builder-v1"
        ))
        try await store.saveMemory(document)
        return document
    }
}

public enum SessionMemoryBuilderError: Error, Equatable, Sendable {
    case evidenceNotFound(UUID)
}
