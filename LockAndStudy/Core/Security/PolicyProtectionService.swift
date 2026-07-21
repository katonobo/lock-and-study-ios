import Foundation

enum ProtectedMutationResult: Equatable {
  case applied
  case managementCodeRequired
  case cooldownScheduled(Date)
  case confirmationRequired
  case rejected
}

final class PolicyProtectionService {
  private let store: LockPolicyStore
  private let managementCode: ManagementCodeStore
  private let cooldown: ProtectedChangeCooldownPolicy
  private let defaults: UserDefaults

  init(store: LockPolicyStore = .init(), managementCode: ManagementCodeStore = .init(), cooldown: ProtectedChangeCooldownPolicy = .init(), defaults: UserDefaults = LockAndStudySharedConstants.defaults) {
    self.store = store; self.managementCode = managementCode; self.cooldown = cooldown; self.defaults = defaults
  }

  func request(proposed: LockPolicy, selectionData: Data?, now: Date) -> ProtectedMutationResult {
    guard let current = store.loadPolicy() else { store.savePolicy(proposed); return .applied }
    guard PolicyChangeClassifier().classify(from: current, to: proposed) == .weaker else {
      store.savePolicy(proposed); return .applied
    }
    if managementCode.hasManagementCode { return .managementCodeRequired }
    let availableAt = cooldown.availableAt(requestedAt: now, commitmentEndsAt: current.commitmentEndsAt)
    store.savePendingChange(.init(id: UUID(), requestedAt: now, availableAt: availableAt,
                                  originalPolicyVersion: current.policyVersion, proposedPolicy: proposed,
                                  pendingSelectionData: selectionData, confirmedAt: nil))
    return .cooldownScheduled(availableAt)
  }

  func approveWithManagementCode(_ code: String, proposed: LockPolicy) -> ProtectedMutationResult {
    guard (try? managementCode.verify(code)) == true else { return .rejected }
    store.savePolicy(proposed); store.savePendingChange(nil); return .applied
  }

  func confirmPending(now: Date, secondConfirmation: Bool) -> ProtectedMutationResult {
    guard let pending = store.loadPendingChange(), now >= pending.availableAt else { return .rejected }
    guard secondConfirmation else { return .confirmationRequired }
    guard store.loadPolicy()?.policyVersion == pending.originalPolicyVersion else { store.savePendingChange(nil); return .rejected }
    if let data = pending.pendingSelectionData {
      defaults.set(data, forKey: LockAndStudySharedConstants.Key.selectionData)
      defaults.set(true, forKey: LockAndStudySharedConstants.Key.selectionCompleted)
    }
    store.savePolicy(pending.proposedPolicy); store.savePendingChange(nil); return .applied
  }
}
