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

struct CertificationChallengeQuestion: Codable, Equatable, Identifiable, Sendable {
  let id: StudyItemID
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let shortExplanation: String
  let longExplanation: String
  let keyPoint: String?
  let category: String
  let subCategory: String?
  let difficulty: String
  let format: String
  let examYear: Int?
  let lawBasisDate: String?
  let sourceNote: String?
  let contentVersion: String
  let questionVersion: Int
  let conceptID: String?
  let variantID: String?
  let minimumReviewSeconds: Int?
  let contrastNote: String?
  let wrongChoiceRationales: [Int: String]?

  var resolvedConceptID: String { conceptID ?? id.rawValue }
  var resolvedVariantID: String { variantID ?? "legacy" }
}

struct CertificationUnlockSessionPayload: Codable, Equatable, Sendable {
  static let schemaID = "certification.unlock-session.v1"

  let pace: AccessPacePreset
  let questions: [CertificationChallengeQuestion]
  var completedQuestionIDs: Set<StudyItemID>
  var attemptCountsByQuestionID: [String: Int]
  var reviewRemainingSecondsByQuestionID: [String: TimeInterval]
  var lastSelectedChoiceIDByQuestionID: [String: Int]
  var activeReviewQuestionID: String?
}

struct CertificationUnlockSessionBuilder: Sendable {
  func makeSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    let packID = request.manifest.id
    let allQuestions = try await request.content.takkenQuestions(for: packID)
    let sampleIDs = try await request.content.sampleIDs(for: packID, itemIDs: Set(allQuestions.map(\.id)))
    let access = ContentAccessService()
    var questions = allQuestions.filter { question in
      access.decision(
        isFreeSample: sampleIDs.contains(question.id),
        manifest: request.manifest,
        entitlement: request.entitlement
      ).isAllowed
    }
    var settings = TakkenSettings.load(packID: packID)
    let availableCategories = Set(questions.map(\.category))
    if !settings.selectedCategories.isEmpty,
      settings.selectedCategories.isDisjoint(with: availableCategories)
    {
      settings.selectedCategories = []
    }
    #if DEBUG
    if let fixtures = TakkenUITestFixtures.requestedQuestions() {
      questions = fixtures
      settings.questionCount = fixtures.count
      }
    #endif
    let recentAnswers = try await request.learning.answers().filter {
      $0.experienceID == .takken && $0.packID == packID
    }
    var pendingPreview = try await request.learning.loadTakkenPendingPreview(
      for: packID, now: request.now)
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
        try await request.learning.saveTakkenPendingPreview(nil, for: packID)
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
      throw ContentRepositoryError.invalid("利用できる資格問題を選べません")
    }
    if let preview = pendingPreview,
      presented.first?.source.resolvedConceptID == preview.conceptID
    {
      _ = try await request.learning.consumeTakkenPendingPreview(
        for: packID, id: preview.id, at: request.now)
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
      return CertificationChallengeQuestion(
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
        wrongChoiceRationales: sourceRationales.isEmpty ? nil : sourceRationales)
    }
    let state = CertificationUnlockSessionPayload(
      pace: request.policy.accessPacePreset,
      questions: snapshots,
      completedQuestionIDs: [],
      attemptCountsByQuestionID: [:],
      reviewRemainingSecondsByQuestionID: [:],
      lastSelectedChoiceIDByQuestionID: [:],
      activeReviewQuestionID: nil)
    return .init(
      schemaID: CertificationUnlockSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }
}

@MainActor
struct CertificationExperience: StudyExperienceFactory {
  let experienceID = StudyExperienceID.certificationV1
  let supportedPayloadSchemaIDs: Set<String> = [CertificationUnlockSessionPayload.schemaID]
  let supportedContentSchemas: Set<ContentSchemaID> = [.certificationQuestionsV1]
  let descriptor = StudyExperienceDescriptor(
    id: .takken,
    title: "資格・知識問題",
    subtitle: "分野別演習・学び直し対応",
    systemImage: "building.columns.fill",
    tintName: "orange",
    supportedExperienceTypes: [.takkenV1]
  )
  let reportProvider: (any StudyExperienceReportProviding)? = TakkenReportProvider()

