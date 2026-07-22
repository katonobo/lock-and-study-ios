import Foundation
import SwiftUI

struct StudyExperienceID: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  static let flashcardV1 = StudyExperienceID(rawValue: "flashcard.v1")
  static let certificationV1 = StudyExperienceID(rawValue: "certification.v1")
  static let safeFallbackV1 = StudyExperienceID(rawValue: "safe-fallback.v1")

  // Presentation/history IDs remain stable for existing learning data.
  static let vocabulary = StudyExperienceID(rawValue: "vocabulary")
  static let takken = StudyExperienceID(rawValue: "takken")
  static let safeFallback = StudyExperienceID(rawValue: "safe-fallback")

  var normalizedTemplateID: StudyExperienceID {
    switch rawValue {
    case "vocabulary", "vocabulary.v1": return .flashcardV1
    case "takken", "certification.takken.v1": return .certificationV1
    case "safe-fallback": return .safeFallbackV1
    default: return self
    }
  }
}
struct StudyExperienceDescriptor: Identifiable, Hashable, Sendable {
  let id: StudyExperienceID
  let title: String
  let subtitle: String
  let systemImage: String
  let tintName: String
  let supportedExperienceTypes: Set<StudyExperienceType>
}

struct StudyExperienceSummary: Equatable, Sendable {
  let experienceID: StudyExperienceID
  let packID: StudyPackID
  let answeredCount: Int
  let correctCount: Int
  let learnedItemCount: Int
  let dueCount: Int
  var accuracy: Double { answeredCount == 0 ? 0 : Double(correctCount) / Double(answeredCount) }
}

enum StudyExperienceDestination: String, Codable, Sendable {
  case home, learning, catalog, records, settings
}

struct ActiveStudyExperience: Identifiable, Equatable, Sendable {
  let id: UUID
  let experienceID: StudyExperienceID
  let packID: StudyPackID
  let destination: StudyExperienceDestination
  let requiresFirstRun: Bool

  init(
    id: UUID = UUID(),
    experienceID: StudyExperienceID,
    packID: StudyPackID,
    destination: StudyExperienceDestination = .home,
    requiresFirstRun: Bool = false
  ) {
    self.id = id
    self.experienceID = experienceID
    self.packID = packID
    self.destination = destination
    self.requiresFirstRun = requiresFirstRun
  }
}

@MainActor
struct StudyExperienceContext {
  let manifest: StudyPackManifest
  let dependencies: DependencyContainer
  let reportProviders: [any StudyExperienceReportProviding]
  let destination: StudyExperienceDestination
  let openMaterialSelection: @MainActor () -> Void
  let beginUnlockStudy: @MainActor () async -> Void
  let completeFirstRun: @MainActor () -> Void
}

struct UnlockChallengeRequest: Sendable {
  let requestID: UUID
  let origin: UnlockChallengeOrigin
  let policy: LockPolicy
  let manifest: StudyPackManifest
  let entitlement: CommerceEntitlementSnapshot
  let progress: [String: ItemProgress]
  let learning: LearningDataStore
  let content: ContentRepository
  let now: Date

  init(
    requestID: UUID,
    origin: UnlockChallengeOrigin,
    policy: LockPolicy,
    manifest: StudyPackManifest,
    entitlement: CommerceEntitlementSnapshot,
    progress: [String: ItemProgress],
    learning: LearningDataStore,
    content: ContentRepository = ContentRepository(),
    now: Date
  ) {
    self.requestID = requestID
    self.origin = origin
    self.policy = policy
    self.manifest = manifest
    self.entitlement = entitlement
    self.progress = progress
    self.learning = learning
    self.content = content
    self.now = now
  }
}

struct UnlockCompletionContext {
  let bundle: ExperienceUnlockBundleSnapshot
  let manifest: StudyPackManifest
  let dependencies: DependencyContainer
  let now: Date
}

enum UnlockAnswerSubmissionResult: Equatable {
  case recordedCorrect
  case recordedIncorrect(remainingActiveSeconds: Int, attemptNumber: Int)
  case expired
  case failed(String)
}

