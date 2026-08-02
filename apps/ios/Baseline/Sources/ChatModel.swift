import AthleteStore
import AthleteSensors
import AthleteAgents
import AthleteCore
import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    enum State: Equatable, Sendable {
        case sent
        case streaming
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        state: State = .sent,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.createdAt = createdAt
    }
}

struct ChatConversation: Equatable, Sendable {
    private(set) var messages: [ChatMessage]

    init(messages: [ChatMessage] = []) {
        self.messages = messages
    }

    init(history: [ChatHistoryMessage]) {
        messages = history.map { message in
            ChatMessage(
                id: message.id,
                role: message.role == .user ? .user : .assistant,
                text: message.text,
                createdAt: message.createdAt
            )
        }
    }

    var isResponding: Bool {
        messages.last?.state == .streaming
    }

    var responsesInput: [ResponsesInputMessage] {
        messages.compactMap { message in
            guard message.state == .sent, !message.text.isEmpty else { return nil }
            return ResponsesInputMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text
            )
        }
    }

    mutating func startUserTurn(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return false }
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", state: .streaming))
        return true
    }

    mutating func appendAssistantDelta(_ delta: String) {
        guard isResponding else { return }
        messages[messages.index(before: messages.endIndex)].text += delta
    }

    @discardableResult
    mutating func finishAssistantReply() -> ChatMessage? {
        guard isResponding else { return nil }
        let index = messages.index(before: messages.endIndex)
        if messages[index].text.isEmpty {
            messages.remove(at: index)
            return nil
        }
        messages[index].state = .sent
        return messages[index]
    }

    mutating func discardAssistantReply() {
        guard isResponding else { return }
        messages.removeLast()
    }
}

@MainActor
@Observable
final class ChatModel {
    var draft = ""
    var conversation = ChatConversation()
    var threads: [ChatThread] = []
    var providers: [ProviderConfiguration] = []
    var selectedThreadID: UUID?
    var errorMessage: String?
    var requiresProviderSettings = false
    var hasNewSession = false

    private let store: AthleteStore?
    private let keyStore: APIKeyStore
    private let client: ResponsesAPIClient
    private var replyTask: Task<Void, Never>?
    private var hasLoaded = false

    var selectedProvider: ProviderConfiguration? {
        providers.first(where: \.isSelected)
    }

    init() {
        do {
            store = try Self.openStore()
            errorMessage = nil
        } catch {
            store = nil
            errorMessage = "Не удалось открыть локальную историю: \(error.localizedDescription)"
        }
        keyStore = APIKeyStore()
        client = ResponsesAPIClient()
    }

    init(store: AthleteStore, keyStore: APIKeyStore = APIKeyStore(), client: ResponsesAPIClient = ResponsesAPIClient()) {
        self.store = store
        self.keyStore = keyStore
        self.client = client
    }

    func load() async {
        guard !hasLoaded, let store else { return }
        hasLoaded = true
        do {
            providers = try await store.providerConfigurations()
            threads = try await store.chatThreads()
            if let session = try await store.latestEvidence(kind: "activity.session.v1") {
                hasNewSession = try await !store.hasEvidence(kind: "user.narrative.v1", derivedFrom: session.id)
            }
            if let first = threads.first {
                try await openChat(first)
            }
        } catch {
            errorMessage = "Не удалось загрузить чат: \(error.localizedDescription)"
        }
    }

    func openChat(_ thread: ChatThread) async throws {
        guard let store else { return }
        let history = try await store.chatMessages(threadID: thread.id)
        selectedThreadID = thread.id
        conversation = ChatConversation(history: history)
        draft = ""
    }

    func newChat() {
        guard !conversation.isResponding else { return }
        selectedThreadID = nil
        conversation = ChatConversation()
        draft = ""
    }

