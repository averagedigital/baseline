import AthleteStore
import SwiftUI

struct FoodDiaryView: View {
    @Environment(\.dismiss) private var dismiss
    let localServices: LocalDeviceServices
    let onOpenThread: (ChatThread) -> Void
    @State private var day = Date()
    @State private var entries: [FoodEntry] = []
    @State private var selectedEntry: FoodEntry?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("День", selection: $day, displayedComponents: .date)
                    HStack {
                        metric("Ккал", total(\.caloriesKcal))
                        metric("Белки", total(\.proteinG))
                        metric("Жиры", total(\.fatG))
                        metric("Углеводы", total(\.carbohydratesG))
                    }
                }
                Section("Записи") {
                    if entries.isEmpty {
                        ContentUnavailableView("Записей нет", systemImage: "fork.knife", description: Text("Добавьте приём пищи через Coach."))
                    }
                    ForEach(entries) { entry in
                        Button { selectedEntry = entry } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.mealType.title).font(.headline)
                                    Spacer()
                                    Text(entry.consumedAt, style: .time).foregroundStyle(.secondary)
                                }
                                Text(entry.items.map(\.name).joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Рацион")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .task(id: day) { await reload() }
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailView(localServices: localServices, entry: entry, onChanged: { await reload() }, onOpenThread: { thread in
                    selectedEntry = nil
                    dismiss()
                    onOpenThread(thread)
                })
            }
            .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Закрыть") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Неизвестная ошибка") }
        }
    }

    private func reload() async {
        let interval = Calendar.current.dateInterval(of: .day, for: day)
        guard let interval else { return }
        do { entries = try await localServices.foodEntries(from: interval.start, to: interval.end) }
        catch { errorMessage = "Не удалось загрузить рацион." }
    }

    private func total(_ keyPath: KeyPath<FoodItemDraft, EstimatedValue>) -> String {
        var low = 0.0; var high = 0.0; var hasValue = false
        for value in entries.flatMap(\.items).map({ $0.value[keyPath: keyPath] }) {
            switch value {
            case let .exact(number): low += number; high += number; hasValue = true
            case let .range(minimum, maximum): low += minimum; high += maximum; hasValue = true
            case .unknown: break
            }
        }
        guard hasValue else { return "—" }
        return abs(low - high) < 0.01 ? String(format: "%.0f", low) : String(format: "%.0f–%.0f", low, high)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FoodEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let localServices: LocalDeviceServices
    let entry: FoodEntry
    let onChanged: () async -> Void
    let onOpenThread: (ChatThread) -> Void
    @State private var consumedAt: Date
    @State private var mealType: MealType
    @State private var notes: String
    @State private var confirmsDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(localServices: LocalDeviceServices, entry: FoodEntry, onChanged: @escaping () async -> Void, onOpenThread: @escaping (ChatThread) -> Void) {
        self.localServices = localServices; self.entry = entry; self.onChanged = onChanged; self.onOpenThread = onOpenThread
        _consumedAt = State(initialValue: entry.consumedAt); _mealType = State(initialValue: entry.mealType); _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Приём пищи") {
                    DatePicker("Время", selection: $consumedAt)
                    Picker("Тип", selection: $mealType) { ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) } }
                    TextField("Заметка", text: $notes, axis: .vertical)
                }
                Section("Состав") {
                    ForEach(entry.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).font(.headline)
                            Text("Ккал \(item.value.caloriesKcal.label) · Б \(item.value.proteinG.label) · Ж \(item.value.fatG.label) · У \(item.value.carbohydratesG.label)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Источник: \(item.value.provenance.rawValue)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if entry.linkedChatMessageID != nil {
                    Section("Источник") { Button("Открыть сообщение Coach") { Task { await openSource() } } }
                }
                Section { Button("Удалить запись", role: .destructive) { confirmsDelete = true } }
            }
            .navigationTitle("Запись")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { Task { await save() } }.disabled(isSaving) }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { Task { await delete() } }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("Закрыть") { errorMessage = nil } } message: { Text(errorMessage ?? "Неизвестная ошибка") }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            _ = try await localServices.updateFoodEntry(id: entry.id, patch: .init(consumedAt: consumedAt, mealType: mealType, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
            await onChanged(); dismiss()
        } catch { errorMessage = "Не удалось обновить запись." }
    }

    private func delete() async {
        do { try await localServices.deleteFoodEntry(id: entry.id); await onChanged(); dismiss() }
        catch { errorMessage = "Не удалось удалить запись." }
    }

    private func openSource() async {
        guard let messageID = entry.linkedChatMessageID else { return }
        do { if let thread = try await localServices.chatThread(containingMessageID: messageID) { onOpenThread(thread) } }
        catch { errorMessage = "Исходный диалог недоступен." }
    }
}

private extension EstimatedValue {
    var label: String {
        switch self {
        case let .exact(value): String(format: "%.0f", value)
        case let .range(low, high): String(format: "%.0f–%.0f", low, high)
        case .unknown: "—"
        }
    }
}

private extension MealType {
    static var allCases: [MealType] { [.breakfast, .lunch, .dinner, .snack, .other] }
    var title: String { switch self { case .breakfast: "Завтрак"; case .lunch: "Обед"; case .dinner: "Ужин"; case .snack: "Перекус"; case .other: "Другое" } }
}
