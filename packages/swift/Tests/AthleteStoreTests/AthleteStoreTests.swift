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
        "provider_configurations", "chat_threads", "chat_messages", "memory_search",
    ]))
}

@Test("История возвращает диалоги по последней активности и сообщения по порядку")
func storesChatHistory() async throws {
    let store = try AthleteStore.inMemory()
    let first = try await store.createChat(title: "Первая тренировка", at: Date(timeIntervalSince1970: 100))
    let second = try await store.createChat(title: "Вторая тренировка", at: Date(timeIntervalSince1970: 200))

    try await store.appendChatMessage(
        ChatHistoryMessage(threadID: first.id, role: .user, text: "Как прошёл подход?", createdAt: Date(timeIntervalSince1970: 300))
    )
    try await store.appendChatMessage(
        ChatHistoryMessage(threadID: first.id, role: .assistant, text: "Темп был ровным.", createdAt: Date(timeIntervalSince1970: 301))
    )

    #expect(try await store.chatThreads().map(\.id) == [first.id, second.id])
    let messages = try await store.chatMessages(threadID: first.id)
    #expect(messages.map(\.role) == [.user, .assistant])
    #expect(messages.map(\.text) == ["Как прошёл подход?", "Темп был ровным."])
}

@Test("Удаление диалога удаляет его сообщения")
func deletesChatHistory() async throws {
    let store = try AthleteStore.inMemory()
    let thread = try await store.createChat(title: "Техника", at: Date(timeIntervalSince1970: 100))
    try await store.appendChatMessage(
        ChatHistoryMessage(threadID: thread.id, role: .user, text: "Проверь технику", createdAt: Date(timeIntervalSince1970: 101))
    )

    try await store.deleteChat(id: thread.id)

    #expect(try await store.chatThreads().isEmpty)
    #expect(try await store.chatMessages(threadID: thread.id).isEmpty)
}

@Test("Выбранным может быть только один Responses API провайдер")
func selectsSingleProvider() async throws {
    let store = try AthleteStore.inMemory()
    let openAI = ProviderConfiguration(
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        model: "gpt-5.6",
        isSelected: true
    )
    let relay = ProviderConfiguration(
        name: "Relay",
        baseURL: "https://llm.example.com/v1",
        model: "gpt-5.6-terra"
    )

    try await store.saveProviderConfiguration(openAI)
    try await store.saveProviderConfiguration(relay)
    try await store.selectProvider(id: relay.id)

    let configurations = try await store.providerConfigurations()
    #expect(configurations.first(where: { $0.id == openAI.id })?.isSelected == false)
    #expect(configurations.first(where: { $0.id == relay.id })?.isSelected == true)
    #expect(try await store.selectedProviderConfiguration()?.id == relay.id)
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
