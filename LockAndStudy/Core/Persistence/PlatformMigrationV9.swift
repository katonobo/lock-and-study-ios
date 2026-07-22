import Foundation

struct PlatformMigrationV9: Sendable {
  func run(defaults: UserDefaults = LockAndStudySharedConstants.defaults) {
    guard !defaults.bool(forKey: LockAndStudySharedConstants.Key.platformMigrationV9Completed)
    else { return }

    let selected = defaults.string(forKey: LockAndStudySharedConstants.Key.selectedPackID)
      ?? "english3000.v1"
    if defaults.string(forKey: LockAndStudySharedConstants.Key.activeUnlockPackID) == nil {
      defaults.set(selected, forKey: LockAndStudySharedConstants.Key.activeUnlockPackID)
    }
    if defaults.string(forKey: LockAndStudySharedConstants.Key.openedPackID) == nil {
      defaults.set(selected, forKey: LockAndStudySharedConstants.Key.openedPackID)
    }
    if defaults.string(forKey: LockAndStudySharedConstants.Key.lastStudiedPackID) == nil {
      defaults.set(selected, forKey: LockAndStudySharedConstants.Key.lastStudiedPackID)
    }

    migrateFirstRun(
      packID: "english3000.v1", legacyExperience: "vocabulary", defaults: defaults)
    migrateFirstRun(
      packID: "takken2026.v1", legacyExperience: "takken", defaults: defaults)
    copyData(
      from: "lockandstudy.experience.vocabulary.settings.v1",
      to: "lockandstudy.pack.english3000.v1.vocabulary.settings.v2",
      defaults: defaults)
    copyData(
      from: "lockandstudy.experience.takken.settings.v1",
      to: "lockandstudy.pack.takken2026.v1.takken.settings.v2",
      defaults: defaults)

    defaults.set(true, forKey: LockAndStudySharedConstants.Key.platformMigrationV9Completed)
  }

  private func migrateFirstRun(
    packID: StudyPackID,
    legacyExperience: String,
    defaults: UserDefaults
  ) {
    let v2 = "lockandstudy.pack.\(packID.rawValue).first-run.completed.v2"
    guard !defaults.bool(forKey: v2) else { return }
    let v1 = "lockandstudy.pack.\(packID.rawValue).first-run.completed.v1"
    let legacy = "lockandstudy.experience.\(legacyExperience).first-run.completed"
    if defaults.bool(forKey: v1) || defaults.bool(forKey: legacy) {
      defaults.set(true, forKey: v2)
    }
  }

  private func copyData(from oldKey: String, to newKey: String, defaults: UserDefaults) {
    guard defaults.data(forKey: newKey) == nil, let data = defaults.data(forKey: oldKey) else {
      return
    }
    defaults.set(data, forKey: newKey)
  }
}
