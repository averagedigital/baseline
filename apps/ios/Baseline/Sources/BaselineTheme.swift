import SwiftUI

enum BaselineTheme {
    static let shell = Color(red: 13 / 255, green: 16 / 255, blue: 19 / 255)
    static let panel = Color(red: 23 / 255, green: 28 / 255, blue: 33 / 255)
    static let raised = Color(red: 29 / 255, green: 35 / 255, blue: 41 / 255)
    static let ink = Color(red: 249 / 255, green: 245 / 255, blue: 242 / 255)
    static let secondary = Color(red: 197 / 255, green: 195 / 255, blue: 200 / 255)
    static let muted = Color(red: 131 / 255, green: 136 / 255, blue: 145 / 255)
    static let accent = Color(red: 249 / 255, green: 204 / 255, blue: 115 / 255)
    static let violet = Color(red: 133 / 255, green: 132 / 255, blue: 189 / 255)
    static let line = Color.white.opacity(0.10)
}

extension View {
    func baselinePanel(radius: CGFloat = 20) -> some View {
        background(BaselineTheme.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BaselineTheme.line, lineWidth: 1)
            }
    }
}
