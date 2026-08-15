import Foundation
import Observation
import SwiftUI

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
    var draft = ""
    var isSending = false
    var errorMessage: String?

    private let backend: BackendAPIClient
    private let feedbackContext: PersonalizationContext
    private var threadID: UUID?

    init(backend: BackendAPIClient, feedbackContext: PersonalizationContext) {
        self.backend = backend
        self.feedbackContext = feedbackContext
    }

    func send(_ value: String? = nil) async {
        let text = (value ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        messages.append(CoachMessage(role: .user, text: text))
        draft = ""
        isSending = true
        errorMessage = nil
        do {
            let response = try await backend.chat(threadID: threadID, message: text)
            threadID = response.threadID
            messages.append(CoachMessage(
                role: .assistant,
                text: response.answerMarkdown,
                recommendationCategory: response.recommendationCategory,
                feedbackContextID: response.feedbackContextID
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
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
            _ = try await backend.sendRecommendationReward(
                feedbackContextID: feedbackContextID,
                reward: Double(value),
                context: feedbackContext
            )
        } catch {
            messages[index].rating = nil
            errorMessage = "Не удалось сохранить оценку совета."
        }
    }
}

struct CoachScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ChatModel
    private let initialPrompt: String?

    init(
        backend: BackendAPIClient,
        feedbackContext: PersonalizationContext,
        initialPrompt: String? = nil
    ) {
        _model = State(initialValue: ChatModel(backend: backend, feedbackContext: feedbackContext))
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
                                Text("Собираю контекст и проверяю ссылки на данные")
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
            .baselinePage()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .task {
                guard let initialPrompt, model.messages.isEmpty else { return }
                await model.send(initialPrompt)
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
            Text("Разбор по вашим данным")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Coach получает сохранённые сессии, явный RPE, последние наблюдения еды и состояние персонализации. При пробеле в данных он должен сказать об этом, а не додумывать.")
                .font(.body)
                .foregroundStyle(BaselineTheme.secondary)
                .lineSpacing(3)
            VStack(spacing: 10) {
                suggestion("Разбери последнюю тренировку")
                suggestion("Что сейчас важнее: нагрузка или восстановление?")
                suggestion("Каких данных тебе не хватает для полезного вывода?")
            }
        }
        .padding(.top, 36)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            Task { await model.send(text) }
        } label: {
            HStack {
                Text(text)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(BaselineTheme.secondary)
            }
        }
        .buttonStyle(BaselineSecondaryButtonStyle())
    }

    @ViewBuilder
    private func messageRow(_ message: CoachMessage) -> some View {
        if message.role == .user {
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(BaselineTheme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text("B")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(BaselineTheme.ink, in: Circle())
                    Text(message.text)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .padding(.leading, 38)
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
            TextField("Сообщение Coach", text: $bindableModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(BaselineTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BaselineTheme.border, lineWidth: 1)
                }
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
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(BaselineTheme.canvas)
    }
}
