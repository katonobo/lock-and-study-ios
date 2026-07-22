import XCTest
@testable import LockAndStudy

final class TakkenLearningEngineV5Tests: XCTestCase {
  func testLegacyJSONDecodesWithStableChoiceIDs() throws {
    let value = try JSONDecoder().decode(TakkenQuestion.self, from: Data("""
      {"id":"legacy","category":"宅建業法","difficulty":"基礎","format":"true_false",
       "prompt":"問題","choices":["正しい","誤り"],"correctIndex":1,"explanation":"解説"}
      """.utf8))
    XCTAssertEqual(value.choices.map(\.id), ["choice-0", "choice-1"])
    XCTAssertEqual(value.correctChoiceID, "choice-1")
    XCTAssertEqual(value.resolvedConceptID, "legacy")
  }

  func testV2FormatsAndStableChoicesDecode() throws {
    for format in TakkenQuestionFormat.allCases {
      let choices = format == .multipleChoice || format == .caseStudy
        ? #"[{"id":"a","text":"A"},{"id":"b","text":"B"},{"id":"c","text":"C"},{"id":"d","text":"D"}]"#
        : #"[{"id":"a","text":"A"},{"id":"b","text":"B"}]"#
      let data = Data("""
        {"id":"q-\(format.rawValue)","conceptID":"concept","variantID":"variant",
         "category":"宅建業法","difficulty":"標準","format":"\(format.rawValue)",
         "prompt":"問題","choices":\(choices),"correctChoiceID":"b","explanation":"解説"}
        """.utf8)
      let value = try JSONDecoder().decode(TakkenQuestion.self, from: data)
      XCTAssertEqual(value.resolvedFormat, format)
      XCTAssertEqual(value.correctChoiceID, "b")
    }
  }

  func testFormatDisplayNamesAreUserFacing() {
    XCTAssertEqual(TakkenQuestionFormat.allCases.map(\.displayName), ["○×", "数値選択", "文言比較", "4択", "事例問題"])
    XCTAssertFalse(TakkenQuestionFormat.allCases.map(\.displayName).contains("true_false"))
  }

