import Foundation

enum AccessPacePreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case frequent5, balanced10, bundled20, extended30
  var id: String { rawValue }
  var title: String {
    switch self {
    case .frequent5: return "1問で5分"
    case .balanced10: return "1問で10分"
    case .bundled20: return "2問で20分"
    case .extended30: return "3問で30分"
    }
  }
  var requiredLearningUnits: Int {
    switch self { case .frequent5, .balanced10: return 1; case .bundled20: return 2; case .extended30: return 3 }
  }
  var unlockDurationMinutes: Int {
    switch self { case .frequent5: return 5; case .balanced10: return 10; case .bundled20: return 20; case .extended30: return 30 }
  }
  var unlockDuration: TimeInterval { TimeInterval(unlockDurationMinutes * 60) }
  var minutesPerUnit: Double { Double(unlockDurationMinutes) / Double(requiredLearningUnits) }
  var isRecommended: Bool { self == .balanced10 }
}

enum ReviewLoadPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case standard, reviewPlus, reviewIntensive
  var id: String { rawValue }
  var title: String {
    switch self { case .standard: return "標準"; case .reviewPlus: return "復習多め"; case .reviewIntensive: return "復習しっかり" }
  }
  var maxAdditionalDueReviews: Int {
    switch self { case .standard: return 0; case .reviewPlus: return 1; case .reviewIntensive: return 2 }
  }
}

enum LockLifecycleState: String, Codable, Sendable {
  case notConfigured, active, temporarilyUnlocked, authorizationLost, exitPending, ended
}

struct OnboardingLockActivationPlanner: Sendable {
  func shouldActivate(
    onboardingCompleted: Bool,
    isAuthorized: Bool,
    hasSelection: Bool,
    isLockEnabled: Bool,
    lifecycleState: LockLifecycleState
  ) -> Bool {
    guard onboardingCompleted, isAuthorized, hasSelection, !isLockEnabled else { return false }
    return lifecycleState == .notConfigured || lifecycleState == .active
  }
}

enum CommitmentPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
  case none, oneDay, sevenDays, thirtyDays
  var id: String { rawValue }
  var title: String {
    switch self { case .none: return "なし"; case .oneDay: return "24時間"; case .sevenDays: return "7日"; case .thirtyDays: return "30日" }
  }
  var duration: TimeInterval? {
    switch self { case .none: return nil; case .oneDay: return 86_400; case .sevenDays: return 604_800; case .thirtyDays: return 2_592_000 }
  }
}

struct LockSelectionTokenSnapshot: Codable, Equatable, Sendable {
  var applicationTokenDigests: Set<String>
  var categoryTokenDigests: Set<String>
  var webDomainTokenDigests: Set<String>
  static let empty = LockSelectionTokenSnapshot(applicationTokenDigests: [], categoryTokenDigests: [], webDomainTokenDigests: [])
  func removesAnyToken(comparedWith proposed: LockSelectionTokenSnapshot) -> Bool {
    !applicationTokenDigests.subtracting(proposed.applicationTokenDigests).isEmpty
      || !categoryTokenDigests.subtracting(proposed.categoryTokenDigests).isEmpty
      || !webDomainTokenDigests.subtracting(proposed.webDomainTokenDigests).isEmpty
  }
  func addsAnyToken(comparedWith old: LockSelectionTokenSnapshot) -> Bool {
    !applicationTokenDigests.subtracting(old.applicationTokenDigests).isEmpty
      || !categoryTokenDigests.subtracting(old.categoryTokenDigests).isEmpty
      || !webDomainTokenDigests.subtracting(old.webDomainTokenDigests).isEmpty
  }
}

struct LockSelectionSummary: Codable, Equatable, Sendable {
  var applicationCount: Int
  var categoryCount: Int
  var webDomainCount: Int
  var digest: String
  var tokenSnapshot: LockSelectionTokenSnapshot? = nil
  static let empty = LockSelectionSummary(applicationCount: 0, categoryCount: 0, webDomainCount: 0, digest: "empty", tokenSnapshot: .empty)
  var totalCount: Int { applicationCount + categoryCount + webDomainCount }
}

struct LockPolicy: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 2
  var schemaVersion = currentSchemaVersion
  var lifecycleState: LockLifecycleState
  var accessPacePreset: AccessPacePreset
  var reviewLoadPreset: ReviewLoadPreset
  var commitmentEndsAt: Date?
  var selectionSummary: LockSelectionSummary
  var protectedMinutesPerDay: Int
  var policyVersion: Int
  var updatedAt: Date

  static func initial(now: Date) -> LockPolicy {
    .init(lifecycleState: .notConfigured, accessPacePreset: .balanced10, reviewLoadPreset: .standard,
          commitmentEndsAt: nil, selectionSummary: .empty, protectedMinutesPerDay: 1_440,
          policyVersion: 1, updatedAt: now)
  }
}

