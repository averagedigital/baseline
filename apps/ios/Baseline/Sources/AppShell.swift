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
    @State private var selectedTab: AppTab = .camera

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraScreen()
                .tag(AppTab.camera)
                .tabItem { Label("Камера", systemImage: "camera.fill") }
            ChatScreen()
                .tag(AppTab.chat)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(BaselineTheme.accent)
    }
}

private struct ChatScreen: View {
    @State private var model = ChatModel()
    @State private var showsHistory = false
    @State private var showsSettings = false
    @State private var providerEditor: ProviderEditor?

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
                        if model.hasNewSession {
                            Button("Новая тренировка готова к разбору") {
                                model.draft = "Разбери последнюю тренировку"
                            }
                            .buttonStyle(.bordered)
                            .tint(BaselineTheme.accent)
                            .accessibilityHint("Подставляет запрос для Coach")
                        }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsHistory = true } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .disabled(model.conversation.isResponding)
                    .accessibilityLabel("История диалогов")
                }
                ToolbarItem(placement: .principal) {
                    modelMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: model.newChat) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.conversation.messages.isEmpty || model.conversation.isResponding)
                    .accessibilityLabel("Новый диалог")
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.conversation.messages.count)
            .task { await model.load() }
            .sheet(isPresented: $showsHistory) {
                ChatHistoryView(model: model)
            }
            .sheet(isPresented: $showsSettings) {
                ProviderSettingsView(model: model)
            }
            .sheet(item: $providerEditor) { editor in
                ProviderEditorView(model: model, editor: editor)
            }
            .onChange(of: model.requiresProviderSettings) { _, required in
                guard required else { return }
                providerEditor = model.selectedProvider.map { ProviderEditor(configuration: $0) } ?? .newOpenAI
                model.requiresProviderSettings = false
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("Закрыть") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Неизвестная ошибка")
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            if model.providers.isEmpty {
                Text("Нет настроенных моделей")
            } else {
                Section("Модели") {
                    ForEach(model.providers) { provider in
                        Button {
                            Task { await model.selectProvider(id: provider.id) }
                        } label: {
                            Label(
                                "\(provider.model) · \(provider.name)",
                                systemImage: provider.isSelected ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
            }
            Divider()
            Button {
                providerEditor = .newOpenAI
            } label: {
                Label("Добавить API", systemImage: "plus.circle")
            }
            Button {
                showsSettings = true
            } label: {
                Label("Управление API", systemImage: "slider.horizontal.3")
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(model.selectedProvider?.model ?? "Выбрать модель")
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BaselineTheme.muted)
                }
                Text(model.selectedProvider.map { "Baseline · \($0.name)" } ?? "Responses API")
                    .font(.caption2)
                    .foregroundStyle(BaselineTheme.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Модель \(model.selectedProvider?.model ?? "не выбрана")")
        .sensoryFeedback(.selection, trigger: model.selectedProvider?.id)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
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
            if model.selectedProvider == nil {
                Button("Добавить Responses API") {
                    providerEditor = .newOpenAI
                }
                .buttonStyle(.borderedProminent)
                .tint(BaselineTheme.accent)
                .foregroundStyle(BaselineTheme.shell)
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
