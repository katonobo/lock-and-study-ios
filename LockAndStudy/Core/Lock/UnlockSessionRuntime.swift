import Foundation

enum UnlockCompletionState: String, Codable, Equatable, Sendable {
  case answering, proofAccepted, sessionCreated, eventRecorded, completed, aborted
}

struct ExperienceSessionPayload: Equatable, Sendable {
  let schemaID: String
  let data: Data
}

enum StudyAnswerValue: Codable, Equatable, Sendable {
  case choice(questionID: String, choiceID: String)
  case choiceID(String)
  case multipleChoiceIDs([String])
  case text(String)
  case decimal(String)
  case completion
}

struct ExperienceCompletionProof: Codable, Equatable, Sendable {
  let sessionID: UUID
  let packID: StudyPackID
  let completedAt: Date
  let evidenceVersion: Int
  var unlockDuration: TimeInterval? = nil
}

struct UnlockChallengeSessionEnvelope: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1
  static let expirationInterval: TimeInterval = 1_800

  let schemaVersion: Int
  let id: UUID
  let requestID: UUID
  let origin: UnlockChallengeOrigin
  let experienceID: StudyExperienceID
  let packID: StudyPackID
  let contentVersion: String
  let policyVersion: Int
  let createdAt: Date
  let expiresAt: Date

  var completionState: UnlockCompletionState
  var completionEventID: UUID
  var createdUnlockSessionID: UUID?
  var abortReason: String?

  let enginePayloadSchemaID: String
  var enginePayload: Data

  func isRecoverable(at date: Date) -> Bool {
    date < expiresAt && abortReason == nil
      && completionState != .completed && completionState != .aborted
  }

}

enum UnlockCompletionProofDecision: Equatable, Sendable {
  case accepted
  case resuming
  case alreadyCompleted
  case rejected(String)
}

actor UnlockChallengeSessionCoordinator {
  private let store: LearningDataStore

  init(store: LearningDataStore) { self.store = store }

  func restore(at date: Date) async throws -> UnlockChallengeSessionEnvelope? {
    guard var envelope = try await store.loadUnlockSessionEnvelope() else { return nil }
    guard envelope.schemaVersion <= UnlockChallengeSessionEnvelope.currentSchemaVersion else {
      envelope.abortReason = "unsupported-envelope-schema"
      envelope.completionState = .aborted
      try await store.saveUnlockSessionEnvelope(envelope)
      return nil
    }
    guard envelope.expiresAt > date else {
      if envelope.completionState != .completed && envelope.completionState != .aborted {
        envelope.abortReason = "challenge-expired-during-recovery"
        envelope.completionState = .aborted
        try await store.saveUnlockSessionEnvelope(envelope)
      }
      return nil
    }
    guard envelope.abortReason == nil, envelope.completionState != .aborted else { return nil }
    return envelope
  }

  func acceptCompletionProof(
    _ proof: ExperienceCompletionProof,
    now: Date
  ) async throws -> UnlockCompletionProofDecision {
    guard var envelope = try await store.loadUnlockSessionEnvelope() else {
      return .rejected("unlock-session-missing")
    }
    guard envelope.id == proof.sessionID, envelope.packID == proof.packID else {
      return .rejected("completion-proof-mismatch")
    }
    guard proof.evidenceVersion == 1 else {
      return .rejected("completion-proof-version")
    }
    guard proof.completedAt <= envelope.expiresAt, now < envelope.expiresAt else {
      envelope.abortReason = "completion-proof-expired"
      envelope.completionState = .aborted
      try await store.saveUnlockSessionEnvelope(envelope)
      return .rejected("completion-proof-expired")
    }
    switch envelope.completionState {
    case .answering:
      envelope.completionState = .proofAccepted
      try await store.saveUnlockSessionEnvelope(envelope)
      return .accepted
    case .proofAccepted, .sessionCreated, .eventRecorded:
      return .resuming
    case .completed:
      return .alreadyCompleted
    case .aborted:
      return .rejected(envelope.abortReason ?? "unlock-session-aborted")
    }
  }

  func abort(reason: String) async throws {
    guard var envelope = try await store.loadUnlockSessionEnvelope() else { return }
    envelope.abortReason = reason
    envelope.completionState = .aborted
    try await store.saveUnlockSessionEnvelope(envelope)
  }
}
