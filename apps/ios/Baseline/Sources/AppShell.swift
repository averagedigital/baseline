import Observation
import SwiftUI

enum AppTab: CaseIterable {
    case camera
    case chat
}

struct MotionIntensityHistory: Equatable {
    private(set) var values: [Double] = []
    let limit: Int

    mutating func append(_ value: Double) {
        values.append(min(max(value, 0), 1))
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }
}

struct AppShell: View {
    var body: some View {
        TabView {
            CameraScreen()
                .tabItem { Label("Камера", systemImage: "camera.fill") }
            ChatScreen()
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(BaselineTheme.accent)
    }
}

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

    init(id: UUID = UUID(), role: Role, text: String, state: State = .sent) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
    }
}

struct ChatConversation: Equatable, Sendable {
    private(set) var messages: [ChatMessage] = []

    var isResponding: Bool {
        messages.last?.state == .streaming
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

    mutating func finishAssistantReply() {
        guard isResponding else { return }
        let index = messages.index(before: messages.endIndex)
        if messages[index].text.isEmpty {
            messages.remove(at: index)
        } else {
            messages[index].state = .sent
        }
    }
}

@MainActor
@Observable
final class ChatModel {
    var draft = ""
    var conversation = ChatConversation()
    private var replyTask: Task<Void, Never>?

    func send(_ input: String? = nil) {
        let prompt = input ?? draft
        guard conversation.startUserTurn(prompt) else { return }
        draft = ""
        replyTask?.cancel()
        let chunks = previewReply(for: prompt)
        replyTask = Task { [weak self] in
            for chunk in chunks {
                do {
                    try await Task.sleep(for: .milliseconds(90))
                } catch {
                    return
                }
                self?.conversation.appendAssistantDelta(chunk)
            }
            self?.conversation.finishAssistantReply()
        }
    }

    func stop() {
        replyTask?.cancel()
        replyTask = nil
        conversation.finishAssistantReply()
    }

    func reset() {
        replyTask?.cancel()
        replyTask = nil
        draft = ""
        conversation = ChatConversation()
    }

    private func previewReply(for prompt: String) -> [String] {
        let text = prompt.lowercased()
        let reply: String
        if text.contains("восстанов") || text.contains("сон") {
            reply = "Для оценки восстановления мне понадобятся сон, самочувствие и последняя нагрузка. После подключения данных я сопоставлю их и предложу конкретный режим на сегодня."
        } else if text.contains("трениров") || text.contains("техник") {
            reply = "Разбор тренировки будет опираться на движение в кадре, интенсивность подходов и паузы. Я выделю отклонения и верну короткие корректировки без лишней статистики."
        } else {
            reply = "Я соберу контекст тренировки, уточню недостающие данные и дам короткий план действий. История диалога сохранит связь между нагрузкой, восстановлением и прогрессом."
        }
        return reply.split(separator: " ").enumerated().map { index, word in
            index == 0 ? String(word) : " \(word)"
        }
    }
}

private struct ChatScreen: View {
    @State private var model = ChatModel()

    private let suggestions = [
        "Разбери последнюю тренировку",
        "Оцени восстановление",
        "Собери план на неделю",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 24) {
                        if model.conversation.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.conversation.messages) { message in
                                ChatMessageRow(message: message)
                                    .id(message.id)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.conversation.messages) { _, messages in
                    guard let id = messages.last?.id else { return }
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .background(BaselineTheme.shell)
            .foregroundStyle(BaselineTheme.ink)
            .navigationTitle("Baseline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: model.reset) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.conversation.messages.isEmpty)
                    .accessibilityLabel("Новый диалог")
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.conversation.messages.count)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        model.send(suggestion)
                    } label: {
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
                    if suggestion != suggestions.last {
                        Divider().overlay(BaselineTheme.line)
                    }
                }
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .leading)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение Baseline", text: $model.draft, axis: .vertical)
                .lineLimit(1...6)
                .submitLabel(.send)
                .onSubmit { model.send() }
                .padding(.leading, 16)
                .padding(.vertical, 13)
            Button {
                model.conversation.isResponding ? model.stop() : model.send()
            } label: {
                Image(systemName: model.conversation.isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
            }
                .frame(width: 44, height: 44)
                .foregroundStyle(BaselineTheme.shell)
                .background(BaselineTheme.accent, in: Circle())
                .disabled(
                    !model.conversation.isResponding
                        && model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
        }
        .padding(6)
        .chatComposerSurface()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(BaselineTheme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BaselineTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(BaselineTheme.panel, in: Circle())
                Group {
                    if message.text.isEmpty && message.state == .streaming {
                        TypingIndicator()
                    } else {
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        PhaseAnimator([0, 1, 2]) { phase in
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(BaselineTheme.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(phase == index ? 1 : 0.3)
                        .scaleEffect(phase == index ? 1.2 : 1)
                }
            }
        } animation: { _ in
            .easeInOut(duration: 0.45)
        }
        .frame(height: 26)
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
                        .stroke(BaselineTheme.line, lineWidth: 1)
                }
        }
    }
}
