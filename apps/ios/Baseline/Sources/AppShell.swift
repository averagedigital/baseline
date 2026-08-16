import SwiftUI

struct AppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CameraModel()
    @State private var selectedTab = AppTab.camera

    var body: some View {
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
            model.setFoodScanEnabled(selectedTab == .camera)
        }
        .onChange(of: selectedTab) { _, tab in
            model.setFoodScanEnabled(tab == .camera)
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

enum AppTab: Hashable, CaseIterable {
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
                isMirrored: model.cameraPosition == .front,
                nutritionByLabel: model.foodDetailsByLabel
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                        model.lockSubject(at: CGPoint(x: location.x / geometry.size.width, y: location.y / geometry.size.height))
                    }
            }
            .ignoresSafeArea()

            VStack {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.trackingTone)
                            .frame(width: 6, height: 6)
                        Text(model.cameraPosition == .front ? "ФРОНТАЛЬНАЯ" : "ОСНОВНАЯ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                    }
                    Spacer()
                    if model.trackingState == .multiplePeople
                        || model.metricExclusionReason == .identityDiscontinuity {
                        Button("Перезафиксировать") {
                            model.resetSubjectLock()
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                    }
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
                    Text(model.trackingLabel.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(model.trackingTone)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 2)
                }

                if let feedback = model.pendingFeedback {
                    CompactRPEOverlay(model: model, feedback: feedback)
                } else {
                    bottomHUD
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var bottomHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ИНТЕНСИВНОСТЬ")
                Spacer()
                Text("АКТИВНЫЕ БЛОКИ")
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.8))

            HStack(alignment: .bottom, spacing: 14) {
                MotionIntensityChart(history: model.intensityHistory)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                Text("\(model.liveSetCount)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 54, alignment: .trailing)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(BaselineTheme.success)
                    .frame(width: 6, height: 6)
                Text("АВТОЗАПИСЬ · \(duration(model.recordingElapsed))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Spacer()
                if model.foodDetectorAvailability != .available {
                    Text("ЕДА НЕДОСТУПНА")
                        .foregroundStyle(BaselineTheme.warning)
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(12)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 10)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct CompactRPEOverlay: View {
    let model: CameraModel
    let feedback: PendingSessionFeedback

    @State private var rpe = 7.0
    @State private var note = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Как ощущалась тренировка?")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "RPE %.0f", rpe))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            Slider(value: $rpe, in: 1...10, step: 1)
                .tint(BaselineTheme.accent)
            TextField("Комментарий, необязательно", text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Пропустить") {
                    model.pendingFeedback = nil
                }
                .foregroundStyle(BaselineTheme.secondary)
                Spacer()
                Button {
                    isSubmitting = true
                    Task {
                        _ = await model.submitRPE(
                            rpe,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            for: feedback
                        )
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting { ProgressView() } else { Text("Сохранить") }
                }
                .disabled(isSubmitting)
            }
        }
        .padding(14)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(BaselineTheme.ink)
        .padding(.top, 10)
    }
}
