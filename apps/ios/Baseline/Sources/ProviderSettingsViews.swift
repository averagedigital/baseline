import AthleteStore
import SwiftUI

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    @State private var editor: ProviderConfiguration?
    @State private var confirmsPersonalizationReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.providers) { provider in
                        Button {
                            Task { await model.selectProvider(provider); dismiss() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(provider.name).foregroundStyle(BaselineTheme.ink)
                                    Text("\(provider.model) · \(provider.baseURL)")
                                        .font(.caption)
                                        .foregroundStyle(BaselineTheme.secondary)
                                }
                                Spacer()
                                if provider.id == model.selectedProviderID { Image(systemName: "checkmark") }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await model.deleteProvider(provider) } } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }
                Section("Персонализация") {
                    Button("Сбросить обученные данные", role: .destructive) { confirmsPersonalizationReset = true }
                }
                Section {
                    Button { editor = ProviderConfiguration(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-5.4", capabilities: .openAI, webSearchEnabled: true, reasoningEffort: .medium) } label: {
                        Label("Добавить провайдера", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Провайдеры")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .sheet(item: $editor) { provider in
                ProviderEditorView(model: model, provider: provider)
            }
            .confirmationDialog("Сбросить персонализацию?", isPresented: $confirmsPersonalizationReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { Task { await model.resetPersonalization() } }
            } message: {
                Text("Будут удалены локальные персональные baseline, прототипы упражнений и обученные рекомендации.")
            }
        }
    }
}

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel
    let provider: ProviderConfiguration
    @State private var name: String
    @State private var baseURL: String
    @State private var modelName: String
    @State private var apiKey = ""
    @State private var webSearchEnabled: Bool
    @State private var reasoningEffort: ProviderReasoningEffort

    init(model: ChatModel, provider: ProviderConfiguration) {
        self.model = model
        self.provider = provider
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _modelName = State(initialValue: provider.model)
        _webSearchEnabled = State(initialValue: provider.webSearchEnabled)
        _reasoningEffort = State(initialValue: provider.reasoningEffort)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Провайдер") {
                    TextField("Название", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Модель", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $apiKey)
                }
                Section("Возможности") {
                    Toggle("Web search", isOn: $webSearchEnabled).disabled(!provider.capabilities.supportsWebSearch)
                    Picker("Reasoning", selection: $reasoningEffort) { ForEach(ProviderReasoningEffort.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.disabled(!provider.capabilities.supportsReasoning)
                    Text("Vision \(provider.capabilities.supportsVision ? "✓" : "—") · Tools \(provider.capabilities.supportsFunctionCalling ? "✓" : "—")")
                        .font(.footnote).foregroundStyle(BaselineTheme.secondary)
                }
                Text("Ключ хранится только в Keychain устройства. Запросы идут напрямую к выбранному совместимому Responses API.")
                    .font(.footnote)
                    .foregroundStyle(BaselineTheme.secondary)
            }
            .navigationTitle("Настройка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let value = ProviderConfiguration(id: provider.id, name: name, baseURL: baseURL, model: modelName, isSelected: true, capabilities: provider.capabilities, webSearchEnabled: webSearchEnabled, reasoningEffort: reasoningEffort)
                        Task { await model.saveProvider(value, apiKey: apiKey); dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.isEmpty)
                }
            }
        }
    }
}
