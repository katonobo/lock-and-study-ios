import Foundation

enum LockAndStudySharedConstants {
  static let appGroupID = "group.com.ameneko.lockandstudy"
  static let migrationAppGroupID = "group.com.ameneko.lockandstudy.migration"
  static let managedSettingsStoreName = "lockandstudy.main"
  static let relockActivityName = "lockandstudy.relock"
  static let openStudyNotificationID = "lockandstudy.open.study"

  enum Key {
    static let onboardingCompleted = "lockandstudy.onboarding.completed"
    static let authorizationApproved = "lockandstudy.authorization.approved"
    static let authorizationLost = "lockandstudy.authorization.lost"
    static let selectionData = "lockandstudy.selection.data"
    static let selectionCompleted = "lockandstudy.selection.completed"
    static let lockPolicy = "lockandstudy.policy.v1"
    static let lockPolicyBackup = "lockandstudy.policy.v1.backup"
    static let lockEnabled = "lockandstudy.lock.enabled"
    static let unlockSession = "lockandstudy.unlock.session.v1"
    static let unlockUntil = "lockandstudy.unlock.until"
    static let pendingUnlockRequest = "lockandstudy.pending.unlock.request.v1"
    static let pendingPolicyChange = "lockandstudy.pending.policy.change.v1"
    static let pendingManagementReset = "lockandstudy.pending.management.reset.v1"
    static let emergencyRecords = "lockandstudy.emergency.records.v1"
    static let lastShieldActionAt = "lockandstudy.diagnostics.shield.at"
    static let lastShieldActionResult = "lockandstudy.diagnostics.shield.result"
    static let lastRelockAt = "lockandstudy.diagnostics.relock.at"
    static let lastRelockResult = "lockandstudy.diagnostics.relock.result"
    static let entitlementCache = "lockandstudy.commerce.snapshot.v1"
    static let knownProductMappings = "lockandstudy.commerce.product-mappings.v1"
    static let selectedPackID = "lockandstudy.content.selected.pack"
    static let settings = "lockandstudy.settings.v1"
  }

  static var defaults: UserDefaults {
    UserDefaults(suiteName: appGroupID) ?? .standard
  }
}

struct SharedPendingUnlockRequest: Codable, Equatable, Identifiable {
  let schemaVersion: Int
  let id: UUID
  let createdAt: Date
  var lastPresentedAt: Date?

  init(id: UUID = UUID(), createdAt: Date = Date(), lastPresentedAt: Date? = nil) {
    schemaVersion = 1
    self.id = id
    self.createdAt = createdAt
    self.lastPresentedAt = lastPresentedAt
  }
}

struct SharedUnlockSession: Codable, Equatable {
  let id: UUID
  let endsAt: Date
}

enum RelockCallbackAction: Equatable {
  case relockNow
  case reschedule(Date)
}

enum RelockCallbackOutcome: Equatable {
  case rescheduled(Date)
  case relockNow(afterScheduleFailure: Bool)
}

struct RelockRecoveryPlanner {
  var clockTolerance: TimeInterval = 3
  func action(now: Date, endsAt: Date?) -> RelockCallbackAction {
    guard let endsAt else { return .relockNow }
    return endsAt.timeIntervalSince(now) > clockTolerance ? .reschedule(endsAt) : .relockNow
  }
}

struct RelockRecoveryExecutor {
  var planner = RelockRecoveryPlanner()

  func execute(now: Date, endsAt: Date?, schedule: (Date) throws -> Void) -> RelockCallbackOutcome {
    switch planner.action(now: now, endsAt: endsAt) {
    case .relockNow:
      return .relockNow(afterScheduleFailure: false)
    case .reschedule(let endsAt):
      do {
        try schedule(endsAt)
        return .rescheduled(endsAt)
      } catch {
        return .relockNow(afterScheduleFailure: true)
      }
    }
  }
}

enum SharedJSON {
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
