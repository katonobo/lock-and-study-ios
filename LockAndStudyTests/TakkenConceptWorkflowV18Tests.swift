import XCTest

@testable import LockAndStudy

@MainActor
final class TakkenConceptWorkflowV18Tests: XCTestCase {
  func testPresentedChoiceKeepsMisconceptionCodeAfterShuffle() throws {
    let presented = TakkenPresentedQuestion.make(
      source: question(), sessionID: UUID(uuidString: "18181818-1818-1818-1818-181818181818")!)
    let wrongPresentedID = try XCTUnwrap(
      presented.presentedChoices.first {
        presented.sourceChoiceID(for: $0.id) == "wrong-number"
      }?.id)

    let snapshot = CertificationChallengeQuestion.make(
      presented: presented, contentVersion: "v18")

    XCTAssertEqual(
      snapshot.misconceptionCodesByChoiceID?[wrongPresentedID], "number")
    XCTAssertNotEqual(wrongPresentedID, snapshot.correctChoiceID)
  }

  func testUnlockWrongAnswerPersistsSameMisconceptionTagAsPractice() async throws {
    let presented = TakkenPresentedQuestion.make(
      source: question(), sessionID: UUID(uuidString: "18181818-1818-1818-1818-181818181818")!)
    let snapshot = CertificationChallengeQuestion.make(
      presented: presented, contentVersion: "v18")
    let wrongPresentedID = try XCTUnwrap(
      snapshot.misconceptionCodesByChoiceID?.first(where: {
        $0.value == "number"
      })?.key)
    let state = CertificationUnlockSessionPayload(
      pace: .balanced10,
      questions: [snapshot],
      completedQuestionIDs: [],
      attemptCountsByQuestionID: [:],
      reviewRemainingSecondsByQuestionID: [:],
      lastSelectedChoiceIDByQuestionID: [:],
      activeReviewQuestionID: nil)
    let payload = try SharedJSON.encoder().encode(state)
    let now = Date(timeIntervalSince1970: 18_000_000)
    let envelope = UnlockChallengeSessionEnvelope(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
      id: UUID(), requestID: UUID(), origin: .manual,
      experienceID: .certificationV1, packID: "takken2026.v1",
      contentVersion: "v18", policyVersion: 1,
      createdAt: now, expiresAt: now.addingTimeInterval(1_800),
      completionState: .answering, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil,
      enginePayloadSchemaID: CertificationUnlockSessionPayload.schemaID,
      enginePayload: payload)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lock-and-study-v18-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let dependencies = DependencyContainer(learningRootURL: root)

    let transition = try await CertificationExperience().acceptAnswer(
      .choice(
        questionID: snapshot.id.rawValue,
        choiceID: String(wrongPresentedID)),
      envelope: envelope,
      dependencies: dependencies)

    guard case .recordedIncorrect = transition.submissionResult else {
      return XCTFail("unlock wrong answer must enter relearning")
    }
    let persistedAnswers = try await dependencies.learning.answers()
    let answer = try XCTUnwrap(persistedAnswers.first)
    XCTAssertEqual(answer.tags, ["misconception:number"])
    XCTAssertEqual(
      answer.tags,
      TakkenMisconceptionTagger.tags(
        correct: false, misconceptionCode: "number"))
  }

