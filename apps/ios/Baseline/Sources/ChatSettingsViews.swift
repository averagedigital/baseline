import AthleteStore
import SwiftUI

struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    @State private var showsProviders = false

    var body: some View {
        NavigationStack {
            Group {
                if model.threads.isEmpty {
                    ContentUnavailableView("История пуста", systemImage: "bubble.left")
                } else {
                    List {
                        ForEach(model.threads) { thread in
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
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(thread.title)
                                        .lineLimit(2)
                                        .foregroundStyle(BaselineTheme.ink)
                                    Text(thread.updatedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(BaselineTheme.secondary)
                                }
                                .padding(.vertical, 4)
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
                    .scrollContentBackground(.hidden)
                }
            }
            .background(BaselineTheme.shell)
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsProviders = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Провайдеры")
                }
            }
            .sheet(isPresented: $showsProviders) {
                ProviderSettingsView(model: model)
            }
        }
        .preferredColorScheme(.dark)
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
                            ForEach(model.providers) { provider in
                                HStack(spacing: 12) {
                                    Button {
                                        Task { await model.selectProvider(id: provider.id) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: provider.isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(provider.isSelected ? BaselineTheme.accent : BaselineTheme.muted)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(provider.name)
                                                    .foregroundStyle(BaselineTheme.ink)
                                                Text(provider.model)
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

private struct ProviderEditor: Identifiable {
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

private struct ProviderEditorView: View {
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
