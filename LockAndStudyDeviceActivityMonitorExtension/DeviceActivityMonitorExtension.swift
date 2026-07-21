import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let relockName = DeviceActivityName(LockAndStudySharedConstants.relockActivityName)
  private let store = ManagedSettingsStore(named: .init(LockAndStudySharedConstants.managedSettingsStoreName))

  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    guard activity == relockName else { return }
    relockIfDue(source: "interval_start")
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    guard activity == relockName else { return }
    relockIfDue(source: "interval_end")
  }

  private func relockIfDue(source: String) {
    let defaults = LockAndStudySharedConstants.defaults
    guard defaults.bool(forKey: LockAndStudySharedConstants.Key.lockEnabled) else {
      record("\(source)_lock_disabled", defaults: defaults)
      return
    }
    let session = defaults.data(forKey: LockAndStudySharedConstants.Key.unlockSession)
      .flatMap { try? SharedJSON.decoder().decode(SharedUnlockSession.self, from: $0) }
    let recovery = RelockRecoveryExecutor().execute(now: Date(), endsAt: session?.endsAt) { endsAt in
      try scheduleRelock(at: endsAt)
    }
    let scheduleFailed: Bool
    switch recovery {
    case .rescheduled:
      record("\(source)_early_callback_rescheduled", defaults: defaults)
      return
    case .relockNow(let afterScheduleFailure):
      scheduleFailed = afterScheduleFailure
    }
    guard let selectionData = defaults.data(forKey: LockAndStudySharedConstants.Key.selectionData),
          let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
          !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty else {
      record("\(source)_selection_missing", defaults: defaults)
      return
    }
    store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens, except: [])
    store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    defaults.removeObject(forKey: LockAndStudySharedConstants.Key.unlockSession)
    defaults.removeObject(forKey: LockAndStudySharedConstants.Key.unlockUntil)
    record(scheduleFailed ? "\(source)_reschedule_failed_failsafe_applied" : "\(source)_applied", defaults: defaults)
    DeviceActivityCenter().stopMonitoring([relockName])
  }

  private func record(_ result: String, defaults: UserDefaults) {
    defaults.set(Date(), forKey: LockAndStudySharedConstants.Key.lastRelockAt)
    defaults.set(result, forKey: LockAndStudySharedConstants.Key.lastRelockResult)
  }

  private func scheduleRelock(at date: Date) throws {
    let center = DeviceActivityCenter()
    center.stopMonitoring([relockName])
    let calendar = Calendar.current
    var start = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
    var end = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date.addingTimeInterval(900))
    start.calendar = calendar; start.timeZone = .current; end.calendar = calendar; end.timeZone = .current
    try center.startMonitoring(relockName, during: .init(intervalStart: start, intervalEnd: end, repeats: false))
  }
}
