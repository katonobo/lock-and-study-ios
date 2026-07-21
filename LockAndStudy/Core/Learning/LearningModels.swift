import Foundation

enum LearningEventKind: String, Codable, Sendable {
  case studyStarted, answerSubmitted, unlockChallengeStarted, unlockSuccess, emergencyUnlock, packPurchased, passStatusChanged, contentMigrated
}

struct LearningEvent: Codable, Identifiable, Equatable, Sendable {
  let schemaVersion: Int
  let id: UUID
  let kind: LearningEventKind
  let occurredAt: Date
  let packID: StudyPackID?
  let sessionID: UUID?
  let detailCode: String?
  init(id: UUID = UUID(), kind: LearningEventKind, occurredAt: Date = Date(), packID: StudyPackID? = nil, sessionID: UUID? = nil, detailCode: String? = nil) {
    schemaVersion = 1; self.id = id; self.kind = kind; self.occurredAt = occurredAt; self.packID = packID; self.sessionID = sessionID; self.detailCode = detailCode
  }
}

struct StudyAnswerRecord: Codable, Identifiable, Equatable, Sendable {
  let schemaVersion: Int
  let id: UUID
  let submissionID: String?
  let experienceID: StudyExperienceID?
  let packID: StudyPackID
  let moduleType: StudyModuleType
  let itemID: StudyItemID
  let prompt: String
  let choices: [StudyChoice]
  let selectedChoiceID: Int
  let correctChoiceID: Int
  let shortExplanation: String
  let longExplanation: String
  let sourceNote: String?
  let category: String
  let subcategory: String?
  let contentVersion: String
  let questionVersion: Int
  let examYear: Int?
  let lawBasisDate: String?
  let answeredAt: Date
  let mode: StudyMode
  let sessionID: UUID
  let isCorrect: Bool
  let feedbackPlan: StudyFeedbackPlan
  let difficulty: String?
  let questionFormat: String?
  let keyPoint: String?
  let tags: [String]?

  init(prompt item: StudyPrompt, selectedChoiceID: Int, answeredAt: Date, mode: StudyMode, sessionID: UUID, feedbackPlan: StudyFeedbackPlan) {
    schemaVersion = 2; id = UUID(); submissionID = nil; experienceID = .init(rawValue: item.moduleType.rawValue); packID = item.packID; moduleType = item.moduleType; itemID = item.itemID
    prompt = item.prompt; choices = item.choices; self.selectedChoiceID = selectedChoiceID; correctChoiceID = item.correctChoiceID
    shortExplanation = item.shortExplanation; longExplanation = item.longExplanation; sourceNote = item.sourceNote
    category = item.category; subcategory = item.subcategory; contentVersion = item.contentVersion; questionVersion = item.questionVersion
    examYear = item.examYear; lawBasisDate = item.lawBasisDate; self.answeredAt = answeredAt; self.mode = mode
    self.sessionID = sessionID; isCorrect = selectedChoiceID == item.correctChoiceID; self.feedbackPlan = feedbackPlan
    difficulty = nil; questionFormat = nil; keyPoint = nil; tags = nil
  }

  init(
    submissionID: String,
    experienceID: StudyExperienceID,
    packID: StudyPackID,
    moduleType: StudyModuleType,
    itemID: StudyItemID,
    prompt: String,
    choices: [StudyChoice],
    selectedChoiceID: Int,
    correctChoiceID: Int,
    shortExplanation: String,
    longExplanation: String,
    sourceNote: String?,
    category: String,
    subcategory: String?,
    contentVersion: String,
    questionVersion: Int,
    examYear: Int?,
    lawBasisDate: String?,
    answeredAt: Date,
    mode: StudyMode,
    sessionID: UUID,
    feedbackPlan: StudyFeedbackPlan,
    difficulty: String? = nil,
    questionFormat: String? = nil,
    keyPoint: String? = nil,
    tags: [String]? = nil
  ) {
    schemaVersion = 2
    id = UUID()
    self.submissionID = submissionID
    self.experienceID = experienceID
    self.packID = packID
    self.moduleType = moduleType
    self.itemID = itemID
    self.prompt = prompt
    self.choices = choices
    self.selectedChoiceID = selectedChoiceID
    self.correctChoiceID = correctChoiceID
    self.shortExplanation = shortExplanation
    self.longExplanation = longExplanation
    self.sourceNote = sourceNote
    self.category = category
    self.subcategory = subcategory
    self.contentVersion = contentVersion
    self.questionVersion = questionVersion
    self.examYear = examYear
    self.lawBasisDate = lawBasisDate
    self.answeredAt = answeredAt
    self.mode = mode
    self.sessionID = sessionID
    isCorrect = selectedChoiceID == correctChoiceID
    self.feedbackPlan = feedbackPlan
    self.difficulty = difficulty
    self.questionFormat = questionFormat
    self.keyPoint = keyPoint
    self.tags = tags
  }
}

