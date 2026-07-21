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

struct VocabularyUnlockChallengeProvider: UnlockChallengeProviding {
  let repository: VocabularyRepository
  init(bundle: Bundle = .main) { repository = .init(bundle: bundle) }

  func makeUnlockChallenge(packID: StudyPackID, request: UnlockChallengeRequest) async throws -> UnlockChallengeSnapshot {
    let package = try repository.load(manifest: request.manifest)
    let settings = VocabularySettings.load()
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
    guard !safePool.isEmpty else { throw ContentRepositoryError.invalid("無料英単語を読み込めません") }
    let planner = VocabularyLearningQueuePlanner()
    var previewItem: VocabularyItem?
    if let preview = try await request.learning.loadVocabularyPendingPreview(now: request.now),
      let candidate = safePool.first(where: { $0.id == preview.itemID }),
      preview.isUsableForRecall(contentVersion: candidate.metadata.contentVersion, now: request.now),
      try await request.learning.consumeVocabularyPendingPreview(id: preview.id, at: request.now)
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
      UnlockQuestionSnapshot.vocabulary(.init(
        id: item.studyItemID,
        word: item.displayWord,
        prompt: item.prompt,
        choices: item.options.enumerated().map { .init(id: $0.offset, text: $0.element) },
        correctChoiceID: item.correctIndex,
        explanation: item.explanationJa,
        exampleEnglish: item.exampleEn,
        exampleJapanese: item.exampleJa,
        speechText: item.speechText,
        levelCode: item.levelCode,
        contentVersion: item.metadata.contentVersion,
        isFreeSample: package.freeSampleIDs.contains(item.id)
      ))
    }
    guard let first = selected.first else { throw ContentRepositoryError.invalid("解除問題を選べません") }
    let reason = access.decision(
      isFreeSample: package.freeSampleIDs.contains(first.id),
      manifest: request.manifest,
      entitlement: request.entitlement
    ).reason
    return .init(
      schemaVersion: 2,
      id: UUID(),
      requestID: request.requestID,
      origin: request.origin,
      experienceID: .vocabulary,
      packID: packID,
      policyVersion: request.policy.policyVersion,
      pace: request.policy.accessPacePreset,
      reviewLoad: request.policy.reviewLoadPreset,
      questions: questions,
      access: .init(packID: packID, reason: reason, verifiedAt: request.entitlement.lastVerifiedAt),
      createdAt: request.now,
      expiresAt: request.now.addingTimeInterval(ExperienceUnlockBundleSnapshot.expirationInterval)
    )
  }
}

@MainActor
struct VocabularyExperience: StudyExperienceFactory {
  let descriptor = StudyExperienceDescriptor(
    id: .vocabulary,
    title: "英単語3,000語",
    subtitle: "5レベル・SRS・無料250語",
    systemImage: "character.book.closed.fill",
    tintName: "indigo",
    supportedPackIDs: ["english3000.v1"]
  )
  let unlockChallengeProvider: any UnlockChallengeProviding = VocabularyUnlockChallengeProvider()
  let reportProvider: (any StudyExperienceReportProviding)? = VocabularyReportProvider()

