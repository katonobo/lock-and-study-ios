import CryptoKit
import Foundation

final class LockPolicyStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let encoder = SharedJSON.encoder()
  private let decoder = SharedJSON.decoder()

  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults) { self.defaults = defaults }

  func loadPolicy() -> LockPolicy? {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.lockPolicy) else { return loadBackup() }
    if let value = try? decoder.decode(LockPolicy.self, from: data), value.schemaVersion == LockPolicy.currentSchemaVersion { return value }
    return loadBackup()
  }

  func savePolicy(_ policy: LockPolicy) {
    if let existing = defaults.data(forKey: LockAndStudySharedConstants.Key.lockPolicy) {
      defaults.set(existing, forKey: LockAndStudySharedConstants.Key.lockPolicyBackup)
    }
    defaults.set(try? encoder.encode(policy), forKey: LockAndStudySharedConstants.Key.lockPolicy)
    defaults.set(policy.lifecycleState == .active || policy.lifecycleState == .temporarilyUnlocked || policy.lifecycleState == .authorizationLost || policy.lifecycleState == .exitPending,
                 forKey: LockAndStudySharedConstants.Key.lockEnabled)
  }

  func loadUnlockSession() -> UnlockSession? { load(UnlockSession.self, key: LockAndStudySharedConstants.Key.unlockSession) }
  func saveUnlockSession(_ session: UnlockSession?) {
    save(session, key: LockAndStudySharedConstants.Key.unlockSession)
    if let session { defaults.set(session.endsAt, forKey: LockAndStudySharedConstants.Key.unlockUntil) }
    else { defaults.removeObject(forKey: LockAndStudySharedConstants.Key.unlockUntil) }
  }
  func loadPendingChange() -> PendingPolicyChange? { load(PendingPolicyChange.self, key: LockAndStudySharedConstants.Key.pendingPolicyChange) }
  func savePendingChange(_ value: PendingPolicyChange?) { save(value, key: LockAndStudySharedConstants.Key.pendingPolicyChange) }
  func loadPendingManagementReset() -> PendingManagementCodeReset? { load(PendingManagementCodeReset.self, key: LockAndStudySharedConstants.Key.pendingManagementReset) }
  func savePendingManagementReset(_ value: PendingManagementCodeReset?) { save(value, key: LockAndStudySharedConstants.Key.pendingManagementReset) }

  var authorizationLost: Bool {
    get { defaults.bool(forKey: LockAndStudySharedConstants.Key.authorizationLost) }
    set { defaults.set(newValue, forKey: LockAndStudySharedConstants.Key.authorizationLost) }
  }

  static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  private func loadBackup() -> LockPolicy? {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.lockPolicyBackup),
          let value = try? decoder.decode(LockPolicy.self, from: data),
          value.schemaVersion == LockPolicy.currentSchemaVersion else { return nil }
    return value
  }
  private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
    defaults.data(forKey: key).flatMap { try? decoder.decode(type, from: $0) }
  }
  private func save<T: Encodable>(_ value: T?, key: String) {
    guard let value else { defaults.removeObject(forKey: key); return }
    defaults.set(try? encoder.encode(value), forKey: key)
  }
}