struct ItemProgress: Codable, Equatable, Sendable {
  let id: CompositeStudyItemID
  var answerCount: Int
  var correctCount: Int
  var incorrectCount: Int
  var consecutiveCorrect: Int
  var lastAnsweredAt: Date?
  var dueAt: Date?
  var easeFactor: Double
  var intervalDays: Int
  static func initial(_ id: CompositeStudyItemID) -> ItemProgress {
    .init(id: id, answerCount: 0, correctCount: 0, incorrectCount: 0, consecutiveCorrect: 0, lastAnsweredAt: nil, dueAt: nil, easeFactor: 2, intervalDays: 0)
  }
}

struct SRSScheduler: Sendable {
  func applying(isCorrect: Bool, to old: ItemProgress, at date: Date) -> ItemProgress {
    var value = old; value.answerCount += 1; value.lastAnsweredAt = date
    if isCorrect {
      value.correctCount += 1; value.consecutiveCorrect += 1
      value.intervalDays = value.intervalDays == 0 ? 1 : max(1, Int(Double(value.intervalDays) * value.easeFactor))
      value.easeFactor = min(2.8, value.easeFactor + 0.05)
      value.dueAt = Calendar.current.date(byAdding: .day, value: value.intervalDays, to: date)
    } else {
      value.incorrectCount += 1; value.consecutiveCorrect = 0; value.intervalDays = 0
      value.easeFactor = max(1.3, value.easeFactor - 0.2); value.dueAt = date.addingTimeInterval(360)
    }
    return value
  }
}

struct UnlockBundleAccessSnapshot: Codable, Equatable, Sendable {
  let packID: StudyPackID
  let reason: ContentAccessReason
  let verifiedAt: Date?
}

struct UnlockLearningBundleSnapshot: Codable, Identifiable, Equatable, Sendable {
  static let expirationInterval: TimeInterval = 1_800
  let schemaVersion: Int
  let id: UUID
  let unlockRequestID: UUID
  let policyVersion: Int
  let pace: AccessPacePreset
  let reviewLoad: ReviewLoadPreset
  let prompts: [StudyPrompt]
  let access: UnlockBundleAccessSnapshot
  let createdAt: Date
  let expiresAt: Date
  var completedItemIDs: [StudyItemID]
  var createdUnlockSessionID: UUID?
  var abortReason: String?
  var isComplete: Bool { completedItemIDs.count >= prompts.count }
  func isRestorable(at date: Date) -> Bool { date < expiresAt && abortReason == nil && createdUnlockSessionID == nil }
}

struct UnlockBundlePlanner: Sendable {
  func make(requestID: UUID, policy: LockPolicy, manifest: StudyPackManifest, prompts: [StudyPrompt], entitlement: CommerceEntitlementSnapshot, progress: [String: ItemProgress], dueItemIDs: Set<StudyItemID>, now: Date) throws -> UnlockLearningBundleSnapshot {
    let accessService = ContentAccessService()
    let allowed = prompts.filter { accessService.decision(for: $0, manifest: manifest, entitlement: entitlement).isAllowed }
    let safePool = allowed.isEmpty ? prompts.filter(\.isFreeSample) : allowed
    guard !safePool.isEmpty else { throw ContentRepositoryError.invalid("無料の解除問題がありません") }
    let orderedPool = safePool.sorted {
      let lhs = progress[$0.id.storageKey]?.answerCount ?? 0
      let rhs = progress[$1.id.storageKey]?.answerCount ?? 0
      return lhs == rhs ? $0.itemID.rawValue < $1.itemID.rawValue : lhs < rhs
    }
    let due = orderedPool.filter { dueItemIDs.contains($0.itemID) }
    let additional = Array(due.prefix(policy.reviewLoadPreset.maxAdditionalDueReviews))
    let additionalIDs = Set(additional.map(\.itemID))
    let base = Array(orderedPool.filter { !additionalIDs.contains($0.itemID) }.prefix(policy.accessPacePreset.requiredLearningUnits))
    let selected = base + additional
    let reason = accessService.decision(for: selected[0], manifest: manifest, entitlement: entitlement).reason
    return .init(schemaVersion: 1, id: UUID(), unlockRequestID: requestID, policyVersion: policy.policyVersion,
                 pace: policy.accessPacePreset, reviewLoad: policy.reviewLoadPreset, prompts: selected,
                 access: .init(packID: manifest.id, reason: reason, verifiedAt: entitlement.lastVerifiedAt),
                 createdAt: now, expiresAt: now.addingTimeInterval(Self.expiration), completedItemIDs: [], createdUnlockSessionID: nil, abortReason: nil)
  }
  private static let expiration = UnlockLearningBundleSnapshot.expirationInterval
}

struct AnswerSubmissionGate: Sendable {
  private(set) var submittedItemIDs: Set<CompositeStudyItemID> = []
  mutating func claim(_ id: CompositeStudyItemID) -> Bool { submittedItemIDs.insert(id).inserted }
}
