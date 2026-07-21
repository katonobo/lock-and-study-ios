import XCTest

@testable import LockAndStudy

final class LearningReportTests: XCTestCase {
  func testCurrentSevenDayPeriodIncludesStartAndExcludesEnd() throws {
    let calendar = calendar(timeZone: "Asia/Tokyo")
    let now = try date("2026-07-22T12:00:00+09:00")
    let period = LearningReportPeriod.currentSevenDays(now: now, calendar: calendar)
    XCTAssertTrue(period.contains(period.startInclusive))
    XCTAssertTrue(period.contains(period.endExclusive.addingTimeInterval(-0.001)))
    XCTAssertFalse(period.contains(period.startInclusive.addingTimeInterval(-0.001)))
    XCTAssertFalse(period.contains(period.endExclusive))
    XCTAssertEqual(
      calendar.dateComponents([.day], from: period.startInclusive, to: period.endExclusive).day, 7)
  }

  func testPreviousCalendarDayAnswerIsNotIncludedAcrossMidnight() throws {
    let calendar = calendar(timeZone: "Asia/Tokyo")
    let now = try date("2026-07-22T00:01:00+09:00")
    let period = LearningReportPeriod.currentSevenDays(now: now, calendar: calendar)
    let beforeStart = period.startInclusive.addingTimeInterval(-1)
    let atStart = period.startInclusive
    let report = try makeReport(
      answers: [answer(at: beforeStart, suffix: "before"), answer(at: atStart, suffix: "start")],
      now: now,
      calendar: calendar)
    XCTAssertEqual(report.answerCount, 1)
  }

  func testFixedCalendarAndTimeZoneProduceStablePeriod() throws {
    let now = try date("2026-07-22T03:00:00Z")
    let tokyo = LearningReportPeriod.currentSevenDays(
      now: now, calendar: calendar(timeZone: "Asia/Tokyo"))
    let utc = LearningReportPeriod.currentSevenDays(
      now: now, calendar: calendar(timeZone: "UTC"))
    XCTAssertNotEqual(tokyo.startInclusive, utc.startInclusive)
    XCTAssertEqual(
      tokyo,
      LearningReportPeriod.currentSevenDays(now: now, calendar: calendar(timeZone: "Asia/Tokyo")))
  }

  func testDSTWeekContainsSevenCalendarDaysWithoutFixedSecondAssumption() throws {
    let calendar = calendar(timeZone: "America/Los_Angeles")
    let now = try date("2026-03-10T12:00:00-07:00")
    let period = LearningReportPeriod.currentSevenDays(now: now, calendar: calendar)
    XCTAssertEqual(
      calendar.dateComponents([.day], from: period.startInclusive, to: period.endExclusive).day, 7)
    XCTAssertNotEqual(period.endExclusive.timeIntervalSince(period.startInclusive), 7 * 86_400)
    let report = try makeReport(now: now, calendar: calendar)
    XCTAssertEqual(report.dailyPoints.count, 7)
  }