  func makeRootView(context: StudyExperienceContext) -> AnyView {
    AnyView(TakkenRootView(context: context))
  }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? {
    AnyView(TakkenFirstRunView(context: context))
  }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    let allProgress = try await context.dependencies.learning.allProgress()
    let progress = allProgress.values.filter {
      $0.id.packID == context.manifest.id && !$0.isSafeFallbackArtifact
    }
    let answers = try await context.dependencies.learning.answers().filter {
      $0.experienceID == .takken && $0.packID == context.manifest.id
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
  func createSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    try await CertificationUnlockSessionBuilder().makeSession(request: request)
  }
  func makeChallengeView(
    envelope: UnlockChallengeSessionEnvelope,
    context: ExperienceChallengeViewContext
  ) -> AnyView {
    guard let state = try? decode(envelope) else {
      return AnyView(ExperienceSessionUnavailableView(context: context))
    }
    return AnyView(TakkenUnlockChallengeView(session: state, context: context))
  }
  func restoreState(payload: Data, schemaID: String) throws -> ExperienceSessionState {
    guard supportedPayloadSchemaIDs.contains(schemaID) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification payload")
    }
    let state = try SharedJSON.decoder().decode(
      CertificationUnlockSessionPayload.self, from: payload)
    return .init(
      completedUnitCount: state.completedQuestionIDs.count,
      totalUnitCount: state.questions.count,
      reviewRemainingSeconds: state.reviewRemainingSecondsByQuestionID.values.max() ?? 0)
  }
  func acceptAnswer(
    _ answer: StudyAnswerValue,
    envelope: UnlockChallengeSessionEnvelope,
    dependencies: DependencyContainer
  ) async throws -> ExperienceSessionTransition {
    var state = try decode(envelope)
    let resolved = try choice(from: answer, state: state)
    guard let question = state.questions.first(where: { $0.id.rawValue == resolved.questionID }) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification question")
    }
    let key = question.id.rawValue
    let remaining = state.reviewRemainingSecondsByQuestionID[key] ?? 0
    guard remaining <= 0 else {
      return try transition(
        state,
        submission: .failed("解説をあと\(max(1, Int(ceil(remaining))))秒確認してから、再挑戦してください。"))
    }
    guard let selectedChoiceID = Int(resolved.choiceID),
      question.choices.contains(where: { $0.id == selectedChoiceID })
    else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification choice") }
    let answeredAt = Date()
    let priorProgress = try await dependencies.learning.progress(
      for: .init(packID: envelope.packID, itemID: question.id))
    let attempt = (state.attemptCountsByQuestionID[key] ?? 0) + 1
    let correct = selectedChoiceID == question.correctChoiceID
    let feedback = correct
      ? StudyFeedbackPlan.immediate
      : TakkenFeedbackPlanner().plan(wrongAttemptCount: attempt)
    let record = StudyAnswerRecord(
      submissionID: "unlock::\(envelope.id.uuidString)::\(key)::attempt::\(attempt)::choice::\(selectedChoiceID)",
      experienceID: .takken,
      packID: envelope.packID,
      moduleType: .takken,
      itemID: question.id,
      prompt: question.prompt,
      choices: question.choices,
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      shortExplanation: question.shortExplanation,
      longExplanation: question.longExplanation,
      sourceNote: question.sourceNote,
      category: question.category,
      subcategory: question.subCategory,
      contentVersion: question.contentVersion,
      questionVersion: question.questionVersion,
      examYear: question.examYear,
      lawBasisDate: question.lawBasisDate,
      answeredAt: answeredAt,
      mode: .unlock,
      sessionID: envelope.id,
      feedbackPlan: feedback,
      difficulty: question.difficulty,
      questionFormat: question.format,
      keyPoint: question.keyPoint,
      learningRole: AnswerLearningRole.classify(mode: .unlock, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false,
      conceptID: question.resolvedConceptID,
      variantID: question.resolvedVariantID,
      attemptNumber: attempt,
      wasFirstAttempt: attempt == 1
    )
    _ = try await dependencies.learning.recordUnique(record)
    state.attemptCountsByQuestionID[key] = attempt
    state.lastSelectedChoiceIDByQuestionID[key] = selectedChoiceID
    if correct {
      state.completedQuestionIDs.insert(question.id)
      state.reviewRemainingSecondsByQuestionID.removeValue(forKey: key)
      state.activeReviewQuestionID = nil
      return try transition(state, submission: .recordedCorrect)
    }
    let stagedSeconds = attempt == 1 ? 10 : (attempt == 2 ? 15 : 20)
    let seconds = max(question.minimumReviewSeconds ?? 10, stagedSeconds)
    state.reviewRemainingSecondsByQuestionID[key] = TimeInterval(seconds)
    state.activeReviewQuestionID = key
    return try transition(
      state,
      submission: .recordedIncorrect(remainingActiveSeconds: seconds, attemptNumber: attempt))
  }
  func activeReviewTick(
    seconds: TimeInterval,
    envelope: UnlockChallengeSessionEnvelope
  ) async throws -> ExperienceSessionTransition {
    var state = try decode(envelope)
    guard let key = state.activeReviewQuestionID else {
      return try transition(state, review: .updated(remainingActiveSeconds: 0))
    }
    let remaining = max(0, (state.reviewRemainingSecondsByQuestionID[key] ?? 0) - max(0, seconds))
    if remaining == 0 {
      state.reviewRemainingSecondsByQuestionID.removeValue(forKey: key)
      state.activeReviewQuestionID = nil
    } else {
      state.reviewRemainingSecondsByQuestionID[key] = remaining
    }
    return try transition(
      state,
      review: .updated(remainingActiveSeconds: max(0, Int(ceil(remaining)))))
  }
  func completionProof(
    envelope: UnlockChallengeSessionEnvelope
  ) throws -> ExperienceCompletionProof? {
    let state = try decode(envelope)
    guard !state.questions.isEmpty,
      state.completedQuestionIDs.count >= state.questions.count
    else { return nil }
    return .init(
      sessionID: envelope.id, packID: envelope.packID,
      completedAt: Date(), evidenceVersion: 1,
      unlockDuration: state.pace.unlockDuration)
  }

  func handleUnlockCompletion(_ context: UnlockRuntimeCompletionContext) async throws {
    let state = try decode(context.envelope)
    if let existing = try await context.dependencies.learning.loadTakkenPendingPreview(
      for: context.manifest.id, now: context.now), existing.sourceUnlockBundleID == context.envelope.id
    {
      return
    }

    let questions = try await context.dependencies.content.takkenQuestions(for: context.manifest.id)
    let settings = TakkenSettings.load(packID: context.manifest.id)
    let completedConcepts = Set(state.questions.map(\.resolvedConceptID))
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
      $0.experienceID == .takken && $0.packID == context.manifest.id
    }
    let candidate = TakkenQuestionSelectionEngine().select(.init(
      questions: pool,
      settings: settings,
      progress: progress,
      recentAnswers: answers,
      packID: context.manifest.id,
      mode: .unlock,
      count: 1,
      sessionID: context.envelope.id,
      pendingPreview: nil,
      now: context.now
    )).first?.source
    guard let candidate else {
      try await context.dependencies.learning.saveTakkenPendingPreview(
        nil, for: context.manifest.id)
      return
    }
    let preview = TakkenPendingPreview(
      id: UUID(),
      packID: context.manifest.id,
      sourceUnlockBundleID: context.envelope.id,
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
    try await context.dependencies.learning.saveTakkenPendingPreview(
      preview, for: context.manifest.id)
  }

  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async {
    try? await dependencies.learning.saveTakkenPendingPreview(nil, for: packID)
  }

  private func decode(
    _ envelope: UnlockChallengeSessionEnvelope
  ) throws -> CertificationUnlockSessionPayload {
    guard envelope.experienceID.normalizedTemplateID == experienceID,
      supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID)
    else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification payload") }
    return try SharedJSON.decoder().decode(
      CertificationUnlockSessionPayload.self, from: envelope.enginePayload)
  }

  private func choice(
    from answer: StudyAnswerValue,
    state: CertificationUnlockSessionPayload
  ) throws -> (questionID: String, choiceID: String) {
    switch answer {
    case .choice(let questionID, let choiceID): return (questionID, choiceID)
    case .choiceID(let choiceID):
      guard let question = state.questions.first(where: {
        !state.completedQuestionIDs.contains($0.id)
      }) else {
        throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification question")
      }
      return (question.id.rawValue, choiceID)
    default:
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "certification choice")
    }
  }

  private func transition(
    _ state: CertificationUnlockSessionPayload,
    submission: UnlockAnswerSubmissionResult? = nil,
    review: UnlockReviewExposureResult? = nil
  ) throws -> ExperienceSessionTransition {
    .init(
      payload: .init(
        schemaID: CertificationUnlockSessionPayload.schemaID,
        data: try SharedJSON.encoder().encode(state)),
      submissionResult: submission,
      reviewResult: review)
  }
}

