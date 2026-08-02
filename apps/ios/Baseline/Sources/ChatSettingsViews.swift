import AthleteStore
import SwiftUI

struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    @State private var query = ""

    private var sections: [ChatHistorySection] {
        ChatHistorySection.group(ChatHistorySection.filter(model.threads, query: query))
    }

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    historyEmptyState
                } else {
                    List {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.threads) { thread in
                                    historyRow(thread)
                                        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            } header: {
                                Text(section.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(1.1)
                                    .foregroundStyle(BaselineTheme.muted)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(.spring(response: 0.38, dampingFraction: 0.88), value: model.threads)
                }
            }
            .background(BaselineTheme.shell)
            .navigationTitle("Диалоги")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по диалогам")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть историю")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.newChat()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Новый диалог")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var historyEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: query.isEmpty ? "text.bubble" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(BaselineTheme.accent)
                .frame(width: 64, height: 64)
                .background(BaselineTheme.accent.opacity(0.08), in: Circle())
            Text(query.isEmpty ? "Диалогов пока нет" : "Ничего не найдено")
                .font(.title3.weight(.semibold))
            Text(query.isEmpty ? "Новый разговор появится здесь после первого сообщения." : "Попробуйте изменить запрос.")
                .font(.subheadline)
                .foregroundStyle(BaselineTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func historyRow(_ thread: ChatThread) -> some View {
        Button {
            Task {
                do {
                    try await model.openChat(thread)
                    dismiss()
                } catch {
                    model.errorMessage = "Не удалось открыть диалог"
                }
            }
        } label: {
            HStack(spacing: 12) {
                Capsule()
                    .fill(model.selectedThreadID == thread.id ? BaselineTheme.accent : BaselineTheme.line)
                    .frame(width: 3, height: 42)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(thread.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BaselineTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(thread.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(BaselineTheme.muted)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(thread.lastMessage ?? "Диалог создан")
                            .font(.subheadline)
                            .foregroundStyle(BaselineTheme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Label("\(thread.messageCount)", systemImage: "bubble.left")
                            .font(.caption2)
                            .foregroundStyle(BaselineTheme.muted)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                model.selectedThreadID == thread.id ? BaselineTheme.raised : Color.clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(model.selectedThreadID == thread.id ? BaselineTheme.accent.opacity(0.28) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await model.deleteChat(thread) }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await model.deleteChat(thread) }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}

struct ChatHistorySection: Identifiable, Equatable {
    enum Kind: Int, CaseIterable {
        case today
        case yesterday
        case week
        case older
    }

    let kind: Kind
    let threads: [ChatThread]
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .today: "Сегодня"
        case .yesterday: "Вчера"
        case .week: "Последние 7 дней"
        case .older: "Ранее"
        }
    }

    static func filter(_ threads: [ChatThread], query: String) -> [ChatThread] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return threads }
        return threads.filter {
            $0.title.localizedCaseInsensitiveContains(value)
                || ($0.lastMessage?.localizedCaseInsensitiveContains(value) ?? false)
        }
    }

    static func group(
        _ threads: [ChatThread],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ChatHistorySection] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday
        let grouped = Dictionary(grouping: threads) { thread in
            if thread.updatedAt >= startOfToday { return Kind.today }
            if thread.updatedAt >= startOfYesterday { return Kind.yesterday }
            if thread.updatedAt >= startOfWeek { return Kind.week }
            return Kind.older
        }
        return Kind.allCases.compactMap { kind in
            guard let threads = grouped[kind], !threads.isEmpty else { return nil }
            return ChatHistorySection(kind: kind, threads: threads)
        }
    }
}

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    @State private var editor: ProviderEditor?

    var body: some View {
        NavigationStack {
            Group {
                if model.providers.isEmpty {
                    ContentUnavailableView {
                        Label("Нет провайдеров", systemImage: "network")
                    } description: {
                        Text("Добавьте endpoint с поддержкой Responses API.")
                    } actions: {
                        Button("Добавить OpenAI") { editor = .newOpenAI }
                            .buttonStyle(.borderedProminent)
                            .tint(BaselineTheme.accent)
                            .foregroundStyle(BaselineTheme.shell)
                    }
                } else {
                    List {
                        Section {
                            HStack(spacing: 14) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(BaselineTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(BaselineTheme.accent.opacity(0.08), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Responses API")
                                        .font(.headline)
                                    Text("Модели доступны в меню заголовка чата")
                                        .font(.caption)
                                        .foregroundStyle(BaselineTheme.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)

                        Section {
                            ForEach(model.providers) { provider in
                                HStack(spacing: 12) {
                                    Button {
                                        Task { await model.selectProvider(id: provider.id) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: provider.isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(provider.isSelected ? BaselineTheme.accent : BaselineTheme.muted)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(provider.model)
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(BaselineTheme.ink)
                                                Text(provider.name)
                                                    .font(.caption)
                                                    .foregroundStyle(BaselineTheme.secondary)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button { editor = ProviderEditor(configuration: provider) } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(BaselineTheme.secondary)
                                    .accessibilityLabel("Изменить \(provider.name)")
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await model.deleteProvider(provider) }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text("POST /responses · локальный контекст · store: false")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .background(BaselineTheme.shell)
            .navigationTitle("Провайдеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = .newOpenAI } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить провайдера")
                }
            }
            .sheet(item: $editor) { editor in
                ProviderEditorView(model: model, editor: editor)
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("Закрыть") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Неизвестная ошибка")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

struct ProviderEditor: Identifiable {
    let configuration: ProviderConfiguration
    var id: UUID { configuration.id }

    static var newOpenAI: ProviderEditor {
        ProviderEditor(configuration: ProviderConfiguration(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.6"
        ))
    }
}

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    let original: ProviderConfiguration
    @State private var name: String
    @State private var baseURL: String
    @State private var modelID: String
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var saveError: String?

    init(model: ChatModel, editor: ProviderEditor) {
        self.model = model
        original = editor.configuration
        _name = State(initialValue: editor.configuration.name)
        _baseURL = State(initialValue: editor.configuration.baseURL)
        _modelID = State(initialValue: editor.configuration.model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .foregroundStyle(BaselineTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Responses API")
                                .font(.headline)
                            Text("POST /responses")
                                .font(.caption.monospaced())
                                .foregroundStyle(BaselineTheme.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Responses API") {
                    TextField("Название", text: $name)
                    TextField("Базовый URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Модель", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField("API-ключ", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Пустое поле сохраняет текущий ключ. Ключ хранится в Keychain.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(BaselineTheme.shell)
            .navigationTitle(original.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            var configuration = original
                            configuration.name = name
                            configuration.baseURL = baseURL
                            configuration.model = modelID
                            if await model.saveProvider(configuration, apiKey: apiKey) {
                                dismiss()
                            } else {
                                saveError = model.errorMessage
                                model.errorMessage = nil
                            }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Ошибка", isPresented: saveErrorBinding) {
                Button("Закрыть") { saveError = nil }
            } message: {
                Text(saveError ?? "Не удалось сохранить провайдера")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }
}
