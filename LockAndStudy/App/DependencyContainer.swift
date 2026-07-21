import Combine
import Foundation

@MainActor
final class LearningDataRevision: ObservableObject {
  @Published private(set) var value = 0
  func bump() { value &+= 1 }
}

@MainActor
final class DependencyContainer {
  let lockController: LockController
  let commerce: StoreKitCommerceService
  let content: ContentRepository
  let learning: LearningDataStore
  let learningRevision: LearningDataRevision
  let managementCode: ManagementCodeStore
  let emergencyStore: EmergencyUnlockStore
  let policyStore: LockPolicyStore

  init(learningRootURL: URL? = nil) {
    lockController = LockController()
    commerce = StoreKitCommerceService()
    content = ContentRepository()
    learningRevision = LearningDataRevision()
    if let learningRootURL {
      learning = LearningDataStore(rootURL: learningRootURL)
    } else {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestResetData") {
          let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LockAndStudy-UITests", isDirectory: true)
          try? FileManager.default.removeItem(at: root)
          learning = LearningDataStore(rootURL: root)
        } else {
          learning = LearningDataStore()
        }
      #else
      learning = LearningDataStore()
      #endif
    }
    managementCode = ManagementCodeStore()
    emergencyStore = EmergencyUnlockStore()
    policyStore = LockPolicyStore()
  }
}
