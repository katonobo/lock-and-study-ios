import Combine
import Foundation
import SwiftUI

enum VocabularyTab: Hashable, Sendable { case home, learning, words, records, settings }

@MainActor
final class VocabularyRouter: ObservableObject {
  @Published var selectedTab: VocabularyTab

  init(destination: StudyExperienceDestination) {
    switch destination {
    case .learning: selectedTab = .learning
    case .catalog: selectedTab = .words
    case .records: selectedTab = .records
    case .settings: selectedTab = .settings
    default: selectedTab = .home
    }
  }
}

struct FlashcardChallengeQuestion: Codable, Equatable, Identifiable, Sendable {
  let id: StudyItemID
  let front: String
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let explanation: String
  let primaryExample: String?
  let secondaryExample: String?
  let speechText: String?
  let courseCode: String
  let contentVersion: String
  let isFreeSample: Bool
}

struct FlashcardUnlockSessionPayload: Codable, Equatable, Sendable {
  static let schemaID = "flashcard.unlock-session.v1"

  let pace: AccessPacePreset
  let questions: [FlashcardChallengeQuestion]
  var completedQuestionIDs: Set<StudyItemID>
  var attemptCountsByQuestionID: [String: Int]
  var reviewRemainingSecondsByQuestionID: [String: TimeInterval]
  var lastSelectedChoiceIDByQuestionID: [String: Int]
  var activeReviewQuestionID: String?

  func hasLaterUncompletedQuestion(after index: Int) -> Bool {
    questions.indices.contains {
      $0 > index && !completedQuestionIDs.contains(questions[$0].id)
    }
  }

  func nextUncompletedQuestionIndex(after index: Int) -> Int? {
    questions.indices.first {
      $0 > index && !completedQuestionIDs.contains(questions[$0].id)
    }
  }
}

struct FlashcardUnlockSessionBuilder: Sendable {
  func makeSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    let packID = request.manifest.id
    let package = try await request.content.vocabularyPackage(for: packID)
    let settings = VocabularySettings.load(packID: packID)
    let access = ContentAccessService()
    let available = package.items.filter { item in
      let selected = settings.selectedLevelCodes.isEmpty || settings.selectedLevelCodes.contains(item.levelCode)
      let allowed = access.decision(
        isFreeSample: package.freeSampleIDs.contains(item.id),
        manifest: request.manifest,
        entitlement: request.entitlement
      ).isAllowed
      return selected && allowed
    }
    let safePool = available.isEmpty ? package.items.filter { package.freeSampleIDs.contains($0.id) } : available
    guard !safePool.isEmpty else { throw ContentRepositoryError.invalid("利用できるカードを読み込めません") }
    let planner = VocabularyLearningQueuePlanner()
    var previewItem: VocabularyItem?
    if let preview = try await request.learning.loadVocabularyPendingPreview(
      for: packID, now: request.now),
      let candidate = safePool.first(where: { $0.id == preview.itemID }),
      preview.isUsableForRecall(contentVersion: candidate.metadata.contentVersion, now: request.now),
      try await request.learning.consumeVocabularyPendingPreview(
        for: packID, id: preview.id, at: request.now)
    {
      previewItem = candidate
    }
    let required = request.policy.accessPacePreset.requiredLearningUnits
    let previewIDs = Set(previewItem.map { [$0.id] } ?? [])
    var selected = (previewItem.map { [$0] } ?? []) + planner.makeQueue(
      items: safePool.filter { !previewIDs.contains($0.id) },
      progress: request.progress,
      packID: packID,
      mode: .unlock,
      count: max(0, required - (previewItem == nil ? 0 : 1)),
      now: request.now
    )
    let selectedIDs = Set(selected.map(\.id))
    let dueReviews = safePool.filter { item in
      guard !selectedIDs.contains(item.id) else { return false }
      let id = CompositeStudyItemID(packID: packID, itemID: item.studyItemID).storageKey
      return request.progress[id]?.dueAt.map { $0 <= request.now } ?? false
    }.sorted {
      let lhs = request.progress[CompositeStudyItemID(packID: packID, itemID: $0.studyItemID).storageKey]?.dueAt ?? .distantFuture
      let rhs = request.progress[CompositeStudyItemID(packID: packID, itemID: $1.studyItemID).storageKey]?.dueAt ?? .distantFuture
      return lhs < rhs
    }
    selected.append(contentsOf: dueReviews.prefix(request.policy.reviewLoadPreset.maxAdditionalDueReviews))
    let questions = selected.map { item in
      FlashcardChallengeQuestion(
        id: item.studyItemID,
        front: item.displayWord,
        prompt: item.prompt,
        choices: item.options.enumerated().map { .init(id: $0.offset, text: $0.element) },
        correctChoiceID: item.correctIndex,
        explanation: item.explanationJa,
        primaryExample: item.exampleEn.nilIfEmpty,
        secondaryExample: item.exampleJa.nilIfEmpty,
        speechText: item.speechText.nilIfEmpty,
        courseCode: item.levelCode,
        contentVersion: item.metadata.contentVersion,
        isFreeSample: package.freeSampleIDs.contains(item.id)
      )
    }
    guard !questions.isEmpty else { throw ContentRepositoryError.invalid("解除問題を選べません") }
    let state = FlashcardUnlockSessionPayload(
      pace: request.policy.accessPacePreset,
      questions: questions,
      completedQuestionIDs: [],
      attemptCountsByQuestionID: [:],
      reviewRemainingSecondsByQuestionID: [:],
      lastSelectedChoiceIDByQuestionID: [:],
      activeReviewQuestionID: nil
    )
    return .init(
      schemaID: FlashcardUnlockSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }
}

