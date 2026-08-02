import AthleteCore
import SwiftUI

struct DashboardView: View {
    let state: DashboardState

    var body: some View {
        ZStack {
            BaselineTheme.shell.ignoresSafeArea()
            Circle()
                .fill(BaselineTheme.violet.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 170, y: -310)
                .accessibilityHidden(true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    brand
                    focus
                    evidence
                    dataGap
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(BaselineTheme.ink)
    }

    private var brand: some View {
        HStack(alignment: .center) {
            Text("BASELINE")
                .font(.system(size: 24, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(BaselineTheme.accent)
                .tracking(0.5)
            Spacer()
            Text("ДЕМО-ДАННЫЕ")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(BaselineTheme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay {
                    Capsule().stroke(BaselineTheme.line, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("МОДЕЛЬ СПОРТСМЕНА / СЕГОДНЯ")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(BaselineTheme.muted)
                Text("ТЕКУЩИЙ\nФОКУС")
                    .font(.system(size: 42, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(-1.2)
                    .lineSpacing(-7)
            }

            Text(state.focus)
                .font(.system(size: 21, weight: .semibold))
                .lineSpacing(4)

            HStack(spacing: 8) {
                Circle()
                    .fill(BaselineTheme.accent)
                    .frame(width: 7, height: 7)
                Text(state.updatedAt.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(BaselineTheme.secondary)
            }

            Divider().overlay(BaselineTheme.line)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ПОКРЫТИЕ")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(BaselineTheme.accent)
                Text(state.coverage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BaselineTheme.secondary)
            }
        }
        .padding(20)
        .baselinePanel(radius: 24)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ДОКАЗАТЕЛЬНАЯ ЛЕНТА")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(BaselineTheme.muted)

            ForEach(state.entries) { entry in
                EvidenceRow(entry: entry)
            }
        }
    }

    private var dataGap: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(BaselineTheme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("ПРОБЕЛ В ДАННЫХ")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(BaselineTheme.accent)
                Text(state.dataGap)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BaselineTheme.secondary)
            }
        }
        .padding(16)
        .baselinePanel(radius: 16)
    }
}

private struct EvidenceRow: View {
    let entry: DashboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(roleColor)
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 8) {
                Text(roleLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(roleColor)
                Text(entry.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineSpacing(3)
                Text(entry.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(BaselineTheme.secondary)
                    .lineSpacing(3)
                if let artifactID = entry.artifactID {
                    Text("CALC / \(artifactID.uuidString.suffix(8))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(BaselineTheme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .baselinePanel(radius: 16)
        .accessibilityElement(children: .combine)
    }

    private var roleLabel: String {
        switch entry.role {
        case .observed: "ИЗМЕРЕНО"
        case .computed: "ВЫЧИСЛЕНО"
        case .inferred: "ГИПОТЕЗА"
        case .userReported: "СЛОВА СПОРТСМЕНА"
        }
    }

    private var roleColor: Color {
        switch entry.role {
        case .observed, .computed: BaselineTheme.accent
        case .inferred: BaselineTheme.violet
        case .userReported: BaselineTheme.ink.opacity(0.72)
        }
    }
}

#Preview {
    DashboardView(state: SampleDashboard.fixture)
}
