import XCTest
@testable import LockAndStudy

final class VocabularyExperienceTests: XCTestCase {
  func testContentValidationFreeSampleAndQuestionGeneration() async throws {
    let manifest = try await releasedManifest("english3000.v1")
    let package = try VocabularyRepository(bundle: .main).load(manifest: manifest)

    XCTAssertEqual(package.items.count, 3_000)
    XCTAssertEqual(package.freeSampleIDs.count, 250)
    XCTAssertEqual(Set(package.items.map(\.levelCode)), Set(VocabularyLevel.allCases.map(\.rawValue)))
    for level in VocabularyLevel.allCases {
      XCTAssertEqual(package.items.filter { $0.levelCode == level.rawValue && package.freeSampleIDs.contains($0.id) }.count, 50)
    }
    for item in package.items.prefix(100) {
      let question = try VocabularyQuestionGenerator().makeQuestion(for: item)
      XCTAssertEqual(question.choices.count, 4)
      XCTAssertEqual(question.choices[question.correctChoiceID].text, item.correctAnswer)
    }
  }

  func testLearningQueueModesAndFeedbackPlan() async throws {
    let manifest = try await releasedManifest("english3000.v1")
    let items = Array(try VocabularyRepository(bundle: .main).load(manifest: manifest).items.prefix(4))
    let now = Date(timeIntervalSince1970: 2_000_000)
    let firstID = CompositeStudyItemID(packID: manifest.id, itemID: items[0].studyItemID)
    let secondID = CompositeStudyItemID(packID: manifest.id, itemID: items[1].studyItemID)
    var progress: [String: ItemProgress] = [:]
    progress[firstID.storageKey] = SRSScheduler().applying(isCorrect: false, to: .initial(firstID), at: now.addingTimeInterval(-1_000))
    progress[secondID.storageKey] = SRSScheduler().applying(isCorrect: true, to: .initial(secondID), at: now.addingTimeInterval(-172_800))

    let planner = VocabularyLearningQueuePlanner()
    XCTAssertEqual(planner.makeQueue(items: items, progress: progress, mode: .mistakes, count: 10, now: now).map(\.id), [items[0].id])
    XCTAssertEqual(planner.makeQueue(items: items, progress: progress, mode: .weakness, count: 10, now: now).map(\.id), [items[0].id])
    XCTAssertEqual(Set(planner.makeQueue(items: items, progress: progress, mode: .newItems, count: 10, now: now).map(\.id)), Set(items.dropFirst(2).map(\.id)))
    XCTAssertEqual(planner.makeQueue(items: items, progress: progress, mode: .practice, count: 1, now: now).first?.id, items[1].id)
    XCTAssertEqual(planner.makeQueue(items: items, progress: progress, mode: .review, count: 10, now: now).map(\.id), [items[1].id, items[0].id])

    let feedback = VocabularyFeedbackPlanner()
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 0), .immediate)
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 1), .relearn6)
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 2), .relearn12)
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 3), .guided20)
    XCTAssertEqual(feedback.waitSeconds(for: .guided20), 20)
  }

  func testUnlockQuizUsesVocabularySnapshotAndFreeSample() async throws {
    let manifest = try await releasedManifest("english3000.v1")
    var policy = LockPolicy.initial(now: .distantPast)
    policy.accessPacePreset = .bundled20
    let request = UnlockChallengeRequest(
      requestID: UUID(), origin: .manual, policy: policy, manifest: manifest, entitlement: .empty,
      progress: [:],
      learning: LearningDataStore(
        rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      now: Date(timeIntervalSince1970: 3_000_000)
    )
    let challenge = try await VocabularyUnlockChallengeProvider(bundle: .main)
      .makeUnlockChallenge(packID: manifest.id, request: request)

    XCTAssertEqual(challenge.experienceID, .vocabulary)
    XCTAssertEqual(challenge.questions.count, 2)
    XCTAssertTrue(challenge.questions.allSatisfy {
      if case .vocabulary(let question) = $0 { return question.isFreeSample && question.choices.count == 4 }
      return false
    })
  }

  func testWeeklyReportUsesOnlyVocabularyAndCurrentWeek() async throws {
    let manifest = try await releasedManifest("english3000.v1")
    let item = try XCTUnwrap(try VocabularyRepository(bundle: .main).load(manifest: manifest).items.first)
    let now = Date(timeIntervalSince1970: 4_000_000)
    let answers = [
      answer(item: item, manifest: manifest, correct: true, at: now.addingTimeInterval(-3_600), suffix: "1"),
      answer(item: item, manifest: manifest, correct: false, at: now.addingTimeInterval(-86_400), suffix: "2"),
      answer(item: item, manifest: manifest, correct: true, at: now.addingTimeInterval(-864_000), suffix: "old")
    ]
    let composite = CompositeStudyItemID(packID: manifest.id, itemID: item.studyItemID)
    var learned = ItemProgress.initial(composite)
    learned.answerCount = 2
    learned.dueAt = now.addingTimeInterval(-1)
    let report = VocabularyWeeklyReportService().make(
      answers: answers, progress: [composite.storageKey: learned], packID: manifest.id, now: now)

    XCTAssertEqual(report.answers, 2)
    XCTAssertEqual(report.correct, 1)
    XCTAssertEqual(report.accuracy, 50)
    XCTAssertEqual(report.learned, 1)
    XCTAssertEqual(report.due, 1)
  }

  @MainActor
  func testVocabularyRouterAndRegistryIsolation() {
    XCTAssertEqual(VocabularyRouter(destination: .catalog).selectedTab, .words)
    XCTAssertEqual(VocabularyRouter(destination: .learning).selectedTab, .learning)
    let registry = StudyExperienceRegistry.standard()
    XCTAssertEqual(registry.factory(for: "english3000.v1")?.descriptor.id, .vocabulary)
    XCTAssertEqual(registry.factory(for: "takken2026.v1")?.descriptor.id, .takken)
    XCTAssertFalse(registry.factory(for: .vocabulary)?.descriptor.supportedPackIDs.contains("takken2026.v1") ?? true)
  }

  func testVocabularyAndTakkenSettingsAreNamespaced() throws {
    let suiteName = "lockandstudy-settings-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var vocabulary = VocabularySettings.standard
    vocabulary.selectedLevelCodes = [VocabularyLevel.level4.rawValue]
    vocabulary.dailyGoal = 25
    try vocabulary.save(defaults: defaults)
    var takken = TakkenSettings.standard
    takken.questionCount = 5
    takken.selectedDifficulties = ["応用"]
    try takken.save(defaults: defaults)

    XCTAssertEqual(VocabularySettings.load(defaults: defaults), vocabulary)
    XCTAssertEqual(TakkenSettings.load(defaults: defaults), takken)
  }

  func testPendingPreviewDisplayBoundaryAndRecallWindowAreIndependent() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    var preview = makePreview(createdAt: now)

    XCTAssertTrue(preview.isDisplayable(at: now))
    XCTAssertTrue(preview.isDisplayable(at: now.addingTimeInterval(119.999)))
    XCTAssertFalse(preview.isDisplayable(at: now.addingTimeInterval(120)))
    preview.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(2))
    XCTAssertTrue(preview.isUsableForRecall(
      contentVersion: preview.contentVersion,
      now: now.addingTimeInterval(120)))
    XCTAssertFalse(preview.isUsableForRecall(
      contentVersion: preview.contentVersion,
      now: preview.recallExpiresAt))
  }

  func testPendingPreviewRequiresTwoForegroundSecondsAndBackgroundResetsUnconfirmedExposure() {
    let now = Date(timeIntervalSince1970: 11_000_000)
    var preview = makePreview(createdAt: now)
    preview.recordForegroundExposure(seconds: 1.9, at: now.addingTimeInterval(1.9))
    XCTAssertNil(preview.confirmedAt)
    XCTAssertEqual(preview.foregroundExposureSeconds, 1.9, accuracy: 0.0001)
    preview.resetUnconfirmedForegroundExposure()
    XCTAssertEqual(preview.foregroundExposureSeconds, 0)
    preview.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(4))
    XCTAssertNotNil(preview.confirmedAt)
    preview.resetUnconfirmedForegroundExposure()
    XCTAssertEqual(preview.foregroundExposureSeconds, 2)
  }

  func testPendingPreviewPersistenceDoesNotExtendDisplayDeadlineAndDeletionClearsIt() async throws {
    let root = temporaryRoot()
    let now = Date(timeIntervalSince1970: 12_000_000)
    let original = makePreview(createdAt: now)
    var store = LearningDataStore(rootURL: root)
    try await store.saveVocabularyPendingPreview(original)

    let at60 = try await store.loadVocabularyPendingPreview(now: now.addingTimeInterval(60))
    XCTAssertEqual(at60?.displayExpiresAt, original.displayExpiresAt)
    store = LearningDataStore(rootURL: root)
    let at90 = try await store.loadVocabularyPendingPreview(now: now.addingTimeInterval(90))
    XCTAssertEqual(at90?.displayExpiresAt, original.displayExpiresAt)
    let loadedAt121 = try await store.loadVocabularyPendingPreview(
      now: now.addingTimeInterval(121))
    let at121 = try XCTUnwrap(loadedAt121)
    XCTAssertFalse(at121.isDisplayable(at: now.addingTimeInterval(121)))

    try await store.deleteLearningHistory()
    let afterDeletion = try await store.loadVocabularyPendingPreview(now: now)
    XCTAssertNil(afterDeletion)
  }

  @MainActor
  func testVocabularyCompletionCreatesPreviewIdempotentlyWhileOtherExperiencesDoNothing() async throws {
    let originalSettings = VocabularySettings.load()
    defer { try? originalSettings.save() }
    try VocabularySettings.standard.save()
    let root = temporaryRoot()
    let dependencies = DependencyContainer(learningRootURL: root)
    let manifest = try await releasedManifest("english3000.v1")
    let request = UnlockChallengeRequest(
      requestID: UUID(), origin: .manual, policy: .initial(now: .distantPast), manifest: manifest,
      entitlement: .empty, progress: [:], learning: dependencies.learning,
      now: Date(timeIntervalSince1970: 13_000_000))
    let challenge = try await VocabularyUnlockChallengeProvider(bundle: .main)
      .makeUnlockChallenge(packID: manifest.id, request: request)
    let bundle = ExperienceUnlockBundleSnapshot(
      schemaVersion: 2, challenge: challenge,
      completedQuestionIDs: Set(challenge.questions.map(\.id)),
      completionState: .eventRecorded, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil)
    let context = UnlockCompletionContext(
      bundle: bundle, manifest: manifest, dependencies: dependencies, now: request.now)

    try await VocabularyExperience().handleUnlockCompletion(context)
    let loaded = try await dependencies.learning.loadVocabularyPendingPreview(now: request.now)
    let first = try XCTUnwrap(loaded)
    XCTAssertEqual(first.sourceUnlockBundleID, bundle.id)
    XCTAssertTrue(first.isDisplayable(at: request.now))
    try await VocabularyExperience().handleUnlockCompletion(context)
    let reloaded = try await dependencies.learning.loadVocabularyPendingPreview(now: request.now)
    XCTAssertEqual(reloaded, first)

    try await dependencies.learning.saveVocabularyPendingPreview(nil)
    try await TakkenExperience().handleUnlockCompletion(context)
    let afterTakken = try await dependencies.learning.loadVocabularyPendingPreview(now: request.now)
    XCTAssertNil(afterTakken)
  }

  func testConfirmedPreviewIsPrioritizedOnceWithoutDuplicateReview() async throws {
    let originalSettings = VocabularySettings.load()
    defer { try? originalSettings.save() }
    try VocabularySettings.standard.save()
    let manifest = try await releasedManifest("english3000.v1")
    let package = try VocabularyRepository(bundle: .main).load(manifest: manifest)
    let candidates = package.items.filter {
      $0.levelCode == VocabularyLevel.level0.rawValue && package.freeSampleIDs.contains($0.id)
    }
    let previewItem = try XCTUnwrap(candidates.last)
    let now = Date(timeIntervalSince1970: 14_000_000)
    let root = temporaryRoot()
    let store = LearningDataStore(rootURL: root)
    var preview = makePreview(
      itemID: previewItem.id, contentVersion: previewItem.metadata.contentVersion, createdAt: now)
    preview.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(2))
    try await store.saveVocabularyPendingPreview(preview)
    let composite = CompositeStudyItemID(packID: manifest.id, itemID: previewItem.studyItemID)
    var due = ItemProgress.initial(composite)
    due.dueAt = now.addingTimeInterval(-1)
    var policy = LockPolicy.initial(now: now)
    policy.accessPacePreset = .bundled20
    policy.reviewLoadPreset = .reviewIntensive
    let request = UnlockChallengeRequest(
      requestID: UUID(), origin: .manual, policy: policy, manifest: manifest, entitlement: .empty,
      progress: [composite.storageKey: due], learning: store, now: now.addingTimeInterval(3))

    let first = try await VocabularyUnlockChallengeProvider(bundle: .main)
      .makeUnlockChallenge(packID: manifest.id, request: request)
    XCTAssertEqual(first.questions.first?.id.rawValue, previewItem.id)
    XCTAssertEqual(first.questions.filter { $0.id.rawValue == previewItem.id }.count, 1)
    let consumed = try await store.loadVocabularyPendingPreview(now: request.now)
    XCTAssertNotNil(consumed?.consumedAt)

    let second = try await VocabularyUnlockChallengeProvider(bundle: .main)
      .makeUnlockChallenge(packID: manifest.id, request: .init(
        requestID: UUID(), origin: .manual, policy: policy, manifest: manifest, entitlement: .empty,
        progress: [:], learning: store, now: now.addingTimeInterval(4)))
    XCTAssertNotEqual(second.questions.first?.id.rawValue, previewItem.id)
  }

  func testPreviewPriorityRejectsContentVersionLevelAndAccessMismatches() async throws {
    let originalSettings = VocabularySettings.load()
    defer { try? originalSettings.save() }
    let manifest = try await releasedManifest("english3000.v1")
    let package = try VocabularyRepository(bundle: .main).load(manifest: manifest)
    let now = Date(timeIntervalSince1970: 15_000_000)

    let level0Samples = package.items.filter {
      $0.levelCode == VocabularyLevel.level0.rawValue && package.freeSampleIDs.contains($0.id)
    }
    let laterSample = try XCTUnwrap(level0Samples.last)
    try VocabularySettings.standard.save()
    var stale = makePreview(itemID: laterSample.id, contentVersion: "obsolete", createdAt: now)
    stale.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(2))
    var generatedChallenge = try await challenge(with: stale, manifest: manifest, now: now)
    XCTAssertNotEqual(generatedChallenge.questions.first?.id.rawValue, laterSample.id)

    var levelSettings = VocabularySettings.standard
    levelSettings.selectedLevelCodes = [VocabularyLevel.level1.rawValue]
    try levelSettings.save()
    var wrongLevel = makePreview(
      itemID: laterSample.id, contentVersion: laterSample.metadata.contentVersion, createdAt: now)
    wrongLevel.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(2))
    generatedChallenge = try await challenge(with: wrongLevel, manifest: manifest, now: now)
    XCTAssertNotEqual(generatedChallenge.questions.first?.id.rawValue, laterSample.id)

    try VocabularySettings.standard.save()
    let paid = try XCTUnwrap(package.items.last {
      $0.levelCode == VocabularyLevel.level0.rawValue && !package.freeSampleIDs.contains($0.id)
    })
    var inaccessible = makePreview(
      itemID: paid.id, contentVersion: paid.metadata.contentVersion, createdAt: now)
    inaccessible.recordForegroundExposure(seconds: 2, at: now.addingTimeInterval(2))
    generatedChallenge = try await challenge(with: inaccessible, manifest: manifest, now: now)
    XCTAssertNotEqual(generatedChallenge.questions.first?.id.rawValue, paid.id)
  }

  @MainActor
  func testExpiredUnlockSubmissionAbortsBundleWithoutRecordingAnswer() async throws {
    let root = temporaryRoot()
    let dependencies = DependencyContainer(learningRootURL: root)
    let manifest = try await releasedManifest("english3000.v1")
    let now = Date().addingTimeInterval(-ExperienceUnlockBundleSnapshot.expirationInterval - 1)
    let challenge = try await VocabularyUnlockChallengeProvider(bundle: .main)
      .makeUnlockChallenge(packID: manifest.id, request: .init(
        requestID: UUID(), origin: .manual, policy: .initial(now: now), manifest: manifest,
        entitlement: .empty, progress: [:], learning: dependencies.learning, now: now))
    let question = try XCTUnwrap(challenge.questions.first)
    let bundle = ExperienceUnlockBundleSnapshot(
      schemaVersion: 2, challenge: challenge, completedQuestionIDs: [],
      completionState: .answering, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil)
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    let model = AppModel(dependencies: dependencies)

    let result = await model.submitUnlockAnswer(
      question: question, selectedChoiceID: question.correctChoiceID, feedback: .immediate)

    XCTAssertEqual(result, .expired)
    let restored = try await dependencies.learning.loadExperienceUnlockBundle()
    let answers = try await dependencies.learning.answers()
    XCTAssertEqual(restored?.completionState, .aborted)
    XCTAssertTrue(answers.isEmpty)
    XCTAssertNil(model.unlockChallenge)
  }

  private func releasedManifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(bundle: .main).releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == id })
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-preview-test-\(UUID().uuidString)", isDirectory: true)
  }

  private func makePreview(
    itemID: String = "vocabulary-preview-item",
    contentVersion: String = "v1",
    createdAt: Date
  ) -> VocabularyPendingPreview {
    .init(
      id: UUID(), sourceUnlockBundleID: UUID(), itemID: itemID,
      contentVersion: contentVersion, createdAt: createdAt,
      recallExpiresAt: createdAt.addingTimeInterval(VocabularyPendingPreview.recallDuration),
      confirmedAt: nil, consumedAt: nil, foregroundExposureSeconds: 0)
  }

  private func challenge(
    with preview: VocabularyPendingPreview,
    manifest: StudyPackManifest,
    now: Date
  ) async throws -> UnlockChallengeSnapshot {
    let store = LearningDataStore(rootURL: temporaryRoot())
    try await store.saveVocabularyPendingPreview(preview)
    return try await VocabularyUnlockChallengeProvider(bundle: .main).makeUnlockChallenge(
      packID: manifest.id,
      request: .init(
        requestID: UUID(), origin: .manual, policy: .initial(now: now), manifest: manifest,
        entitlement: .empty, progress: [:], learning: store, now: now.addingTimeInterval(3)))
  }

  private func answer(item: VocabularyItem, manifest: StudyPackManifest, correct: Bool, at date: Date, suffix: String) -> StudyAnswerRecord {
    .init(
      submissionID: "weekly-\(suffix)", experienceID: .vocabulary, packID: manifest.id,
      moduleType: .vocabulary, itemID: item.studyItemID, prompt: item.prompt,
      choices: item.options.enumerated().map { .init(id: $0.offset, text: $0.element) },
      selectedChoiceID: correct ? item.correctIndex : (item.correctIndex + 1) % item.options.count,
      correctChoiceID: item.correctIndex, shortExplanation: item.explanationJa,
      longExplanation: item.explanationJa, sourceNote: nil, category: item.levelCode,
      subcategory: item.primaryPosJa, contentVersion: item.metadata.contentVersion,
      questionVersion: 1, examYear: nil, lawBasisDate: nil, answeredAt: date,
      mode: .practice, sessionID: UUID(), feedbackPlan: correct ? .immediate : .relearn6
    )
  }
}
