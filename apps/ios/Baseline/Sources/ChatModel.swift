import Foundation
import Observation
import SwiftUI
import AthleteStore

struct CoachMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let recommendationCategory: String?
    let feedbackContextID: UUID?
    var rating: Int?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        recommendationCategory: String? = nil,
        feedbackContextID: UUID? = nil,
        rating: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.recommendationCategory = recommendationCategory
        self.feedbackContextID = feedbackContextID
        self.rating = rating
    }
}

@MainActor
@Observable
final class ChatModel {
    var messages: [CoachMessage] = []
    var threads: [ChatThread] = []
    var providers: [ProviderConfiguration] = []
    var selectedProviderID: UUID?
    var draft = ""
    var isSending = false
    var errorMessage: String?
    var requiresProviderSettings = false

    private let localServices: LocalDeviceServices
    private let keyStore = APIKeyStore()
    private let apiClient = ResponsesAPIClient()
    private var threadID: UUID?

    init(localServices: LocalDeviceServices) {
        self.localServices = localServices
    }

    func loadMostRecentThread() async {
        do {
            providers = try await localServices.providerConfigurations()
            selectedProviderID = providers.first(where: \.isSelected)?.id ?? providers.first?.id
            threads = try await localServices.chatThreads()
            if messages.isEmpty, let (thread, history) = try await localServices.mostRecentChat() {
                load(thread: thread, history: history)
            }
        } catch {
            errorMessage = "Не удалось загрузить историю Coach."
        }
    }

    func openChat(_ thread: ChatThread) async {
        do { load(thread: thread, history: try await localServices.chatMessages(threadID: thread.id)) }
        catch { errorMessage = "Не удалось открыть диалог." }
    }

    func refreshThreads() async {
        do { threads = try await localServices.chatThreads() } catch { errorMessage = "Не удалось загрузить диалоги." }
    }

    private func load(thread: ChatThread, history: [ChatHistoryMessage]) {
        threadID = thread.id
        messages = history.map { item in
            CoachMessage(id: item.id, role: item.role == .user ? .user : .assistant, text: item.text)
        }
    }

    func startNewThread() {
        threadID = nil
        messages.removeAll()
        draft = ""
        errorMessage = nil
    }