    func send(_ input: String? = nil) {
        let prompt = (input ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !conversation.isResponding else { return }
        guard let store else {
            errorMessage = "Локальная история недоступна"
            return
        }
        guard let provider = selectedProvider else {
            Task { await saveDebrief(prompt, in: store) }
            requiresProviderSettings = true
            return
        }
        let apiKey: String
        do {
            guard let storedKey = try keyStore.load(providerID: provider.id), !storedKey.isEmpty else {
                requiresProviderSettings = true
                return
            }
            apiKey = storedKey
        } catch {
            errorMessage = "Не удалось прочитать API-ключ из Keychain"
            return
        }
        guard conversation.startUserTurn(prompt) else { return }
        draft = ""
        let context = conversation.responsesInput
        let userMessage = conversation.messages[conversation.messages.index(conversation.messages.endIndex, offsetBy: -2)]
        replyTask = Task { [weak self] in
            await self?.recordDebrief(prompt, in: store, provider: provider, apiKey: apiKey)
            await self?.performRequest(
                store: store,
                provider: provider,
                apiKey: apiKey,
                prompt: prompt,
                userMessage: userMessage,
                context: context
            )
        }
    }

    private func recordDebrief(_ text: String, in store: AthleteStore, provider: ProviderConfiguration, apiKey: String) async {
        do {
            guard let session = try await store.latestEvidence(kind: "activity.session.v1"),
                  try await !store.hasEvidence(kind: "user.narrative.v1", derivedFrom: session.id) else {
                return
            }
            try await appendDebrief(text, session: session, to: store)
            _ = try await SessionMemoryBuilder(
                store: store,
                provider: ResponsesAgentProvider(provider: provider, apiKey: apiKey, client: client)
            ).build(for: session.id)
            hasNewSession = false
        } catch {
            errorMessage = "Не удалось сохранить разбор тренировки"
        }
    }

    private func saveDebrief(_ text: String, in store: AthleteStore) async {
        do {
            guard let session = try await store.latestEvidence(kind: "activity.session.v1"),
                  try await !store.hasEvidence(kind: "user.narrative.v1", derivedFrom: session.id) else { return }
            try await appendDebrief(text, session: session, to: store)
            hasNewSession = false
        } catch {
            errorMessage = "Не удалось сохранить разбор тренировки"
        }
    }

    private func appendDebrief(_ text: String, session: EvidenceEnvelope, to store: AthleteStore) async throws {
        let narrative = try UserNarrativeBuilder().make(text: text, sessionEvidenceID: session.id)
        let envelope = try narrative.envelope()
        try await store.appendEvidence(envelope, payload: narrative)
    }

    func stop() {
        replyTask?.cancel()
        replyTask = nil
        guard let message = conversation.finishAssistantReply(), let threadID = selectedThreadID, let store else { return }
        Task {
            do {
                try await store.appendChatMessage(message.historyMessage(threadID: threadID))
                await refreshThreads()
            } catch {
                errorMessage = "Не удалось сохранить остановленный ответ"
            }
        }
    }

    func selectProvider(id: UUID) async {
        guard let store else { return }
        do {
            try await store.selectProvider(id: id)
            providers = try await store.providerConfigurations()
        } catch {
            errorMessage = "Не удалось выбрать провайдера"
        }
    }

    @discardableResult
    func saveProvider(_ configuration: ProviderConfiguration, apiKey: String) async -> Bool {
        guard let store else { return false }
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !baseURL.isEmpty, !model.isEmpty,
              let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            errorMessage = "Заполните имя, корректный базовый URL и модель"
            return false
        }
        do {
            let existingKey = try keyStore.load(providerID: configuration.id)
            guard !apiKey.isEmpty || existingKey != nil else {
                errorMessage = "Введите API-ключ"
                return false
            }
            var saved = configuration
            saved.name = name
            saved.baseURL = baseURL
            saved.model = model
            saved.isSelected = configuration.isSelected || selectedProvider == nil
            try await store.saveProviderConfiguration(saved)
            if !apiKey.isEmpty {
                try keyStore.save(apiKey, providerID: saved.id)
            }
            providers = try await store.providerConfigurations()
            requiresProviderSettings = false
            return true
        } catch {
            errorMessage = "Не удалось сохранить провайдера"
            return false
        }
    }

    func deleteProvider(_ configuration: ProviderConfiguration) async {
        guard let store else { return }
        do {
            try await store.deleteProviderConfiguration(id: configuration.id)
            try keyStore.delete(providerID: configuration.id)
            providers = try await store.providerConfigurations()
        } catch {
            errorMessage = "Не удалось удалить провайдера"
        }
    }

    func deleteChat(_ thread: ChatThread) async {
        guard let store else { return }
        do {
            try await store.deleteChat(id: thread.id)
            if selectedThreadID == thread.id {
                newChat()
            }
            threads = try await store.chatThreads()
        } catch {
            errorMessage = "Не удалось удалить диалог"
        }
    }

    private func performRequest(
        store: AthleteStore,
        provider: ProviderConfiguration,
        apiKey: String,
        prompt: String,
        userMessage: ChatMessage,
        context: [ResponsesInputMessage]
    ) async {
        do {
            let threadID: UUID
            if let selectedThreadID {
                threadID = selectedThreadID
            } else {
                let thread = try await store.createChat(title: Self.title(for: prompt))
                selectedThreadID = thread.id
                threadID = thread.id
            }
            try await store.appendChatMessage(userMessage.historyMessage(threadID: threadID))
            await refreshThreads()
            try await client.stream(provider: provider, apiKey: apiKey, messages: context) { [weak self] delta in
                await MainActor.run {
                    self?.conversation.appendAssistantDelta(delta)
                }
            }
            if let assistant = conversation.finishAssistantReply() {
                try await store.appendChatMessage(assistant.historyMessage(threadID: threadID))
                await refreshThreads()
            }
            replyTask = nil
        } catch {
            guard !Task.isCancelled else { return }
            conversation.discardAssistantReply()
            replyTask = nil
            errorMessage = Self.message(for: error)
        }
    }

    private func refreshThreads() async {
        guard let store else { return }
        do {
            threads = try await store.chatThreads()
        } catch {
            errorMessage = "Не удалось обновить историю"
        }
    }

    private static func openStore() throws -> AthleteStore {
        let manager = FileManager.default
        let root = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Baseline", directoryHint: .isDirectory)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        return try AthleteStore(path: root.appending(path: "baseline.sqlite").path)
    }

    private static func title(for prompt: String) -> String {
        String(prompt.prefix(52))
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let ResponsesAPIError.httpStatus(code):
            "Responses API вернул HTTP \(code)"
        case let ResponsesAPIError.remote(message):
            message
        case ResponsesAPIError.invalidBaseURL:
            "Некорректный базовый URL провайдера"
        case ResponsesAPIError.incompleteStream:
            "Responses API оборвал поток ответа"
        default:
            "Не удалось получить ответ: \(error.localizedDescription)"
        }
    }
}

private extension ChatMessage {
    func historyMessage(threadID: UUID) -> ChatHistoryMessage {
        ChatHistoryMessage(
            id: id,
            threadID: threadID,
            role: role == .user ? .user : .assistant,
            text: text,
            createdAt: createdAt
        )
    }
}
