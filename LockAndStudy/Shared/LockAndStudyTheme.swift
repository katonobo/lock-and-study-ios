import SwiftUI

enum LockAndStudyTheme {
  static let brand = Color(red: 0.09, green: 0.42, blue: 0.43)
  static let accent = Color(red: 0.25, green: 0.68, blue: 0.57)
  static let vocabulary = Color.indigo
  static let takken = Color.orange
}

struct StudyCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

extension View { func studyCard() -> some View { modifier(StudyCardModifier()) } }

