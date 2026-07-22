#if DEBUG
  import Foundation

  @MainActor
  extension AppModel {
    func seedReportUITestData() async throws {
      let now = Date()
      let vocabularySession = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
      let takkenSession = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
      let fixtures: [StudyAnswerRecord] = [
        .init(
          submissionID: "ui-report-vocabulary", experienceID: .vocabulary,
          packID: "english3000.v1", moduleType: .vocabulary, itemID: "ui-word",
          prompt: "学習レポート用英単語", choices: [.init(id: 0, text: "意味")],
          selectedChoiceID: 0, correctChoiceID: 0, shortExplanation: "説明",
          longExplanation: "説明", sourceNote: nil, category: "level0", subcategory: "名詞",
          contentVersion: "ui", questionVersion: 1, examYear: nil, lawBasisDate: nil,
          answeredAt: now.addingTimeInterval(-3_600), mode: .unlock,
          sessionID: vocabularySession, feedbackPlan: .immediate,
          learningRole: .newItem, wasNewAtSubmission: true, wasDueAtSubmission: false),
        .init(
          submissionID: "ui-report-takken-wrong", experienceID: .takken,
          packID: "takken2026.v1", moduleType: .takken, itemID: "ui-takken",
          prompt: "学習レポート用宅建",
          choices: [
            .init(id: 0, text: "誤り"), .init(id: 1, text: "正しい"),
          ],
          selectedChoiceID: 0, correctChoiceID: 1, shortExplanation: "説明",
          longExplanation: "説明", sourceNote: nil, category: "宅建業法", subcategory: "免許",
          contentVersion: "ui", questionVersion: 1, examYear: 2026,
          lawBasisDate: "2026-04-01", answeredAt: now.addingTimeInterval(-1_900),
          mode: .practice, sessionID: takkenSession, feedbackPlan: .relearn6,
          difficulty: "基礎", questionFormat: TakkenQuestionFormat.trueFalse.rawValue,
          learningRole: .newItem, wasNewAtSubmission: true,
          wasDueAtSubmission: false, conceptID: "ui-takken-concept", variantID: "base",
          attemptNumber: 1, wasFirstAttempt: true),
        .init(
          submissionID: "ui-report-takken-correct", experienceID: .takken,
          packID: "takken2026.v1", moduleType: .takken, itemID: "ui-takken",
          prompt: "学習レポート用宅建",
          choices: [
            .init(id: 0, text: "誤り"), .init(id: 1, text: "正しい"),
          ],
          selectedChoiceID: 1, correctChoiceID: 1, shortExplanation: "説明",
          longExplanation: "説明", sourceNote: nil, category: "宅建業法", subcategory: "免許",
          contentVersion: "ui", questionVersion: 1, examYear: 2026,
          lawBasisDate: "2026-04-01", answeredAt: now.addingTimeInterval(-1_800),
          mode: .practice, sessionID: takkenSession, feedbackPlan: .immediate,
          difficulty: "基礎", questionFormat: TakkenQuestionFormat.trueFalse.rawValue,
          learningRole: .generalReview, wasNewAtSubmission: false,
          wasDueAtSubmission: false, conceptID: "ui-takken-concept", variantID: "base",
          attemptNumber: 2, wasFirstAttempt: false),
      ]
      for fixture in fixtures { _ = try await dependencies.learning.recordUnique(fixture) }
      try await dependencies.learning.record(
        .init(
          id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
          kind: .unlockChallengeStarted, occurredAt: now.addingTimeInterval(-3_700),
          packID: "english3000.v1", sessionID: vocabularySession, unlockOrigin: .shield))
      try await dependencies.learning.record(
        .init(
          id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
          kind: .unlockSuccess, occurredAt: now.addingTimeInterval(-3_500),
          packID: "english3000.v1", sessionID: vocabularySession, unlockOrigin: .shield))
    }
  }
#endif
