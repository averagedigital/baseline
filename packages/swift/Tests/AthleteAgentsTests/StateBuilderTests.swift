import AthleteAgents
import AthleteCore
import AthleteStore
import Foundation
import Testing

@Test("ContextCompiler сохраняет coverage и укладывается в budget")
func contextCompilerPrioritizesCoverage() throws {
    let compiler = ContextCompiler()
    let fragments = [
        ContextFragment(
            id: "activity-details",
            moduleID: "org.baseline.activity",
            scope: DateInterval(start: .distantPast, duration: 10),
            purpose: .analysis,
            evidenceIDs: [],
            estimatedTokenCount: 60,
            markdown: "Подробности"
        ),
        ContextFragment(
            id: "activity-coverage",
            moduleID: "org.baseline.activity",
            scope: DateInterval(start: .distantPast, duration: 10),
            purpose: .coverage,
            evidenceIDs: [],
            estimatedTokenCount: 20,
            markdown: "Покрытие"
        ),
        ContextFragment(
            id: "activity-coverage",
            moduleID: "org.baseline.activity",
            scope: DateInterval(start: .distantPast, duration: 10),
            purpose: .coverage,
            evidenceIDs: [],
            estimatedTokenCount: 20,
            markdown: "Дубликат"
        ),
    ]

    let result = try compiler.compile(fragments: fragments, tokenBudget: 50)

    #expect(result.fragments.map(\.id) == ["activity-coverage"])
    #expect(result.estimatedTokenCount == 20)
}

@Test("ContextCompiler не скрывает coverage при недостаточном budget")
func contextCompilerRejectsBudgetBelowCoverage() {
    let fragment = ContextFragment(
        id: "coverage",
        moduleID: "org.baseline.activity",
        scope: DateInterval(start: .distantPast, duration: 10),
        purpose: .coverage,
        evidenceIDs: [],
        estimatedTokenCount: 20,
        markdown: "Покрытие"
    )

    #expect(throws: ContextCompilerError.insufficientCoverageBudget(required: 20, available: 10)) {
        try ContextCompiler().compile(fragments: [fragment], tokenBudget: 10)
    }
}

@Test("State Builder сохраняет только verified memory")
func stateBuilderProducesVerifiedMemory() async throws {
    let evidenceID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    let artifactID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    let provider = MockProvider(
        responses: [AgentResponse(
            text: "Выполнено 4 подхода [calc:\(artifactID.uuidString)]. Сессия учтена [ev:\(evidenceID.uuidString)].",
            providerID: "mock",
            modelID: "mock-state-builder"
        )]
    )
    let agent = StateBuilderAgent(provider: provider)

    let document = try await agent.build(StateBuilderInput(
        kind: .session,
        scope: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 300),
        revision: 1,
        supersedes: nil,
        evidenceIDs: [evidenceID],
        artifactIDs: [artifactID],
        staleArtifactIDs: [],
        inputDigest: "sha256:session",
        context: "Покрытие полное.",
        promptVersion: "state-builder-v1"
    ))

    #expect(document.verificationStatus == .verified)
    #expect(document.basedOn == [.evidence(evidenceID), .artifact(artifactID)])
}

@Test("State Builder отклоняет неподтверждённый числовой вывод")
func stateBuilderRejectsUngroundedOutput() async throws {
    let provider = MockProvider(
        responses: [AgentResponse(text: "Выполнено 4 подхода.", providerID: "mock", modelID: "mock")]
    )
    let agent = StateBuilderAgent(provider: provider)

    await #expect(throws: StateBuilderError.verificationFailed([.exactNumberWithoutArtifact(line: 1)])) {
        try await agent.build(StateBuilderInput(
            kind: .session,
            scope: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 300),
            revision: 1,
            supersedes: nil,
            evidenceIDs: [],
            artifactIDs: [],
            staleArtifactIDs: [],
            inputDigest: "sha256:session",
            context: "Нет числовых artifacts.",
            promptVersion: "state-builder-v1"
        ))
    }
}

@Test("Evidence проходит через State Builder в verified session memory")
func persistsVerifiedSessionMemory() async throws {
    let store = try AthleteStore.inMemory()
    let evidence = EvidenceEnvelope(
        id: UUID(), moduleID: "org.baseline.activity", moduleVersion: "v1", kind: "activity.session.v1",
        observedFrom: Date(timeIntervalSince1970: 100), observedTo: Date(timeIntervalSince1970: 200),
        ingestedAt: Date(timeIntervalSince1970: 200), epistemicRole: .computed,
        provenance: Provenance(sourceID: "test", producerID: "activity", producerVersion: "v1", method: nil),
        privacyClass: .sensitiveLocal,
        payload: PayloadReference(mediaType: "application/json", schemaID: nil, schemaVersion: nil, storageURI: "baseline://test"),
        derivedFrom: [], supersedes: nil, contentDigest: "sha256:test"
    )
    try await store.appendEvidence(evidence)
    let provider = MockProvider(responses: [AgentResponse(
        text: "Сессия сохранена [ev:\(evidence.id.uuidString)].", providerID: "mock", modelID: "mock-state"
    )])

    let document = try await SessionMemoryBuilder(store: store, provider: provider).build(for: evidence.id)

    #expect(document.verificationStatus == .verified)
    #expect(try await store.memory(id: document.id)?.verificationStatus == .verified)
}