enum UnlockReviewExposureResult: Equatable {
  case updated(remainingActiveSeconds: Int)
  case expired
  case failed(String)
}

struct VocabularyUnlockQuestionSnapshot: Codable, Equatable, Identifiable, Sendable {
  let id: StudyItemID
  let word: String
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let explanation: String
  let exampleEnglish: String
  let exampleJapanese: String
  let speechText: String
  let levelCode: String
  let contentVersion: String
  let isFreeSample: Bool
}

struct TakkenUnlockQuestionSnapshot: Codable, Equatable, Identifiable, Sendable {
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

struct SafeFallbackUnlockQuestionSnapshot: Codable, Equatable, Identifiable, Sendable {
  let id: StudyItemID
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let explanation: String
}

enum UnlockQuestionSnapshot: Codable, Equatable, Identifiable, Sendable {
  case vocabulary(VocabularyUnlockQuestionSnapshot)
  case takken(TakkenUnlockQuestionSnapshot)
  case safeFallback(SafeFallbackUnlockQuestionSnapshot)

  var id: StudyItemID {
    switch self {
    case .vocabulary(let value): return value.id
    case .takken(let value): return value.id
    case .safeFallback(let value): return value.id
    }
  }
  var choices: [StudyChoice] {
    switch self {
    case .vocabulary(let value): return value.choices
    case .takken(let value): return value.choices
    case .safeFallback(let value): return value.choices
    }
  }
  var correctChoiceID: Int {
    switch self {
    case .vocabulary(let value): return value.correctChoiceID
    case .takken(let value): return value.correctChoiceID
    case .safeFallback(let value): return value.correctChoiceID
    }
  }
  var legacyContentVersion: String {
    switch self {
    case .vocabulary(let value): return value.contentVersion
    case .takken(let value): return value.contentVersion
    case .safeFallback: return "built-in-v1"
    }
  }
}

struct UnlockChallengeSnapshot: Codable, Equatable, Identifiable, Sendable {
  let schemaVersion: Int
  let id: UUID
  let requestID: UUID
  let origin: UnlockChallengeOrigin?
  let experienceID: StudyExperienceID
  let packID: StudyPackID
  let policyVersion: Int
  let pace: AccessPacePreset
  let reviewLoad: ReviewLoadPreset
  let questions: [UnlockQuestionSnapshot]
  let access: UnlockBundleAccessSnapshot
  let createdAt: Date
  let expiresAt: Date

  var resolvedOrigin: UnlockChallengeOrigin { origin ?? .legacyUnknown }
}

enum UnlockCompletionState: String, Codable, Equatable, Sendable {
  case answering, proofAccepted, sessionCreated, eventRecorded, completed, aborted
}

struct ExperienceUnlockBundleSnapshot: Codable, Equatable, Identifiable, Sendable {
  static let expirationInterval: TimeInterval = 1_800
  let schemaVersion: Int
  var challenge: UnlockChallengeSnapshot
  var completedQuestionIDs: Set<StudyItemID>
  var completionState: UnlockCompletionState
  var completionEventID: UUID
  var createdUnlockSessionID: UUID?
  var abortReason: String?
  var attemptCountsByQuestionID: [String: Int]? = nil
  var reviewRequiredUntilByQuestionID: [String: Date]? = nil
  var reviewRemainingActiveSecondsByQuestionID: [String: TimeInterval]? = nil
  var reviewLastActiveAtByQuestionID: [String: Date]? = nil
  var lastSelectedChoiceIDByQuestionID: [String: Int]? = nil

  var id: UUID { challenge.id }
  var isComplete: Bool { completedQuestionIDs.count >= challenge.questions.count }
  func isAnswering(at date: Date) -> Bool {
    date < challenge.expiresAt && abortReason == nil && completionState == .answering
  }