  func makeRootView(context: StudyExperienceContext) -> AnyView {
    AnyView(VocabularyRootView(context: context))
  }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? {
    AnyView(VocabularyFirstRunView(context: context))
  }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    let allProgress = try await context.dependencies.learning.allProgress()
    let progress = allProgress.values.filter { $0.id.packID == context.manifest.id }
    let answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .vocabulary }
    return .init(
      experienceID: .vocabulary,
      packID: context.manifest.id,
      answeredCount: answers.count,
      correctCount: answers.filter(\.isCorrect).count,
      learnedItemCount: progress.filter { $0.answerCount > 0 }.count,
      dueCount: progress.filter { $0.dueAt.map { $0 <= Date() } ?? false }.count
    )
  }
  func makeUnlockChallengeView(snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) -> AnyView {
    AnyView(VocabularyUnlockChallengeView(bundle: snapshot, context: context))
  }

  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {
    if let existing = try await context.dependencies.learning.loadVocabularyPendingPreview(
      now: context.now),
      existing.sourceUnlockBundleID == context.bundle.id
    {
      return
    }

    let package = try VocabularyRepository().load(manifest: context.manifest)
    let settings = VocabularySettings.load()
    let access = ContentAccessService()
    let completedIDs = Set(context.bundle.challenge.questions.map { $0.id.rawValue })
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
      try await context.dependencies.learning.saveVocabularyPendingPreview(nil)
      return
    }
    let preview = VocabularyPendingPreview(
      id: UUID(),
      sourceUnlockBundleID: context.bundle.id,
      itemID: candidate.id,
      contentVersion: candidate.metadata.contentVersion,
      createdAt: context.now,
      recallExpiresAt: context.now.addingTimeInterval(VocabularyPendingPreview.recallDuration),
      confirmedAt: nil,
      consumedAt: nil,
      foregroundExposureSeconds: 0
    )
    try await context.dependencies.learning.saveVocabularyPendingPreview(preview)
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
  private let repository = VocabularyRepository()
  private let planner = VocabularyLearningQueuePlanner()
  private let generator = VocabularyQuestionGenerator()
  private let feedbackPlanner = VocabularyFeedbackPlanner()
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
      let package = try repository.load(manifest: context.manifest)
      freeSampleIDs = package.freeSampleIDs
      let access = ContentAccessService()
      items = package.items.filter {
        access.decision(
          isFreeSample: package.freeSampleIDs.contains($0.id),
          manifest: context.manifest,
          entitlement: context.dependencies.commerce.entitlement
        ).isAllowed
      }
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .vocabulary }
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestVocabularyPreview"),
        let item = items.first
      {
        let now = Date()
        try await context.dependencies.learning.saveVocabularyPendingPreview(.init(
          id: UUID(),
          sourceUnlockBundleID: UUID(),
          itemID: item.id,
          contentVersion: item.metadata.contentVersion,
          createdAt: now.addingTimeInterval(-118),
          recallExpiresAt: now.addingTimeInterval(VocabularyPendingPreview.recallDuration),
          confirmedAt: nil,
          consumedAt: nil,
          foregroundExposureSeconds: 0
        ))
      }
      #endif
      pendingPreview = try await context.dependencies.learning.loadVocabularyPendingPreview(now: Date())
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    if settings.selectedLevelCodes.isEmpty { settings.selectedLevelCodes = [VocabularyLevel.level0.rawValue] }
    do { try settings.save() }
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
      try await context.dependencies.learning.saveVocabularyPendingPreview(preview)
      pendingPreview = preview
    } catch { errorMessage = "予習状態を保存できませんでした。\n\(error.localizedDescription)" }
  }

  func clearPendingPreviewExposureIfUnconfirmed() async {
    guard var preview = pendingPreview, preview.confirmedAt == nil,
      preview.foregroundExposureSeconds != 0
    else { return }
    preview.resetUnconfirmedForegroundExposure()
    do {
      try await context.dependencies.learning.saveVocabularyPendingPreview(preview)
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
      guard !questions.isEmpty else { errorMessage = emptyMessage(for: mode); return }
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
      answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .vocabulary }
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
  var learnedCount: Int { progress.values.filter { $0.id.packID == context.manifest.id && $0.answerCount > 0 }.count }
  var dueCount: Int { progress.values.filter { $0.id.packID == context.manifest.id && ($0.dueAt.map { $0 <= Date() } ?? false) }.count }
  func itemProgress(_ item: VocabularyItem) -> ItemProgress {
    progress[CompositeStudyItemID(packID: context.manifest.id, itemID: item.studyItemID).storageKey]
      ?? .initial(.init(packID: context.manifest.id, itemID: item.studyItemID))
  }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int { feedbackPlanner.waitSeconds(for: plan) }
  private func emptyMessage(for mode: StudyMode) -> String {
    switch mode {
    case .review: return "期限が来た復習はありません。"
    case .mistakes: return "復習する誤答はまだありません。"
    case .weakness: return "苦手として判定された単語はまだありません。"
    case .newItems: return "このコースの新出単語は一巡しました。期限到来復習を続けられます。"
    default: return "利用できる問題がありません。"
    }
  }
}
