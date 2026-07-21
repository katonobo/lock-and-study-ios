import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum LockControllerError: LocalizedError, Equatable {
  case authorizationRequired, selectionRequired, scheduleFailed, unavailable
  var errorDescription: String? {
    switch self {
    case .authorizationRequired: return "Screen Timeの許可が必要です。"
    case .selectionRequired: return "ロックするアプリ、カテゴリ、またはWebサイトを選んでください。"
    case .scheduleFailed: return "安全な再ロックを予約できなかったため、今回は解除しませんでした。"
    case .unavailable: return "この環境ではScreen Time制御を利用できません。"
    }
  }
}

@MainActor
protocol LockControlling: AnyObject {
  var isAuthorized: Bool { get }
  var authorizationLost: Bool { get }
  var hasSelection: Bool { get }
  var isLockEnabled: Bool { get }
  var unlockUntil: Date? { get }
  var lastErrorMessage: String? { get }
  var isMockMode: Bool { get }
  func requestAuthorization() async throws
  func loadSelection() -> FamilyActivitySelection?
  func saveSelection(_ selection: FamilyActivitySelection) throws
  func markMockSelectionCompleted()
  func setLockEnabled(_ enabled: Bool) async throws
  func beginUnlockSession(kind: UnlockSessionKind, duration: TimeInterval, reasonCode: String?) async throws -> UnlockSession
  func refreshLockState() async
}

@MainActor
final class LockController: ObservableObject, LockControlling {
  @Published private(set) var revision = 0
  private let backend: any LockControlling
  var isAuthorized: Bool { backend.isAuthorized }
  var authorizationLost: Bool { backend.authorizationLost }
  var hasSelection: Bool { backend.hasSelection }
  var isLockEnabled: Bool { backend.isLockEnabled }
  var unlockUntil: Date? { backend.unlockUntil }
  var lastErrorMessage: String? { backend.lastErrorMessage }
  var isMockMode: Bool { backend.isMockMode }

  init(backend: (any LockControlling)? = nil) {
    if let backend { self.backend = backend }
    else {
      #if targetEnvironment(simulator)
      self.backend = MockLockController()
      #else
      self.backend = ProcessInfo.processInfo.arguments.contains("-LockAndStudyUseMock") ? MockLockController() : RealScreenTimeLockController()
      #endif
    }
  }
  func requestAuthorization() async throws { try await backend.requestAuthorization(); revision += 1 }
  func loadSelection() -> FamilyActivitySelection? { backend.loadSelection() }
  func saveSelection(_ selection: FamilyActivitySelection) throws { try backend.saveSelection(selection); revision += 1 }
  func markMockSelectionCompleted() { backend.markMockSelectionCompleted(); revision += 1 }
  func setLockEnabled(_ enabled: Bool) async throws { try await backend.setLockEnabled(enabled); revision += 1 }
  func beginUnlockSession(kind: UnlockSessionKind, duration: TimeInterval, reasonCode: String?) async throws -> UnlockSession {
    let result = try await backend.beginUnlockSession(kind: kind, duration: duration, reasonCode: reasonCode)
    revision += 1
    return result
  }
  func refreshLockState() async { await backend.refreshLockState(); revision += 1 }
}

extension FamilyActivitySelection {
  var lockAndStudyIsEmpty: Bool { applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty }
  func lockAndStudySummary(encoded: Data) -> LockSelectionSummary {
    .init(applicationCount: applicationTokens.count, categoryCount: categoryTokens.count,
          webDomainCount: webDomainTokens.count, digest: LockPolicyStore.digest(encoded))
  }
}

