import AthleteCore
import AthleteStore
import Foundation
import GRDB
import Testing

@Test("Evidence ledger сохраняет событие без потери provenance")
func appendsEvidence() async throws {
    let store = try AthleteStore.inMemory()
    let envelope = makeEvidence(id: UUID())

    try await store.appendEvidence(envelope)

    #expect(try await store.evidence(id: envelope.id) == envelope)
}

@Test("Evidence ledger не переписывает существующее событие")
func rejectsDuplicateEvidence() async throws {
    let store = try AthleteStore.inMemory()
    let envelope = makeEvidence(id: UUID())
    try await store.appendEvidence(envelope)

    await #expect(throws: (any Error).self) {
        try await store.appendEvidence(envelope)
    }
    #expect(try await store.evidence(id: envelope.id) == envelope)
}

@Test("Correction делает зависимую память stale")
func correctionInvalidatesMemory() async throws {
    let store = try AthleteStore.inMemory()
    let evidence = makeEvidence(id: UUID())
    let document = makeMemory(evidenceID: evidence.id)
    try await store.appendEvidence(evidence)
    try await store.saveMemory(document)

    try await store.markMemoryStale(dependingOn: evidence.id)

    #expect(try await store.memory(id: document.id)?.verificationStatus == .stale)
}

@Test("Миграция создаёт обязательные таблицы и FTS5")
func createsRequiredTables() async throws {
    let store = try AthleteStore.inMemory()
    let tables = try await store.schemaObjects()

    #expect(tables.isSuperset(of: [
        "module_manifests", "evidence_events", "evidence_derivations",
        "analysis_artifacts", "memory_documents", "memory_claim_index",
        "memory_dependencies", "analysis_jobs", "agent_runs", "user_corrections",
        "goals", "plan_events", "experiment_events", "consent_grants",
        "provider_configurations", "memory_search",
    ]))
}

private func makeEvidence(id: UUID) -> EvidenceEnvelope {
    EvidenceEnvelope(
        id: id,
        moduleID: "org.baseline.activity",
        moduleVersion: "0.1.0",
        kind: "activity.session.v1",
        observedFrom: Date(timeIntervalSince1970: 100),
        observedTo: Date(timeIntervalSince1970: 200),
        ingestedAt: Date(timeIntervalSince1970: 210),
        epistemicRole: .computed,
        provenance: Provenance(
            sourceID: "synthetic-pose",
            producerID: "activity",
            producerVersion: "0.1.0",
            method: "segmentation-v1"
        ),
        privacyClass: .sensitiveLocal,
        payload: PayloadReference(
            mediaType: "application/json",
            schemaID: "activity.session",
            schemaVersion: "1",
            storageURI: "baseline://payloads/\(id.uuidString)"
        ),
        derivedFrom: [],
        supersedes: nil,
        contentDigest: "sha256:\(id.uuidString)"
    )
}

private func makeMemory(evidenceID: UUID) -> MemoryDocument {
    MemoryDocument(
        id: UUID(),
        kind: .session,
        scope: DateInterval(start: Date(timeIntervalSince1970: 100), duration: 100),
        revision: 1,
        createdAt: Date(timeIntervalSince1970: 220),
        supersedes: nil,
        basedOn: [.evidence(evidenceID)],
        modelID: "mock",
        providerID: "mock",
        promptVersion: "state-builder-v1",
        inputDigest: "sha256:input",
        verificationStatus: .verified,
        markdown: "Сессия сохранена [ev:\(evidenceID.uuidString)]."
    )
}