typealias TakkenExperience = CertificationExperience

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
  var profile: CertificationPresentationProfile {
    context.manifest.certificationPresentation
  }
  var categoryDefinitions: [CertificationCategoryDefinition] {
    if !profile.categoryDefinitions.isEmpty { return profile.categoryDefinitions }
    return Array(Set(questions.map(\.category))).sorted().map {
      .init(code: $0, title: $0)
    }
  }
  private let selectionEngine = TakkenQuestionSelectionEngine()
  private let feedbackPlanner = TakkenFeedbackPlanner()
  private var cancellables: Set<AnyCancellable> = []

  init(context: StudyExperienceContext) {
    self.context = context
    settings = .load(packID: context.manifest.id)
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
      let allQuestions = try await context.dependencies.content.takkenQuestions(
        for: context.manifest.id)
      let sampleIDs = try await context.dependencies.content.sampleIDs(
        for: context.manifest.id,
        itemIDs: Set(allQuestions.map(\.id)))
      let access = ContentAccessService()
      questions = allQuestions.filter {
        access.decision(
          isFreeSample: sampleIDs.contains($0.id),
          manifest: context.manifest,
          entitlement: context.dependencies.commerce.entitlement
        ).isAllowed
      }
      let availableCategories = Set(allQuestions.map(\.category))
      if !settings.selectedCategories.isEmpty,
        settings.selectedCategories.isDisjoint(with: availableCategories)
      {
        settings.selectedCategories = profile.categoryDefinitions.first.map { [$0.code] } ?? []
        try settings.save(packID: context.manifest.id)
      }
      #if DEBUG
        if let fixture = TakkenUITestFixtures.requestedQuestion() {
          questions = [fixture]
          settings.questionCount = 1
        }
      #endif
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter {
        $0.experienceID == .takken && $0.packID == context.manifest.id
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
          id: UUID(), packID: context.manifest.id, sourceUnlockBundleID: UUID(),
          conceptID: question.resolvedConceptID, sourceQuestionID: question.id,
          preferredVariantID: question.resolvedVariantID,
          contentVersion: context.manifest.contentVersion,
          createdAt: now.addingTimeInterval(-elapsed),
          recallExpiresAt: now.addingTimeInterval(TakkenPendingPreview.recallDuration),
          confirmedAt: nil, consumedAt: nil, foregroundExposureSeconds: 0
        ), for: context.manifest.id)
      }
      #endif
      pendingPreview = try await context.dependencies.learning.loadTakkenPendingPreview(
        for: context.manifest.id, now: Date())
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    do { try settings.save(packID: context.manifest.id) }
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
      try await context.dependencies.learning.saveTakkenPendingPreview(
        preview, for: context.manifest.id)
      pendingPreview = preview
    } catch { errorMessage = "予習状態を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func clearPendingPreviewExposureIfUnconfirmed() async {
    guard var preview = pendingPreview, preview.confirmedAt == nil,
      preview.foregroundExposureSeconds != 0
    else { return }
    preview.resetUnconfirmedForegroundExposure()
    do {
      try await context.dependencies.learning.saveTakkenPendingPreview(
        preview, for: context.manifest.id)
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
        $0.experienceID == .takken && $0.packID == context.manifest.id
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
    TakkenRecordsAnalyzer().summary(
      answers: answers,
      packID: context.manifest.id,
      now: Date())
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
