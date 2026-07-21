import Foundation
import ManagedSettings
import ManagedSettingsUI
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {
  override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { handle(action, completionHandler) }
  override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { handle(action, completionHandler) }
  override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { handle(action, completionHandler) }

  private func handle(_ action: ShieldAction, _ completion: @escaping (ShieldActionResponse) -> Void) {
    let defaults = LockAndStudySharedConstants.defaults
    let now = Date()
    switch action {
    case .primaryButtonPressed:
      if defaults.data(forKey: LockAndStudySharedConstants.Key.pendingUnlockRequest) == nil {
        let request = SharedPendingUnlockRequest(createdAt: now)
        defaults.set(try? SharedJSON.encoder().encode(request), forKey: LockAndStudySharedConstants.Key.pendingUnlockRequest)
      }
      defaults.set(now, forKey: LockAndStudySharedConstants.Key.lastShieldActionAt)
      defaults.set("primary_closed", forKey: LockAndStudySharedConstants.Key.lastShieldActionResult)
      scheduleNotificationIfAuthorized()
      completion(.close)
    case .secondaryButtonPressed:
      defaults.set(now, forKey: LockAndStudySharedConstants.Key.lastShieldActionAt)
      defaults.set("secondary_closed", forKey: LockAndStudySharedConstants.Key.lastShieldActionResult)
      completion(.close)
    default:
      completion(.none)
    }
  }

  private func scheduleNotificationIfAuthorized() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
      let content = UNMutableNotificationContent()
      content.title = "ロックンスタディ"
      content.body = "学習して、一時的に利用できます。"
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: LockAndStudySharedConstants.openStudyNotificationID,
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
      )
      center.add(request)
    }
  }
}
