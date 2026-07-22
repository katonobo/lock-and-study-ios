import Combine
import Foundation
import SwiftUI

enum TakkenTab: Hashable, Sendable { case home, questions, practice, records, settings }

@MainActor
final class TakkenRouter: ObservableObject {
  @Published var selectedTab: TakkenTab

  init(destination: StudyExperienceDestination) {
    switch destination {
    case .catalog: selectedTab = .questions
    case .learning: selectedTab = .practice
    case .records: selectedTab = .records
    case .settings: selectedTab = .settings
    default: selectedTab = .home
    }
  }
}

struct TakkenUnlockChallengeProvider: UnlockChallengeProviding {
  let repository: TakkenQuestionRepository
  init(bundle: Bundle = .main) { repository = .init(bundle: bundle) }

  func makeUnlockChallenge(
    packID: StudyPackID, request: UnlockChallengeRequest
  ) async throws -> UnlockChallengeSnapshot {
    var questions = try repository.load(manifest: request.manifest)
    var settings = TakkenSettings.load()
    #if DEBUG
    if let fixtures = TakkenUITestFixtures.requestedQuestions() {
      questions = fixtures
      settings.questionCount = fixtures.count
      }
    #endif
    let recentAnswers = try await request.learning.answers().filter { $0.experienceID == .takken }
    var pendingPreview = try await request.learning.loadTakkenPendingPreview(now: request.now)
    if let preview = pendingPreview {
      let candidateExists = questions.contains { question in
        question.resolvedConceptID == preview.conceptID
          && question.unlockEligible
          && (settings.selectedCategories.isEmpty
            || settings.selectedCategories.contains(question.category))
          && (settings.selectedDifficulties.isEmpty
            || settings.selectedDifficulties.contains(question.difficulty))
      }
      if !preview.isUsableForRecall(
        contentVersion: request.manifest.contentVersion, now: request.now) || !candidateExists
      {
        try await request.learning.saveTakkenPendingPreview(nil)
        pendingPreview = nil
      }
    }

    let required = request.policy.accessPacePreset.requiredLearningUnits
    let challengeID = UUID()
    var presented = TakkenQuestionSelectionEngine().select(.init(
      questions: questions,
      settings: settings,
      progress: request.progress,
      recentAnswers: recentAnswers,
      packID: packID,
      mode: .unlock,
      count: required,
      sessionID: challengeID,
      pendingPreview: pendingPreview,
      now: request.now
    ))
    let selectedIDs = Set(presented.map(\.id))
    let selectedConcepts = Set(presented.map { $0.source.resolvedConceptID })
    let additionalDue = TakkenQuestionSelectionEngine().select(.init(
      questions: questions.filter {
        !selectedIDs.contains($0.id) && !selectedConcepts.contains($0.resolvedConceptID)
      },
      settings: settings,
      progress: request.progress,
      recentAnswers: recentAnswers,
      packID: packID,
      mode: .review,
      count: request.policy.reviewLoadPreset.maxAdditionalDueReviews,
      sessionID: challengeID,
      pendingPreview: nil,
      now: request.now
    ))
    presented.append(contentsOf: additionalDue)
    guard !presented.isEmpty else {
      throw ContentRepositoryError.invalid("無料宅建問題を選べません")
    }
    if let preview = pendingPreview,
      presented.first?.source.resolvedConceptID == preview.conceptID
    {
      _ = try await request.learning.consumeTakkenPendingPreview(id: preview.id, at: request.now)
    }

    let snapshots = presented.map { question in
      let sourceRationales = Dictionary(uniqueKeysWithValues: question.presentedChoices.compactMap {
        displayed -> (Int, String)? in
        guard let sourceID = question.sourceChoiceID(for: displayed.id),
          displayed.id != question.correctChoiceID,
          let rationale = question.source.choices.first(where: { $0.id == sourceID })?.rationale
            ?? question.source.wrongChoiceRationales?[sourceID]
        else { return nil }
        return (displayed.id, rationale)
      })
      return UnlockQuestionSnapshot.takken(.init(
        id: .init(rawValue: question.source.id),
        prompt: question.source.prompt,
        choices: question.presentedChoices,
        correctChoiceID: question.correctChoiceID,
        shortExplanation: question.source.shortExplanation ?? question.source.explanation,
        longExplanation: question.source.longExplanation ?? question.source.explanation,
        keyPoint: question.source.keyPoint,
        category: question.source.category,
        subCategory: question.source.subCategory,
        difficulty: question.source.difficulty,
        format: question.source.resolvedFormat.rawValue,
        examYear: question.source.examYear,
        lawBasisDate: question.source.lawBasisDate,
        sourceNote: question.source.sourceNote,
        contentVersion: request.manifest.contentVersion,
        questionVersion: question.source.version ?? 1,
        conceptID: question.source.resolvedConceptID,
        variantID: question.source.resolvedVariantID,
        minimumReviewSeconds: question.source.minimumReviewSeconds,
        contrastNote: question.source.contrastNote,
        wrongChoiceRationales: sourceRationales.isEmpty ? nil : sourceRationales
      ))
    }
    return .init(
      schemaVersion: 3,
      id: challengeID,
      requestID: request.requestID,
      origin: request.origin,
      experienceID: .takken,
      packID: packID,
      policyVersion: request.policy.policyVersion,
      pace: request.policy.accessPacePreset,
      reviewLoad: request.policy.reviewLoadPreset,
      questions: snapshots,
      access: .init(
        packID: packID, reason: .freeSample,
        verifiedAt: request.entitlement.lastVerifiedAt),
      createdAt: request.now,
      expiresAt: request.now.addingTimeInterval(
        ExperienceUnlockBundleSnapshot.expirationInterval)
    )
  }
}

