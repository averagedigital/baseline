import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AthleteStore

struct PendingChatImage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let data: Data
    let mimeType: String
    let width: Int
    let height: Int
}

private enum ChatAttachmentPreparationError: Error { case encodingFailed }

struct CoachMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let attachments: [ChatAttachment]
    let citations: [ChatCitation]
    let recommendationCategory: String?
    let feedbackContextID: UUID?
    var rating: Int?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachments: [ChatAttachment] = [],
        citations: [ChatCitation] = [],
        recommendationCategory: String? = nil,
        feedbackContextID: UUID? = nil,
        rating: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.citations = citations
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
    var pendingImages: [PendingChatImage] = []
    var isSending = false
    var activity: CoachActivity?
    var errorMessage: String?
    var requiresProviderSettings = false

    let localServices: LocalDeviceServices
    private let keyStore = APIKeyStore()
    private let apiClient = ResponsesAPIClient()
    private var threadID: UUID?

    init(localServices: LocalDeviceServices) {
        self.localServices = localServices
    }

    func loadMostRecentThread() async {
        do {
            let storedProviders = try await localServices.providerConfigurations()
            if let stored = storedProviders.first(where: \.isSelected) ?? storedProviders.first {
                let openAI = OpenAIProvider.normalize(stored)
                if openAI != stored { try await localServices.saveProviderConfiguration(openAI) }
                providers = [openAI]
                selectedProviderID = openAI.id
            }
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
            CoachMessage(id: item.id, role: item.role == .user ? .user : .assistant, text: item.text, attachments: item.attachments, citations: item.citations)
        }
    }

    func startNewThread() {
        threadID = nil
        messages.removeAll()
        draft = ""
        pendingImages.removeAll()
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
        let images = pendingImages
        guard (!text.isEmpty || !images.isEmpty), !isSending else { return }
        guard let provider = providers.first(where: { $0.id == selectedProviderID }),
              let apiKey = try? keyStore.load(providerID: provider.id),
              !apiKey.isEmpty else {
            requiresProviderSettings = true
            errorMessage = "Сначала настройте облачного провайдера Coach."
            return
        }
        guard images.isEmpty || provider.capabilities.supportsVision else {
            errorMessage = ResponsesAPIError.unsupportedVision.localizedDescription
            return
        }
        draft = ""
        pendingImages.removeAll()
        isSending = true
        errorMessage = nil
        var streamingMessageID: UUID?
        do {
            let title = text.isEmpty ? "Фото питания" : String(text.prefix(48))
            let targetThread = try await ensureThread(title: title)
            let messageID = UUID()
            let prepared = try await Task.detached(priority: .userInitiated) { try Self.persist(images, messageID: messageID) }.value
            let attachments = prepared.attachments
            let userMessage = CoachMessage(id: messageID, role: .user, text: text, attachments: attachments)
            messages.append(userMessage)
            try await localServices.appendChatMessage(ChatHistoryMessage(id: messageID, threadID: targetThread, role: .user, text: text, attachments: attachments))
            let context = try await localServices.cloudCoachContext(threadID: targetThread, message: text)
            let history = messages.dropLast().suffix(12).map { message in
                ResponsesInputMessage(role: message.role == .user ? .user : .assistant, content: message.text)
            }
            let imageURLs = prepared.transportData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
            let current = ResponsesInputMessage(role: .user, content: text, imageDataURLs: imageURLs)
            let prompt = ResponsesInputMessage(role: .user, content: "[BASELINE LOCAL CONTEXT]\n\(context)")
            let pendingAssistantID = UUID()
            streamingMessageID = pendingAssistantID
            messages.append(CoachMessage(id: pendingAssistantID, role: .assistant, text: ""))
            let result = try await apiClient.run(
                provider: provider,
                apiKey: apiKey,
                messages: Array(history) + [current, prompt],
                instructions: CoachPrompt.instructions,
                tools: CoachToolDefinition.foodDiary,
                onActivity: { [weak self] activity in await MainActor.run { self?.activity = activity } },
                onTextUpdate: { [weak self] text in
                    await MainActor.run {
                        guard let index = self?.messages.firstIndex(where: { $0.id == pendingAssistantID }) else { return }
                        self?.messages[index].text = text
                    }
                },
                execute: { [localServices] call in
                    await localServices.executeFoodTool(call, linkedChatMessageID: messageID, linkedAttachmentIDs: attachments.map(\.id))
                }
            )
            let answer = result.text
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResponsesAPIError.incompleteStream }
            let assistantID = UUID()
            let citations = result.citations.map { ChatCitation(messageID: assistantID, title: $0.title, url: $0.url) }
            try await localServices.appendChatMessage(ChatHistoryMessage(id: assistantID, threadID: targetThread, role: .assistant, text: answer, citations: citations))
            threadID = targetThread
            messages.removeAll { $0.id == pendingAssistantID }
            streamingMessageID = nil
            messages.append(CoachMessage(
                id: assistantID,
                role: .assistant,
                text: answer,
                citations: citations,
                recommendationCategory: "none",
                feedbackContextID: nil
            ))
        } catch {
            if let streamingMessageID { messages.removeAll { $0.id == streamingMessageID } }
            errorMessage = message(for: error)
        }
        activity = nil
        isSending = false
    }

    func addImage(data: Data, mimeType: String) {
        guard pendingImages.count < 5, let image = UIImage(data: data) else {
            errorMessage = "Не удалось прочитать изображение."
            return
        }
        pendingImages.append(.init(data: data, mimeType: mimeType, width: Int(image.size.width), height: Int(image.size.height)))
    }

    func removePendingImage(id: UUID) { pendingImages.removeAll { $0.id == id } }

    private nonisolated static func persist(_ images: [PendingChatImage], messageID: UUID) throws -> (attachments: [ChatAttachment], transportData: [Data]) {
        guard !images.isEmpty else { return ([], []) }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Baseline/ChatAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            var transportData: [Data] = []
            let attachments = try images.map { image in
                let ext = UTType(mimeType: image.mimeType)?.preferredFilenameExtension ?? "bin"
                let url = root.appendingPathComponent("\(UUID().uuidString).\(ext)")
                try image.data.write(to: url, options: .atomic)
                written.append(url)
                guard let transport = transportJPEG(from: image.data) else { throw ChatAttachmentPreparationError.encodingFailed }
                let transportURL = root.appendingPathComponent("\(UUID().uuidString)-transport.jpg")
                try transport.write(to: transportURL, options: .atomic)
                written.append(transportURL)
                transportData.append(transport)
                return ChatAttachment(messageID: messageID, localPath: url.path, transportPath: transportURL.path, mimeType: image.mimeType, width: image.width, height: image.height, byteSize: image.data.count)
            }
            return (attachments, transportData)
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    private nonisolated static func transportJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let limit: CGFloat = 2_048
        let scale = min(1, limit / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    private func message(for error: Error) -> String {
        if let error = error as? ResponsesAPIError { return error.localizedDescription }
        if error is DecodingError { return "Локальные данные Baseline имеют старый или неполный формат. Запрос Coach не отправлен." }
        return error.localizedDescription
    }

    private func ensureThread(title: String) async throws -> UUID {
        if let threadID { return threadID }
        let thread = try await localServices.createChat(title: title)
        threads.insert(thread, at: 0)
        return thread.id
    }

    func saveProvider(_ provider: ProviderConfiguration, apiKey: String) async {
        do {
            let openAI = OpenAIProvider.normalize(provider)
            try await localServices.saveProviderConfiguration(openAI)
            if !apiKey.isEmpty { try keyStore.save(apiKey, providerID: openAI.id) }
            providers = [openAI]
            selectedProviderID = openAI.id
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

    func resetPersonalization() async {
        do { try await localServices.resetPersonalization() }
        catch { errorMessage = "Не удалось сбросить персонализацию." }
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
    @State private var showsProviders = false
    @State private var showsCamera = false
    @State private var showsFoodDiary = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var previewAttachment: ChatAttachment?
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
                                Text(activityText)
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
                    Menu {
                        if model.threads.isEmpty {
                            Text("История пуста")
                        } else {
                            ForEach(Array(model.threads.prefix(8))) { thread in
                                Button(thread.title) {
                                    Task { await model.openChat(thread) }
                                }
                            }
                        }
                        Divider()
                        Button("Настроить API", systemImage: "key") {
                            showsProviders = true
                        }
                        Button("Рацион", systemImage: "fork.knife") {
                            showsFoodDiary = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Диалоги и API")
                }
                ToolbarItem(placement: .principal) {
                    Text("Baseline")
                        .font(.headline)
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
            .sheet(isPresented: $showsProviders) { ProviderSettingsView(model: model) }
            .sheet(isPresented: $showsFoodDiary) {
                FoodDiaryView(localServices: model.localServices) { thread in Task { await model.openChat(thread) } }
            }
            .sheet(isPresented: $showsCamera) {
                CameraImagePicker(isPresented: $showsCamera) { data, mimeType in model.addImage(data: data, mimeType: mimeType) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $previewAttachment) { attachment in
                NavigationStack {
                    Group {
                        LocalOriginalImage(path: attachment.localPath)
                            .scaledToFit()
                            .background(.black)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { previewAttachment = nil } }
                    }
                }
            }
            .task {
                await model.loadMostRecentThread()
                if let initialPrompt, model.messages.isEmpty { await model.send(initialPrompt) }
            }
            .onChange(of: model.requiresProviderSettings) { _, value in
                if value { showsProviders = true }
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                        model.addImage(data: data, mimeType: item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg")
                    }
                    selectedPhotos.removeAll()
                }
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

    private var activityText: String {
        switch model.activity {
        case .analyzingImages: "Анализирую фотографии…"
        case .searchingWeb: "Ищу пищевую ценность в интернете…"
        case let .callingTool(name): name.contains("food") ? "Обновляю дневник питания…" : "Выполняю действие…"
        case .streamingText: "Формирую ответ…"
        case .thinking, nil: "Анализирую данные…"
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 100)
            VStack(alignment: .leading, spacing: 10) {
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
                suggestionRow("Что изменилось за неделю?")
            }
            if model.providers.isEmpty {
                Button("Добавить API key") {
                    showsProviders = true
                }
                .buttonStyle(.borderedProminent)
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
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(message.attachments) { attachment in
                    Button { previewAttachment = attachment } label: {
                        LocalOriginalImage(path: attachment.localPath)
                            .scaledToFit()
                            .frame(maxWidth: 340, maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Открыть прикреплённое изображение")
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(BaselineTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                CoachMarkdownView(markdown: message.text)
                if !message.citations.isEmpty {
                    ForEach(message.citations) { citation in
                        Link(destination: citation.url) {
                            Label(citation.title ?? citation.url.host() ?? citation.url.absoluteString, systemImage: "link")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                if message.recommendationCategory != nil,
                   message.recommendationCategory != "none" {
                    HStack(spacing: 10) {
                        Text("Полезно?")
                            .font(.caption)
                            .foregroundStyle(BaselineTheme.secondary)
                        ratingButton(systemName: "hand.thumbsup", value: 1, message: message)
                        ratingButton(systemName: "hand.thumbsdown", value: -1, message: message)
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
        return VStack(alignment: .leading, spacing: 6) {
            if !model.pendingImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingImages) { pending in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: pending.data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                Button { model.removePendingImage(id: pending.id) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .accessibilityLabel("Удалить изображение")
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { showsCamera = true } label: {
                    Image(systemName: "camera")
                        .frame(width: 30, height: 44)
                }
                .disabled(model.isSending || model.pendingImages.count >= 5 || !UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityLabel("Сделать фотографию")
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(0, 5 - model.pendingImages.count), matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .frame(width: 36, height: 44)
                }
                .disabled(model.isSending || model.pendingImages.count >= 5)
                .accessibilityLabel("Добавить фотографии")
                TextField("Сообщение Baseline", text: $bindableModel.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit { Task { await model.send() } }
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
                .disabled((model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingImages.isEmpty) || model.isSending)
            }
        }
        .padding(6)
        .chatComposerSurface()
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private struct LocalOriginalImage: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable() }
            else { ProgressView().frame(minWidth: 80, minHeight: 80) }
        }
        .task(id: path) {
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: URL(fileURLWithPath: path)) }.value
            image = data.flatMap(UIImage.init)
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data, String) -> Void
        @Binding var isPresented: Bool
        init(isPresented: Binding<Bool>, onImage: @escaping (Data, String) -> Void) { _isPresented = isPresented; self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { isPresented = false }
            if let url = info[.imageURL] as? URL, let data = try? Data(contentsOf: url) {
                onImage(data, UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg")
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1) {
                onImage(data, "image/jpeg")
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { isPresented = false }
    }
}

private extension View {
    func chatComposerSurface() -> some View {
        background(BaselineTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BaselineTheme.border, lineWidth: 1)
            }
    }
}

#Preview("Coach empty") {
    CoachScreen(localServices: LocalDeviceServices(store: nil))
}
