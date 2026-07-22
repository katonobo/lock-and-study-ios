import XCTest

@testable import LockAndStudy

final class TakkenFinalizationV6Tests: XCTestCase {
  func testCorrectChoiceIDIsCanonicalAcrossSupportedDecodeShapes() throws {
    let idOnly = try decodeQuestion(correctFields: #""correctChoiceID":"b""#)
    XCTAssertEqual(idOnly.correctChoiceID, "b")
    XCTAssertEqual(idOnly.correctIndex, 1)

    let indexOnly = try decodeQuestion(correctFields: #""correctIndex":1"#)
    XCTAssertEqual(indexOnly.correctChoiceID, "b")
    XCTAssertEqual(indexOnly.correctIndex, 1)

    let matching = try decodeQuestion(
      correctFields: #""correctChoiceID":"b","correctIndex":1"#)
    XCTAssertEqual(matching.correctIndex, 1)
  }

  func testCorrectChoiceDecodeRejectsMismatchBoundsDuplicatesAndCorrectRationale() {
    XCTAssertThrowsError(
      try decodeQuestion(
        correctFields: #""correctChoiceID":"b","correctIndex":0"#))
    XCTAssertThrowsError(try decodeQuestion(correctFields: #""correctIndex":2"#))
    XCTAssertThrowsError(
      try decodeQuestion(
        correctFields: #""correctChoiceID":"b""#,
        choices: #"[{"id":"b","text":"A"},{"id":"b","text":"B"}]"#))
    XCTAssertThrowsError(
      try decodeQuestion(
        correctFields: #""correctChoiceID":"b","wrongChoiceRationales":{"b":"誤答扱い"}"#))
  }

  func testUnlockProgressUsesLocalCompletedStateForTwoThreeAndRestoredQuestions() {
    let two = makeBundle(questionCount: 2)
    var completed: Set<StudyItemID> = []
    XCTAssertTrue(two.hasLaterUncompletedQuestion(after: 0, completedQuestionIDs: completed))
    completed.insert("safe-0")
    XCTAssertEqual(two.nextUncompletedQuestionIndex(after: 0, completedQuestionIDs: completed), 1)
    XCTAssertFalse(two.hasLaterUncompletedQuestion(after: 1, completedQuestionIDs: completed))
    completed.insert("safe-1")
    completed.insert("safe-1")
    XCTAssertEqual(completed.count, 2)

    let three = makeBundle(questionCount: 3, completed: ["safe-0"])
    var restored: Set<StudyItemID> = ["safe-0"]
    XCTAssertEqual(
      three.nextUncompletedQuestionIndex(after: 0, completedQuestionIDs: restored), 1)
    restored.insert("safe-1")
    XCTAssertEqual(
      three.nextUncompletedQuestionIndex(after: 1, completedQuestionIDs: restored), 2)
    restored.insert("safe-2")
    XCTAssertFalse(three.hasLaterUncompletedQuestion(after: 2, completedQuestionIDs: restored))
    XCTAssertEqual(restored.count, 3)
  }

  func testActiveReviewRemainingPersistsAcrossRelaunchAndIgnoresBackground() async throws {
    let root = temporaryRoot()
    var bundle = makeTakkenBundle()
    let questionID: StudyItemID = "takken-review"
    bundle.reviewRemainingActiveSecondsByQuestionID = [questionID.rawValue: 10]
    XCTAssertEqual(bundle.applyActiveReviewExposure(3, for: questionID), 7)
    try await LearningDataStore(rootURL: root).saveExperienceUnlockBundle(bundle)

    let firstLoaded = try await LearningDataStore(rootURL: root).loadExperienceUnlockBundle()
    var restored = try XCTUnwrap(firstLoaded)
    XCTAssertEqual(restored.reviewRemainingActiveSecondsByQuestionID?[questionID.rawValue], 7)
    try await LearningDataStore(rootURL: root).saveExperienceUnlockBundle(restored)
    let secondLoaded = try await LearningDataStore(rootURL: root).loadExperienceUnlockBundle()
    restored = try XCTUnwrap(secondLoaded)
    XCTAssertEqual(restored.reviewRemainingActiveSecondsByQuestionID?[questionID.rawValue], 7)
    XCTAssertEqual(restored.applyActiveReviewExposure(7, for: questionID), 0)
    XCTAssertNil(restored.reviewRemainingActiveSecondsByQuestionID?[questionID.rawValue])
  }

  func testLegacyReviewDeadlineMigratesOnceAndCapsAtMinimum() {
    let now = Date(timeIntervalSince1970: 1_000)
    var bundle = makeTakkenBundle(createdAt: now)
    bundle.reviewRequiredUntilByQuestionID = ["takken-review": now.addingTimeInterval(100)]
    XCTAssertTrue(bundle.migrateLegacyReviewState(at: now))
    XCTAssertEqual(bundle.reviewRemainingActiveSecondsByQuestionID?["takken-review"], 10)
    XCTAssertNil(bundle.reviewRequiredUntilByQuestionID)
    XCTAssertFalse(bundle.migrateLegacyReviewState(at: now.addingTimeInterval(5)))
    XCTAssertEqual(bundle.reviewRemainingActiveSecondsByQuestionID?["takken-review"], 10)
  }

  @MainActor
  func testUnlockSubmissionReturnsAuthoritativeWaitAndCorrectClearsReview() async throws {
    let dependencies = DependencyContainer(learningRootURL: temporaryRoot())
    let question = try XCTUnwrap(makeTakkenBundle().challenge.questions.first)
    var bundle = makeTakkenBundle()
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    let model = AppModel(dependencies: dependencies)

    let wrong = await model.submitUnlockAnswer(
      question: question, selectedChoiceID: 0, feedback: .relearn6)
    XCTAssertEqual(wrong, .recordedIncorrect(remainingActiveSeconds: 10, attemptNumber: 1))
    let wrongBundle = try await dependencies.learning.loadExperienceUnlockBundle()
    bundle = try XCTUnwrap(wrongBundle)
    XCTAssertEqual(bundle.reviewRemainingActiveSecondsByQuestionID?["takken-review"], 10)

    bundle.reviewRemainingActiveSecondsByQuestionID = nil
    bundle.reviewLastActiveAtByQuestionID = ["takken-review": Date()]
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    let correct = await model.submitUnlockAnswer(
      question: question, selectedChoiceID: 1, feedback: .immediate)
    XCTAssertEqual(correct, .recordedCorrect)
    let completedBundle = try await dependencies.learning.loadExperienceUnlockBundle()
    let completed = try XCTUnwrap(completedBundle)
    XCTAssertTrue(completed.completedQuestionIDs.contains("takken-review"))
    XCTAssertNil(completed.reviewRemainingActiveSecondsByQuestionID?["takken-review"])
    XCTAssertNil(completed.reviewLastActiveAtByQuestionID?["takken-review"])
    XCTAssertNil(completed.lastSelectedChoiceIDByQuestionID?["takken-review"])
  }

  func testPreviewResolverPrefersSourceThenFallsBackToConcept() {
    let now = Date(timeIntervalSince1970: 2_000)
    let source = makeQuestion(id: "source", concept: "concept", variant: "base")
    let other = makeQuestion(id: "other", concept: "concept", variant: "other")
    let preview = makePreview(
      sourceQuestionID: "source", conceptID: "concept", contentVersion: "v2", now: now)
    let resolver = TakkenPendingPreviewResolver()
    XCTAssertEqual(
      resolver.visibleQuestion(
        for: preview, in: [other, source], contentVersion: "v2", at: now)?.id,
      "source")

    let fallback = makePreview(
      sourceQuestionID: "removed", conceptID: "concept", contentVersion: "v2", now: now)
    XCTAssertEqual(
      resolver.visibleQuestion(
        for: fallback, in: [other], contentVersion: "v2", at: now)?.id,
      "other")
    XCTAssertNil(
      resolver.visibleQuestion(
        for: preview, in: [source], contentVersion: "changed", at: now))
  }

  @MainActor
  func testNormalPracticeDoesNotConsumeUnlockPreview() async throws {
    let dependencies = DependencyContainer(learningRootURL: temporaryRoot())
    let manifest = try await takkenManifest()
    let questions = try TakkenQuestionRepository(bundle: .main).load(manifest: manifest)
    let source = try XCTUnwrap(questions.first)
    let now = Date()
    var preview = makePreview(
      sourceQuestionID: source.id, conceptID: source.resolvedConceptID,
      contentVersion: manifest.contentVersion, now: now)
    preview.recordForegroundExposure(seconds: 2, at: now)
    try await dependencies.learning.saveTakkenPendingPreview(preview)
    let context = StudyExperienceContext(
      manifest: manifest, dependencies: dependencies, reportProviders: [], destination: .home,
      openMaterialSelection: {}, beginUnlockStudy: {}, completeFirstRun: {})
    let model = TakkenAppModel(context: context)
    await model.load()
    model.settings = .standard
    model.start(mode: .practice)

    let stored = try await dependencies.learning.loadTakkenPendingPreview(now: now)
    XCTAssertNil(stored?.consumedAt)
  }

  func testFormatHistoryCountsOnePresentationDespiteRetries() {
    let now = Date(timeIntervalSince1970: 3_000)
    let formats = TakkenQuestionFormat.allCases
    let base = (0..<20).map { index in
      makeAnswer(
        itemID: "history-\(index)", conceptID: "history-\(index)",
        format: formats[index % formats.count], sessionID: UUID(), attempt: 1,
        correct: true, at: now.addingTimeInterval(TimeInterval(index)))
    }
    let retried = (0..<10).map { index in
      makeAnswer(
        itemID: base[0].itemID.rawValue, conceptID: "history-0", format: .trueFalse,
        sessionID: base[0].sessionID, attempt: index + 2, correct: false,
        at: now.addingTimeInterval(TimeInterval(20 + index)))
    }
    let candidates = formats.map {
      makeQuestion(id: "candidate-\($0.rawValue)", format: $0)
    }
    let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let plain = select(candidates, history: base, sessionID: requestID)
    let withRetries = select(candidates, history: base + retried, sessionID: requestID)
    XCTAssertEqual(plain.map(\.id), withRetries.map(\.id))
  }

  func testReportUsesSessionConceptUnitsUniqueWeakConceptsAndHidesZeroFormats() async throws {
    let now = Date()
    let session = UUID()
    let relearn = [
      makeAnswer(
        itemID: "new", conceptID: "new-concept", format: .trueFalse,
        sessionID: session, attempt: 1, correct: false, at: now),
      makeAnswer(
        itemID: "new", conceptID: "new-concept", format: .trueFalse,
        sessionID: session, attempt: 2, correct: true, at: now.addingTimeInterval(1)),
    ]
    let manifest = try await takkenManifest()
    var section = try report(answers: relearn, manifest: manifest, now: now)
    XCTAssertEqual(section.metrics.first { $0.id == "takken.new" }?.value, "1論点")
    XCTAssertEqual(section.metrics.first { $0.id == "takken.review" }?.value, "0論点")
    XCTAssertEqual(section.metrics.first { $0.id == "takken.relearned" }?.value, "1論点")
    XCTAssertEqual(section.currentMetrics.map(\.id), ["takken.format.true_false"])

    let repeatedOneConcept = (0..<3).map { index in
      makeAnswer(
        itemID: "same", conceptID: "same", format: .trueFalse,
        sessionID: UUID(), attempt: 1, correct: false,
        at: now.addingTimeInterval(TimeInterval(index)))
    }
    section = try report(answers: repeatedOneConcept, manifest: manifest, now: now)
    XCTAssertTrue(section.weakAreas.isEmpty)

    let threeConcepts = (0..<3).map { index in
      makeAnswer(
        itemID: "weak-\(index)", conceptID: "weak-\(index)", format: .trueFalse,
        sessionID: UUID(), attempt: 1, correct: false,
        at: now.addingTimeInterval(TimeInterval(index)))
    }
    section = try report(answers: threeConcepts, manifest: manifest, now: now)
    XCTAssertEqual(section.weakAreas.first?.answerCount, 3)
  }

  private func decodeQuestion(
    correctFields: String,
    choices: String = #"[{"id":"a","text":"A"},{"id":"b","text":"B"}]"#
  ) throws -> TakkenQuestion {
    try JSONDecoder().decode(
      TakkenQuestion.self,
      from: Data(
        """
        {"id":"decode","category":"宅建業法","difficulty":"基礎",
         "format":"true_false","prompt":"問題","choices":\(choices),
         \(correctFields),"explanation":"解説"}
        """.utf8))
  }

  private func makeBundle(
    questionCount: Int,
    completed: Set<StudyItemID> = []
  ) -> ExperienceUnlockBundleSnapshot {
    let now = Date()
    let questions = (0..<questionCount).map { index in
      UnlockQuestionSnapshot.safeFallback(
        .init(
          id: .init(rawValue: "safe-\(index)"), prompt: "問題\(index)",
          choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
          correctChoiceID: 0, explanation: "解説"))
    }
    return .init(
      schemaVersion: 3,
      challenge: .init(
        schemaVersion: 3, id: UUID(), requestID: UUID(), origin: .manual,
        experienceID: .safeFallback, packID: "english3000.v1", policyVersion: 1,
        pace: .balanced10, reviewLoad: .standard, questions: questions,
        access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
        createdAt: now, expiresAt: now.addingTimeInterval(1_800)),
      completedQuestionIDs: completed, completionState: .answering,
      completionEventID: UUID(), createdUnlockSessionID: nil, abortReason: nil)
  }

  private func makeTakkenBundle(createdAt: Date = Date()) -> ExperienceUnlockBundleSnapshot {
    let question = UnlockQuestionSnapshot.takken(
      .init(
        id: "takken-review", prompt: "問題",
        choices: [.init(id: 0, text: "誤答"), .init(id: 1, text: "正解")],
        correctChoiceID: 1, shortExplanation: "短い解説", longExplanation: "詳しい解説",
        keyPoint: "要点", category: "宅建業法", subCategory: "免許", difficulty: "基礎",
        format: TakkenQuestionFormat.trueFalse.rawValue, examYear: 2026,
        lawBasisDate: "2026-04-01", sourceNote: "出典", contentVersion: "v2",
        questionVersion: 2, conceptID: "concept", variantID: "base",
        minimumReviewSeconds: 10, contrastNote: "比較", wrongChoiceRationales: [0: "違い"]))
    return .init(
      schemaVersion: 3,
      challenge: .init(
        schemaVersion: 3, id: UUID(), requestID: UUID(), origin: .manual,
        experienceID: .takken, packID: "takken2026.v1", policyVersion: 1,
        pace: .balanced10, reviewLoad: .standard, questions: [question],
        access: .init(packID: "takken2026.v1", reason: .freeSample, verifiedAt: nil),
        createdAt: createdAt, expiresAt: Date().addingTimeInterval(1_800)),
      completedQuestionIDs: [], completionState: .answering,
      completionEventID: UUID(), createdUnlockSessionID: nil, abortReason: nil)
  }

  private func makeQuestion(
    id: String,
    concept: String? = nil,
    variant: String = "base",
    format: TakkenQuestionFormat = .trueFalse
  ) -> TakkenQuestion {
    let count = format == .multipleChoice || format == .caseStudy ? 4 : 2
    let choices = (0..<count).map { index in
      TakkenChoice(
        id: index == 0 ? "correct" : "wrong-\(index)",
        text: index == 0 ? "正解" : "誤答\(index)",
        rationale: index == 0 ? nil : "誤答理由", misconceptionCode: nil)
    }
    return .init(
      id: id, conceptID: concept ?? "concept-\(id)", variantID: variant,
      format: format, prompt: "問題", choices: choices, correctChoiceID: "correct")
  }

  private func makePreview(
    sourceQuestionID: String,
    conceptID: String,
    contentVersion: String,
    now: Date
  ) -> TakkenPendingPreview {
    .init(
      id: UUID(), sourceUnlockBundleID: UUID(), conceptID: conceptID,
      sourceQuestionID: sourceQuestionID, preferredVariantID: "base",
      contentVersion: contentVersion, createdAt: now,
      recallExpiresAt: now.addingTimeInterval(86_400), confirmedAt: nil,
      consumedAt: nil, foregroundExposureSeconds: 0)
  }

  private func select(
    _ questions: [TakkenQuestion],
    history: [StudyAnswerRecord],
    sessionID: UUID
  ) -> [TakkenPresentedQuestion] {
    TakkenQuestionSelectionEngine().select(
      .init(
        questions: questions, settings: .standard, progress: [:], recentAnswers: history,
        packID: "takken2026.v1", mode: .practice, count: 1,
        sessionID: sessionID, pendingPreview: nil, now: Date()))
  }

  private func makeAnswer(
    itemID: String,
    conceptID: String,
    format: TakkenQuestionFormat,
    sessionID: UUID,
    attempt: Int,
    correct: Bool,
    at date: Date
  ) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString, experienceID: .takken,
      packID: "takken2026.v1", moduleType: .takken, itemID: .init(rawValue: itemID),
      prompt: "問題", choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
      selectedChoiceID: correct ? 0 : 1, correctChoiceID: 0,
      shortExplanation: "短い解説", longExplanation: "詳しい解説", sourceNote: "出典",
      category: "宅建業法", subcategory: "免許", contentVersion: "v2",
      questionVersion: 2, examYear: 2026, lawBasisDate: "2026-04-01",
      answeredAt: date, mode: .practice, sessionID: sessionID,
      feedbackPlan: correct ? .immediate : .relearn6, questionFormat: format.rawValue,
      learningRole: attempt == 1 ? .newItem : .mistakeReview,
      wasNewAtSubmission: attempt == 1, wasDueAtSubmission: false,
      conceptID: conceptID, variantID: "base", attemptNumber: attempt,
      wasFirstAttempt: attempt == 1)
  }

  private func report(
    answers: [StudyAnswerRecord],
    manifest: StudyPackManifest,
    now: Date
  ) throws -> StudyMaterialReportSection {
    try TakkenReportProvider().makeReportSection(
      snapshot: .init(
        answers: answers, events: [], progress: [:], manifests: [manifest],
        entitlement: .empty),
      manifest: manifest,
      period: .init(
        startInclusive: now.addingTimeInterval(-1),
        endExclusive: now.addingTimeInterval(60)),
      now: now, calendar: .current)
  }

  private func takkenManifest() async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(bundle: .main).releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" })
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-v6-\(UUID().uuidString)", isDirectory: true)
  }
}
