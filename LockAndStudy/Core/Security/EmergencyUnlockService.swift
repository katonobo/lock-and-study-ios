import Foundation

enum EmergencyUnlockReason: String, Codable, CaseIterable, Identifiable, Sendable {
  case communication, travel, health, workOrSchool, other
  var id: String { rawValue }
  var title: String {
    switch self { case .communication: return "連絡が必要"; case .travel: return "移動・交通"; case .health: return "健康・安全"; case .workOrSchool: return "仕事・学校"; case .other: return "その他" }
  }
}

struct EmergencyUnlockRecord: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let usedAt: Date
  let reason: EmergencyUnlockReason
}

struct EmergencyUnlockPolicy: Sendable {
  let rollingWindow: TimeInterval = 86_400
  let activeWaitDuration: TimeInterval = 30
  let holdDuration: TimeInterval = 5
  let unlockDuration: TimeInterval = 900
  func canUse(lastUsedAt: Date?, now: Date) -> Bool { lastUsedAt.map { now.timeIntervalSince($0) >= rollingWindow } ?? true }
}

final class EmergencyUnlockStore: @unchecked Sendable {
  private let defaults: UserDefaults
  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults) { self.defaults = defaults }
  func records() -> [EmergencyUnlockRecord] {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.emergencyRecords) else { return [] }
    return (try? SharedJSON.decoder().decode([EmergencyUnlockRecord].self, from: data)) ?? []
  }
  func append(reason: EmergencyUnlockReason, at date: Date) {
    var values = records()
    values.append(.init(id: UUID(), usedAt: date, reason: reason))
    defaults.set(try? SharedJSON.encoder().encode(Array(values.suffix(50))), forKey: LockAndStudySharedConstants.Key.emergencyRecords)
  }
  func canUse(at date: Date, policy: EmergencyUnlockPolicy = .init()) -> Bool {
    policy.canUse(lastUsedAt: records().last?.usedAt, now: date)
  }
}

struct ActiveWaitCounter: Equatable, Sendable {
  let required: TimeInterval
  private(set) var accumulated: TimeInterval = 0
  mutating func addActiveTime(_ interval: TimeInterval) { accumulated = min(required, accumulated + max(0, interval)) }
  var isComplete: Bool { accumulated >= required }
  var remaining: TimeInterval { max(0, required - accumulated) }
}

