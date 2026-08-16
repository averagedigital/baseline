import AthleteStore
import SwiftUI

enum OpenAIProvider {
    enum Model: String, CaseIterable, Identifiable {
        case gpt56Sol = "gpt-5.6-sol"
        case gpt56Terra = "gpt-5.6-terra"
        case gpt56Luna = "gpt-5.6-luna"
        case gpt55 = "gpt-5.5"
        case gpt55Pro = "gpt-5.5-pro"
        case gpt54 = "gpt-5.4"
        case gpt54Pro = "gpt-5.4-pro"
        case gpt54Mini = "gpt-5.4-mini"
        case gpt54Nano = "gpt-5.4-nano"

        var id: String { rawValue }
        var reasoningEfforts: [ProviderReasoningEffort] {
            switch self {
            case .gpt55Pro, .gpt54Pro: [.medium, .high, .xhigh]
            case .gpt56Sol, .gpt56Terra, .gpt56Luna: ProviderReasoningEffort.allCases
            default: [.off, .low, .medium, .high, .xhigh]
            }
        }
    }

    static let models = Model.allCases
    static let name = "OpenAI"
    static let baseURL = "https://api.openai.com/v1"

    static func normalize(_ configuration: ProviderConfiguration) -> ProviderConfiguration {
        let wasOpenAI = configuration.capabilities == .openAI
        let model = Model(rawValue: configuration.model) ?? .gpt56Sol
        let reasoningEffort = model.reasoningEfforts.contains(configuration.reasoningEffort) ? configuration.reasoningEffort : .medium
        return ProviderConfiguration(
            id: configuration.id,
            name: name,
            baseURL: baseURL,
            model: model.rawValue,
            isSelected: true,
            capabilities: .openAI,
            webSearchEnabled: wasOpenAI ? configuration.webSearchEnabled : true,
            reasoningEffort: reasoningEffort
        )
    }
}

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
                            editor = provider
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
                    if model.providers.isEmpty {
                        Button {
                            editor = OpenAIProvider.normalize(ProviderConfiguration(
                                name: OpenAIProvider.name,
                                baseURL: OpenAIProvider.baseURL,
                                model: OpenAIProvider.Model.gpt56Sol.rawValue,
                                capabilities: .openAI,
                                webSearchEnabled: true,
                                reasoningEffort: .medium
                            ))
                        } label: {
                            Label("Настроить OpenAI", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("OpenAI")
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
    @State private var selectedModel: OpenAIProvider.Model
    @State private var apiKey = ""
    @State private var webSearchEnabled: Bool
    @State private var reasoningEffort: ProviderReasoningEffort

    init(model: ChatModel, provider: ProviderConfiguration) {
        self.model = model
        self.provider = provider
        _selectedModel = State(initialValue: OpenAIProvider.Model(rawValue: provider.model) ?? .gpt56Sol)
        _webSearchEnabled = State(initialValue: provider.webSearchEnabled)
        _reasoningEffort = State(initialValue: provider.reasoningEffort)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Провайдер") {
                    LabeledContent("Провайдер", value: OpenAIProvider.name)
                    Picker("Модель", selection: $selectedModel) {
                        ForEach(OpenAIProvider.models) { model in Text(model.rawValue).tag(model) }
                    }
                    SecureField("API key", text: $apiKey)
                }
                Section("Возможности") {
                    Toggle("Web search", isOn: $webSearchEnabled).disabled(!provider.capabilities.supportsWebSearch)
                    Picker("Reasoning", selection: $reasoningEffort) { ForEach(selectedModel.reasoningEfforts, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Text("Vision \(provider.capabilities.supportsVision ? "✓" : "—") · Tools \(provider.capabilities.supportsFunctionCalling ? "✓" : "—")")
                        .font(.footnote).foregroundStyle(BaselineTheme.secondary)
                }
                Text("Ключ хранится только в Keychain устройства. Запросы идут напрямую к выбранному совместимому Responses API.")
                    .font(.footnote)
                    .foregroundStyle(BaselineTheme.secondary)
            }
            .navigationTitle("Настройка")
            .onChange(of: selectedModel) { _, model in
                if !model.reasoningEfforts.contains(reasoningEffort) { reasoningEffort = .medium }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let value = ProviderConfiguration(id: provider.id, name: OpenAIProvider.name, baseURL: OpenAIProvider.baseURL, model: selectedModel.rawValue, isSelected: true, capabilities: .openAI, webSearchEnabled: webSearchEnabled, reasoningEffort: reasoningEffort)
                        Task { await model.saveProvider(value, apiKey: apiKey); dismiss() }
                    }
                    .disabled(!model.providers.contains(where: { $0.id == provider.id }) && apiKey.isEmpty)
                }
            }
        }
    }
}
