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
    var selected = planner.makeQueue(
      items: safePool,
      progress: request.progress,
      packID: packID,
      mode: .unlock,
      count: request.policy.accessPacePreset.requiredLearningUnits,
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
  @Published var settings: VocabularySettings
  @Published var session: VocabularySessionPresentation?
  @Published var errorMessage: String?
  @Published private(set) var isLoading = false

  let context: StudyExperienceContext
  private let repository = VocabularyRepository()
  private let planner = VocabularyLearningQueuePlanner()
  private let generator = VocabularyQuestionGenerator()
  private let feedbackPlanner = VocabularyFeedbackPlanner()

  init(context: StudyExperienceContext) {
    self.context = context
    settings = .load()
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
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    if settings.selectedLevelCodes.isEmpty { settings.selectedLevelCodes = [VocabularyLevel.level0.rawValue] }
    settings.save()
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
  ) async -> StudyFeedbackPlan {
    let isCorrect = selectedChoiceID == question.correctChoiceID
    let plan = feedbackPlanner.plan(wrongAttemptCount: isCorrect ? 0 : attempt + 1)
    let item = question.item
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
      answeredAt: Date(),
      mode: session?.mode ?? .practice,
      sessionID: sessionID,
      feedbackPlan: plan,
      tags: [item.metadata.cefr, item.partOfSpeechJa]
    )
    do {
      _ = try await context.dependencies.learning.recordUnique(record)
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .vocabulary }
    } catch { errorMessage = error.localizedDescription }
    return plan
  }

  var weeklyReport: VocabularyWeeklyReport {
    VocabularyWeeklyReportService().make(answers: answers, progress: progress, now: Date())
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
