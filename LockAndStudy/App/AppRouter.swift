import Foundation

enum AppTab: Hashable { case home, library, records, settings }

struct StudySessionPresentation: Identifiable, Equatable {
  let id: UUID
  let packID: StudyPackID
  let packTitle: String
  let mode: StudyMode
  let prompts: [StudyPrompt]
  let bundleID: UUID?
}

