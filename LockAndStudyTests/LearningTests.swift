import XCTest
@testable import LockAndStudy

final class LearningTests: XCTestCase {
  func testCompositeIDPreventsCrossPackCollision() {
    XCTAssertNotEqual(CompositeStudyItemID(packID: "a", itemID: "1").storageKey, CompositeStudyItemID(packID: "b", itemID: "1").storageKey)
  }

  func testAnswerDoubleTapGate() {
    var gate = AnswerSubmissionGate(); let id = CompositeStudyItemID(packID: "a", itemID: "1")
    XCTAssertTrue(gate.claim(id)); XCTAssertFalse(gate.claim(id))
  }

  func testSRSWrongThenCorrect() {
    let id = CompositeStudyItemID(packID: "a", itemID: "1"); let now = Date(timeIntervalSince1970: 1_000)
    let wrong = SRSScheduler().applying(isCorrect: false, to: .initial(id), at: now)
    XCTAssertEqual(wrong.incorrectCount, 1); XCTAssertEqual(wrong.dueAt, now.addingTimeInterval(360))
    let correct = SRSScheduler().applying(isCorrect: true, to: wrong, at: now)
    XCTAssertEqual(correct.correctCount, 1); XCTAssertEqual(correct.intervalDays, 1)
  }

  func testPersistenceNDJSONExportDeleteAndBundleExpiry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lockandstudy-test-\(UUID().uuidString)")
    let store = LearningDataStore(rootURL: root)
    let prompt = fixturePrompt()
    let answer = StudyAnswerRecord(prompt: prompt, selectedChoiceID: 1, answeredAt: Date(timeIntervalSince1970: 1_000), mode: .practice, sessionID: UUID(), feedbackPlan: .immediate)
    try await store.record(answer)
    let answers = try await store.answers(monthKey: "1970-01")
    XCTAssertEqual(answers.count, 1)
    let exportURL = try await store.exportJSON()
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    var bundle = UnlockLearningBundleSnapshot(schemaVersion: 1, id: UUID(), unlockRequestID: UUID(), policyVersion: 1, pace: .balanced10, reviewLoad: .standard, prompts: [prompt], access: .init(packID: "a", reason: .freeSample, verifiedAt: nil), createdAt: .distantPast, expiresAt: .distantPast, completedItemIDs: [], createdUnlockSessionID: nil, abortReason: nil)
    try await store.saveUnlockBundle(bundle)
    let expiredBundle = try await store.loadUnlockBundle(now: Date())
    XCTAssertNil(expiredBundle)
    bundle.abortReason = "emergency"
    try await store.saveUnlockBundle(bundle)
    let abortedBundle = try await store.loadUnlockBundle(now: .distantPast)
    XCTAssertNil(abortedBundle)
    try await store.deleteLearningHistory()
    let finalProgress = try await store.allProgress()
    XCTAssertTrue(finalProgress.isEmpty)
  }

  func testLegacyProgressImportIsValidatedAndIdempotent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lockandstudy-legacy-test-\(UUID().uuidString)")
    let store = LearningDataStore(rootURL: root)
    let event = LegacyProgressEvent(id: UUID(), sourceBundleID: "com.ameneko.eitangolock",
                                    sourceContentVersion: "legacy", packID: "english3000.v1", itemID: "word-1",
                                    answeredAt: Date(timeIntervalSince1970: 2_000), correctCount: 3,
                                    incorrectCount: 1, dueAt: Date(timeIntervalSince1970: 3_000))
    let export = LegacyProgressExport(schemaVersion: 1, exportID: UUID(), sourceBundleID: "com.ameneko.eitangolock",
                                      createdAt: Date(), events: [event])
    let firstImportCount = try await store.importLegacyProgress(export)
    let secondImportCount = try await store.importLegacyProgress(export)
    XCTAssertEqual(firstImportCount, 1)
    XCTAssertEqual(secondImportCount, 0)
    let progress = try await store.progress(for: .init(packID: "english3000.v1", itemID: "word-1"))
    XCTAssertEqual(progress.answerCount, 4)
    XCTAssertEqual(progress.correctCount, 3)
    XCTAssertEqual(progress.incorrectCount, 1)

    let forged = LegacyProgressEvent(id: UUID(), sourceBundleID: "com.ameneko.eitangolock",
                                     sourceContentVersion: "legacy", packID: "takken2026.v1", itemID: "q1",
                                     answeredAt: nil, correctCount: 1, incorrectCount: 0, dueAt: nil)
    let forgedExport = LegacyProgressExport(schemaVersion: 1, exportID: UUID(), sourceBundleID: "com.ameneko.eitangolock",
                                            createdAt: Date(), events: [forged])
    do {
      _ = try await store.importLegacyProgress(forgedExport)
      XCTFail("Cross-pack legacy progress must be rejected")
    } catch let error as LegacyMigrationError {
      XCTAssertEqual(error.localizedDescription, LegacyMigrationError.invalidClaim.localizedDescription)
    }
  }

  func testDurableAnswerSubmissionIsIdempotentAcrossRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lockandstudy-idempotency-test-\(UUID().uuidString)")
    let store = LearningDataStore(rootURL: root)
    let prompt = fixturePrompt()
    let sessionID = UUID()
    let answer = StudyAnswerRecord(
      submissionID: "fixed-submission", experienceID: .takken, packID: prompt.packID,
      moduleType: prompt.moduleType, itemID: prompt.itemID, prompt: prompt.prompt,
      choices: prompt.choices, selectedChoiceID: prompt.correctChoiceID,
      correctChoiceID: prompt.correctChoiceID, shortExplanation: prompt.shortExplanation,
      longExplanation: prompt.longExplanation, sourceNote: prompt.sourceNote,
      category: prompt.category, subcategory: prompt.subcategory,
      contentVersion: prompt.contentVersion, questionVersion: prompt.questionVersion,
      examYear: prompt.examYear, lawBasisDate: prompt.lawBasisDate,
      answeredAt: Date(timeIntervalSince1970: 1_000), mode: .unlock,
      sessionID: sessionID, feedbackPlan: .immediate
    )

    let firstWrite = try await store.recordUnique(answer)
    let retryWrite = try await store.recordUnique(answer)
    let answers = try await store.answers()
    let events = try await store.events()
    let progress = try await store.progress(for: prompt.id)
    XCTAssertTrue(firstWrite)
    XCTAssertFalse(retryWrite)
    XCTAssertEqual(answers.count, 1)
    XCTAssertEqual(events.filter { $0.kind == .answerSubmitted }.count, 1)
    XCTAssertEqual(progress.answerCount, 1)
  }

  func testAllMonthAnswerQueryAndDeletionCoverEveryFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lockandstudy-month-test-\(UUID().uuidString)")
    let store = LearningDataStore(rootURL: root)
    let prompt = fixturePrompt()
    for (index, date) in [Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 40_000_000)].enumerated() {
      let record = StudyAnswerRecord(
        submissionID: "month-\(index)", experienceID: .takken, packID: prompt.packID,
        moduleType: prompt.moduleType, itemID: .init(rawValue: "\(index)"), prompt: prompt.prompt,
        choices: prompt.choices, selectedChoiceID: prompt.correctChoiceID,
        correctChoiceID: prompt.correctChoiceID, shortExplanation: prompt.shortExplanation,
        longExplanation: prompt.longExplanation, sourceNote: nil, category: prompt.category,
        subcategory: nil, contentVersion: "1", questionVersion: 1, examYear: 2026,
        lawBasisDate: "2026-04-01", answeredAt: date, mode: .practice,
        sessionID: UUID(), feedbackPlan: .immediate
      )
      let wrote = try await store.recordUnique(record)
      XCTAssertTrue(wrote)
    }
    let monthKeys = try await store.availableAnswerMonthKeys()
    let answers = try await store.answers()
    XCTAssertEqual(monthKeys.count, 2)
    XCTAssertEqual(answers.count, 2)
    let corruptBackup = root.appendingPathComponent("progress.v1.json.corrupt-test.bak")
    try Data("backup".utf8).write(to: corruptBackup)
    try await store.deleteLearningHistory()
    let remainingMonths = try await store.availableAnswerMonthKeys()
    let remainingEvents = try await store.events()
    let remainingBundle = try await store.loadExperienceUnlockBundle()
    XCTAssertTrue(remainingMonths.isEmpty)
    XCTAssertTrue(remainingEvents.isEmpty)
    XCTAssertNil(remainingBundle)
    XCTAssertFalse(FileManager.default.fileExists(atPath: corruptBackup.path))
  }

  func testUnlockBundleCompletionCheckpointRoundTripsAtEveryCrashBoundary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lockandstudy-checkpoint-test-\(UUID().uuidString)")
    let store = LearningDataStore(rootURL: root)
    let now = Date(timeIntervalSince1970: 8_000_000)
    let question = UnlockQuestionSnapshot.safeFallback(.init(
      id: "safe-1", prompt: "継続する行動は？",
      choices: [.init(id: 0, text: "学ぶ"), .init(id: 1, text: "やめる")],
      correctChoiceID: 0, explanation: "短くても続けます。"
    ))
    let challenge = UnlockChallengeSnapshot(
      schemaVersion: 2, id: UUID(), requestID: UUID(), origin: .legacyUnknown,
      experienceID: .safeFallback,
      packID: "english3000.v1", policyVersion: 1, pace: .balanced10,
      reviewLoad: .standard, questions: [question],
      access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
      createdAt: now, expiresAt: now.addingTimeInterval(1_800)
    )
    var bundle = ExperienceUnlockBundleSnapshot(
      schemaVersion: 2, challenge: challenge, completedQuestionIDs: [question.id],
      completionState: .answering, completionEventID: UUID(), createdUnlockSessionID: nil,
      abortReason: nil
    )
    for state in [UnlockCompletionState.answering, .sessionCreated, .eventRecorded, .completed] {
      bundle.completionState = state
      if state == .sessionCreated { bundle.createdUnlockSessionID = UUID() }
      try await store.saveExperienceUnlockBundle(bundle)
      let restored = try await store.loadExperienceUnlockBundle()
      XCTAssertEqual(restored?.completionState, state)
      XCTAssertEqual(restored?.completionEventID, bundle.completionEventID)
      XCTAssertTrue(restored?.isComplete == true)
    }
  }

  private func fixturePrompt() -> StudyPrompt {
    .init(packID: "a", moduleType: .takken, itemID: "1", prompt: "問題", choices: [.init(id: 0, text: "誤り"), .init(id: 1, text: "正しい")], correctChoiceID: 1, shortExplanation: "短い解説", longExplanation: "長い解説", sourceNote: nil, category: "分野", subcategory: nil, contentVersion: "1", questionVersion: 1, examYear: 2026, lawBasisDate: "2026-04-01", isFreeSample: true, speechText: nil, exampleText: nil)
  }
}
