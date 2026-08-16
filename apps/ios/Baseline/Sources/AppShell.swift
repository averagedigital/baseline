import SwiftUI

struct AppShell: View {
    @State private var model = CameraModel()
    @State private var showsCoach = false
    @State private var showsSettings = false
    @State private var coachPrompt: String?

    var body: some View {
        @Bindable var bindableModel = model

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    CameraCard(model: model)
                    LatestFoodCard(model: model)
                    HomeInsightCard(model: model) {
                        coachPrompt = nil
                        showsCoach = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refreshHome() }
            .baselinePage()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await model.startCamera()
            await model.refreshHome()
        }
        .sheet(isPresented: $showsCoach) {
            CoachScreen(
                localServices: model.localServices,
                initialPrompt: coachPrompt
            )
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(model: model)
        }
        .sheet(item: $bindableModel.pendingFeedback) { feedback in
            SessionFeedbackSheet(feedback: feedback) { value, note in
                await model.submitRPE(value, note: note, for: feedback)
            } onSkip: {
                model.pendingFeedback = nil
            }
        }
        .alert("Baseline", isPresented: errorBinding) {
            Button("Закрыть") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Неизвестная ошибка")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Baseline")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Тренировка, питание и персональный контекст")
                    .font(.caption)
                    .foregroundStyle(BaselineTheme.secondary)
            }
            Spacer()
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BaselineTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(BaselineTheme.surface, in: Circle())
                    .overlay { Circle().stroke(BaselineTheme.border, lineWidth: 1) }
            }
            .accessibilityLabel("Настройки")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct SessionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let feedback: PendingSessionFeedback
    let submit: (Double, String) async -> Bool
    let onSkip: () -> Void

    @State private var rpe = 7.0
    @State private var note = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Как ощущалась тренировка?")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Явный RPE обучает только локальную калибровку сложности. Активные блоки и время он не переписывает.")
                        .font(.subheadline)
                        .foregroundStyle(BaselineTheme.secondary)
                        .lineSpacing(3)
                }

                VStack(spacing: 12) {
                    Text(String(format: "RPE %.0f", rpe))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Slider(value: $rpe, in: 1...10, step: 1)
                        .tint(BaselineTheme.accent)
                    HStack {
                        Text("легко")
                        Spacer()
                        Text("предел")
                    }
                    .font(.caption)
                    .foregroundStyle(BaselineTheme.secondary)
                }
                .padding(18)
                .baselineCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Комментарий, необязательно")
                        .font(.subheadline.weight(.semibold))
                    TextField("Например: присед 100 кг × 5", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(13)
                        .background(BaselineTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BaselineTheme.border, lineWidth: 1)
                        }
                }

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await submit(rpe, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        isSubmitting = false
                        if success { dismiss() }
                    }
                } label: {
                    HStack {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text("Сохранить обратную связь")
                    }
                }
                .buttonStyle(BaselinePrimaryButtonStyle())
                .disabled(isSubmitting)

                Button("Пропустить") {
                    onSkip()
                    dismiss()
                }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(BaselineTheme.secondary)
                    .disabled(isSubmitting)
            }
            .padding(20)
            .baselinePage()
            .navigationTitle("После тренировки")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: CameraModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Камера") {
                    Toggle(
                        "Автоматически определять еду",
                        isOn: Binding(
                            get: { model.foodScanEnabled },
                            set: { model.setFoodScanEnabled($0) }
                        )
                    )
                    Button("Сбросить фиксацию спортсмена") {
                        model.resetSubjectLock()
                    }
                }

                Section("Приватность") {
                    Label("Видео не записывается", systemImage: "video.slash")
                    Label("Session evidence хранится локально", systemImage: "waveform.path.ecg")
                    Label("Изображения камеры обрабатываются только в памяти и не сохраняются", systemImage: "fork.knife")
                }

                Section("Архитектура") {
                    Text("На устройстве: камера, фиксация человека, realtime-метрики, контекст, Coach и персонализация.")
                        .font(.footnote)
                        .foregroundStyle(BaselineTheme.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .baselinePage()
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
