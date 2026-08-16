import SwiftUI

struct AppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CameraModel()

    var body: some View {
        @Bindable var bindableModel = model

        TabView {
            NavigationStack {
                CameraCard(model: model)
                    .padding(16)
                    .baselinePage()
                    .navigationTitle("Камера")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Камера", systemImage: "camera.fill") }

            CoachScreen(localServices: model.localServices)
                .tabItem { Label("Coach", systemImage: "sparkles") }
        }
        .tint(BaselineTheme.accent)
        .task {
            await model.startCamera()
            model.startWorkout()
        }
        .onChange(of: scenePhase) { _, phase in
            Task { @MainActor in
                switch phase {
                case .active:
                    await model.startCamera()
                    model.startWorkout()
                case .background:
                    await model.stopWorkout()
                    model.stopCamera()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
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
