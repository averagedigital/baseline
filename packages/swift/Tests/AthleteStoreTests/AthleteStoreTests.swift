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

@Test("Chat attachments support image-only messages and survive restart")
func chatAttachmentsSurviveRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databasePath = directory.appendingPathComponent("db.sqlite").path
    let imageURL = directory.appendingPathComponent("meal.jpg")
    try Data([1, 2, 3]).write(to: imageURL)
    defer { try? FileManager.default.removeItem(at: directory) }

    let threadID: UUID
    do {
        let store = try AthleteStore(path: databasePath)
        let thread = try await store.createChat(title: "Обед")
        threadID = thread.id
        let messageID = UUID()
        let attachments = [
            ChatAttachment(messageID: messageID, localPath: imageURL.path, mimeType: "image/jpeg", width: 1200, height: 800, byteSize: 3),
            ChatAttachment(messageID: messageID, localPath: imageURL.path + ".second", mimeType: "image/jpeg", width: 800, height: 1200, byteSize: 4),
        ]
        let citation = ChatCitation(messageID: messageID, title: "Источник", url: try #require(URL(string: "https://example.com/food")))
        try await store.appendChatMessage(ChatHistoryMessage(id: messageID, threadID: thread.id, role: .user, text: "", attachments: attachments, citations: [citation]))
    }

    let restored = try AthleteStore(path: databasePath)
    let message = try #require(try await restored.chatMessages(threadID: threadID).first)
    #expect(message.text.isEmpty)
    #expect(message.attachments.count == 2)
    #expect(message.attachments.first?.width == 1200)
    #expect(message.citations.first?.url.absoluteString == "https://example.com/food")
    #expect(try await restored.chatThread(containingMessageID: message.id)?.id == threadID)
}

@Test("Named personalization states survive restart and reset together")
func namedPersonalizationStatePersistsAndResets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("state.sqlite").path
    try await AthleteStore(path: path).savePersonalizationState(["samples": 3], id: "continual-personalization-v1", at: Date())

    let restored = try AthleteStore(path: path)
    #expect(try await restored.loadPersonalizationState(id: "continual-personalization-v1", as: [String: Int].self) == ["samples": 3])
    try await restored.clearPersonalizationState()
    #expect(try await restored.loadPersonalizationState(id: "continual-personalization-v1", as: [String: Int].self) == nil)
}

@Test("Deleting a chat removes attachment files")
func deletingChatRemovesAttachmentFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("photo.jpg")
    let transport = directory.appendingPathComponent("photo-transport.jpg")
    try Data([1]).write(to: file)
    try Data([2]).write(to: transport)
    let store = try AthleteStore.inMemory()
    let thread = try await store.createChat(title: "Фото")
    let messageID = UUID()
    try await store.appendChatMessage(ChatHistoryMessage(
        id: messageID,
        threadID: thread.id,
        role: .user,
        text: "Фото",
        attachments: [ChatAttachment(messageID: messageID, localPath: file.path, transportPath: transport.path, mimeType: "image/jpeg", width: 1, height: 1, byteSize: 1)]
    ))

    try await store.deleteChat(id: thread.id)

    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: transport.path))
}

@Test("Food diary tool calls are atomic and idempotent")
func foodDiaryCreateIsAtomicAndIdempotent() async throws {
    let store = try AthleteStore.inMemory()
    let toolCallID = "call-create-1"
    let request = FoodEntryDraft(
        consumedAt: Date(timeIntervalSince1970: 1_000),
        mealType: .lunch,
        items: [FoodItemDraft(name: "Паста", amount: .range(low: 150, high: 220), unit: "g", caloriesKcal: .range(low: 240, high: 360), proteinG: .unknown, fatG: .unknown, carbohydratesG: .range(low: 45, high: 70), provenance: .modelEstimated, confidence: 0.72)],
        notes: "По фотографии"
    )

    let first = try await store.createFoodEntry(request, toolCallID: toolCallID)
    let repeated = try await store.createFoodEntry(request, toolCallID: toolCallID)

    #expect(first == repeated)
    #expect(try await store.foodEntries(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2_000)).count == 1)
    await #expect(throws: (any Error).self) {
        try await store.createFoodEntry(
            FoodEntryDraft(consumedAt: Date(), mealType: .snack, items: [FoodItemDraft(name: "", amount: .unknown, unit: nil, caloriesKcal: .unknown, proteinG: .unknown, fatG: .unknown, carbohydratesG: .unknown, provenance: .modelEstimated, confidence: 0.5)]),
            toolCallID: "invalid"
        )
    }
    #expect(try await store.foodEntries(from: Date(timeIntervalSince1970: 0), to: Date.distantFuture).count == 1)
}

@Test("Food diary supports partial update, read and delete")
func foodDiaryUpdateAndDelete() async throws {
    let store = try AthleteStore.inMemory()
    let created = try await store.createFoodEntry(
        FoodEntryDraft(consumedAt: Date(timeIntervalSince1970: 1_000), mealType: .breakfast, items: [FoodItemDraft(name: "Курица", amount: .exact(180), unit: "g", caloriesKcal: .exact(297), proteinG: .exact(55), fatG: .exact(6), carbohydratesG: .exact(0), provenance: .modelEstimated, confidence: 0.78)]),
        toolCallID: "create"
    )
    let updated = try await store.updateFoodEntry(id: created.id, patch: FoodEntryPatch(notes: "Уточнено пользователем"), toolCallID: "update")
    #expect(updated.notes == "Уточнено пользователем")
    #expect(try await store.foodEntry(id: created.id)?.items.first?.name == "Курица")

    #expect(try await store.deleteFoodEntry(id: created.id, toolCallID: "delete"))
    #expect(try await store.foodEntry(id: created.id) == nil)
    #expect(try await store.deleteFoodEntry(id: created.id, toolCallID: "delete"))
}

@Test("Legacy provider configuration decodes with disabled optional capabilities")
func legacyProviderConfigurationIsBackwardCompatible() throws {
    let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","baseURL":"https://example.invalid/v1","model":"text-only","isSelected":true}"#.utf8)
    let provider = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
    #expect(provider.capabilities == .textOnly)
    #expect(!provider.webSearchEnabled)
    #expect(provider.reasoningEffort == .off)
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
