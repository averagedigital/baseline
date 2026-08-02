@preconcurrency import AVFoundation
import AthleteSensors
import Observation
import SwiftUI

@MainActor
@Observable
final class CameraModel {
    var samples: [PoseSample] = []
    var trackingState: PoseTrackingState = .lost
    var errorMessage: String?
    var isRunning = false

    let pipeline: CameraPipeline

    init(pipeline: CameraPipeline = CameraPipeline()) {
        self.pipeline = pipeline
        pipeline.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.samples = frame.samples
                self?.trackingState = frame.trackingState
            }
        }
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
            }
        }
    }

    func start() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }
        guard granted else {
            errorMessage = "Нет доступа к камере."
            return
        }
        do {
            try await pipeline.start()
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        pipeline.stop()
        isRunning = false
        samples = []
        trackingState = .lost
    }
}

struct CameraScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = CameraModel()

    var body: some View {
        ZStack {
            CameraPreview(session: model.pipeline.session)
                .ignoresSafeArea()
            Color.black.opacity(0.12).ignoresSafeArea()
            PoseOverlay(samples: model.samples, state: model.trackingState)
                .ignoresSafeArea()

            VStack {
                header
                Spacer()
                status
                control
            }
            .padding(20)
        }
        .background(Color.black)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            Text("КАМЕРА / ЛОКАЛЬНО")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
            Spacer()
            Button("Закрыть", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.46), in: Circle())
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var status: some View {
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58), in: Capsule())
                .foregroundStyle(skeletonColor)
        }
    }

    private var control: some View {
        Button {
            if model.isRunning {
                model.stop()
            } else {
                Task { await model.start() }
            }
        } label: {
            Text(model.isRunning ? "ОСТАНОВИТЬ" : "НАЧАТЬ")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(1)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BaselineTheme.shell)
        .background(BaselineTheme.accent, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 12)
    }

    private var statusLabel: String {
        switch model.trackingState {
        case .stable: "TRACKING СТАБИЛЕН"
        case .degraded: "TRACKING НЕПОЛНЫЙ"
        case .lost: "ТЕЛО НЕ НАЙДЕНО"
        case .multiplePeople: "В КАДРЕ НЕСКОЛЬКО ЛЮДЕЙ"
        }
    }

    private var skeletonColor: Color {
        switch model.trackingState {
        case .stable: .green
        case .degraded, .multiplePeople: BaselineTheme.accent
        case .lost: .clear
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct PoseOverlay: View {
    let samples: [PoseSample]
    let state: PoseTrackingState

    var body: some View {
        Canvas { context, size in
            let points = Dictionary(uniqueKeysWithValues: samples.map {
                ($0.joint, CGPoint(x: $0.point.x * size.width, y: $0.point.y * size.height))
            })
            for bone in bones {
                guard let start = points[bone.0], let end = points[bone.1] else { continue }
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(color), lineWidth: 3)
            }
            for point in points.values {
                let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }

    private var color: Color {
        switch state {
        case .stable: .green
        case .degraded, .multiplePeople: BaselineTheme.accent
        case .lost: .clear
        }
    }

    private var bones: [(PoseJoint, PoseJoint)] {
        [
            (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.neck, .root), (.root, .leftHip), (.root, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        ]
    }
}
