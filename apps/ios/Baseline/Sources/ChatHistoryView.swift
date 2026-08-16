import AthleteStore
import SwiftUI

struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.threads) { thread in
                    Button {
                        Task { await model.openChat(thread); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(thread.title).foregroundStyle(BaselineTheme.ink)
                            Text(thread.lastMessage ?? "Новый диалог")
                                .font(.caption)
                                .foregroundStyle(BaselineTheme.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await model.deleteChat(thread) } } label: { Label("Удалить", systemImage: "trash") }
                    }
                }
            }
            .overlay {
                if model.threads.isEmpty { ContentUnavailableView("История пуста", systemImage: "bubble.left.and.bubble.right") }
            }
            .navigationTitle("История")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .task { await model.refreshThreads() }
        }
    }
}