  @discardableResult
  mutating func migrateLegacyReviewState(at migrationDate: Date) -> Bool {
    guard let legacy = reviewRequiredUntilByQuestionID, !legacy.isEmpty else { return false }
    var remaining = reviewRemainingActiveSecondsByQuestionID ?? [:]
    let minimums = Dictionary(uniqueKeysWithValues: challenge.questions.compactMap {
      snapshot -> (String, TimeInterval)? in
      guard case .takken(let question) = snapshot else { return nil }
      return (question.id.rawValue, TimeInterval(question.minimumReviewSeconds ?? 10))
    })
    for (questionID, deadline) in legacy where remaining[questionID] == nil {
      let maximum = minimums[questionID] ?? 20
      remaining[questionID] = min(maximum, max(0, deadline.timeIntervalSince(migrationDate)))
    }
    reviewRemainingActiveSecondsByQuestionID = remaining.isEmpty ? nil : remaining
    reviewRequiredUntilByQuestionID = nil
    reviewLastActiveAtByQuestionID = nil
    return true
  }

  mutating func clearReviewState(for questionID: StudyItemID) {
    reviewRequiredUntilByQuestionID?.removeValue(forKey: questionID.rawValue)
    reviewRemainingActiveSecondsByQuestionID?.removeValue(forKey: questionID.rawValue)
    reviewLastActiveAtByQuestionID?.removeValue(forKey: questionID.rawValue)
    lastSelectedChoiceIDByQuestionID?.removeValue(forKey: questionID.rawValue)
  }

  @discardableResult
  mutating func applyActiveReviewExposure(
    _ elapsedSeconds: TimeInterval,
    for questionID: StudyItemID
  ) -> TimeInterval {
    let key = questionID.rawValue
    var remaining = reviewRemainingActiveSecondsByQuestionID ?? [:]
    let value = max(0, (remaining[key] ?? 0) - max(0, elapsedSeconds))
    if value > 0 { remaining[key] = value } else { remaining.removeValue(forKey: key) }
    reviewRemainingActiveSecondsByQuestionID = remaining.isEmpty ? nil : remaining
    return value
  }

  func hasLaterUncompletedQuestion(
    after index: Int,
    completedQuestionIDs: Set<StudyItemID>
  ) -> Bool {
    challenge.questions.indices.contains { candidate in
      candidate > index && !completedQuestionIDs.contains(challenge.questions[candidate].id)
    }
  }

  func nextUncompletedQuestionIndex(
    after index: Int,
    completedQuestionIDs: Set<StudyItemID>
  ) -> Int? {
    challenge.questions.indices.first { candidate in
      candidate > index && !completedQuestionIDs.contains(challenge.questions[candidate].id)
    }
  }
}

protocol UnlockChallengeProviding: Sendable {
  func makeUnlockChallenge(
    packID: StudyPackID,
    request: UnlockChallengeRequest
  ) async throws -> UnlockChallengeSnapshot
}

@MainActor
struct UnlockChallengeViewContext {
  let bundle: ExperienceUnlockBundleSnapshot
  let submit: @MainActor (UnlockQuestionSnapshot, Int, StudyFeedbackPlan) async -> UnlockAnswerSubmissionResult
  let updateReviewExposure: @MainActor (StudyItemID, Bool) async -> UnlockReviewExposureResult
  let restart: @MainActor () async -> Void
  let complete: @MainActor () async -> Void
}

struct UnlockAnswerRecordContext: Sendable {
  let question: UnlockQuestionSnapshot
  let selectedChoiceID: Int
  let feedback: StudyFeedbackPlan
  let bundle: ExperienceUnlockBundleSnapshot
  let answeredAt: Date
  let priorProgress: ItemProgress
  let attemptNumber: Int

  var submissionID: String {
    "unlock::\(bundle.id.uuidString)::\(question.id.rawValue)::attempt::\(attemptNumber)::choice::\(selectedChoiceID)"
  }
  var learningRole: AnswerLearningRole {
    AnswerLearningRole.classify(mode: .unlock, progress: priorProgress, at: answeredAt)
  }
  var wasNew: Bool { priorProgress.answerCount == 0 }
  var wasDue: Bool { priorProgress.dueAt.map { $0 <= answeredAt } ?? false }
}

enum StudyExperienceRuntimeError: LocalizedError {
  case incompatibleQuestion(expected: String)

