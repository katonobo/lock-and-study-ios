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

  func makeUnlockChallenge(packID: StudyPackID, request: UnlockChallengeRequest) async throws -> UnlockChallengeSnapshot {
    let questions = try repository.load(manifest: request.manifest)
    let settings = TakkenSettings.load()
    let service = TakkenQuestionService()
    let required = request.policy.accessPacePreset.requiredLearningUnits
    var selected = service.practiceQuestions(
      questions: questions,
      progress: request.progress,
      packID: packID,
      settings: settings,
      mode: .unlock,
      count: required,
      now: request.now
    )
    let selectedIDs = Set(selected.map(\.id))
    let due = questions.filter { question in
      guard question.unlockEligible, !selectedIDs.contains(question.id) else { return false }
      let key = CompositeStudyItemID(packID: packID, itemID: .init(rawValue: question.id)).storageKey
      return request.progress[key]?.dueAt.map { $0 <= request.now } ?? false
    }.sorted { lhs, rhs in
      let left = request.progress[CompositeStudyItemID(packID: packID, itemID: .init(rawValue: lhs.id)).storageKey]?.dueAt ?? .distantFuture
      let right = request.progress[CompositeStudyItemID(packID: packID, itemID: .init(rawValue: rhs.id)).storageKey]?.dueAt ?? .distantFuture
      return left < right
    }
    selected.append(contentsOf: due.prefix(request.policy.reviewLoadPreset.maxAdditionalDueReviews))
    guard !selected.isEmpty else { throw ContentRepositoryError.invalid("無料宅建問題を選べません") }
    let snapshots = selected.map { question in
      UnlockQuestionSnapshot.takken(.init(
        id: .init(rawValue: question.id),
        prompt: question.prompt,
        choices: question.choices.enumerated().map { .init(id: $0.offset, text: $0.element) },
        correctChoiceID: question.correctIndex,
        shortExplanation: question.shortExplanation ?? question.explanation,
        longExplanation: question.longExplanation ?? question.explanation,
        keyPoint: question.keyPoint,
        category: question.category,
        subCategory: question.subCategory,
        difficulty: question.difficulty,
        format: question.format?.rawValue ?? "multiple_choice",
        examYear: question.examYear,
        lawBasisDate: question.lawBasisDate,
        sourceNote: question.sourceNote,
        contentVersion: request.manifest.contentVersion,
        questionVersion: question.version ?? 1
      ))
    }
    return .init(
      schemaVersion: 2,
      id: UUID(),
      requestID: request.requestID,
      origin: request.origin,
      experienceID: .takken,
      packID: packID,
      policyVersion: request.policy.policyVersion,
      pace: request.policy.accessPacePreset,
      reviewLoad: request.policy.reviewLoadPreset,
      questions: snapshots,
      access: .init(packID: packID, reason: .freeSample, verifiedAt: request.entitlement.lastVerifiedAt),
      createdAt: request.now,
      expiresAt: request.now.addingTimeInterval(ExperienceUnlockBundleSnapshot.expirationInterval)
    )
  }
}

@MainActor
struct TakkenExperience: StudyExperienceFactory {
  let descriptor = StudyExperienceDescriptor(
    id: .takken,
    title: "宅建2026",
    subtitle: "品質確認済み無料100問",
    systemImage: "building.columns.fill",
    tintName: "orange",
    supportedPackIDs: ["takken2026.v1"]
  )
  let unlockChallengeProvider: any UnlockChallengeProviding = TakkenUnlockChallengeProvider()
  let reportProvider: (any StudyExperienceReportProviding)? = TakkenReportProvider()

  func makeRootView(context: StudyExperienceContext) -> AnyView { AnyView(TakkenRootView(context: context)) }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? { AnyView(TakkenFirstRunView(context: context)) }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    let allProgress = try await context.dependencies.learning.allProgress()
    let progress = allProgress.values.filter { $0.id.packID == context.manifest.id }
    let answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .takken }
    return .init(
      experienceID: .takken,
      packID: context.manifest.id,
      answeredCount: answers.count,
      correctCount: answers.filter(\.isCorrect).count,
      learnedItemCount: progress.filter { $0.answerCount > 0 }.count,
      dueCount: progress.filter { $0.dueAt.map { $0 <= Date() } ?? false }.count
    )
  }
  func makeUnlockChallengeView(snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) -> AnyView {
    AnyView(TakkenUnlockChallengeView(bundle: snapshot, context: context))
  }
}

struct TakkenSessionPresentation: Identifiable {
  let id: UUID
  let mode: StudyMode
  let questions: [TakkenQuestion]
}