  func testMisconceptionResolvesAcrossDifferentVariantsAndSessionsThenReactivates() {
    let policy = TakkenConceptMasteryPolicy()
    let base = Date(timeIntervalSince1970: 19_000_000)
    let wrong = answer(
      variantID: "base", format: .trueFalse, correct: false,
      sessionID: UUID(), at: base, tags: ["misconception:number"])
    let firstRecall = answer(
      variantID: "number-a", format: .numberChoice, correct: true,
      sessionID: UUID(), at: base.addingTimeInterval(100))
    let secondRecall = answer(
      variantID: "number-b", format: .numberChoice, correct: true,
      sessionID: UUID(), at: base.addingTimeInterval(200))

    let resolved = policy.snapshot(
      conceptID: "concept-v18",
      answers: [wrong, firstRecall, secondRecall],
      now: base.addingTimeInterval(300))
    XCTAssertEqual(resolved.state, .mastered)
    XCTAssertFalse(resolved.weakMisconceptionCodes.contains("number"))

    let recentWrong = answer(
      variantID: "number-c", format: .numberChoice, correct: false,
      sessionID: UUID(), at: base.addingTimeInterval(400),
      tags: ["misconception:number"])
    let reactivated = policy.snapshot(
      conceptID: "concept-v18",
      answers: [wrong, firstRecall, secondRecall, recentWrong],
      now: base.addingTimeInterval(500))
    XCTAssertEqual(reactivated.state, .relearning)
    XCTAssertEqual(reactivated.weakMisconceptionCodes, ["number"])
  }

  func testMasteryAfterWrongClearsOldMisconceptionEvenAcrossOtherUsefulFormats() {
    let base = Date(timeIntervalSince1970: 20_000_000)
    let values = [
      answer(
        variantID: "case", format: .caseStudy, correct: false,
        sessionID: UUID(), at: base, tags: ["misconception:exception"]),
      answer(
        variantID: "judgment", format: .trueFalse, correct: true,
        sessionID: UUID(), at: base.addingTimeInterval(100)),
      answer(
        variantID: "wording", format: .wordingContrast, correct: true,
        sessionID: UUID(), at: base.addingTimeInterval(200)),
    ]
    let snapshot = TakkenConceptMasteryPolicy().snapshot(
      conceptID: "concept-v18", answers: values,
      now: base.addingTimeInterval(300))
    XCTAssertEqual(snapshot.state, .mastered)
    XCTAssertTrue(snapshot.weakMisconceptionCodes.isEmpty)
  }

  private func question() -> TakkenQuestion {
    .init(
      id: "v18-question", conceptID: "concept-v18", variantID: "base",
      format: .multipleChoice, prompt: "正しい数値を選んでください。",
      choices: [
        .init(
          id: "correct", text: "2年", rationale: nil,
          misconceptionCode: nil),
        .init(
          id: "wrong-number", text: "3年",
          rationale: "期間の数字を別制度と混同しています。",
          misconceptionCode: "number"),
        .init(
          id: "wrong-scope", text: "4年",
          rationale: "適用範囲の条件を混同しています。",
          misconceptionCode: "scope"),
        .init(
          id: "wrong-exception", text: "5年",
          rationale: "原則と例外の条件を混同しています。",
          misconceptionCode: "exception"),
      ],
      correctChoiceID: "correct", importance: "高",
      explanation: "正しい期間は2年です。")
  }

  private func answer(
    variantID: String,
    format: TakkenQuestionFormat,
    correct: Bool,
    sessionID: UUID,
    at date: Date,
    tags: [String] = []
  ) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString, experienceID: .takken,
      packID: "takken2026.v1", moduleType: .takken,
      itemID: .init(rawValue: variantID), prompt: "問題",
      choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
      selectedChoiceID: correct ? 0 : 1, correctChoiceID: 0,
      shortExplanation: "短い解説", longExplanation: "詳しい解説",
      sourceNote: "test", category: "宅建業法", subcategory: "免許制度",
      contentVersion: "v18", questionVersion: 18, examYear: 2026,
      lawBasisDate: "2026-04-01", answeredAt: date, mode: .practice,
      sessionID: sessionID, feedbackPlan: correct ? .immediate : .relearn6,
      difficulty: "標準", questionFormat: format.rawValue, keyPoint: "要点",
      tags: tags, learningRole: .generalReview,
      wasNewAtSubmission: true, wasDueAtSubmission: false,
      conceptID: "concept-v18", variantID: variantID, attemptNumber: 1,
      wasFirstAttempt: true)
  }
}