@MainActor
final class MockLockController: LockControlling {
  private let defaults: UserDefaults
  private let dateProvider: any DateProviding
  private let policyStore: LockPolicyStore
  private(set) var lastErrorMessage: String?
  var isMockMode: Bool { true }
  var isAuthorized: Bool { defaults.bool(forKey: LockAndStudySharedConstants.Key.authorizationApproved) }
  var authorizationLost: Bool { policyStore.authorizationLost }
  var hasSelection: Bool { defaults.bool(forKey: LockAndStudySharedConstants.Key.selectionCompleted) }
  var isLockEnabled: Bool { defaults.bool(forKey: LockAndStudySharedConstants.Key.lockEnabled) }
  var unlockUntil: Date? { policyStore.loadUnlockSession()?.endsAt }

  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults, dateProvider: any DateProviding = SystemDateProvider()) {
    self.defaults = defaults; self.dateProvider = dateProvider; policyStore = .init(defaults: defaults)
  }
  func requestAuthorization() async throws {
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.authorizationApproved)
    policyStore.authorizationLost = false
  }
  func loadSelection() -> FamilyActivitySelection? {
    defaults.data(forKey: LockAndStudySharedConstants.Key.selectionData).flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
  }
  func saveSelection(_ selection: FamilyActivitySelection) throws {
    guard !selection.lockAndStudyIsEmpty else { throw LockControllerError.selectionRequired }
    let data = try JSONEncoder().encode(selection)
    defaults.set(data, forKey: LockAndStudySharedConstants.Key.selectionData)
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.selectionCompleted)
    updatePolicy { $0.selectionSummary = selection.lockAndStudySummary(encoded: data) }
  }
  func markMockSelectionCompleted() { defaults.set(true, forKey: LockAndStudySharedConstants.Key.selectionCompleted) }
  func setLockEnabled(_ enabled: Bool) async throws {
    if enabled && !isAuthorized { throw LockControllerError.authorizationRequired }
    if enabled && !hasSelection { throw LockControllerError.selectionRequired }
    updatePolicy { $0.lifecycleState = enabled ? .active : .ended; $0.policyVersion += 1 }
    defaults.set(enabled, forKey: LockAndStudySharedConstants.Key.lockEnabled)
    if !enabled { policyStore.saveUnlockSession(nil) }
  }
  func beginUnlockSession(kind: UnlockSessionKind, duration: TimeInterval, reasonCode: String?) async throws -> UnlockSession {
    guard isLockEnabled else { throw LockControllerError.selectionRequired }
    let now = dateProvider.now()
    let policy = policyStore.loadPolicy() ?? .initial(now: now)
    let session = UnlockSessionCoordinator().make(kind: kind, duration: duration, reasonCode: reasonCode,
                                                   policyVersion: policy.policyVersion, existing: policyStore.loadUnlockSession(), now: now)
    policyStore.saveUnlockSession(session)
    updatePolicy { $0.lifecycleState = .temporarilyUnlocked }
    return session
  }
  func refreshLockState() async {
    if let session = policyStore.loadUnlockSession(), !session.isActive(at: dateProvider.now()) {
      policyStore.saveUnlockSession(nil)
      updatePolicy { $0.lifecycleState = .active }
    }
  }
  private func updatePolicy(_ mutation: (inout LockPolicy) -> Void) {
    var policy = policyStore.loadPolicy() ?? .initial(now: dateProvider.now())
    mutation(&policy); policy.updatedAt = dateProvider.now(); policyStore.savePolicy(policy)
  }
}