@MainActor
struct TakkenExperience: StudyExperienceFactory {
  let descriptor = StudyExperienceDescriptor(
    id: .takken,
    title: "宅建2026",
    subtitle: "品質確認済み教材",
    systemImage: "building.columns.fill",
    tintName: "orange",
    supportedPackIDs: ["takken2026.v1"]
  )
  let unlockChallengeProvider: any UnlockChallengeProviding = TakkenUnlockChallengeProvider()
  let reportProvider: (any StudyExperienceReportProviding)? = TakkenReportProvider()

  func makeRootView(context: StudyExperienceContext) -> AnyView {
    AnyView(TakkenRootView(context: context))
  }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? {
    AnyView(TakkenFirstRunView(context: context))
  }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    let allProgress = try await context.dependencies.learning.allProgress()
    let progress = allProgress.values.filter { $0.id.packID == context.manifest.id }
    let answers = try await context.dependencies.learning.answers().filter {
      $0.experienceID == .takken
    }
    return .init(
      experienceID: .takken,
      packID: context.manifest.id,
      answeredCount: answers.count,
      correctCount: answers.filter(\.isCorrect).count,
      learnedItemCount: progress.filter { $0.answerCount > 0 }.count,
      dueCount: progress.filter { $0.dueAt.map { $0 <= Date() } ?? false }.count
    )
  }
  func makeUnlockChallengeView(
    snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext
  ) -> AnyView {
    AnyView(TakkenUnlockChallengeView(bundle: snapshot, context: context))
  }

  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {
    guard context.bundle.challenge.experienceID == .takken,
      context.manifest.moduleType == .takken
    else { return }
    if let existing = try await context.dependencies.learning.loadTakkenPendingPreview(
      now: context.now), existing.sourceUnlockBundleID == context.bundle.id
    {
      return
    }

    let questions = try TakkenQuestionRepository().load(manifest: context.manifest)
    let settings = TakkenSettings.load()
    let completedConcepts: Set<String> = Set(context.bundle.challenge.questions.compactMap { snapshot in
      guard case .takken(let question) = snapshot else { return nil }
      return question.resolvedConceptID
    })
    let eligible = questions.filter { question in
      question.unlockEligible
        && (settings.selectedCategories.isEmpty
          || settings.selectedCategories.contains(question.category))
        && (settings.selectedDifficulties.isEmpty
          || settings.selectedDifficulties.contains(question.difficulty))
    }
    let newConceptPool = eligible.filter { !completedConcepts.contains($0.resolvedConceptID) }
    let pool = newConceptPool.isEmpty ? eligible : newConceptPool
    let progress = try await context.dependencies.learning.allProgress()
    let answers = try await context.dependencies.learning.answers().filter {
      $0.experienceID == .takken
    }
    let candidate = TakkenQuestionSelectionEngine().select(.init(
      questions: pool,
      settings: settings,
      progress: progress,
      recentAnswers: answers,
      packID: context.manifest.id,
      mode: .unlock,
      count: 1,
      sessionID: context.bundle.id,
      pendingPreview: nil,
      now: context.now
    )).first?.source
    guard let candidate else {
      try await context.dependencies.learning.saveTakkenPendingPreview(nil)
      return
    }
    let preview = TakkenPendingPreview(
      id: UUID(),
      sourceUnlockBundleID: context.bundle.id,
      conceptID: candidate.resolvedConceptID,
      sourceQuestionID: candidate.id,
      preferredVariantID: candidate.resolvedVariantID,
      contentVersion: context.manifest.contentVersion,
      createdAt: context.now,
      recallExpiresAt: context.now.addingTimeInterval(TakkenPendingPreview.recallDuration),
      confirmedAt: nil,
      consumedAt: nil,
      foregroundExposureSeconds: 0
    )
    try await context.dependencies.learning.saveTakkenPendingPreview(preview)
  }
}

