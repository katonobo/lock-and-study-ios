import Foundation
import UserNotifications

struct NotificationService: Sendable {
  func requestAuthorization() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
  }

  func scheduleUnlockEnd(session: UnlockSession) async {
    let content = UNMutableNotificationContent()
    content.title = "再ロックしました"
    content.body = "次に利用するときは、また短い学習から始められます。"
    content.sound = .default
    let interval = max(1, session.endsAt.timeIntervalSinceNow)
    let request = UNNotificationRequest(identifier: "lockandstudy.unlock.end.\(session.id.uuidString)", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    try? await UNUserNotificationCenter.current().add(request)
  }

  func cancel(sessionID: UUID) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lockandstudy.unlock.end.\(sessionID.uuidString)"])
  }
}

