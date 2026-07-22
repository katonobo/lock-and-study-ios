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

struct UnlockRuntimeCompletionContext {
  let envelope: UnlockChallengeSessionEnvelope
  let manifest: StudyPackManifest
  let dependencies: DependencyContainer
  let now: Date
}

enum UnlockAnswerSubmissionResult: Equatable, Sendable {
  case recordedCorrect
  case recordedIncorrect(remainingActiveSeconds: Int, attemptNumber: Int)
  case expired
  case failed(String)
}

enum UnlockReviewExposureResult: Equatable, Sendable {
  case updated(remainingActiveSeconds: Int)
  case expired
  case failed(String)
}

struct ExperienceSessionState: Equatable, Sendable {
  let completedUnitCount: Int
  let totalUnitCount: Int
  let reviewRemainingSeconds: TimeInterval

  var isComplete: Bool {
    totalUnitCount > 0 && completedUnitCount >= totalUnitCount
  }
}

struct ExperienceSessionTransition: Sendable {
  let payload: ExperienceSessionPayload
  let submissionResult: UnlockAnswerSubmissionResult?
  let reviewResult: UnlockReviewExposureResult?
}

@MainActor
struct ExperienceChallengeViewContext {
  let manifest: StudyPackManifest
  let submit: @MainActor (StudyAnswerValue) async -> UnlockAnswerSubmissionResult
  let updateReviewExposure: @MainActor (Bool) async -> UnlockReviewExposureResult
  let restart: @MainActor () async -> Void
  let complete: @MainActor () async -> Void
}

@MainActor
protocol StudyExperienceSessionRuntime: Sendable {
  var experienceID: StudyExperienceID { get }
  var supportedPayloadSchemaIDs: Set<String> { get }
  func createSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload
  func makeChallengeView(
    envelope: UnlockChallengeSessionEnvelope,
    context: ExperienceChallengeViewContext
  ) -> AnyView
  func restoreState(payload: Data, schemaID: String) throws -> ExperienceSessionState
  func acceptAnswer(
    _ answer: StudyAnswerValue,
    envelope: UnlockChallengeSessionEnvelope,
    dependencies: DependencyContainer
  ) async throws -> ExperienceSessionTransition
  func activeReviewTick(
    seconds: TimeInterval,
    envelope: UnlockChallengeSessionEnvelope
  ) async throws -> ExperienceSessionTransition
  func completionProof(
    envelope: UnlockChallengeSessionEnvelope
  ) throws -> ExperienceCompletionProof?
  func handleUnlockCompletion(_ context: UnlockRuntimeCompletionContext) async throws
  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async
}

extension StudyExperienceSessionRuntime {
  func handleUnlockCompletion(_ context: UnlockRuntimeCompletionContext) async throws {}
  func clearTransientState(packID: StudyPackID, dependencies: DependencyContainer) async {}
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
protocol StudyExperienceFactory: StudyExperienceSessionRuntime {
  var descriptor: StudyExperienceDescriptor { get }
  var supportedContentSchemas: Set<ContentSchemaID> { get }
  var reportProvider: (any StudyExperienceReportProviding)? { get }
  func validateCompatibility(with manifest: StudyPackManifest) -> [String]
  func makeRootView(context: StudyExperienceContext) -> AnyView
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView?
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary
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