@MainActor
struct FlashcardExperience: StudyExperienceFactory {
  let experienceID = StudyExperienceID.flashcardV1
  let supportedPayloadSchemaIDs: Set<String> = [FlashcardUnlockSessionPayload.schemaID]
  let supportedContentSchemas: Set<ContentSchemaID> = [.flashcardItemsV1]
  let descriptor = StudyExperienceDescriptor(
    id: .vocabulary,
    title: "暗記カード",
    subtitle: "コース・SRS・予習対応",
    systemImage: "character.book.closed.fill",
    tintName: "indigo",
    supportedExperienceTypes: [.vocabularyV1]
  )
  let reportProvider: (any StudyExperienceReportProviding)? = VocabularyReportProvider()

  func makeRootView(context: StudyExperienceContext) -> AnyView {
    AnyView(VocabularyRootView(context: context))
  }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? {
    AnyView(VocabularyFirstRunView(context: context))
  }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    let allProgress = try await context.dependencies.learning.allProgress()
    let progress = allProgress.values.filter {
      $0.id.packID == context.manifest.id && !$0.isSafeFallbackArtifact
    }
    let answers = try await context.dependencies.learning.answers().filter {
      $0.experienceID == .vocabulary && $0.packID == context.manifest.id
    }
    return .init(
      experienceID: .vocabulary,
      packID: context.manifest.id,
      answeredCount: answers.count,
      correctCount: answers.filter(\.isCorrect).count,
      learnedItemCount: progress.filter { $0.answerCount > 0 }.count,
      dueCount: progress.filter { $0.dueAt.map { $0 <= Date() } ?? false }.count
    )
  }
  func createSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    try await FlashcardUnlockSessionBuilder().makeSession(request: request)
  }
  func makeChallengeView(
    envelope: UnlockChallengeSessionEnvelope,
    context: ExperienceChallengeViewContext
  ) -> AnyView {
    guard let state = try? decode(envelope) else {
      return AnyView(ExperienceSessionUnavailableView(context: context))
    }
    return AnyView(VocabularyUnlockChallengeView(session: state, context: context))
  }
  func restoreState(payload: Data, schemaID: String) throws -> ExperienceSessionState {
    guard supportedPayloadSchemaIDs.contains(schemaID) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard payload")
    }
    let value = try SharedJSON.decoder().decode(FlashcardUnlockSessionPayload.self, from: payload)
    return .init(
      completedUnitCount: value.completedQuestionIDs.count,
      totalUnitCount: value.questions.count,
      reviewRemainingSeconds: value.reviewRemainingSecondsByQuestionID.values.max() ?? 0)
  }
  func acceptAnswer(
    _ answer: StudyAnswerValue,
    envelope: UnlockChallengeSessionEnvelope,
    dependencies: DependencyContainer
  ) async throws -> ExperienceSessionTransition {
    var state = try decode(envelope)
    let resolved = try choice(from: answer, state: state)
    guard let question = state.questions.first(where: { $0.id.rawValue == resolved.questionID }) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard question")
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
    else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard choice") }
    let answeredAt = Date()
    let priorProgress = try await dependencies.learning.progress(
      for: .init(packID: envelope.packID, itemID: question.id))
    let attempt = (state.attemptCountsByQuestionID[key] ?? 0) + 1
    let correct = selectedChoiceID == question.correctChoiceID
    let feedback = correct
      ? StudyFeedbackPlan.immediate
      : VocabularyFeedbackPlanner().plan(wrongAttemptCount: attempt)
    let record = StudyAnswerRecord(
      submissionID: "unlock::\(envelope.id.uuidString)::\(key)::attempt::\(attempt)::choice::\(selectedChoiceID)",
      experienceID: .vocabulary,
      packID: envelope.packID,
      moduleType: .vocabulary,
      itemID: question.id,
      prompt: question.prompt,
      choices: question.choices,
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      shortExplanation: question.explanation,
      longExplanation: ([question.explanation] + [question.primaryExample, question.secondaryExample].compactMap { $0 })
        .joined(separator: "\n"),
      sourceNote: nil,
      category: question.courseCode,
      subcategory: nil,
      contentVersion: question.contentVersion,
      questionVersion: 1,
      examYear: nil,
      lawBasisDate: nil,
      answeredAt: answeredAt,
      mode: .unlock,
      sessionID: envelope.id,
      feedbackPlan: feedback,
      learningRole: AnswerLearningRole.classify(mode: .unlock, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false,
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
    let seconds = feedback.minimumActiveReviewSeconds
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
    if let existing = try await context.dependencies.learning.loadVocabularyPendingPreview(
      for: context.manifest.id, now: context.now),
      existing.sourceUnlockBundleID == context.envelope.id
    {
      return
    }

    let package = try await context.dependencies.content.vocabularyPackage(
      for: context.manifest.id)
    let settings = VocabularySettings.load(packID: context.manifest.id)
    let access = ContentAccessService()
    let completedIDs = Set(state.questions.map { $0.id.rawValue })
    let available = package.items.filter { item in
      !completedIDs.contains(item.id)
        && (settings.selectedLevelCodes.isEmpty
          || settings.selectedLevelCodes.contains(item.levelCode))
        && access.decision(
          isFreeSample: package.freeSampleIDs.contains(item.id),
          manifest: context.manifest,
          entitlement: context.dependencies.commerce.entitlement
        ).isAllowed
    }
    let progress = try await context.dependencies.learning.allProgress()
    guard let candidate = VocabularyLearningQueuePlanner().makeQueue(
      items: available,
      progress: progress,
      packID: context.manifest.id,
      mode: .unlock,
      count: 1,
      now: context.now
    ).first else {
      try await context.dependencies.learning.saveVocabularyPendingPreview(
        nil, for: context.manifest.id)
      return
    }
    let preview = VocabularyPendingPreview(
      id: UUID(),
      packID: context.manifest.id,
      sourceUnlockBundleID: context.envelope.id,
      itemID: candidate.id,
      contentVersion: candidate.metadata.contentVersion,
      createdAt: context.now,
      recallExpiresAt: context.now.addingTimeInterval(VocabularyPendingPreview.recallDuration),
      confirmedAt: nil,
      consumedAt: nil,
      foregroundExposureSeconds: 0
    )
    try await context.dependencies.learning.saveVocabularyPendingPreview(
      preview, for: context.manifest.id)
  }

  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async {
    try? await dependencies.learning.saveVocabularyPendingPreview(nil, for: packID)
  }

  private func decode(_ envelope: UnlockChallengeSessionEnvelope) throws -> FlashcardUnlockSessionPayload {
    guard envelope.experienceID.normalizedTemplateID == experienceID,
      supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID)
    else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard payload") }
    return try SharedJSON.decoder().decode(
      FlashcardUnlockSessionPayload.self, from: envelope.enginePayload)
  }

  private func choice(
    from answer: StudyAnswerValue,
    state: FlashcardUnlockSessionPayload
  ) throws -> (questionID: String, choiceID: String) {
    switch answer {
    case .choice(let questionID, let choiceID): return (questionID, choiceID)
    case .choiceID(let choiceID):
      guard let question = state.questions.first(where: {
        !state.completedQuestionIDs.contains($0.id)
      }) else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard question") }
      return (question.id.rawValue, choiceID)
    default: throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "flashcard choice")
    }
  }

  private func transition(
    _ state: FlashcardUnlockSessionPayload,
    submission: UnlockAnswerSubmissionResult? = nil,
    review: UnlockReviewExposureResult? = nil
  ) throws -> ExperienceSessionTransition {
    .init(
      payload: .init(
        schemaID: FlashcardUnlockSessionPayload.schemaID,
        data: try SharedJSON.encoder().encode(state)),
      submissionResult: submission,
      reviewResult: review)
  }
}

