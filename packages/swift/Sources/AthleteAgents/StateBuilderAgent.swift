import AthleteCore
import Foundation

public struct StateBuilderInput: Sendable {
    public let kind: MemoryKind
    public let scope: DateInterval
    public let revision: Int
    public let supersedes: UUID?
    public let evidenceIDs: [UUID]
    public let artifactIDs: [UUID]
    public let staleArtifactIDs: Set<UUID>
    public let inputDigest: String
    public let context: String
    public let promptVersion: String

    public init(
        kind: MemoryKind,
        scope: DateInterval,
        revision: Int,
        supersedes: UUID?,
        evidenceIDs: [UUID],
        artifactIDs: [UUID],
        staleArtifactIDs: Set<UUID>,
        inputDigest: String,
        context: String,
        promptVersion: String
    ) {
        self.kind = kind
        self.scope = scope
        self.revision = revision
        self.supersedes = supersedes
        self.evidenceIDs = evidenceIDs
        self.artifactIDs = artifactIDs
        self.staleArtifactIDs = staleArtifactIDs
        self.inputDigest = inputDigest
        self.context = context
        self.promptVersion = promptVersion
    }
}

public struct StateBuilderAgent: Sendable {
    private let provider: any LLMProvider
    private let verifier: GroundingVerifier

    public init(provider: any LLMProvider, verifier: GroundingVerifier = GroundingVerifier()) {
        self.provider = provider
        self.verifier = verifier
    }

    public func build(_ input: StateBuilderInput) async throws -> MemoryDocument {
        let response = try await provider.complete(AgentRequest(
            role: .stateBuilder,
            promptVersion: input.promptVersion,
            context: input.context
        ))
        let dependencies = input.evidenceIDs.map(MemoryDependency.evidence)
            + input.artifactIDs.map(MemoryDependency.artifact)
        let draft = MemoryDocument(
            id: UUID(),
            kind: input.kind,
            scope: input.scope,
            revision: input.revision,
            createdAt: Date(),
            supersedes: input.supersedes,
            basedOn: dependencies,
            modelID: response.modelID,
            providerID: response.providerID,
            promptVersion: input.promptVersion,
            inputDigest: input.inputDigest,
            verificationStatus: .needsReview,
            markdown: response.text
        )
        let report = verifier.verify(
            document: draft,
            evidenceIDs: Set(input.evidenceIDs),
            artifactIDs: Set(input.artifactIDs),
            staleArtifactIDs: input.staleArtifactIDs
        )
        guard report.status == .verified else {
            throw StateBuilderError.verificationFailed(report.issues)
        }
        return draft.withVerificationStatus(.verified)
    }
}

public enum StateBuilderError: Error, Equatable, Sendable {
    case verificationFailed([GroundingIssue])
}

private extension MemoryDocument {
    func withVerificationStatus(_ status: VerificationStatus) -> MemoryDocument {
        MemoryDocument(
            id: id,
            kind: kind,
            scope: scope,
            revision: revision,
            createdAt: createdAt,
            supersedes: supersedes,
            basedOn: basedOn,
            modelID: modelID,
            providerID: providerID,
            promptVersion: promptVersion,
            inputDigest: inputDigest,
            verificationStatus: status,
            markdown: markdown
        )
    }
}
