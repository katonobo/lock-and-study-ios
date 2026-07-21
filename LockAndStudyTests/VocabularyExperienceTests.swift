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
      requestID: UUID(), policy: policy, manifest: manifest, entitlement: .empty,
      progress: [:], now: Date(timeIntervalSince1970: 3_000_000)
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
    let report = VocabularyWeeklyReportService().make(answers: answers, progress: [composite.storageKey: learned], now: now)

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
    vocabulary.save(defaults: defaults)
    var takken = TakkenSettings.standard
    takken.questionCount = 5
    takken.selectedDifficulties = ["応用"]
    takken.save(defaults: defaults)

    XCTAssertEqual(VocabularySettings.load(defaults: defaults), vocabulary)
    XCTAssertEqual(TakkenSettings.load(defaults: defaults), takken)
  }

  private func releasedManifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(bundle: .main).releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == id })
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