@MainActor
final class TakkenAppModel: ObservableObject {
  @Published private(set) var questions: [TakkenQuestion] = []
  @Published private(set) var progress: [String: ItemProgress] = [:]
  @Published private(set) var answers: [StudyAnswerRecord] = []
  @Published var settings: TakkenSettings
  @Published var session: TakkenSessionPresentation?
  @Published var errorMessage: String?
  @Published private(set) var isLoading = false

  let context: StudyExperienceContext
  private let repository = TakkenQuestionRepository()
  private let service = TakkenQuestionService()
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
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .takken }
    } catch { errorMessage = error.localizedDescription }
  }

  func saveSettings() {
    do { try settings.save() }
    catch { errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)" }
  }
  func start(mode: StudyMode) {
    let queue = service.practiceQuestions(
      questions: questions,
      progress: progress,
      packID: context.manifest.id,
      settings: settings,
      mode: mode,
      count: settings.questionCount,
      now: Date()
    )
    guard !queue.isEmpty else { errorMessage = emptyMessage(for: mode); return }
    session = .init(id: UUID(), mode: mode, questions: queue)
    let sessionID = session?.id
    Task { try? await context.dependencies.learning.record(.init(kind: .studyStarted, packID: context.manifest.id, sessionID: sessionID)) }
  }

  func recordAnswer(question: TakkenQuestion, selectedChoiceID: Int, sessionID: UUID, attempt: Int) async -> StudyAnswerSubmissionResult {
    let correct = selectedChoiceID == question.correctIndex
    let plan = feedbackPlanner.plan(wrongAttemptCount: correct ? 0 : attempt + 1)
    let answeredAt = Date()
    let mode = session?.mode ?? .practice
    let compositeID = CompositeStudyItemID(
      packID: context.manifest.id, itemID: .init(rawValue: question.id))
    let priorProgress = progress[compositeID.storageKey] ?? .initial(compositeID)
    let record = StudyAnswerRecord(
      submissionID: "takken::\(sessionID.uuidString)::\(question.id)::\(selectedChoiceID)::\(attempt)",
      experienceID: .takken,
      packID: context.manifest.id,
      moduleType: .takken,
      itemID: .init(rawValue: question.id),
      prompt: question.prompt,
      choices: question.choices.enumerated().map { .init(id: $0.offset, text: $0.element) },
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctIndex,
      shortExplanation: question.shortExplanation ?? question.explanation,
      longExplanation: question.longExplanation ?? question.explanation,
      sourceNote: question.sourceNote,
      category: question.category,
      subcategory: question.subCategory,
      contentVersion: context.manifest.contentVersion,
      questionVersion: question.version ?? 1,
      examYear: question.examYear,
      lawBasisDate: question.lawBasisDate,
      answeredAt: answeredAt,
      mode: mode,
      sessionID: sessionID,
      feedbackPlan: plan,
      difficulty: question.difficulty,
      questionFormat: question.format?.rawValue,
      keyPoint: question.keyPoint,
      tags: question.tags,
      learningRole: .classify(mode: mode, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false
    )
    do {
      _ = try await context.dependencies.learning.recordUnique(record)
      progress = try await context.dependencies.learning.allProgress()
      answers = try await context.dependencies.learning.answers().filter { $0.experienceID == .takken }
      context.dependencies.learningRevision.bump()
      return correct ? .recordedCorrect(plan) : .recordedIncorrect(plan)
    } catch {
      let message = error.localizedDescription
      errorMessage = message
      return .failed(message)
    }
  }

  func itemProgress(_ question: TakkenQuestion) -> ItemProgress {
    progress[CompositeStudyItemID(packID: context.manifest.id, itemID: .init(rawValue: question.id)).storageKey]
      ?? .initial(.init(packID: context.manifest.id, itemID: .init(rawValue: question.id)))
  }
  var categories: [String] { Array(Set(questions.map(\.category))).sorted() }
  func subCategories(category: String?) -> [String] {
    Array(Set(questions.filter { category == nil || $0.category == category }.compactMap(\.subCategory))).sorted()
  }
  var summary: TakkenRecordsSummary { TakkenRecordsAnalyzer().summary(answers: answers, now: Date()) }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int { feedbackPlanner.waitSeconds(for: plan) }
  private func emptyMessage(for mode: StudyMode) -> String {
    switch mode { case .review: return "期限が来た復習問題はありません。"; case .mistakes: return "復習する誤答はありません。"; case .weakness: return "苦手問題はまだありません。"; case .newItems: return "未回答問題はありません。"; default: return "条件に合う問題がありません。" }
  }
}
