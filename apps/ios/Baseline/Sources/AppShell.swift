import SwiftUI

struct AppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CameraModel()
    @State private var selectedTab = AppTab.camera

    var body: some View {
        @Bindable var bindableModel = model

        TabView(selection: $selectedTab) {
            CameraScreen(model: model)
            .tag(AppTab.camera)
            .tabItem { Label("Камера", systemImage: "camera.fill") }

            CoachScreen(localServices: model.localServices)
                .tag(AppTab.chat)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right.fill") }
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

private enum AppTab: Hashable {
    case camera
    case chat
}

private struct CameraScreen: View {
    let model: CameraModel

    var body: some View {
        ZStack {
            CameraPreview(
                session: model.pipeline.session,
                isMirrored: model.cameraPosition == .front
            )
            .ignoresSafeArea()
            PoseOverlay(
                samples: model.samples,
                boundingBox: model.boundingBox,
                state: model.trackingState
            )
            .ignoresSafeArea()
            FoodDetectionOverlay(
                objects: model.foodObjects,
                sourceSize: model.foodSourceSize,
                isMirrored: model.cameraPosition == .front
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(BaselineTheme.success)
                            .frame(width: 6, height: 6)
                        Text(model.cameraPosition == .front ? "ФРОНТАЛЬНАЯ" : "ОСНОВНАЯ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                    }
                    Spacer()
                    Button {
                        Task { await model.switchCamera() }
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Переключить камеру")
                }
                .foregroundStyle(.white)

                Spacer()

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                } else {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(statusColor)
                        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                        .padding(.bottom, 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(BaselineTheme.accent)
                            .frame(width: 5, height: 5)
                            .shadow(color: BaselineTheme.accent.opacity(0.85), radius: 4)
                        Text("ИНТЕНСИВНОСТЬ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    MotionIntensityChart(history: model.intensityHistory)
                        .frame(height: 74)
                }
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var statusLabel: String {
        switch model.trackingState {
        case .stable: "TRACKING СТАБИЛЕН"
        case .degraded: "TRACKING НЕПОЛНЫЙ"
        case .acquiring: "ПОИСК СПОРТСМЕНА"
        case .lost: "ТЕЛО НЕ НАЙДЕНО"
        case .multiplePeople: "В КАДРЕ НЕСКОЛЬКО ЛЮДЕЙ"
        }
    }

    private var statusColor: Color {
        switch model.trackingState {
        case .stable, .degraded, .acquiring, .multiplePeople: BaselineTheme.success
        case .lost: .clear
        }
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