  func testSeedShuffleIsReproducibleAndKeepsCorrectAnswer() {
    let question = makeQuestion(id: "shuffle", format: .multipleChoice)
    let session = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let first = TakkenPresentedQuestion.make(source: question, sessionID: session)
    let second = TakkenPresentedQuestion.make(source: question, sessionID: session)
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.presentedChoices[first.correctChoiceID].text, "正解")
    XCTAssertEqual(first.sourceChoiceID(for: first.correctChoiceID), question.correctChoiceID)
  }

  func testSelectionAvoidsDuplicateConceptsAndRecentItems() {
    let recent = makeAnswer(questionID: "recent", conceptID: "recent-concept", format: .trueFalse)
    let questions = [
      makeQuestion(id: "recent", concept: "recent-concept", variant: "a"),
      makeQuestion(id: "recent-b", concept: "recent-concept", variant: "b"),
      makeQuestion(id: "fresh", concept: "fresh-concept", variant: "a"),
    ]
    let result = select(questions, count: 2, recent: [recent])
    XCTAssertEqual(Set(result.map { $0.source.resolvedConceptID }).count, 2)
    XCTAssertEqual(result.first?.id, "fresh")
  }

  func testFormatRotationPrefersMissingFormat() {
    let history = (0..<20).map {
      makeAnswer(questionID: "old-\($0)", conceptID: "old-\($0)", format: .trueFalse)
    }
    let result = select([
      makeQuestion(id: "tf", format: .trueFalse),
      makeQuestion(id: "number", format: .numberChoice),
    ], count: 1, recent: history)
    XCTAssertEqual(result.first?.source.resolvedFormat, .numberChoice)
  }

  func testPreviewLifecycleIs120SecondsAndRequiresTwoForegroundSeconds() {
    let now = Date(timeIntervalSince1970: 10_000)
    var preview = makePreview(createdAt: now)
    XCTAssertTrue(preview.isDisplayable(at: now.addingTimeInterval(119.9)))
    XCTAssertFalse(preview.isDisplayable(at: now.addingTimeInterval(120)))
    preview.recordForegroundExposure(seconds: 1, at: now.addingTimeInterval(1))
    XCTAssertNil(preview.confirmedAt)
    preview.recordForegroundExposure(seconds: 1, at: now.addingTimeInterval(2))
    XCTAssertNotNil(preview.confirmedAt)
  }

  func testPreviewVersionExpiryAndDifferentVariantPriority() {
    let now = Date(timeIntervalSince1970: 20_000)
    var preview = makePreview(createdAt: now)
    preview.recordForegroundExposure(seconds: 2, at: now)
    XCTAssertTrue(preview.isUsableForRecall(contentVersion: "v2", now: now))
    XCTAssertFalse(preview.isUsableForRecall(contentVersion: "other", now: now))
    XCTAssertFalse(preview.isUsableForRecall(contentVersion: "v2", now: preview.recallExpiresAt))
    let selected = select([
      makeQuestion(id: "base", concept: "preview-concept", variant: "base"),
      makeQuestion(id: "variant", concept: "preview-concept", variant: "different",
                   format: .wordingContrast),
    ], count: 1, preview: preview)
    XCTAssertEqual(selected.first?.source.resolvedVariantID, "different")
  }

  func testPreviewCanBeConsumedOnlyOnce() async throws {
    let store = temporaryStore()
    let now = Date()
    var preview = makePreview(createdAt: now)
    preview.recordForegroundExposure(seconds: 2, at: now)
    try await store.saveTakkenPendingPreview(preview)
    let firstConsume = try await store.consumeTakkenPendingPreview(id: preview.id, at: now)
    let secondConsume = try await store.consumeTakkenPendingPreview(id: preview.id, at: now)
    XCTAssertTrue(firstConsume)
    XCTAssertFalse(secondConsume)
  }

  func testWrongReviewKeepsExplanationUntilExplicitRetryAndStagesTime() {
    let presented = TakkenPresentedQuestion.make(
      source: makeQuestion(id: "review", minimumReviewSeconds: 5), sessionID: UUID())
    let wrong = presented.presentedChoices.first { $0.id != presented.correctChoiceID }!.id
    let start = Date(timeIntervalSince1970: 30_000)
    var machine = TakkenAnswerStateMachine()
    machine.record(selectedChoiceID: wrong, question: presented, at: start)
    XCTAssertEqual(machine.remainingSeconds(at: start), 10)
    machine.update(at: start.addingTimeInterval(10))
    guard case .readyToRetry(let first) = machine.phase else { return XCTFail("retry state") }
    XCTAssertFalse(first.explanation.rule.isEmpty)
    XCTAssertTrue(machine.retry())
    machine.record(selectedChoiceID: wrong, question: presented, at: start.addingTimeInterval(11))
    XCTAssertEqual(machine.remainingSeconds(at: start.addingTimeInterval(11)), 15)
    machine.update(at: start.addingTimeInterval(26))
    XCTAssertTrue(machine.retry())
    machine.record(selectedChoiceID: wrong, question: presented, at: start.addingTimeInterval(27))
    XCTAssertEqual(machine.remainingSeconds(at: start.addingTimeInterval(27)), 20)
  }

  func testCorrectAfterWrongIsRelearned() {
    let presented = TakkenPresentedQuestion.make(source: makeQuestion(id: "relearn"), sessionID: UUID())
    let wrong = presented.presentedChoices.first { $0.id != presented.correctChoiceID }!.id
    var machine = TakkenAnswerStateMachine()
    machine.record(selectedChoiceID: wrong, question: presented, at: .distantPast)
    machine.update(at: .distantFuture)
    XCTAssertTrue(machine.retry())
    machine.record(selectedChoiceID: presented.correctChoiceID, question: presented, at: Date())
    guard case .answeredCorrect(let state) = machine.phase else { return XCTFail("correct state") }
    XCTAssertTrue(state.wasRelearned)
  }

  func testUnlockWrongReviewRestoresAcrossRelaunch() {
    let now = Date(timeIntervalSince1970: 40_000)
    let question = TakkenUnlockQuestionSnapshot(
      id: "restore", prompt: "問題",
      choices: [.init(id: 0, text: "誤答"), .init(id: 1, text: "正解")],
      correctChoiceID: 1, shortExplanation: "違い", longExplanation: "正しいルール",
      keyPoint: "要点", category: "宅建業法", subCategory: "免許", difficulty: "基礎",
      format: TakkenQuestionFormat.trueFalse.rawValue, examYear: 2026,
      lawBasisDate: "2026-04-01", sourceNote: "校閲済み", contentVersion: "v2",
      questionVersion: 2, conceptID: "restore-concept", variantID: "base",
      minimumReviewSeconds: 10, contrastNote: "比較", wrongChoiceRationales: [0: "主体が違う"])
    var reviewing = TakkenAnswerStateMachine(
      restoring: question, selectedChoiceID: 0, wrongAttemptCount: 2,
      reviewRequiredUntil: now.addingTimeInterval(8), now: now)
    XCTAssertEqual(reviewing.wrongAttemptCount, 2)
    XCTAssertEqual(reviewing.remainingSeconds(at: now), 8)
    reviewing.update(at: now.addingTimeInterval(8))
    XCTAssertTrue(reviewing.retry())

    let ready = TakkenAnswerStateMachine(
      restoring: question, selectedChoiceID: 0, wrongAttemptCount: 2,
      reviewRequiredUntil: now.addingTimeInterval(-1), now: now)
    guard case .readyToRetry(let state) = ready.phase else { return XCTFail("retry restored") }
    XCTAssertEqual(state.explanation.selectedText, "誤答")
    XCTAssertEqual(state.explanation.correctText, "正解")
  }

  func testMultipleWrongAttemptsPersistAndDuplicateSubmissionIsIdempotent() async throws {
    let store = temporaryStore()
    let first = makeAnswer(questionID: "same", conceptID: "concept", format: .numberChoice,
                           correct: false, attempt: 1, submissionID: "attempt-1")
    let second = makeAnswer(questionID: "same", conceptID: "concept", format: .numberChoice,
                            correct: false, attempt: 2, submissionID: "attempt-2")
    let firstWrite = try await store.recordUnique(first)
    let duplicateWrite = try await store.recordUnique(first)
    let secondWrite = try await store.recordUnique(second)
    let answers = try await store.answers()
    let progress = try await store.progress(for: .init(packID: "takken2026.v1", itemID: "same"))
    XCTAssertTrue(firstWrite)
    XCTAssertFalse(duplicateWrite)
    XCTAssertTrue(secondWrite)
    XCTAssertEqual(answers.count, 2)
    XCTAssertEqual(progress.incorrectCount, 2)
  }

  func testOldAnswerAndUnlockBundleDecodeWithoutV5Fields() throws {
    let answer = makeAnswer(questionID: "legacy", conceptID: "legacy", format: .trueFalse)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any])
    for key in ["conceptID", "variantID", "attemptNumber", "wasFirstAttempt"] { object.removeValue(forKey: key) }
    let decoded = try JSONDecoder().decode(
      StudyAnswerRecord.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.conceptID)
    XCTAssertNil(decoded.attemptNumber)
  }

  func testDeletingHistoryDeletesTakkenPreview() async throws {
    let store = temporaryStore()
    try await store.saveTakkenPendingPreview(makePreview(createdAt: Date()))
    try await store.deleteLearningHistory()
    let preview = try await store.loadTakkenPendingPreview(now: Date())
    XCTAssertNil(preview)
  }

  func testTakkenReportInitialAccuracyRelearnedConceptsFormatsAndPeriodWeakAreas() async throws {
    let now = Date()
    let session = UUID()
    let answers = [
      makeAnswer(questionID: "a1", conceptID: "a", format: .numberChoice,
                 correct: false, attempt: 1, submissionID: "a-1", sessionID: session, at: now),
      makeAnswer(questionID: "a2", conceptID: "a", format: .wordingContrast,
                 correct: true, attempt: 2, submissionID: "a-2", sessionID: session,
                 at: now.addingTimeInterval(1)),
      makeAnswer(questionID: "b", conceptID: "b", format: .multipleChoice,
                 correct: true, attempt: 1, submissionID: "b-1", at: now),
      makeAnswer(questionID: "c", conceptID: "c", format: .trueFalse,
                 correct: false, attempt: 1, submissionID: "c-1", at: now),
    ]
    let manifests = try await ContentRepository(source: BundledContentSource(bundle: .main))
      .releasedManifests()
    let manifest = try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" })
    let snapshot = LearningReportDataSnapshot(
      answers: answers, events: [], progress: [:], manifests: manifests, entitlement: .empty)
    let section = try TakkenReportProvider().makeReportSection(
      snapshot: snapshot, manifest: manifest,
      period: .init(startInclusive: now.addingTimeInterval(-1), endExclusive: now.addingTimeInterval(10)),
      now: now, calendar: .current)
    XCTAssertEqual(section.metrics.first { $0.id == "takken.initialAccuracy" }?.value, "33%")
    XCTAssertEqual(section.metrics.first { $0.id == "takken.relearned" }?.value, "1論点")
    XCTAssertEqual(section.metrics.first { $0.id == "takken.concepts" }?.value, "3論点")
    XCTAssertEqual(section.currentMetrics.first { $0.id == "takken.format.number_choice" }?.value, "1問・0%")
    XCTAssertEqual(section.weakAreas.first?.answerCount, 3)
  }

  // MARK: - Fixtures

  private func makeQuestion(
    id: String, concept: String? = nil, variant: String = "base",
    format: TakkenQuestionFormat = .trueFalse, minimumReviewSeconds: Int? = nil
  ) -> TakkenQuestion {
    let choices: [TakkenChoice]
    if format == .multipleChoice || format == .caseStudy {
      choices = [
        .init(id: "correct", text: "正解", rationale: nil, misconceptionCode: nil),
        .init(id: "wrong-1", text: "誤答1", rationale: "条件が違います。", misconceptionCode: "condition"),
        .init(id: "wrong-2", text: "誤答2", rationale: "主体が違います。", misconceptionCode: "actor"),
        .init(id: "wrong-3", text: "誤答3", rationale: "期限が違います。", misconceptionCode: "term"),
      ]
    } else {
      choices = [
        .init(id: "correct", text: "正解", rationale: nil, misconceptionCode: nil),
        .init(id: "wrong", text: "誤答", rationale: "正しいルールと異なります。", misconceptionCode: "rule"),
      ]
    }
    return .init(
      id: id, conceptID: concept ?? "concept-\(id)", variantID: variant, format: format,
      prompt: "\(id)の問題", choices: choices, correctChoiceID: "correct",
      explanation: "正しいルールを詳しく確認します。",
      preview: .init(title: "予習", rule: "覚えるルール", contrast: "違い", mnemonic: nil),
      minimumReviewSeconds: minimumReviewSeconds, contrastNote: "混同しやすい違い")
  }

  private func select(
    _ questions: [TakkenQuestion], count: Int, recent: [StudyAnswerRecord] = [],
    preview: TakkenPendingPreview? = nil
  ) -> [TakkenPresentedQuestion] {
    TakkenQuestionSelectionEngine().select(.init(
      questions: questions, settings: .standard, progress: [:], recentAnswers: recent,
      packID: "takken2026.v1", mode: .practice, count: count,
      sessionID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
      pendingPreview: preview, now: Date()))
  }

  private func makePreview(createdAt: Date) -> TakkenPendingPreview {
    .init(
      id: UUID(), sourceUnlockBundleID: UUID(), conceptID: "preview-concept",
      sourceQuestionID: "base", preferredVariantID: "base", contentVersion: "v2",
      createdAt: createdAt, recallExpiresAt: createdAt.addingTimeInterval(86_400),
      confirmedAt: nil, consumedAt: nil, foregroundExposureSeconds: 0)
  }

  private func makeAnswer(
    questionID: String, conceptID: String, format: TakkenQuestionFormat,
    correct: Bool = true, attempt: Int = 1, submissionID: String? = nil,
    sessionID: UUID = UUID(), at: Date = Date()
  ) -> StudyAnswerRecord {
    .init(
      submissionID: submissionID ?? "answer-\(UUID().uuidString)", experienceID: .takken,
      packID: "takken2026.v1", moduleType: .takken, itemID: .init(rawValue: questionID),
      prompt: "問題", choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
      selectedChoiceID: correct ? 0 : 1, correctChoiceID: 0,
      shortExplanation: "短い解説", longExplanation: "詳しい解説と追加情報",
      sourceNote: "test", category: "宅建業法", subcategory: "免許制度",
      contentVersion: "v2", questionVersion: 2, examYear: 2026,
      lawBasisDate: "2026-04-01", answeredAt: at, mode: .practice,
      sessionID: sessionID, feedbackPlan: correct ? .immediate : .relearn6,
      difficulty: "標準", questionFormat: format.rawValue, keyPoint: "要点", tags: [],
      learningRole: attempt == 1 ? .newItem : .mistakeReview,
      wasNewAtSubmission: attempt == 1, wasDueAtSubmission: false,
      conceptID: conceptID, variantID: "variant-\(questionID)", attemptNumber: attempt,
      wasFirstAttempt: attempt == 1)
  }

  private func temporaryStore() -> LearningDataStore {
    LearningDataStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }
}
