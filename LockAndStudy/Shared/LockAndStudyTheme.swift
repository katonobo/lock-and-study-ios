import SwiftUI

enum LockAndStudyTheme {
  static let teal = Color(red: 0.08, green: 0.42, blue: 0.44)
  static let mint = Color(red: 0.48, green: 0.84, blue: 0.72)
  static let navy = Color(red: 0.05, green: 0.15, blue: 0.22)
  static let warm = Color(red: 0.94, green: 0.69, blue: 0.35)
  static let brand = teal
  static let accent = mint
  static let vocabulary = Color.indigo
  static let takken = Color.orange
  static let cornerRadius: CGFloat = 18
}

struct StudyCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LockAndStudyTheme.cornerRadius, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: LockAndStudyTheme.cornerRadius, style: .continuous))
  }
}

struct PrimaryActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 52)
      .foregroundStyle(.white)
      .background(LockAndStudyTheme.teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
  }
}

struct SecondaryActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 52)
      .foregroundStyle(LockAndStudyTheme.teal)
      .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LockAndStudyTheme.teal.opacity(0.35)))
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.45)
  }
}

extension View {
  func studyCard() -> some View { modifier(StudyCardModifier()) }
  func primaryActionStyle() -> some View { buttonStyle(PrimaryActionButtonStyle()) }
  func secondaryActionStyle() -> some View { buttonStyle(SecondaryActionButtonStyle()) }
}
