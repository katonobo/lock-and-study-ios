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
  let unlockSessions: UnlockChallengeSessionCoordinator
  let pendingPreviews: PendingPreviewStore
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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-LockAndStudyUITestResetData")
          || arguments.contains("-LockAndStudyUITestPersistentLearningRoot")
        {
          let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LockAndStudy-UITests", isDirectory: true)
          if arguments.contains("-LockAndStudyUITestResetData") {
            try? FileManager.default.removeItem(at: root)
          }
          learning = LearningDataStore(rootURL: root)
        } else {
          learning = LearningDataStore()
        }
      #else
      learning = LearningDataStore()
      #endif
    }
    unlockSessions = UnlockChallengeSessionCoordinator(store: learning)
    pendingPreviews = PendingPreviewStore(
      rootURL: learningRootURL?.appendingPathComponent("PendingPreviews", isDirectory: true))
    managementCode = ManagementCodeStore()
    emergencyStore = EmergencyUnlockStore()
    policyStore = LockPolicyStore()
  }
}
