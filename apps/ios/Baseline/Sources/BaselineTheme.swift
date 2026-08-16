import SwiftUI

enum BaselineTheme {
    static let canvas = Color(red: 246 / 255, green: 247 / 255, blue: 249 / 255)
    static let surface = Color.white
    static let ink = Color(red: 17 / 255, green: 19 / 255, blue: 24 / 255)
    static let secondary = Color(red: 102 / 255, green: 112 / 255, blue: 133 / 255)
    static let muted = Color(red: 152 / 255, green: 162 / 255, blue: 179 / 255)
    static let border = Color(red: 228 / 255, green: 231 / 255, blue: 236 / 255)
    static let accent = Color(red: 36 / 255, green: 87 / 255, blue: 1)
    static let accentSoft = Color(red: 236 / 255, green: 241 / 255, blue: 1)
    static let success = Color(red: 21 / 255, green: 122 / 255, blue: 85 / 255)
    static let successSoft = Color(red: 234 / 255, green: 247 / 255, blue: 241 / 255)
    static let warning = Color(red: 168 / 255, green: 103 / 255, blue: 28 / 255)
    static let warningSoft = Color(red: 255 / 255, green: 246 / 255, blue: 232 / 255)
    static let danger = Color(red: 199 / 255, green: 61 / 255, blue: 77 / 255)
    static let dangerSoft = Color(red: 255 / 255, green: 238 / 255, blue: 241 / 255)

    // Names retained for the reference chat/settings surface.
    static let shell = canvas
    static let raised = accentSoft
    static let panel = surface
    static let line = border

    static let compactAnimation = Animation.easeOut(duration: 0.20)
    static let standardAnimation = Animation.easeOut(duration: 0.24)
}

extension View {
    func baselineCard(radius: CGFloat = 20) -> some View {
        background(BaselineTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BaselineTheme.border, lineWidth: 1)
            }
    }

    func baselinePage() -> some View {
        background(BaselineTheme.canvas.ignoresSafeArea())
            .foregroundStyle(BaselineTheme.ink)
    }
}

struct BaselinePrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                BaselineTheme.accent.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(reduceMotion ? nil : BaselineTheme.compactAnimation, value: configuration.isPressed)
    }
}

struct BaselineSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(BaselineTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(BaselineTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BaselineTheme.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : BaselineTheme.compactAnimation, value: configuration.isPressed)
    }
}