  func testOnlyShieldOriginCountsAsLearningOpportunity() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let events = [
      event(.unlockChallengeStarted, at: now, session: UUID(), origin: .shield),
      event(.unlockChallengeStarted, at: now, session: UUID(), origin: .manual),
      event(.unlockChallengeStarted, at: now, session: UUID(), origin: .legacyUnknown),
    ]
    XCTAssertEqual(try makeReport(events: events, now: now).learningOpportunityCount, 1)
  }

  func testManualOriginNeverCountsAsLearningOpportunity() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let session = UUID()
    let report = try makeReport(
      answers: [answer(at: now, session: session)],
      events: [event(.unlockChallengeStarted, at: now, session: session, origin: .manual)],
      now: now)
    XCTAssertEqual(report.learningOpportunityCount, 0)
    XCTAssertEqual(report.learningStartedCount, 0)
  }

  func testShieldOpportunityCountsAsStartedOnlyAfterAnAnswer() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let answered = UUID()
    let abandoned = UUID()
    let report = try makeReport(
      answers: [answer(at: now, session: answered)],
      events: [
        event(.unlockChallengeStarted, at: now, session: answered, origin: .shield),
        event(.unlockChallengeStarted, at: now, session: abandoned, origin: .shield),
      ], now: now)
    XCTAssertEqual(report.learningOpportunityCount, 2)
    XCTAssertEqual(report.learningStartedCount, 1)
  }

  func testOnlyActualUnlockSuccessCountsAsEarnedUnlock() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let report = try makeReport(
      events: [
        event(.unlockSuccess, at: now, session: UUID(), origin: .shield),
        event(.unlockChallengeCompleted, at: now, session: UUID(), origin: .shield),
      ], now: now)
    XCTAssertEqual(report.earnedUnlockCount, 1)
    XCTAssertEqual(report.shieldEarnedUnlockCount, 1)
  }

  func testDuplicateSessionEventsAreNotDoubleCounted() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let session = UUID()
    let report = try makeReport(
      events: [
        event(.unlockChallengeStarted, at: now, session: session, origin: .shield),
        event(
          .unlockChallengeStarted, at: now.addingTimeInterval(1), session: session, origin: .shield),
      ], now: now)
    XCTAssertEqual(report.learningOpportunityCount, 1)
  }

  func testPracticeAndUnlockAnswersRemainDistinguishable() throws {
    let now = try date("2026-07-22T12:00:00Z")
    let values = [
      answer(at: now, mode: .practice, suffix: "practice"),
      answer(at: now, mode: .unlock, suffix: "unlock"),
    ]
    XCTAssertEqual(values.filter { $0.mode == .unlock }.count, 1)
    XCTAssertEqual(values.filter { $0.mode != .unlock }.count, 1)
    XCTAssertEqual(try makeReport(answers: values, now: now).answerCount, 2)
  }

  func testNewAndReviewRolesUseTypedFieldsAndLegacyReconstruction() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let first = answer(at: now, role: nil, suffix: "first")
    let later = answer(at: now.addingTimeInterval(60), role: nil, suffix: "later")
    let typed = answer(
      at: now.addingTimeInterval(120), role: .mistakeReview, suffix: "typed")
    let snapshot = snapshot(answers: [later, typed, first])
    XCTAssertEqual(snapshot.effectiveLearningRole(for: first), .newItem)
    XCTAssertEqual(snapshot.effectiveLearningRole(for: later), .generalReview)
    XCTAssertEqual(snapshot.effectiveLearningRole(for: typed), .mistakeReview)
  }

  func testVocabularyProviderDoesNotIncludeTakkenAnswers() async throws {
    let manifests = try await ContentRepository(bundle: .main).releasedManifests()
    let vocabulary = try XCTUnwrap(manifests.first { $0.id == "english3000.v1" })
    let now = Date()
    let values = [
      answer(
        packID: vocabulary.id, experienceID: .vocabulary, module: .vocabulary, at: now, suffix: "v"),
      answer(packID: "takken2026.v1", experienceID: .takken, module: .takken, at: now, suffix: "t"),
    ]
    let section = try VocabularyReportProvider().makeReportSection(
      snapshot: snapshot(answers: values, manifests: manifests), manifest: vocabulary,
      period: .currentSevenDays(now: now, calendar: .current), now: now, calendar: .current)
    XCTAssertEqual(section.metrics.first { $0.id == "vocabulary.answers" }?.value, "1問")
  }

  func testTakkenProviderDoesNotIncludeVocabularyAnswers() async throws {
    let manifests = try await ContentRepository(bundle: .main).releasedManifests()
    let takken = try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" })
    let now = Date()
    let values = [
      answer(packID: takken.id, experienceID: .takken, module: .takken, at: now, suffix: "t"),
      answer(
        packID: "english3000.v1", experienceID: .vocabulary, module: .vocabulary, at: now,
        suffix: "v"),
    ]
    let section = try TakkenReportProvider().makeReportSection(
      snapshot: snapshot(answers: values, manifests: manifests), manifest: takken,
      period: .currentSevenDays(now: now, calendar: .current), now: now, calendar: .current)
    XCTAssertEqual(section.metrics.first { $0.id == "takken.answers" }?.value, "1問")
  }

  func testStreakCanExceedSevenDays() throws {
    let calendar = calendar(timeZone: "UTC")
    let now = try date("2026-07-22T12:00:00Z")
    let answers = (0..<12).map { offset in
      answer(
        at: calendar.date(byAdding: .day, value: -offset, to: now) ?? now,
        itemID: .init(rawValue: "item-\(offset)"), suffix: "\(offset)")
    }
    XCTAssertEqual(try makeReport(answers: answers, now: now, calendar: calendar).streak, 12)
  }

  func testDeletingLearningHistoryMakesReportEmpty() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LearningDataStore(rootURL: root)
    try await store.record(answer(at: Date(), suffix: "delete"))
    try await store.deleteLearningHistory()
    let report = try LearningReportService(providers: []).makeReport(
      snapshot: snapshot(
        answers: try await store.answers(), events: try await store.events(),
        progress: try await store.allProgress()),
      scope: .allMaterials, now: Date(), calendar: .current)
    XCTAssertTrue(report.isEmpty)
  }

  func testEmptyEntitlementStillGeneratesCurrentWeekReport() throws {
    let now = Date()
    let report = try LearningReportService(providers: []).makeReport(
      snapshot: snapshot(answers: [answer(at: now)], entitlement: .empty),
      scope: .allMaterials, now: now, calendar: .current)
    XCTAssertEqual(report.answerCount, 1)
  }

  func testLegacyEventAnswerAndChallengeDecodeWithoutNewOptionalFields() throws {
    let event = event(.unlockChallengeStarted, at: Date(), session: UUID(), origin: .shield)
    let decodedEvent: LearningEvent = try decodeAfterRemoving(
      event, keys: ["unlockOrigin"], as: LearningEvent.self)
    XCTAssertEqual(decodedEvent.resolvedUnlockOrigin, .legacyUnknown)

    let record = answer(at: Date(), role: .newItem)
    let decodedAnswer: StudyAnswerRecord = try decodeAfterRemoving(
      record,
      keys: ["learningRole", "wasNewAtSubmission", "wasDueAtSubmission"],
      as: StudyAnswerRecord.self)
    XCTAssertNil(decodedAnswer.learningRole)
    XCTAssertNil(decodedAnswer.wasNewAtSubmission)

    let question = UnlockQuestionSnapshot.safeFallback(
      .init(
        id: "legacy-safe", prompt: "学習を続けますか？",
        choices: [.init(id: 0, text: "続ける")], correctChoiceID: 0,
        explanation: "過去データの復元確認"))
    let now = Date()
    let challenge = UnlockChallengeSnapshot(
      schemaVersion: 1, id: UUID(), requestID: UUID(), origin: .shield,
      experienceID: .safeFallback, packID: "english3000.v1", policyVersion: 1,
      pace: .balanced10, reviewLoad: .standard, questions: [question],
      access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
      createdAt: now, expiresAt: now.addingTimeInterval(1_800))
    let decodedChallenge: UnlockChallengeSnapshot = try decodeAfterRemoving(
      challenge, keys: ["origin"], as: UnlockChallengeSnapshot.self)
    XCTAssertEqual(decodedChallenge.resolvedOrigin, .legacyUnknown)
  }

  func testShareTextContainsOnlyAggregateLearningValues() throws {
    let now = Date()
    let report = try makeReport(answers: [answer(at: now)], now: now)
    let text = LearningReportShareService().text(for: report, calendar: .current)
    XCTAssertTrue(LearningReportPrivacyPolicy.validateShareText(text))
    for forbidden in [
      "applicationToken", "categoryToken", "webDomainToken", "managementCode",
      "緊急解除理由", "transactionID", "個別の問題文",
    ] {
      XCTAssertFalse(text.contains(forbidden))
    }
  }

  func testEmptyReportDoesNotCrashAndHasNaturalHeadline() throws {
    let report = try makeReport(now: Date())
    XCTAssertTrue(report.isEmpty)
    XCTAssertEqual(report.dailyPoints.count, 7)
    XCTAssertEqual(report.headline, "今週の学習を、ここに積み上げていきます")
  }

  @MainActor
  func testNormalStudySaveFailureDoesNotReturnRecordedResultOrAdvanceSRS() async throws {
    let blockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-report-blocked-\(UUID().uuidString)")
    try Data("not-a-directory".utf8).write(to: blockedRoot)
    defer { try? FileManager.default.removeItem(at: blockedRoot) }
    let dependencies = DependencyContainer(learningRootURL: blockedRoot)
    let manifests = try await dependencies.content.releasedManifests()
    let manifest = try XCTUnwrap(manifests.first { $0.id == "english3000.v1" })
    let item = try XCTUnwrap(try VocabularyRepository().load(manifest: manifest).items.first)
    let question = try VocabularyQuestionGenerator().makeQuestion(for: item)
    let context = StudyExperienceContext(
      manifest: manifest, dependencies: dependencies,
      reportProviders: [VocabularyReportProvider(), TakkenReportProvider()],
      destination: .home, openMaterialSelection: {}, beginUnlockStudy: {}, completeFirstRun: {})
    let model = VocabularyAppModel(context: context)
    let result = await model.recordAnswer(
      question: question, selectedChoiceID: question.correctChoiceID,
      sessionID: UUID(), attempt: 0)
    guard case .failed = result else {
      return XCTFail("保存失敗を記録成功として扱ってはいけません")
    }
    let progress = try? await dependencies.learning.allProgress()
    XCTAssertTrue(progress?.isEmpty ?? true)
  }

  @MainActor
  func testTakkenNormalStudySaveFailureDoesNotReturnRecordedResultOrAdvanceSRS() async throws {
    let blockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-report-takken-blocked-\(UUID().uuidString)")
    try Data("not-a-directory".utf8).write(to: blockedRoot)
    defer { try? FileManager.default.removeItem(at: blockedRoot) }
    let dependencies = DependencyContainer(learningRootURL: blockedRoot)
    let manifests = try await dependencies.content.releasedManifests()
    let manifest = try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" })
    let question = try XCTUnwrap(try TakkenQuestionRepository().load(manifest: manifest).first)
    let context = StudyExperienceContext(
      manifest: manifest, dependencies: dependencies,
      reportProviders: [VocabularyReportProvider(), TakkenReportProvider()],
      destination: .home, openMaterialSelection: {}, beginUnlockStudy: {}, completeFirstRun: {})
    let model = TakkenAppModel(context: context)
    let result = await model.recordAnswer(
      question: question, selectedChoiceID: question.correctIndex,
      sessionID: UUID(), attempt: 0)
    guard case .failed = result else {
      return XCTFail("宅建の保存失敗を記録成功として扱ってはいけません")
    }
    let progress = try? await dependencies.learning.allProgress()
    XCTAssertTrue(progress?.isEmpty ?? true)
  }

  @MainActor
  func testUnlockCompletionWithoutCreatedSessionRecordsChallengeCompleted() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let dependencies = DependencyContainer(learningRootURL: root)
    let now = Date()
    let question = UnlockQuestionSnapshot.safeFallback(
      .init(
        id: "safe-report", prompt: "学ぶ？",
        choices: [.init(id: 0, text: "学ぶ")], correctChoiceID: 0, explanation: "続けます"))
    let challenge = UnlockChallengeSnapshot(
      schemaVersion: 2, id: UUID(), requestID: UUID(), origin: .manual,
      experienceID: .safeFallback, packID: "english3000.v1", policyVersion: 1,
      pace: .balanced10, reviewLoad: .standard, questions: [question],
      access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
      createdAt: now, expiresAt: now.addingTimeInterval(1_800))
    let bundle = ExperienceUnlockBundleSnapshot(
      schemaVersion: 2, challenge: challenge, completedQuestionIDs: [question.id],
      completionState: .answering, completionEventID: UUID(), createdUnlockSessionID: nil,
      abortReason: nil)
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    let model = AppModel(dependencies: dependencies)
    await model.completeUnlockChallenge()
    let events = try await dependencies.learning.events()
    XCTAssertEqual(events.filter { $0.kind == .unlockChallengeCompleted }.count, 1)
    XCTAssertFalse(events.contains { $0.kind == .unlockSuccess })
  }

  private func makeReport(
    answers: [StudyAnswerRecord] = [],
    events: [LearningEvent] = [],
    now: Date,
    calendar: Calendar = .current
  ) throws -> LearningReport {
    try LearningReportService(providers: []).makeReport(
      snapshot: snapshot(answers: answers, events: events), scope: .allMaterials,
      now: now, calendar: calendar)
  }

  private func snapshot(
    answers: [StudyAnswerRecord] = [],
    events: [LearningEvent] = [],
    progress: [String: ItemProgress] = [:],
    manifests: [StudyPackManifest] = [],
    entitlement: CommerceEntitlementSnapshot = .empty
  ) -> LearningReportDataSnapshot {
    .init(
      answers: answers, events: events, progress: progress, manifests: manifests,
      entitlement: entitlement)
  }

  private func answer(
    packID: StudyPackID = "english3000.v1",
    experienceID: StudyExperienceID = .vocabulary,
    module: StudyModuleType = .vocabulary,
    at date: Date,
    mode: StudyMode = .practice,
    session: UUID = UUID(),
    itemID: StudyItemID = "shared-item",
    role: AnswerLearningRole? = .newItem,
    suffix: String = UUID().uuidString
  ) -> StudyAnswerRecord {
    .init(
      submissionID: "report-\(suffix)", experienceID: experienceID, packID: packID,
      moduleType: module, itemID: itemID, prompt: "集計用の問題",
      choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤り")],
      selectedChoiceID: 0, correctChoiceID: 0, shortExplanation: "集計用",
      longExplanation: "集計用", sourceNote: nil, category: "分野", subcategory: "小分野",
      contentVersion: "test", questionVersion: 1, examYear: 2026,
      lawBasisDate: "2026-04-01", answeredAt: date, mode: mode, sessionID: session,
      feedbackPlan: .immediate, learningRole: role,
      wasNewAtSubmission: role.map { $0 == .newItem }, wasDueAtSubmission: role.map { _ in false })
  }

  private func event(
    _ kind: LearningEventKind,
    at date: Date,
    session: UUID?,
    origin: UnlockChallengeOrigin?
  ) -> LearningEvent {
    .init(
      kind: kind, occurredAt: date, packID: "english3000.v1", sessionID: session,
      unlockOrigin: origin)
  }

  private func calendar(timeZone identifier: String) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: identifier) ?? .gmt
    value.locale = Locale(identifier: "en_US_POSIX")
    return value
  }

  private func date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    return try XCTUnwrap(formatter.date(from: value))
  }

  private func decodeAfterRemoving<T: Codable, U: Decodable>(
    _ value: T,
    keys: [String],
    as type: U.Type
  ) throws -> U {
    let data = try SharedJSON.encoder().encode(value)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for key in keys { object.removeValue(forKey: key) }
    return try SharedJSON.decoder().decode(
      U.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
