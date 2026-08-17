import MarkdownUI
import SwiftUI

struct CoachMarkdownView: View {
  let markdown: String

  var body: some View {
    Markdown(markdown)
      .markdownTheme(.baselineCoach)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

@MainActor
private var coachHeadingGradient: MeshGradient {
  MeshGradient(
    width: 3,
    height: 2,
    points: [
      [0, 0], [0.5, 0], [1, 0],
      [0, 1], [0.5, 1], [1, 1],
    ],
    colors: [
      BaselineTheme.accent, .purple, BaselineTheme.danger,
      BaselineTheme.success, BaselineTheme.accent, BaselineTheme.warning,
    ]
  )
}

extension Theme {
  @MainActor
  fileprivate static var baselineCoach: Theme {
    Theme()
      .text {
        FontSize(17)
      }
      .strong {
        FontWeight(.bold)
        ForegroundColor(BaselineTheme.accent)
      }
      .emphasis {
        FontStyle(.italic)
        ForegroundColor(BaselineTheme.success)
      }
      .link {
        ForegroundColor(BaselineTheme.accent)
        UnderlineStyle(.single)
      }
      .code {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.9))
        ForegroundColor(BaselineTheme.warning)
        BackgroundColor(BaselineTheme.warningSoft)
      }
      .heading1 { configuration in
        configuration.label
          .foregroundStyle(coachHeadingGradient)
          .markdownTextStyle {
            FontSize(.em(1.55))
            FontWeight(.heavy)
          }
          .markdownMargin(top: .em(0.7), bottom: .em(0.35))
      }
      .heading2 { configuration in
        configuration.label
          .foregroundStyle(coachHeadingGradient)
          .markdownTextStyle {
            FontSize(.em(1.3))
            FontWeight(.bold)
          }
          .markdownMargin(top: .em(0.65), bottom: .em(0.3))
      }
      .heading3 { configuration in
        configuration.label
          .markdownTextStyle {
            FontSize(.em(1.12))
            FontWeight(.bold)
            ForegroundColor(BaselineTheme.success)
          }
          .markdownMargin(top: .em(0.55), bottom: .em(0.25))
      }
      .paragraph { configuration in
        configuration.label
          .fixedSize(horizontal: false, vertical: true)
          .relativeLineSpacing(.em(0.2))
          .markdownMargin(top: .zero, bottom: .em(0.8))
      }
      .blockquote { configuration in
        configuration.label
          .padding(.vertical, 10)
          .padding(.horizontal, 14)
          .markdownTextStyle {
            ForegroundColor(BaselineTheme.accent)
            FontWeight(.medium)
          }
          .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
              .fill(BaselineTheme.accent)
              .frame(width: 4)
          }
          .background(BaselineTheme.accentSoft.opacity(0.75))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .markdownMargin(top: .em(0.25), bottom: .em(0.75))
      }
      .codeBlock { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .markdownTextStyle {
              FontFamilyVariant(.monospaced)
              FontSize(.em(0.88))
              ForegroundColor(Color(red: 0.72, green: 0.84, blue: 1))
              BackgroundColor(nil)
            }
        }
        .background(Color(red: 0.06, green: 0.09, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .markdownMargin(top: .em(0.25), bottom: .em(0.8))
      }
      .bulletedListMarker { _ in
        Circle()
          .fill(BaselineTheme.accent)
          .relativeFrame(width: .em(0.42), height: .em(0.42))
          .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
      }
      .numberedListMarker { configuration in
        Text("\(configuration.itemNumber).")
          .fontWeight(.bold)
          .foregroundStyle(BaselineTheme.accent)
          .monospacedDigit()
          .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
      }
      .taskListMarker { configuration in
        Image(systemName: configuration.isCompleted ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(configuration.isCompleted ? BaselineTheme.success : BaselineTheme.accent)
          .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
      }
      .listItem { configuration in
        configuration.label.markdownMargin(top: .em(0.18))
      }
      .table { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .markdownTableBorderStyle(.init(color: BaselineTheme.border))
            .markdownTableBackgroundStyle(
              .alternatingRows(BaselineTheme.surface, BaselineTheme.accentSoft.opacity(0.55))
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .markdownMargin(top: .em(0.25), bottom: .em(0.8))
      }
      .tableCell { configuration in
        configuration.label
          .markdownTextStyle {
            if configuration.row == 0 {
              FontWeight(.bold)
              ForegroundColor(BaselineTheme.accent)
            }
            BackgroundColor(nil)
          }
          .padding(.vertical, 7)
          .padding(.horizontal, 10)
      }
      .thematicBreak {
        LinearGradient(
          colors: [BaselineTheme.accent, .purple, BaselineTheme.danger],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(height: 2)
        .clipShape(Capsule())
        .markdownMargin(top: .em(0.7), bottom: .em(0.7))
      }
  }
}
