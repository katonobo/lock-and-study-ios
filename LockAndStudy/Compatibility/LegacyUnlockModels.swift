import Foundation
import SwiftUI

/// Codable models written by platform releases before v10.
/// They are decoded only for migration and source compatibility; new sessions never use them.
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
  let submit: @MainActor (
    UnlockQuestionSnapshot, Int, StudyFeedbackPlan
  ) async -> UnlockAnswerSubmissionResult
  let updateReviewExposure: @MainActor (
    StudyItemID, Bool
  ) async -> UnlockReviewExposureResult
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
