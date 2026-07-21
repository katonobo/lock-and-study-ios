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

  init(store: LockPolicyStore = .init(), managementCode: ManagementCodeStore = .init(), cooldown: ProtectedChangeCooldownPolicy = .init()) {
    self.store = store; self.managementCode = managementCode; self.cooldown = cooldown
  }

  func request(proposed: LockPolicy, selectionData: Data?, now: Date) -> ProtectedMutationResult {
    guard let current = store.loadPolicy() else {
      if selectionData == nil { store.savePolicy(proposed) }
      return .applied
    }
    guard PolicyChangeClassifier().classify(from: current, to: proposed) == .weaker else {
      if selectionData == nil { store.savePolicy(proposed) }
      return .applied
    }
    if managementCode.hasManagementCode { return .managementCodeRequired }
    let availableAt = cooldown.availableAt(requestedAt: now, commitmentEndsAt: current.commitmentEndsAt)
    store.savePendingChange(.init(id: UUID(), requestedAt: now, availableAt: availableAt,
                                  originalPolicyVersion: current.policyVersion, proposedPolicy: proposed,
                                  pendingSelectionData: selectionData, confirmedAt: nil))
    return .cooldownScheduled(availableAt)
  }

  func validatedPending(now: Date, secondConfirmation: Bool) -> PendingPolicyChange? {
    guard let pending = store.loadPendingChange(), now >= pending.availableAt else { return nil }
    guard secondConfirmation else { return nil }
    guard store.loadPolicy()?.policyVersion == pending.originalPolicyVersion else {
      store.savePendingChange(nil)
      return nil
    }
    return pending
  }

  func commitPending(_ pending: PendingPolicyChange) {
    store.savePolicy(pending.proposedPolicy)
    store.savePendingChange(nil)
  }
}