enum PolicyChangeStrength: String, Codable, Sendable { case stronger, neutral, weaker }

struct PolicyChangeClassifier: Sendable {
  func classify(from old: LockPolicy, to new: LockPolicy) -> PolicyChangeStrength {
    var stronger = false
    var weaker = false
    if let oldTokens = old.selectionSummary.tokenSnapshot, let newTokens = new.selectionSummary.tokenSnapshot {
      if oldTokens.removesAnyToken(comparedWith: newTokens) { weaker = true }
      if newTokens.addsAnyToken(comparedWith: oldTokens) { stronger = true }
    } else {
      if new.selectionSummary.totalCount > old.selectionSummary.totalCount { stronger = true }
      if new.selectionSummary.totalCount < old.selectionSummary.totalCount { weaker = true }
    }
    if old.selectionSummary.totalCount > 0 && new.selectionSummary.totalCount == 0 { weaker = true }
    if new.selectionSummary.totalCount == old.selectionSummary.totalCount,
       new.selectionSummary.digest != old.selectionSummary.digest { weaker = true }
    if new.accessPacePreset.minutesPerUnit > old.accessPacePreset.minutesPerUnit ||
       new.accessPacePreset.unlockDurationMinutes > old.accessPacePreset.unlockDurationMinutes { weaker = true }
    if new.accessPacePreset.minutesPerUnit < old.accessPacePreset.minutesPerUnit ||
       new.accessPacePreset.unlockDurationMinutes < old.accessPacePreset.unlockDurationMinutes { stronger = true }
    if new.reviewLoadPreset.maxAdditionalDueReviews < old.reviewLoadPreset.maxAdditionalDueReviews { weaker = true }
    if new.reviewLoadPreset.maxAdditionalDueReviews > old.reviewLoadPreset.maxAdditionalDueReviews { stronger = true }
    if new.protectedMinutesPerDay < old.protectedMinutesPerDay { weaker = true }
    if new.protectedMinutesPerDay > old.protectedMinutesPerDay { stronger = true }
    switch (old.commitmentEndsAt, new.commitmentEndsAt) {
    case (let oldDate?, let newDate?):
      if newDate < oldDate { weaker = true }; if newDate > oldDate { stronger = true }
    case (.some, nil): weaker = true
    case (nil, .some): stronger = true
    default: break
    }
    if old.lifecycleState != .ended && new.lifecycleState == .ended { weaker = true }
    if weaker { return .weaker }
    return stronger ? .stronger : .neutral
  }
}

struct ProtectedChangeCooldownPolicy: Sendable {
  var cooldown: TimeInterval = 86_400
  func availableAt(requestedAt: Date, commitmentEndsAt: Date?) -> Date {
    max(requestedAt.addingTimeInterval(cooldown), commitmentEndsAt ?? .distantPast)
  }
}

enum UnlockSessionKind: String, Codable, Sendable { case earnedByStudy, emergency, managementCodeApproved }

struct UnlockSession: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: UnlockSessionKind
  let startedAt: Date
  let endsAt: Date
  let reasonCode: String?
  let policyVersion: Int
  func isActive(at date: Date) -> Bool { endsAt > date }
}

struct UnlockSessionCoordinator: Sendable {
  func make(kind: UnlockSessionKind, duration: TimeInterval, reasonCode: String?, policyVersion: Int, existing: UnlockSession?, now: Date) -> UnlockSession {
    if let existing, existing.isActive(at: now), kind == .earnedByStudy,
       reasonCode != nil, existing.reasonCode == reasonCode {
      return .init(id: existing.id, kind: kind, startedAt: existing.startedAt,
                   endsAt: existing.endsAt, reasonCode: reasonCode, policyVersion: policyVersion)
    }
    if let existing, existing.isActive(at: now), kind != .earnedByStudy {
      return .init(id: existing.id, kind: kind, startedAt: existing.startedAt,
                   endsAt: max(existing.endsAt, now.addingTimeInterval(duration)), reasonCode: reasonCode,
                   policyVersion: policyVersion)
    }
    return .init(id: UUID(), kind: kind, startedAt: now, endsAt: now.addingTimeInterval(max(0, duration)),
                 reasonCode: reasonCode, policyVersion: policyVersion)
  }
}

struct PendingPolicyChange: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let requestedAt: Date
  let availableAt: Date
  let originalPolicyVersion: Int
  let proposedPolicy: LockPolicy
  let pendingSelectionData: Data?
  var confirmedAt: Date?
}

struct PendingManagementCodeReset: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let requestedAt: Date
  let availableAt: Date
}
