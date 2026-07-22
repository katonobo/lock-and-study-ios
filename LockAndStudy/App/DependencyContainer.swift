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
  let contentPackages: any ContentPackageStoring
  let learning: LearningDataStore
  let unlockSessions: UnlockChallengeSessionCoordinator
  let pendingPreviews: PendingPreviewStore
  let learningRevision: LearningDataRevision
  let managementCode: ManagementCodeStore
  let emergencyStore: EmergencyUnlockStore
  let policyStore: LockPolicyStore

  init(
    learningRootURL: URL? = nil,
    contentSource: (any ContentAssetSource)? = nil,
    catalogDataOverride: Data? = nil
  ) {
    lockController = LockController()
    commerce = StoreKitCommerceService()
    let bundled = BundledContentSource()
    let catalogSource: any ContentAssetSource = catalogDataOverride.map {
      CatalogDataOverrideSource(data: $0, packageSource: bundled)
    } ?? bundled
    let packageRoot = learningRootURL?.appendingPathComponent(
      "InstalledContent", isDirectory: true)
    let packageStore = ContentPackageStore(rootURL: packageRoot)
    contentPackages = packageStore
    let productionSource: any ContentAssetSource
    if let contentSource {
      productionSource = CompositeContentSource([
        contentSource,
        catalogSource,
        SafeFallbackContentSource(),
      ])
    } else {
      productionSource = CompositeContentSource([
        InstalledContentSource(catalogSource: catalogSource, store: packageStore),
        catalogSource,
        SafeFallbackContentSource(),
      ])
    }
    let catalogStore = ValidatedCatalogStore(
      rootURL: learningRootURL?.appendingPathComponent("CatalogState", isDirectory: true))
    content = ContentRepository(
      source: productionSource,
      validatedCatalogStore: catalogStore)
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
