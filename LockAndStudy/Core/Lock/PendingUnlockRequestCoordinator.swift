import Foundation

struct PendingUnlockRequestCoordinator {
  let defaults: UserDefaults
  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults) { self.defaults = defaults }

  func consumeIfEligible(isLockEnabled: Bool, isAuthorized: Bool, hasSelection: Bool, unlockUntil: Date?, now: Date) -> SharedPendingUnlockRequest? {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.pendingUnlockRequest),
          let request = try? SharedJSON.decoder().decode(SharedPendingUnlockRequest.self, from: data) else { return nil }
    if now.timeIntervalSince(request.createdAt) > 7_200 || !isLockEnabled {
      defaults.removeObject(forKey: LockAndStudySharedConstants.Key.pendingUnlockRequest)
      return nil
    }
    guard isAuthorized, hasSelection, unlockUntil.map({ $0 <= now }) ?? true else { return nil }
    defaults.removeObject(forKey: LockAndStudySharedConstants.Key.pendingUnlockRequest)
    return request
  }
}

