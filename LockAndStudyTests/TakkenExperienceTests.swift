import XCTest
@testable import LockAndStudy

final class TakkenExperienceTests: XCTestCase {
  func testQuestionRepositoryMetadataDifficultyAndAnnualReviewContract() async throws {
    let manifest = try await releasedManifest()
    let questions = try TakkenQuestionRepository(
      packageRoot: try XCTUnwrap(Bundle.main.resourceURL)
    ).load(manifest: manifest)

    XCTAssertEqual(questions.count, 100)
    XCTAssertEqual(Set(questions.map(\.category)), ["宅建業法"])
    XCTAssertEqual(Set(questions.map(\.difficulty)), ["基礎", "標準", "応用"])
    XCTAssertGreaterThan(Set(questions.compactMap(\.subCategory)).count, 5)
    XCTAssertTrue(questions.allSatisfy { $0.examYear == 2026 && $0.lawBasisDate == "2026-04-01" })
    XCTAssertTrue(questions.allSatisfy { $0.reviewStatus == "checked" && !$0.isPlaceholder && !$0.retired })
    XCTAssertEqual(manifest.qualification?.requiresAnnualReview, true)
    XCTAssertFalse(manifest.saleReady)
  }

  func testQuestionServiceListFiltersAndQuizSettings() async throws {
    let manifest = try await releasedManifest()
    let questions = try TakkenQuestionRepository(
      packageRoot: try XCTUnwrap(Bundle.main.resourceURL)
    ).load(manifest: manifest)
    let first = questions[0], second = questions[1]
    let firstID = CompositeStudyItemID(packID: manifest.id, itemID: .init(rawValue: first.id))
    let secondID = CompositeStudyItemID(packID: manifest.id, itemID: .init(rawValue: second.id))
    let now = Date(timeIntervalSince1970: 5_000_000)
    let progress = [
      firstID.storageKey: SRSScheduler().applying(isCorrect: false, to: .initial(firstID), at: now),
      secondID.storageKey: SRSScheduler().applying(isCorrect: true, to: .initial(secondID), at: now)
    ]
    let service = TakkenQuestionService()
    XCTAssertTrue(service.filter(questions: questions, progress: progress, packID: manifest.id, status: .incorrect).contains { $0.id == first.id })
    XCTAssertTrue(service.filter(questions: questions, progress: progress, packID: manifest.id, status: .correct).contains { $0.id == second.id })
    let applied = service.filter(questions: questions, progress: progress, packID: manifest.id, difficulties: ["応用"])
    XCTAssertFalse(applied.isEmpty)
    XCTAssertTrue(applied.allSatisfy { $0.difficulty == "応用" })

    var settings = TakkenSettings.standard
    settings.selectedDifficulties = ["基礎"]
    settings.last30DaysFocus = true
    settings.questionCount = 5
    let queue = service.practiceQuestions(
      questions: questions, progress: progress, packID: manifest.id,
      settings: settings, mode: .practice, count: settings.questionCount, now: now
    )
    XCTAssertEqual(queue.count, 5)
    XCTAssertTrue(queue.allSatisfy { $0.difficulty == "基礎" })
    let feedback = TakkenFeedbackPlanner()
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 1), .relearn6)
    XCTAssertEqual(feedback.plan(wrongAttemptCount: 2), .relearn12)
    XCTAssertEqual(feedback.waitSeconds(for: .relearn12), 15)
  }

  func testListAndDetailViewModelsExposeCategoriesAndAnswerHistory() async throws {
    let manifest = try await releasedManifest()
    let questions = try TakkenQuestionRepository(
      packageRoot: try XCTUnwrap(Bundle.main.resourceURL)
    ).load(manifest: manifest)
    let list = TakkenQuestionListViewModel(questions: questions, progress: [:], packID: manifest.id)
    XCTAssertEqual(list.categories, ["宅建業法"])
    XCTAssertGreaterThan(list.subCategories(in: "宅建業法").count, 5)
    let question = questions[0]
    let recent = answer(question: question, manifest: manifest, correct: false, at: Date(timeIntervalSince1970: 7_000), suffix: "recent")
    let old = answer(question: question, manifest: manifest, correct: true, at: Date(timeIntervalSince1970: 6_000), suffix: "old")
    let detail = TakkenQuestionDetailViewModel(
      question: question, answers: [old, recent], packID: manifest.id)
    XCTAssertEqual(detail.answerHistory.map(\.submissionID), [recent.submissionID, old.submissionID])
    XCTAssertFalse(detail.correctChoiceText.isEmpty)
    XCTAssertFalse(detail.explanation.isEmpty)
  }

  func testRecordsAndUnlockQuestionSelection() async throws {
    let manifest = try await releasedManifest()
    let questions = try TakkenQuestionRepository(
      packageRoot: try XCTUnwrap(Bundle.main.resourceURL)
    ).load(manifest: manifest)
    let now = Date(timeIntervalSince1970: 6_000_000)
    let answers = [
      answer(question: questions[0], manifest: manifest, correct: true, at: now, suffix: "1"),
      answer(question: questions[1], manifest: manifest, correct: false, at: now, suffix: "2")
    ]
    let summary = TakkenRecordsAnalyzer().summary(
      answers: answers, packID: manifest.id, now: now)
    XCTAssertEqual(summary.answerCount, 2)
    XCTAssertEqual(summary.correctCount, 1)
    XCTAssertEqual(summary.wrongCount, 1)
    XCTAssertEqual(summary.byCategory["宅建業法"]?.answered, 2)
    XCTAssertNotNil(summary.bySubCategory[questions[0].subCategory ?? ""])

    var policy = LockPolicy.initial(now: .distantPast)
    policy.accessPacePreset = .extended30
    let challenge = try await TakkenUnlockChallengeProvider().makeUnlockChallenge(
      packID: manifest.id,
      request: .init(
        requestID: UUID(), origin: .manual, policy: policy, manifest: manifest, entitlement: .empty,
        progress: [:], learning: temporaryLearningStore(), now: now)
    )
    XCTAssertEqual(challenge.experienceID, .takken)
    XCTAssertEqual(challenge.questions.count, 3)
    XCTAssertTrue(challenge.questions.allSatisfy { if case .takken = $0 { return true }; return false })
    XCTAssertEqual(challenge.access.reason, .freeSample)
  }

  func testFreePremiumSplitAndSafeFallback() async throws {
    let manifest = try await releasedManifest()
    let access = ContentAccessService()
    XCTAssertEqual(access.decision(isFreeSample: true, manifest: manifest, entitlement: .empty).reason, .freeSample)
    XCTAssertFalse(access.decision(isFreeSample: false, manifest: manifest, entitlement: .empty).isAllowed)
    let now = Date(timeIntervalSince1970: 7_000_000)
    let fallback = try await SafeFallbackUnlockChallengeProvider().makeUnlockChallenge(
      packID: manifest.id,
      request: .init(
        requestID: UUID(), origin: .manual, policy: .initial(now: now), manifest: manifest,
        entitlement: .empty, progress: [:], learning: temporaryLearningStore(), now: now)
    )
    XCTAssertEqual(fallback.experienceID, .safeFallback)
    XCTAssertTrue(fallback.questions.allSatisfy { if case .safeFallback = $0 { return true }; return false })
  }

  @MainActor
  func testTakkenRouterIsolation() {
    XCTAssertEqual(TakkenRouter(destination: .catalog).selectedTab, .questions)
    XCTAssertEqual(TakkenRouter(destination: .learning).selectedTab, .practice)
    XCTAssertEqual(TakkenRouter(destination: .settings).selectedTab, .settings)
  }

  private func releasedManifest() async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(source: BundledContentSource(bundle: .main))
      .releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" })
  }

  private func temporaryLearningStore() -> LearningDataStore {
    LearningDataStore(
      rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }

  private func answer(question: TakkenQuestion, manifest: StudyPackManifest, correct: Bool, at date: Date, suffix: String) -> StudyAnswerRecord {
    .init(
      submissionID: "takken-\(suffix)", experienceID: .takken, packID: manifest.id,
      moduleType: .takken, itemID: .init(rawValue: question.id), prompt: question.prompt,
      choices: question.choices.enumerated().map {
        StudyChoice(id: $0.offset, text: $0.element.text)
      },
      selectedChoiceID: correct ? question.correctIndex : (question.correctIndex + 1) % question.choices.count,
      correctChoiceID: question.correctIndex, shortExplanation: question.shortExplanation ?? question.explanation,
      longExplanation: question.longExplanation ?? question.explanation, sourceNote: question.sourceNote,
      category: question.category, subcategory: question.subCategory, contentVersion: manifest.contentVersion,
      questionVersion: question.version ?? 1, examYear: question.examYear, lawBasisDate: question.lawBasisDate,
      answeredAt: date, mode: .practice, sessionID: UUID(), feedbackPlan: correct ? .immediate : .relearn6,
      difficulty: question.difficulty, questionFormat: question.format?.rawValue,
      keyPoint: question.keyPoint, tags: question.tags
    )
  }
}