struct TakkenSessionPresentation: Identifiable {
  let id: UUID
  let mode: StudyMode
  let questions: [TakkenPresentedQuestion]
}

@MainActor
final class TakkenAppModel: ObservableObject {
  @Published private(set) var questions: [TakkenQuestion] = []
  @Published private(set) var progress: [String: ItemProgress] = [:]
  @Published private(set) var answers: [StudyAnswerRecord] = []
  @Published private(set) var pendingPreview: TakkenPendingPreview?
  @Published var settings: TakkenSettings
  @Published var session: TakkenSessionPresentation?
  @Published var errorMessage: String?
  @Published private(set) var isLoading = false

  let context: StudyExperienceContext
  private let repository = TakkenQuestionRepository()
  private let selectionEngine = TakkenQuestionSelectionEngine()
  private let feedbackPlanner = TakkenFeedbackPlanner()
  private var cancellables: Set<AnyCancellable> = []

  init(context: StudyExperienceContext) {
    self.context = context
    settings = .load()
    context.dependencies.commerce.$entitlement
      .dropFirst()
      .sink { [weak self] _ in Task { @MainActor in await self?.load() } }
      .store(in: &cancellables)
    context.dependencies.learningRevision.$value
      .dropFirst()
      .sink { [weak self] _ in Task { @MainActor in await self?.load() } }
      .store(in: &cancellables)
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      questions = try repository.load(manifest: context.manifest)
      #if DEBUG
        if let fixture = TakkenUITestFixtures.requestedQuestion() {
          questions = [fixture]
          settings.questionCount = 1
        }
      #endif
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter {
        $0.experienceID == .takken
      }
      #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if (arguments.contains("-LockAndStudyUITestTakkenPreview")
          || arguments.contains("-LockAndStudyUITestTakkenPreviewVisible")),
        let question = questions.first
      {
        let now = Date()
        let elapsed: TimeInterval = arguments.contains("-LockAndStudyUITestTakkenPreview")
          ? 118 : 10
        try await context.dependencies.learning.saveTakkenPendingPreview(.init(
          id: UUID(), sourceUnlockBundleID: UUID(),
          conceptID: question.resolvedConceptID, sourceQuestionID: question.id,
          preferredVariantID: question.resolvedVariantID,
          contentVersion: context.manifest.contentVersion,
          createdAt: now.addingTimeInterval(-elapsed),
          recallExpiresAt: now.addingTimeInterval(TakkenPendingPreview.recallDuration),
          confirmedAt: nil, consumedAt: nil, foregroundExposureSeconds: 0
        ))
      }
      #endif
      pendingPreview = try await context.dependencies.learning.loadTakkenPendingPreview(
        now: Date())
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    do { try settings.save() }
    catch { errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func visiblePendingPreviewQuestion(at date: Date) -> TakkenQuestion? {
    TakkenPendingPreviewResolver().visibleQuestion(
      for: pendingPreview, in: questions,
      contentVersion: context.manifest.contentVersion, at: date)
  }

  func confirmPendingPreviewVisible(seconds: TimeInterval, now: Date = Date()) async {
    guard seconds > 0, var preview = pendingPreview, preview.confirmedAt == nil,
      preview.isDisplayable(at: now)
    else { return }
    preview.recordForegroundExposure(seconds: seconds, at: now)
    do {
      try await context.dependencies.learning.saveTakkenPendingPreview(preview)
      pendingPreview = preview
    } catch { errorMessage = "予習状態を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func clearPendingPreviewExposureIfUnconfirmed() async {
    guard var preview = pendingPreview, preview.confirmedAt == nil,
      preview.foregroundExposureSeconds != 0
    else { return }
    preview.resetUnconfirmedForegroundExposure()
    do {
      try await context.dependencies.learning.saveTakkenPendingPreview(preview)
      pendingPreview = preview
    } catch { errorMessage = "予習状態を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func start(mode: StudyMode) {
    let sessionID = UUID()
    let now = Date()
    let queue = selectionEngine.select(.init(
      questions: questions,
      settings: settings,
      progress: progress,
      recentAnswers: answers,
      packID: context.manifest.id,
      mode: mode,
      count: settings.questionCount,
      sessionID: sessionID,
      pendingPreview: nil,
      now: now
    ))
    guard !queue.isEmpty else { errorMessage = emptyMessage(for: mode); return }
    session = .init(id: sessionID, mode: mode, questions: queue)
    Task {
      do {
        try await context.dependencies.learning.record(.init(
          kind: .studyStarted, packID: context.manifest.id, sessionID: sessionID))
      } catch {
        errorMessage = "学習開始を記録できませんでした。\n\(error.localizedDescription)"
      }
    }
  }

  func recordAnswer(
    question: TakkenPresentedQuestion, selectedChoiceID: Int, sessionID: UUID, attempt: Int
  ) async -> StudyAnswerSubmissionResult {
    let correct = selectedChoiceID == question.correctChoiceID
    let ordinal = max(1, attempt + 1)
    let plan = feedbackPlanner.plan(wrongAttemptCount: correct ? 0 : ordinal)
    let answeredAt = Date()
    let mode = session?.mode ?? .practice
    let source = question.source
    let compositeID = CompositeStudyItemID(
      packID: context.manifest.id, itemID: .init(rawValue: source.id))
    let priorProgress = progress[compositeID.storageKey] ?? .initial(compositeID)
    let selectedStableID = question.sourceChoiceID(for: selectedChoiceID) ?? "unknown"
    let record = StudyAnswerRecord(
      submissionID:
        "takken::\(sessionID.uuidString)::\(source.id)::attempt::\(ordinal)::choice::\(selectedStableID)",
      experienceID: .takken,
      packID: context.manifest.id,
      moduleType: .takken,
      itemID: .init(rawValue: source.id),
      prompt: source.prompt,
      choices: question.presentedChoices,
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      shortExplanation: source.shortExplanation ?? source.explanation,
      longExplanation: source.longExplanation ?? source.explanation,
      sourceNote: source.sourceNote,
      category: source.category,
      subcategory: source.subCategory,
      contentVersion: context.manifest.contentVersion,
      questionVersion: source.version ?? 1,
      examYear: source.examYear,
      lawBasisDate: source.lawBasisDate,
      answeredAt: answeredAt,
      mode: mode,
      sessionID: sessionID,
      feedbackPlan: plan,
      difficulty: source.difficulty,
      questionFormat: source.resolvedFormat.rawValue,
      keyPoint: source.keyPoint,
      tags: source.tags,
      learningRole: .classify(mode: mode, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false,
      conceptID: source.resolvedConceptID,
      variantID: source.resolvedVariantID,
      attemptNumber: ordinal,
      wasFirstAttempt: ordinal == 1
    )
    do {
      _ = try await context.dependencies.learning.recordUnique(record)
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter {
        $0.experienceID == .takken
      }
      context.dependencies.learningRevision.bump()
      return correct ? .recordedCorrect(plan) : .recordedIncorrect(plan)
    } catch {
      let message = error.localizedDescription
      errorMessage = message
      return .failed(message)
    }
  }

  func recordAnswer(
    question: TakkenQuestion, selectedChoiceID: Int, sessionID: UUID, attempt: Int
  ) async -> StudyAnswerSubmissionResult {
    let choices = question.choices.enumerated().map { StudyChoice(id: $0.offset, text: $0.element.text) }
    let presented = TakkenPresentedQuestion(
      source: question,
      presentedChoices: choices,
      correctChoiceID: question.correctIndex,
      seed: 0,
      sourceChoiceIDsByPresentedID: Dictionary(uniqueKeysWithValues:
        question.choices.enumerated().map { ($0.offset, $0.element.id) }))
    return await recordAnswer(
      question: presented, selectedChoiceID: selectedChoiceID, sessionID: sessionID,
      attempt: attempt)
  }

  func itemProgress(_ question: TakkenQuestion) -> ItemProgress {
    progress[CompositeStudyItemID(
      packID: context.manifest.id, itemID: .init(rawValue: question.id)).storageKey]
      ?? .initial(.init(packID: context.manifest.id, itemID: .init(rawValue: question.id)))
  }
  var categories: [String] { Array(Set(questions.map(\.category))).sorted() }
  func subCategories(category: String?) -> [String] {
    Array(Set(questions.filter { category == nil || $0.category == category }
      .compactMap(\.subCategory))).sorted()
  }
  var summary: TakkenRecordsSummary {
    TakkenRecordsAnalyzer().summary(answers: answers, now: Date())
  }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int {
    feedbackPlanner.waitSeconds(for: plan)
  }
  private func emptyMessage(for mode: StudyMode) -> String {
    switch mode {
    case .review: return "期限が来た復習問題はありません。"
    case .mistakes: return "復習する誤答はありません。"
    case .weakness: return "苦手問題はまだありません。"
    case .newItems: return "未回答問題はありません。"
    default: return "条件に合う問題がありません。"
    }
  }
}

#if DEBUG
  enum TakkenUITestFixtures {
    static func requestedQuestions(
      arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> [TakkenQuestion]? {
      guard let base = requestedQuestion(arguments: arguments) else { return nil }
      let count = arguments.contains("-LockAndStudyUITestUnlock3")
        ? 3 : (arguments.contains("-LockAndStudyUITestUnlock2") ? 2 : 1)
      return (0..<count).map { index in
        guard index > 0 else { return base }
        return TakkenQuestion(
          id: "\(base.id)-\(index + 1)",
          conceptID: "\(base.resolvedConceptID)-\(index + 1)",
          variantID: base.resolvedVariantID,
          format: base.resolvedFormat,
          prompt: "UIテスト用の宅建問題\(index + 1)です。正しい選択肢を選んでください。",
          choices: base.choices,
          correctChoiceID: base.correctChoiceID,
          category: base.category,
          subCategory: base.subCategory,
          difficulty: base.difficulty,
          importance: base.importance,
          explanation: base.explanation,
          preview: base.preview,
          minimumReviewSeconds: base.minimumReviewSeconds,
          contrastNote: base.contrastNote)
      }
    }

    static func requestedQuestion(arguments: [String] = ProcessInfo.processInfo.arguments)
      -> TakkenQuestion?
    {
      let format: TakkenQuestionFormat?
      if arguments.contains("-LockAndStudyUITestTakkenV5TrueFalse") {
        format = .trueFalse
      } else if arguments.contains("-LockAndStudyUITestTakkenV5Number") {
        format = .numberChoice
      } else if arguments.contains("-LockAndStudyUITestTakkenV5Wording") {
        format = .wordingContrast
      } else if arguments.contains("-LockAndStudyUITestTakkenV5MultipleChoice") {
        format = .multipleChoice
      } else {
        format = nil
      }
      guard let format else { return nil }
      let extraChoices: [TakkenChoice] =
        format == .multipleChoice
        ? [
          .init(id: "wrong-2", text: "誤答2", rationale: "例外条件が異なります。", misconceptionCode: "exception"),
          .init(id: "wrong-3", text: "誤答3", rationale: "期限が異なります。", misconceptionCode: "deadline"),
        ] : []
      return TakkenQuestion(
        id: "ui-v5-\(format.rawValue)", conceptID: "ui-v5-concept",
        variantID: format.rawValue, format: format,
        prompt: "UIテスト用の宅建問題です。正しい選択肢を選んでください。",
        choices: [
          .init(id: "wrong", text: "誤答", rationale: "主体と条件が異なります。", misconceptionCode: "subject"),
          .init(id: "correct", text: "正解", rationale: nil, misconceptionCode: nil),
        ] + extraChoices,
        correctChoiceID: "correct", explanation: "正しいルールを覚えます。",
        preview: .init(
          title: "UIテスト論点", rule: "正しいルールを覚えます。",
          contrast: "主体と条件の違いに注意します。", mnemonic: nil),
        minimumReviewSeconds: 10,
        contrastNote: "主体と条件の違いに注意します。")
    }
  }
#endif