  var errorDescription: String? {
    switch self {
    case .incompatibleQuestion(let expected):
      return "解除問題が\(expected)の実行形式と一致しません。"
    }
  }
}

@MainActor
protocol StudyExperienceFactory {
  var experienceID: StudyExperienceID { get }
  var descriptor: StudyExperienceDescriptor { get }
  var supportedContentSchemas: Set<ContentSchemaID> { get }
  var unlockChallengeProvider: any UnlockChallengeProviding { get }
  var reportProvider: (any StudyExperienceReportProviding)? { get }
  func validateCompatibility(with manifest: StudyPackManifest) -> [String]
  func makeRootView(context: StudyExperienceContext) -> AnyView
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView?
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary
  func makeUnlockChallengeView(
    snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext
  ) -> AnyView
  func makeUnlockAnswerRecord(_ context: UnlockAnswerRecordContext) throws -> StudyAnswerRecord
  func minimumReviewSeconds(
    for context: UnlockAnswerRecordContext
  ) throws -> Int
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws
  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async
}

extension StudyExperienceFactory {
  var reportProvider: (any StudyExperienceReportProviding)? { nil }
  func validateCompatibility(with manifest: StudyPackManifest) -> [String] {
    guard manifest.experienceID.normalizedTemplateID == experienceID else {
      return ["experience IDが一致しません"]
    }
    let relevant = manifest.components.filter {
      $0.experienceID.normalizedTemplateID == experienceID
    }
    guard !relevant.isEmpty else { return ["対応componentがありません"] }
    let unsupported = relevant.filter { !supportedContentSchemas.contains($0.contentSchemaID) }
    return unsupported.map { "未対応content schema: \($0.contentSchemaID.rawValue)" }
  }
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {}
  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async {}
  func minimumReviewSeconds(for context: UnlockAnswerRecordContext) throws -> Int {
    switch context.feedback {
    case .immediate: return 0
    case .relearn6: return 6
    case .relearn12: return 12
    case .guided20: return 20
    }
  }
}

@MainActor
struct StudyExperienceRegistry {
  private let factoriesByPresentationID: [StudyExperienceID: any StudyExperienceFactory]
  private let factoriesByExperienceID: [StudyExperienceID: any StudyExperienceFactory]
  private let factoriesByType: [StudyExperienceType: any StudyExperienceFactory]

  init(factories: [any StudyExperienceFactory]) {
    factoriesByPresentationID = Dictionary(
      uniqueKeysWithValues: factories.map { ($0.descriptor.id, $0) })
    factoriesByExperienceID = Dictionary(
      uniqueKeysWithValues: factories.map { ($0.experienceID, $0) })
    factoriesByType = Dictionary(uniqueKeysWithValues: factories.flatMap { factory in
      factory.descriptor.supportedExperienceTypes.map { ($0, factory) }
    })
  }

  func factory(for id: StudyExperienceID) -> (any StudyExperienceFactory)? {
    factoriesByPresentationID[id] ?? factoriesByExperienceID[id.normalizedTemplateID]
  }
  func factory(forExperienceID id: StudyExperienceID) -> (any StudyExperienceFactory)? {
    factoriesByExperienceID[id.normalizedTemplateID]
  }
  func factory(for type: StudyExperienceType) -> (any StudyExperienceFactory)? {
    factoriesByType[type]
      ?? factoriesByExperienceID[StudyExperienceID(rawValue: type.rawValue).normalizedTemplateID]
  }
  func factory(for manifest: StudyPackManifest) -> (any StudyExperienceFactory)? {
    factory(forExperienceID: manifest.experienceID)
  }
  var descriptors: [StudyExperienceDescriptor] {
    factoriesByExperienceID.values.map(\.descriptor).sorted { $0.title < $1.title }
  }
  var reportProviders: [any StudyExperienceReportProviding] {
    factoriesByExperienceID.values.compactMap(\.reportProvider)
  }
  static func standard() -> StudyExperienceRegistry {
    .init(factories: [VocabularyExperience(), TakkenExperience(), SafeFallbackExperience()])
  }
}
