import Foundation
import SwiftUI

struct StudyExperienceID: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  static let vocabulary = StudyExperienceID(rawValue: "vocabulary")
  static let takken = StudyExperienceID(rawValue: "takken")
  static let safeFallback = StudyExperienceID(rawValue: "safe-fallback")
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
  case answering, sessionCreated, eventRecorded, completed, aborted
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

@MainActor
protocol StudyExperienceFactory {
  var descriptor: StudyExperienceDescriptor { get }
  var unlockChallengeProvider: any UnlockChallengeProviding { get }
  var reportProvider: (any StudyExperienceReportProviding)? { get }
  func makeRootView(context: StudyExperienceContext) -> AnyView
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView?
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary
  func makeUnlockChallengeView(
    snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext
  ) -> AnyView
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws
}

extension StudyExperienceFactory {
  var reportProvider: (any StudyExperienceReportProviding)? { nil }
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {}
}

@MainActor
struct StudyExperienceRegistry {
  private let factories: [StudyExperienceID: any StudyExperienceFactory]
  private let factoriesByType: [StudyExperienceType: any StudyExperienceFactory]

  init(factories: [any StudyExperienceFactory]) {
    self.factories = Dictionary(uniqueKeysWithValues: factories.map { ($0.descriptor.id, $0) })
    factoriesByType = Dictionary(uniqueKeysWithValues: factories.flatMap { factory in
      factory.descriptor.supportedExperienceTypes.map { ($0, factory) }
    })
  }

  func factory(for id: StudyExperienceID) -> (any StudyExperienceFactory)? { factories[id] }
  func factory(for type: StudyExperienceType) -> (any StudyExperienceFactory)? {
    factoriesByType[type]
  }
  func factory(for manifest: StudyPackManifest) -> (any StudyExperienceFactory)? {
    factory(for: manifest.experienceType)
  }
  var descriptors: [StudyExperienceDescriptor] {
    factories.values.map(\.descriptor).sorted { $0.title < $1.title }
  }
  var reportProviders: [any StudyExperienceReportProviding] {
    factories.values.compactMap(\.reportProvider)
  }
  static func standard() -> StudyExperienceRegistry {
    .init(factories: [VocabularyExperience(), TakkenExperience(), SafeFallbackExperience()])
  }
}