    func deleteChat(_ thread: ChatThread) async {
        do {
            try await localServices.deleteChat(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if threadID == thread.id { startNewThread() }
        } catch { errorMessage = "Не удалось удалить диалог." }
    }

    func send(_ value: String? = nil) async {
        let text = (value ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let provider = providers.first(where: { $0.id == selectedProviderID }),
              let apiKey = try? keyStore.load(providerID: provider.id),
              !apiKey.isEmpty else {
            requiresProviderSettings = true
            errorMessage = "Сначала настройте облачного провайдера Coach."
            return
        }
        messages.append(CoachMessage(role: .user, text: text))
        draft = ""
        isSending = true
        errorMessage = nil
        do {
            let targetThread = try await ensureThread(title: String(text.prefix(48)))
            try await localServices.appendChatMessage(ChatHistoryMessage(threadID: targetThread, role: .user, text: text))
            let context = try await localServices.cloudCoachContext(threadID: targetThread, message: text)
            let history = messages.dropLast().suffix(12).map { message in
                ResponsesInputMessage(role: message.role == .user ? .user : .assistant, content: message.text)
            }
            let prompt = ResponsesInputMessage(role: .user, content: "[BASELINE LOCAL CONTEXT]\n\(context)")
            let answer = try await apiClient.stream(
                provider: provider,
                apiKey: apiKey,
                messages: Array(history) + [prompt],
                instructions: "Отвечай на языке последнего сообщения пользователя. Используй только приведённые локальные факты. Не выдумывай числа, калории или результаты, которых нет в facts."
            )
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResponsesAPIError.incompleteStream }
            try await localServices.appendChatMessage(ChatHistoryMessage(threadID: targetThread, role: .assistant, text: answer))
            threadID = targetThread
            messages.append(CoachMessage(
                role: .assistant,
                text: answer,
                recommendationCategory: "none",
                feedbackContextID: nil
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    private func ensureThread(title: String) async throws -> UUID {
        if let threadID { return threadID }
        let thread = try await localServices.createChat(title: title)
        threads.insert(thread, at: 0)
        return thread.id
    }

    func saveProvider(_ provider: ProviderConfiguration, apiKey: String) async {
        do {
            try await localServices.saveProviderConfiguration(provider)
            try keyStore.save(apiKey, providerID: provider.id)
            providers = try await localServices.providerConfigurations()
            selectedProviderID = provider.id
            requiresProviderSettings = false
        } catch { errorMessage = "Не удалось сохранить настройки провайдера." }
    }

    func selectProvider(_ provider: ProviderConfiguration) async {
        do { try await localServices.selectProvider(id: provider.id); providers = try await localServices.providerConfigurations(); selectedProviderID = provider.id }
        catch { errorMessage = "Не удалось выбрать провайдера." }
    }

    func deleteProvider(_ provider: ProviderConfiguration) async {
        do { try await localServices.deleteProviderConfiguration(id: provider.id); try keyStore.delete(providerID: provider.id); providers = try await localServices.providerConfigurations(); selectedProviderID = providers.first?.id }
        catch { errorMessage = "Не удалось удалить провайдера." }
    }

    func rate(messageID: UUID, useful: Bool) async {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].role == .assistant,
              let category = messages[index].recommendationCategory,
              category != "none",
              let feedbackContextID = messages[index].feedbackContextID else { return }
        let value = useful ? 1 : -1
        messages[index].rating = value
        do {
            _ = try await localServices.sendRecommendationReward(
                feedbackContextID: feedbackContextID,
                reward: Double(value)
            )
        } catch {
            messages[index].rating = nil
            errorMessage = "Не удалось сохранить оценку совета."
        }
    }
}

struct CoachScreen: View {
    @State private var model: ChatModel
    @State private var showsHistory = false
    @State private var showsProviders = false
    private let initialPrompt: String?

    init(
        localServices: LocalDeviceServices,
        initialPrompt: String? = nil
    ) {
        _model = State(initialValue: ChatModel(localServices: localServices))
        self.initialPrompt = initialPrompt
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.messages.isEmpty {
                            emptyState
                        }
                        ForEach(model.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if model.isSending {
                            HStack(spacing: 9) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Анализирую данные тренировки…")
                                    .font(.subheadline)
                                    .foregroundStyle(BaselineTheme.secondary)
                            }
                            .padding(.vertical, 8)
                            .id("loading")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { _, _ in
                    guard let id = model.messages.last?.id else { return }
                    withAnimation(BaselineTheme.standardAnimation) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
                .onChange(of: model.isSending) { _, value in
                    guard value else { return }
                    withAnimation(BaselineTheme.standardAnimation) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
            .background(BaselineTheme.canvas)
            .foregroundStyle(BaselineTheme.ink)
            .navigationTitle("Baseline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("История чатов")
                }
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(model.providers) { provider in
                            Button {
                                Task { await model.selectProvider(provider) }
                            } label: {
                                Label(provider.name, systemImage: provider.id == model.selectedProviderID ? "checkmark" : "")
                            }
                        }
                        Divider()
                        Button("Настройки провайдера") { showsProviders = true }
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.providers.first(where: { $0.id == model.selectedProviderID })?.name ?? "Настроить Coach")
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(BaselineTheme.ink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.startNewThread() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.messages.isEmpty || model.isSending)
                    .accessibilityLabel("Новый диалог")
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .sheet(isPresented: $showsHistory) { ChatHistoryView(model: model) }
            .sheet(isPresented: $showsProviders) { ProviderSettingsView(model: model) }
            .task {
                await model.loadMostRecentThread()
                if let initialPrompt, model.messages.isEmpty { await model.send(initialPrompt) }
            }
            .onChange(of: model.requiresProviderSettings) { _, value in
                if value { showsProviders = true }
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("Закрыть") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Неизвестная ошибка")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 100)
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(BaselineTheme.accent)
                Text("Что разбираем?")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("Тренировка, восстановление или следующий шаг.")
                    .font(.body)
                    .foregroundStyle(BaselineTheme.secondary)
            }
            VStack(spacing: 0) {
                suggestionRow("Разбери последнюю тренировку")
                Divider().overlay(BaselineTheme.border)
                suggestionRow("Оцени восстановление")
                Divider().overlay(BaselineTheme.border)
                suggestionRow("Собери план на неделю")
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .leading)
    }

    private func suggestionRow(_ suggestion: String) -> some View {
        Button { Task { await model.send(suggestion) } } label: {
            HStack {
                Text(suggestion)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(BaselineTheme.muted)
            }
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messageRow(_ message: CoachMessage) -> some View {
        if message.role == .user {
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(BaselineTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BaselineTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(BaselineTheme.surface, in: Circle())
                VStack(alignment: .leading, spacing: 12) {
                    Text(message.text)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                if message.recommendationCategory != nil,
                   message.recommendationCategory != "none" {
                    HStack(spacing: 10) {
                        Text("Полезно?")
                            .font(.caption)
                            .foregroundStyle(BaselineTheme.secondary)
                        ratingButton(systemName: "hand.thumbsup", value: 1, message: message)
                        ratingButton(systemName: "hand.thumbsdown", value: -1, message: message)
                    }
                    .padding(.leading, 0)
                }
                }
            }
        }
    }

    private func ratingButton(systemName: String, value: Int, message: CoachMessage) -> some View {
        Button {
            Task { await model.rate(messageID: message.id, useful: value == 1) }
        } label: {
            Image(systemName: message.rating == value ? "\(systemName).fill" : systemName)
                .frame(width: 30, height: 30)
                .background(BaselineTheme.surface, in: Circle())
                .overlay { Circle().stroke(BaselineTheme.border, lineWidth: 1) }
        }
        .foregroundStyle(message.rating == value ? BaselineTheme.accent : BaselineTheme.secondary)
        .disabled(message.rating != nil)
        .accessibilityLabel(value == 1 ? "Полезно" : "Не полезно")
    }

    private var composer: some View {
        @Bindable var bindableModel = model
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение Baseline", text: $bindableModel.draft, axis: .vertical)
                .lineLimit(1...6)
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
                .padding(.leading, 16)
                .padding(.vertical, 13)
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(BaselineTheme.accent, in: Circle())
            }
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
        }
        .padding(6)
        .chatComposerSurface()
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private extension View {
    @ViewBuilder
    func chatComposerSurface() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(BaselineTheme.border, lineWidth: 1)
                }
        }
    }
}

#Preview("Coach empty") {
    CoachScreen(localServices: LocalDeviceServices(store: nil))
}