@MainActor
final class RealScreenTimeLockController: LockControlling {
  private let defaults: UserDefaults
  private let dateProvider: any DateProviding
  private let policyStore: LockPolicyStore
  private let managedStore = ManagedSettingsStore(named: .init(LockAndStudySharedConstants.managedSettingsStoreName))
  private let activityCenter = DeviceActivityCenter()
  private(set) var lastErrorMessage: String?
  var isMockMode: Bool { false }
  var isAuthorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }
  var authorizationLost: Bool { policyStore.authorizationLost }
  var hasSelection: Bool { !(loadSelection()?.lockAndStudyIsEmpty ?? true) }
  var isLockEnabled: Bool { defaults.bool(forKey: LockAndStudySharedConstants.Key.lockEnabled) }
  var unlockUntil: Date? { policyStore.loadUnlockSession()?.endsAt }

  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults, dateProvider: any DateProviding = SystemDateProvider()) {
    self.defaults = defaults; self.dateProvider = dateProvider; policyStore = .init(defaults: defaults)
  }
  func requestAuthorization() async throws {
    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    guard isAuthorized else { throw LockControllerError.authorizationRequired }
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.authorizationApproved)
    policyStore.authorizationLost = false
  }
  func loadSelection() -> FamilyActivitySelection? {
    defaults.data(forKey: LockAndStudySharedConstants.Key.selectionData).flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
  }
  func saveSelection(_ selection: FamilyActivitySelection) throws {
    guard !selection.lockAndStudyIsEmpty else { throw LockControllerError.selectionRequired }
    let data = try JSONEncoder().encode(selection)
    defaults.set(data, forKey: LockAndStudySharedConstants.Key.selectionData)
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.selectionCompleted)
    updatePolicy { $0.selectionSummary = selection.lockAndStudySummary(encoded: data) }
  }
  func markMockSelectionCompleted() {}
  func setLockEnabled(_ enabled: Bool) async throws {
    if enabled {
      try applyShield()
      defaults.set(true, forKey: LockAndStudySharedConstants.Key.lockEnabled)
      updatePolicy { $0.lifecycleState = .active; $0.policyVersion += 1 }
    } else {
      clearShield(); defaults.set(false, forKey: LockAndStudySharedConstants.Key.lockEnabled)
      if let session = policyStore.loadUnlockSession() { NotificationService().cancel(sessionID: session.id) }
      policyStore.saveUnlockSession(nil)
      activityCenter.stopMonitoring([.init(LockAndStudySharedConstants.relockActivityName)])
      updatePolicy { $0.lifecycleState = .ended; $0.policyVersion += 1 }
    }
  }
  func beginUnlockSession(kind: UnlockSessionKind, duration: TimeInterval, reasonCode: String?) async throws -> UnlockSession {
    guard isLockEnabled else { throw LockControllerError.selectionRequired }
    let now = dateProvider.now()
    let policy = policyStore.loadPolicy() ?? .initial(now: now)
    let session = UnlockSessionCoordinator().make(kind: kind, duration: duration, reasonCode: reasonCode,
                                                   policyVersion: policy.policyVersion, existing: policyStore.loadUnlockSession(), now: now)
    do { try scheduleRelock(at: session.endsAt) }
    catch { lastErrorMessage = LockControllerError.scheduleFailed.localizedDescription; throw LockControllerError.scheduleFailed }
    policyStore.saveUnlockSession(session)
    clearShield()
    updatePolicy { $0.lifecycleState = .temporarilyUnlocked }
    await NotificationService().scheduleUnlockEnd(session: session)
    return session
  }
  func refreshLockState() async {
    defaults.set(isAuthorized, forKey: LockAndStudySharedConstants.Key.authorizationApproved)
    guard isLockEnabled else { return }
    guard isAuthorized else {
      policyStore.authorizationLost = true
      updatePolicy { $0.lifecycleState = .authorizationLost }
      return
    }
    policyStore.authorizationLost = false
    if let session = policyStore.loadUnlockSession(), session.isActive(at: dateProvider.now()) { clearShield(); return }
    policyStore.saveUnlockSession(nil)
    do { try applyShield(); lastErrorMessage = nil; updatePolicy { $0.lifecycleState = .active } }
    catch { lastErrorMessage = error.localizedDescription }
  }
  private func applyShield() throws {
    guard isAuthorized else { throw LockControllerError.authorizationRequired }
    guard let selection = loadSelection(), !selection.lockAndStudyIsEmpty else { throw LockControllerError.selectionRequired }
    managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    managedStore.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens, except: [])
    managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
  }
  private func clearShield() {
    managedStore.shield.applications = nil; managedStore.shield.applicationCategories = nil; managedStore.shield.webDomains = nil
  }
  private func scheduleRelock(at date: Date) throws {
    let name = DeviceActivityName(LockAndStudySharedConstants.relockActivityName)
    activityCenter.stopMonitoring([name])
    let calendar = Calendar.current
    var start = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
    var end = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date.addingTimeInterval(900))
    start.calendar = calendar; start.timeZone = .current; end.calendar = calendar; end.timeZone = .current
    try activityCenter.startMonitoring(name, during: .init(intervalStart: start, intervalEnd: end, repeats: false))
  }
  private func updatePolicy(_ mutation: (inout LockPolicy) -> Void) {
    var policy = policyStore.loadPolicy() ?? .initial(now: dateProvider.now())
    mutation(&policy); policy.updatedAt = dateProvider.now(); policyStore.savePolicy(policy)
  }
}

