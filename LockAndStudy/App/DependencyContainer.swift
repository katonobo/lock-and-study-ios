import Foundation

@MainActor
final class DependencyContainer {
  let lockController: LockController
  let commerce: StoreKitCommerceService
  let content: ContentRepository
  let learning: LearningDataStore
  let managementCode: ManagementCodeStore
  let emergencyStore: EmergencyUnlockStore
  let policyStore: LockPolicyStore

  init() {
    lockController = LockController()
    commerce = StoreKitCommerceService()
    content = ContentRepository()
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestResetData") {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("LockAndStudy-UITests", isDirectory: true)
      try? FileManager.default.removeItem(at: root)
      learning = LearningDataStore(rootURL: root)
    } else {
      learning = LearningDataStore()
    }
    #else
    learning = LearningDataStore()
    #endif
    managementCode = ManagementCodeStore()
    emergencyStore = EmergencyUnlockStore()
    policyStore = LockPolicyStore()
  }
}
