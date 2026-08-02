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

private struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
}

private struct ChatScreen: View {
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if messages.isEmpty {
                        ContentUnavailableView(
                            "Baseline",
                            systemImage: "sparkles",
                            description: Text("Спросите о тренировке или восстановлении")
                        )
                        .frame(minHeight: 520)
                    }
                    ForEach(messages) { message in
                        Text(message.text)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(BaselineTheme.raised, in: RoundedRectangle(cornerRadius: 20))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(16)
            }
            .background(BaselineTheme.shell)
            .navigationTitle("Чат")
            .safeAreaInset(edge: .bottom) { composer }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Button("Отправить", systemImage: "arrow.up") { send() }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .foregroundStyle(BaselineTheme.shell)
                .background(BaselineTheme.accent, in: Circle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(text: text))
        draft = ""
    }
}
