import XCTest

@testable import LockAndStudy

final class TakkenConceptMasterV17Tests: XCTestCase {
  private let policy = TakkenConceptMasteryPolicy()

  func testUnansweredConceptIsUnlearnedAndLegacyFallsBackToItemID() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    XCTAssertEqual(
      policy.snapshot(conceptID: "new", answers: [], now: now).state,
      .unlearned)

    let legacy = answer(
      itemID: "legacy-item", conceptID: nil, variantID: nil,
      correct: true, sessionID: UUID(), attempt: nil, at: now)
    let snapshot = policy.snapshot(
      conceptID: "legacy-item", answers: [legacy], now: now)
    XCTAssertEqual(snapshot.answerCount, 1)
    XCTAssertEqual(snapshot.state, .learning)
  }

  func testWrongAnswerAndSameSessionRetryDoNotMasterConcept() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let session = UUID()
    let wrong = answer(
      itemID: "q-a", conceptID: "concept", variantID: "a",
      correct: false, sessionID: session, attempt: 1, at: now,
      tags: ["misconception:number"])
    let retry = answer(
      itemID: "q-a", conceptID: "concept", variantID: "a",
      correct: true, sessionID: session, attempt: 2,
      at: now.addingTimeInterval(10))
    let snapshot = policy.snapshot(
      conceptID: "concept", answers: [wrong, retry],
      now: now.addingTimeInterval(20))
    XCTAssertEqual(snapshot.state, .relearning)
    XCTAssertEqual(snapshot.distinctSessionCount, 1)
    XCTAssertEqual(snapshot.weakMisconceptionCodes, Set(["number"]))
  }

  func testDifferentSessionsAndVariantsProgressThroughStabilizingAndMastered() {
    let now = Date(timeIntervalSince1970: 3_000_000)
    let firstSession = UUID()
    let secondSession = UUID()
    let first = answer(
      itemID: "q-a", conceptID: "concept", variantID: "a",
      correct: true, sessionID: firstSession, attempt: 1,
      at: now.addingTimeInterval(-86_400))
    let sameVariant = answer(
      itemID: "q-a", conceptID: "concept", variantID: "a",
      correct: true, sessionID: secondSession, attempt: 1, at: now)
    XCTAssertEqual(
      policy.snapshot(
        conceptID: "concept", answers: [first, sameVariant], now: now
      ).state,
      .stabilizing)

    let differentVariant = answer(
      itemID: "q-b", conceptID: "concept", variantID: "b",
      correct: true, sessionID: secondSession, attempt: 1, at: now)
    let mastered = policy.snapshot(
      conceptID: "concept", answers: [first, differentVariant], now: now)
    XCTAssertEqual(mastered.state, .mastered)
    XCTAssertEqual(mastered.distinctVariantCount, 2)
    XCTAssertEqual(mastered.consecutiveFirstAttemptCorrect, 2)
  }

  func testReviewIntervalsAndDueStateAreDeterministic() {
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 0), 0)
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 1), 1)
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 2), 3)
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 3), 7)
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 4), 14)
    XCTAssertEqual(policy.reviewIntervalDays(forFirstAttemptCorrectStreak: 5), 30)

    let now = Date(timeIntervalSince1970: 4_000_000)
    let old = answer(
      itemID: "old", conceptID: "due", variantID: "base",
      correct: true, sessionID: UUID(), attempt: 1,
      at: now.addingTimeInterval(-2 * 86_400))
    XCTAssertEqual(
      policy.snapshot(conceptID: "due", answers: [old], now: now).state,
      .due)
  }

  func testSelectionChoosesConceptFirstAndPrioritizesDueConcept() {
    let now = Date(timeIntervalSince1970: 5_000_000)
    let dueHistory = answer(
      itemID: "due-old", conceptID: "due-concept", variantID: "old",
      correct: true, sessionID: UUID(), attempt: 1,
      at: now.addingTimeInterval(-2 * 86_400))
    let selected = select(
      [
        question(id: "fresh", conceptID: "fresh-concept", variantID: "base"),
        question(id: "due-new", conceptID: "due-concept", variantID: "new"),
        question(id: "due-other", conceptID: "due-concept", variantID: "other"),
      ],
      history: [dueHistory], now: now, count: 2)
    XCTAssertEqual(selected.first?.source.resolvedConceptID, "due-concept")
    XCTAssertEqual(Set(selected.map { $0.source.resolvedConceptID }).count, 2)
  }

  func testSelectionUsesWeakMisconceptionAndAvoidsRecentVariant() {
    let now = Date(timeIntervalSince1970: 6_000_000)
    let history = answer(
      itemID: "old", conceptID: "weak", variantID: "old",
      format: .trueFalse, correct: false, sessionID: UUID(), attempt: 1,
      at: now.addingTimeInterval(-100), tags: ["misconception:number"])
    let selected = select(
      [
        question(
          id: "tf", conceptID: "weak", variantID: "old", format: .trueFalse),
        question(
          id: "number", conceptID: "weak", variantID: "number",
          format: .numberChoice),
      ],
      history: [history], now: now, count: 1)
    XCTAssertEqual(selected.first?.source.resolvedFormat, .numberChoice)
    XCTAssertEqual(selected.first?.source.resolvedVariantID, "number")
  }

  func testUnlockExcludesLongCaseStudyAndPreviewChoosesDifferentVariant() {
    let now = Date(timeIntervalSince1970: 7_000_000)
    let preview = TakkenPendingPreview(
      id: UUID(), sourceUnlockBundleID: UUID(), conceptID: "preview",
      sourceQuestionID: "base", preferredVariantID: "base",
      contentVersion: "v2", createdAt: now,
      recallExpiresAt: now.addingTimeInterval(86_400), confirmedAt: now,
      consumedAt: nil, foregroundExposureSeconds: 2)
    let values = [
      question(
        id: "base", conceptID: "preview", variantID: "base",
        format: .caseStudy, estimatedSeconds: 45),
      question(
        id: "alternate", conceptID: "preview", variantID: "alternate",
        format: .wordingContrast, estimatedSeconds: 20),
    ]
    let request = request(
      values, history: [], now: now, count: 1, mode: .unlock,
      preview: preview)
    let selected = TakkenQuestionSelectionEngine().select(request)
    XCTAssertEqual(selected.map(\.source.id), ["alternate"])
  }

  func testSelectionDoesNotRepeatConceptWhenRequestedCountExceedsDistinctConcepts() {
    let selected = select(
      [
        question(id: "shared-a", conceptID: "shared", variantID: "a"),
        question(
          id: "shared-b", conceptID: "shared", variantID: "b",
          format: .wordingContrast),
        question(id: "other", conceptID: "other", variantID: "base"),
      ],
      history: [],
      now: Date(timeIntervalSince1970: 8_000_000),
      count: 3)

    XCTAssertEqual(selected.count, 2)
    XCTAssertEqual(Set(selected.map(\.source.resolvedConceptID)).count, selected.count)
  }

  private func question(
    id: String,
    conceptID: String,
    variantID: String,
    format: TakkenQuestionFormat = .trueFalse,
    estimatedSeconds: Int? = nil
  ) -> TakkenQuestion {
    let count = format == .multipleChoice || format == .caseStudy ? 4 : 2
    let choices = (0..<count).map { index in
      TakkenChoice(
        id: index == 0 ? "correct" : "wrong-\(index)",
        text: index == 0 ? "正解" : "誤答\(index)",
        rationale: index == 0 ? nil : "主体・時期・数字の条件が異なります。",
        misconceptionCode: index == 0 ? nil : "condition")
    }
    return .init(
      id: id, conceptID: conceptID, variantID: variantID, format: format,
      prompt: "問題", choices: choices, correctChoiceID: "correct",
      importance: "高", explanation: "正しい規則を詳しく確認します。",
      estimatedSeconds: estimatedSeconds)
  }

  private func select(
    _ questions: [TakkenQuestion],
    history: [StudyAnswerRecord],
    now: Date,
    count: Int
  ) -> [TakkenPresentedQuestion] {
    TakkenQuestionSelectionEngine().select(
      request(questions, history: history, now: now, count: count))
  }

  private func request(
    _ questions: [TakkenQuestion],
    history: [StudyAnswerRecord],
    now: Date,
    count: Int,
    mode: StudyMode = .practice,
    preview: TakkenPendingPreview? = nil
  ) -> TakkenQuestionSelectionRequest {
    .init(
      questions: questions, settings: .standard, progress: [:],
      recentAnswers: history, packID: "takken2026.v1", mode: mode,
      count: count,
      sessionID: UUID(uuidString: "17171717-1717-1717-1717-171717171717")!,
      pendingPreview: preview, now: now)
  }

  private func answer(
    itemID: String,
    conceptID: String?,
    variantID: String?,
    format: TakkenQuestionFormat = .trueFalse,
    correct: Bool,
    sessionID: UUID,
    attempt: Int?,
    at date: Date,
    tags: [String] = []
  ) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString, experienceID: .takken,
      packID: "takken2026.v1", moduleType: .takken,
      itemID: .init(rawValue: itemID), prompt: "問題",
      choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
      selectedChoiceID: correct ? 0 : 1, correctChoiceID: 0,
      shortExplanation: "短い解説", longExplanation: "追加条件を含む詳しい解説",
      sourceNote: "test", category: "宅建業法", subcategory: "免許制度",
      contentVersion: "v2", questionVersion: 2, examYear: 2026,
      lawBasisDate: "2026-04-01", answeredAt: date, mode: .practice,
      sessionID: sessionID, feedbackPlan: correct ? .immediate : .relearn6,
      difficulty: "標準", questionFormat: format.rawValue, keyPoint: "要点",
      tags: tags, learningRole: .generalReview,
      wasNewAtSubmission: attempt == 1, wasDueAtSubmission: false,
      conceptID: conceptID, variantID: variantID, attemptNumber: attempt,
      wasFirstAttempt: attempt.map { $0 == 1 })
  }
}