typealias VocabularyExperience = FlashcardExperience

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension StudyFeedbackPlan {
  var minimumActiveReviewSeconds: Int {
    switch self {
    case .immediate: return 0
    case .relearn6: return 6
    case .relearn12: return 12
    case .guided20: return 20
    }
  }
}

struct VocabularySessionPresentation: Identifiable {
  let id: UUID
  let mode: StudyMode
  let questions: [VocabularyQuestion]
}

@MainActor
final class VocabularyAppModel: ObservableObject {
  @Published private(set) var items: [VocabularyItem] = []
  @Published private(set) var freeSampleIDs: Set<String> = []
  @Published private(set) var progress: [String: ItemProgress] = [:]
  @Published private(set) var answers: [StudyAnswerRecord] = []
  @Published private(set) var pendingPreview: VocabularyPendingPreview?
  @Published var settings: VocabularySettings
  @Published var session: VocabularySessionPresentation?
  @Published var errorMessage: String?
  @Published private(set) var isLoading = false

  let context: StudyExperienceContext
  var profile: FlashcardPresentationProfile { context.manifest.flashcardPresentation }
  var courseDefinitions: [FlashcardCourseDefinition] {
    if !profile.courseDefinitions.isEmpty { return profile.courseDefinitions }
    return Array(Set(items.map(\.levelCode))).sorted().map {
      .init(code: $0, title: $0, subtitle: nil, sampleLabel: nil)
    }
  }
  private let planner = VocabularyLearningQueuePlanner()
  private let generator = VocabularyQuestionGenerator()
  private let feedbackPlanner = VocabularyFeedbackPlanner()
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
      let package = try await context.dependencies.content.vocabularyPackage(
        for: context.manifest.id)
      freeSampleIDs = package.freeSampleIDs
      let access = ContentAccessService()
      items = package.items.filter {
        access.decision(
          isFreeSample: package.freeSampleIDs.contains($0.id),
          manifest: context.manifest,
          entitlement: context.dependencies.commerce.entitlement
        ).isAllowed
      }
      let availableCourses = Set(package.items.map(\.levelCode))
      if settings.selectedLevelCodes.isDisjoint(with: availableCourses),
        let first = profile.courseDefinitions.first?.code ?? availableCourses.sorted().first
      {
        settings.selectedLevelCodes = [first]
        try settings.save(packID: context.manifest.id)
      }
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter {
        $0.experienceID == .vocabulary && $0.packID == context.manifest.id
      }
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestVocabularyPreview"),
        let item = items.first
      {
        let now = Date()
        try await context.dependencies.learning.saveVocabularyPendingPreview(.init(
          id: UUID(),
          packID: context.manifest.id,
          sourceUnlockBundleID: UUID(),
          itemID: item.id,
          contentVersion: item.metadata.contentVersion,
          createdAt: now.addingTimeInterval(-118),
          recallExpiresAt: now.addingTimeInterval(VocabularyPendingPreview.recallDuration),
          confirmedAt: nil,
          consumedAt: nil,
          foregroundExposureSeconds: 0
        ), for: context.manifest.id)
      }
      #endif
      pendingPreview = try await context.dependencies.learning.loadVocabularyPendingPreview(
        for: context.manifest.id, now: Date())
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    if settings.selectedLevelCodes.isEmpty,
      let first = courseDefinitions.first?.code
    {
      settings.selectedLevelCodes = [first]
    }
    do { try settings.save(packID: context.manifest.id) }
    catch { errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func visiblePendingPreviewItem(at date: Date) -> VocabularyItem? {
    guard let preview = pendingPreview, preview.isDisplayable(at: date) else { return nil }
    return items.first { $0.id == preview.itemID && $0.metadata.contentVersion == preview.contentVersion }
  }

  func confirmPendingPreviewVisible(seconds: TimeInterval, now: Date = Date()) async {
    guard seconds > 0, var preview = pendingPreview,
      preview.confirmedAt == nil,
      preview.isDisplayable(at: now)
    else { return }
    preview.recordForegroundExposure(seconds: seconds, at: now)
    do {
      try await context.dependencies.learning.saveVocabularyPendingPreview(
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
      try await context.dependencies.learning.saveVocabularyPendingPreview(
        preview, for: context.manifest.id)
      pendingPreview = preview
    } catch { errorMessage = "予習状態を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func start(mode: StudyMode) {
    let scoped = items.filter { settings.selectedLevelCodes.contains($0.levelCode) }
    let queue = planner.makeQueue(
      items: scoped.isEmpty ? items : scoped,
      progress: progress,
      packID: context.manifest.id,
      mode: mode,
      count: max(1, settings.dailyGoal),
      now: Date()
    )
    do {
      let questions = try queue.map(generator.makeQuestion)
      guard !questions.isEmpty else { errorMessage = emptyStateMessage(for: mode); return }
      session = .init(id: UUID(), mode: mode, questions: questions)
      Task { try? await context.dependencies.learning.record(.init(kind: .studyStarted, packID: context.manifest.id, sessionID: session?.id)) }
    } catch { errorMessage = error.localizedDescription }
  }

  func recordAnswer(
    question: VocabularyQuestion,
    selectedChoiceID: Int,
    sessionID: UUID,
    attempt: Int
  ) async -> StudyAnswerSubmissionResult {
    let isCorrect = selectedChoiceID == question.correctChoiceID
    let plan = feedbackPlanner.plan(wrongAttemptCount: isCorrect ? 0 : attempt + 1)
    let item = question.item
    let answeredAt = Date()
    let mode = session?.mode ?? .practice
    let compositeID = CompositeStudyItemID(packID: context.manifest.id, itemID: item.studyItemID)
    let priorProgress = progress[compositeID.storageKey] ?? .initial(compositeID)
    let record = StudyAnswerRecord(
      submissionID: "vocabulary::\(sessionID.uuidString)::\(item.id)::\(selectedChoiceID)::\(attempt)",
      experienceID: .vocabulary,
      packID: context.manifest.id,
      moduleType: .vocabulary,
      itemID: item.studyItemID,
      prompt: item.prompt,
      choices: question.choices,
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      shortExplanation: item.explanationJa,
      longExplanation: "\(item.explanationJa)\n\(item.exampleEn)\n\(item.exampleJa)",
      sourceNote: nil,
      category: item.levelCode,
      subcategory: item.primaryPosJa,
      contentVersion: item.metadata.contentVersion,
      questionVersion: 1,
      examYear: nil,
      lawBasisDate: nil,
      answeredAt: answeredAt,
      mode: mode,
      sessionID: sessionID,
      feedbackPlan: plan,
      tags: [item.metadata.cefr, item.partOfSpeechJa],
      learningRole: .classify(mode: mode, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false
    )
    do {
      _ = try await context.dependencies.learning.recordUnique(record)
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter {
        $0.experienceID == .vocabulary && $0.packID == context.manifest.id
      }
      context.dependencies.learningRevision.bump()
      return isCorrect ? .recordedCorrect(plan) : .recordedIncorrect(plan)
    } catch {
      let message = error.localizedDescription
      errorMessage = message
      return .failed(message)
    }
  }

  var weeklyReport: VocabularyWeeklyReport {
    VocabularyWeeklyReportService().make(
      answers: answers, progress: progress, packID: context.manifest.id, now: Date())
  }
  var pendingPreviewExamplesEnabled: Bool {
    profile.supportsExamples && settings.examplesEnabled
  }
  var learnedCount: Int {
    progress.values.filter {
      $0.id.packID == context.manifest.id && !$0.isSafeFallbackArtifact && $0.answerCount > 0
    }.count
  }
  var dueCount: Int {
    progress.values.filter {
      $0.id.packID == context.manifest.id && !$0.isSafeFallbackArtifact
        && ($0.dueAt.map { $0 <= Date() } ?? false)
    }.count
  }
  func itemProgress(_ item: VocabularyItem) -> ItemProgress {
    progress[CompositeStudyItemID(packID: context.manifest.id, itemID: item.studyItemID).storageKey]
      ?? .initial(.init(packID: context.manifest.id, itemID: item.studyItemID))
  }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int { feedbackPlanner.waitSeconds(for: plan) }
  func emptyStateMessage(for mode: StudyMode) -> String {
    let copy = profile.resolvedEmptyStateCopy
    switch mode {
    case .review: return copy.noDueReview
    case .mistakes: return copy.noMistakes
    case .weakness: return copy.noWeakItems
    case .newItems: return copy.noNewItems
    default: return copy.noAvailableItems
    }
  }
}
