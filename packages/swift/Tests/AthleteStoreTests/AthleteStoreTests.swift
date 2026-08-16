import AthleteCore
import AthleteSensors
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
    let firstThread = try #require(try await store.chatThreads().first)
    #expect(firstThread.lastMessage == "Темп был ровным.")
    #expect(firstThread.messageCount == 2)
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

@Test("File-backed store восстанавливает state, exposure, food и chat после restart")
func fileBackedRestartRestoresLocalState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("db.sqlite").path
    defer { try? FileManager.default.removeItem(at: directory) }

    let threadID: UUID
    let exposureID = UUID()
    let foodID = UUID()
    do {
        let store = try AthleteStore(path: path)
        let thread = try await store.createChat(title: "Restart")
        threadID = thread.id
        try await store.appendChatMessage(ChatHistoryMessage(threadID: thread.id, role: .user, text: "Сохранись"))
        try await store.savePersonalizationState("state-v1", at: Date(timeIntervalSince1970: 10))
        try await store.saveRecommendationExposure(StoredRecommendationExposure(id: exposureID, payload: Data("exposure".utf8), createdAt: Date(timeIntervalSince1970: 11)))
        try await store.saveFoodObservation(StoredFoodObservation(id: foodID, payload: Data("food".utf8), capturedAt: Date(timeIntervalSince1970: 12)))
    }

    let store = try AthleteStore(path: path)
    #expect(try await store.loadPersonalizationState(as: String.self) == "state-v1")
    #expect(try await store.recommendationExposure(id: exposureID)?.payload == Data("exposure".utf8))
    #expect(try await store.recentFoodObservations(limit: 1).first?.id == foodID)
    #expect(try await store.chatMessages(threadID: threadID).map(\.text) == ["Сохранись"])
}

@Test("RPE idempotency keeps one feedback event and one session-derived evidence")
func sessionRPEIsIdempotent() async throws {
    let store = try AthleteStore.inMemory()
    let sessionID = UUID()
    let session = makeEvidence(id: sessionID)
    try await store.appendEvidence(session)
    let eventID = UUID()
    let rpe = SessionRPEEvidence(sessionEvidenceID: sessionID, rpe: 8, note: "Тяжело")
    let narrativeID = UUID()
    let narrativeEnvelope = try rpe.envelope(id: narrativeID, ingestedAt: Date(timeIntervalSince1970: 10))
    let payload = try JSONEncoder().encode(rpe)

    let first = try await store.applySessionRPE(
        eventID: eventID,
        sourceEvidenceID: sessionID,
        feedbackPayload: payload,
        createdAt: Date(timeIntervalSince1970: 10),
        statePayload: Data("state-1".utf8),
        narrativeEnvelope: narrativeEnvelope,
        narrativePayload: payload
    )
    let second = try await store.applySessionRPE(
        eventID: eventID,
        sourceEvidenceID: sessionID,
        feedbackPayload: payload,
        createdAt: Date(timeIntervalSince1970: 11),
        statePayload: Data("state-2".utf8),
        narrativeEnvelope: narrativeEnvelope,
        narrativePayload: payload
    )

    #expect(first)
    #expect(!second)
    #expect(try await store.hasFeedbackEvent(id: eventID))
    #expect(try await store.evidence(id: narrativeID)?.derivedFrom == [sessionID])
    #expect(try await store.payload(for: narrativeID, as: SessionRPEEvidence.self) == rpe)
}

@Test("Reward snapshot is idempotent and preserves the first reward")
func recommendationRewardIsIdempotent() async throws {
    let store = try AthleteStore.inMemory()
    let exposureID = UUID()
    try await store.saveRecommendationExposure(
        StoredRecommendationExposure(id: exposureID, payload: Data("feature-vector-A".utf8), createdAt: Date(timeIntervalSince1970: 10))
    )
    let firstEventID = UUID()
    let secondEventID = UUID()

    let first = try await store.applyRecommendationReward(
        exposureID: exposureID,
        reward: 1,
        feedbackEventID: firstEventID,
        feedbackPayload: Data("reward-1".utf8),
        createdAt: Date(timeIntervalSince1970: 11),
        statePayload: Data("bandit-from-A".utf8)
    )
    let second = try await store.applyRecommendationReward(
        exposureID: exposureID,
        reward: -1,
        feedbackEventID: secondEventID,
        feedbackPayload: Data("reward-2".utf8),
        createdAt: Date(timeIntervalSince1970: 12),
        statePayload: Data("bandit-from-other".utf8)
    )

    #expect(first)
    #expect(!second)
    #expect(try await store.recommendationExposure(id: exposureID)?.reward == 1)
    #expect(try await store.hasFeedbackEvent(id: firstEventID))
    #expect(!(try await store.hasFeedbackEvent(id: secondEventID)))
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
