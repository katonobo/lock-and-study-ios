import Combine
import Foundation
import OSLog
import StoreKit

@MainActor
final class StoreKitCommerceService: ObservableObject {
  @Published private(set) var products: [StoreProductPresentation] = []
  @Published private(set) var entitlement: CommerceEntitlementSnapshot
  @Published private(set) var state: PurchaseState = .idle
  private var storeProducts: [Product] = []
  private let defaults: UserDefaults
  private let dateProvider: any DateProviding
  private let logger = Logger(subsystem: "com.ameneko.lockandstudy", category: "StoreKit")
  private var productCatalog: ProductCatalog
  private var updatesTask: Task<Void, Never>?
  #if DEBUG
    private let uiTestScenario: CommerceUITestScenario?
  #endif

  init(
    defaults: UserDefaults = LockAndStudySharedConstants.defaults,
    dateProvider: any DateProviding = SystemDateProvider()
  ) {
    self.defaults = defaults
    self.dateProvider = dateProvider
    productCatalog = ProductCatalog(
      manifests: [],
      knownProductMappings: Self.loadKnownProductMappings(defaults: defaults))
    #if DEBUG
      uiTestScenario = CommerceUITestScenario(arguments: ProcessInfo.processInfo.arguments)
      entitlement =
        uiTestScenario?.initialEntitlement(now: dateProvider.now())
        ?? Self.loadCache(defaults: defaults).sanitized(at: dateProvider.now())
    #else
      entitlement = Self.loadCache(defaults: defaults).sanitized(at: dateProvider.now())
    #endif
    updatesTask = Task { [weak self] in await self?.observeUpdates() }
  }
  deinit { updatesTask?.cancel() }

  func configure(manifests: [StudyPackManifest]) {
    productCatalog = ProductCatalog(
      manifests: manifests,
      knownProductMappings: productCatalog.productMappings)
    defaults.set(
      try? SharedJSON.encoder().encode(productCatalog.productMappings),
      forKey: LockAndStudySharedConstants.Key.knownProductMappings)
  }

  func loadProducts() async {
    #if DEBUG
      if uiTestScenario != nil {
        products = Self.uiTestProducts(catalog: productCatalog)
        state = .idle
        return
      }
    #endif
    state = .loading
    do {
      storeProducts = try await Product.products(for: productCatalog.allIDs)
      var values: [StoreProductPresentation] = []
      for product in storeProducts {
        guard let descriptor = productCatalog.descriptor(for: product.id) else { continue }
        let trialEligible: Bool
        if descriptor.kind == .passYearly, let subscription = product.subscription {
          trialEligible = await subscription.isEligibleForIntroOffer
        } else {
          trialEligible = false
        }
        values.append(
          .init(
            id: product.id, kind: descriptor.kind, packID: descriptor.packID,
            displayName: product.displayName,
            description: product.description, displayPrice: product.displayPrice,
            isFamilyShareable: product.isFamilyShareable, isTrialEligible: trialEligible))
      }
      products = values.sorted {
        productCatalog.allIDs.firstIndex(of: $0.id)! < productCatalog.allIDs.firstIndex(of: $1.id)!
      }
      state = .idle
    } catch {
      products = []
      state = .failed("購入情報を取得できませんでした。")
    }
  }

  func purchase(productID: String) async {
    #if DEBUG
      if let uiTestScenario {
        if uiTestScenario == .pending {
          state = .pending
          return
        }
        guard let descriptor = productCatalog.descriptor(for: productID) else {
          state = .failed("テスト商品が見つかりません。")
          return
        }
        if descriptor.isSubscription {
          entitlement.activePass = .init(
            productID: productID, expirationDate: dateProvider.now().addingTimeInterval(31_536_000),
            state: .active, ownershipType: .purchased)
        } else if let packID = descriptor.packID,
          !entitlement.ownedPacks.contains(where: { $0.packID == packID })
        {
          entitlement.ownedPacks.append(
            .init(
              packID: packID, productID: productID, purchaseDate: dateProvider.now(),
              ownershipType: .purchased, source: .appStore))
        }
        state = .purchased
        saveCache()
        return
      }
    #endif
    if storeProducts.isEmpty { await loadProducts() }
    guard let product = storeProducts.first(where: { $0.id == productID }) else {
      state = .failed("この商品は現在購入できません。")
      return
    }
    state = .purchasing(productID)
    do {
      switch try await product.purchase() {
      case .success(let result):
        let transaction = try verified(result)
        await refreshEntitlements()
        await transaction.finish()
        state = .purchased
      case .pending: state = .pending
      case .userCancelled: state = .cancelled
      @unknown default: state = .failed("購入結果を確認できませんでした。")
      }
    } catch { state = .failed("購入を完了できませんでした。請求は確定していません。") }
  }

  func restore() async {
    #if DEBUG
      if uiTestScenario == .restore {
        let packID = StudyPackID(rawValue: "english3000.v1")
        entitlement.ownedPacks = [
          .init(
            packID: packID, productID: StoreProductKind.english3000.productID,
            purchaseDate: dateProvider.now(), ownershipType: .purchased, source: .appStore)
        ]
        state = .purchased
        saveCache()
        return
      }
    #endif
    do {
      try await AppStore.sync()
      await refreshEntitlements()
      state =
        entitlement.activePass != nil || !entitlement.ownedPacks.isEmpty
        ? .purchased : .failed("復元できる購入が見つかりませんでした。")
    } catch { state = .failed("購入を復元できませんでした。") }
  }

  func refreshEntitlements() async {
    #if DEBUG
      if uiTestScenario != nil {
        saveCache()
        return
      }
    #endif
    var candidates: [EntitlementCandidate] = []
    for await result in Transaction.currentEntitlements {
      guard let transaction = try? verified(result) else { continue }
      guard
        productCatalog.isPass(transaction.productID)
          || productCatalog.packID(for: transaction.productID) != nil
      else {
        logger.notice(
          "Unknown StoreKit product ignored: \(transaction.productID, privacy: .public)")
        continue
      }
      candidates.append(
        .init(
          productID: transaction.productID, purchaseDate: transaction.purchaseDate,
          expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate,
          isUpgraded: transaction.isUpgraded,
          familyShared: transaction.ownershipType == .familyShared))
    }
    entitlement = CommerceEntitlementResolver().resolve(
      candidates: candidates,
      legacy: entitlement.legacyGrants,
      productMappings: productCatalog.productMappings,
      now: dateProvider.now())
    await applySubscriptionState()
    saveCache()
  }

  func addLegacyGrants(_ grants: [LegacyGrant]) {
    let deduplicated = Dictionary(
      (entitlement.legacyGrants + grants).map { ($0.id, $0) },
      uniquingKeysWith: { current, _ in current })
    let mergedGrants = Array(deduplicated.values)
    let legacy = CommerceEntitlementResolver().resolve(
      candidates: [],
      legacy: mergedGrants,
      productMappings: productCatalog.productMappings,
      now: dateProvider.now())
    let storePacks = entitlement.ownedPacks.filter { $0.source != .verifiedLegacyMigration }
    entitlement.ownedPacks =
      storePacks
      + legacy.ownedPacks.filter { candidate in
        !storePacks.contains(where: { $0.packID == candidate.packID })
      }
    if entitlement.activePass?.permitsAccess != true { entitlement.activePass = legacy.activePass }
    entitlement.legacyGrants = mergedGrants
    saveCache()
  }

  private func applySubscriptionState() async {
    var bestState: StudyPassState?
    for product in storeProducts where productCatalog.isPass(product.id) {
      guard let statuses = try? await product.subscription?.status else { continue }
      for status in statuses {
        let candidate: StudyPassState
        switch status.state {
        case .subscribed: candidate = .active
        case .inGracePeriod: candidate = .gracePeriod
        case .inBillingRetryPeriod: candidate = .billingRetry
        case .expired: candidate = .expired
        case .revoked: candidate = .revoked
        default: candidate = .inactive
        }
        if candidate == .active || candidate == .gracePeriod {
          bestState = candidate
          break
        }
        if bestState == nil { bestState = candidate }
      }
    }
    if let bestState, var pass = entitlement.activePass {
      pass = .init(
        productID: pass.productID, expirationDate: pass.expirationDate, state: bestState,
        ownershipType: pass.ownershipType)
      entitlement.activePass = pass.permitsAccess || bestState == .billingRetry ? pass : nil
    }
  }

  private func observeUpdates() async {
    for await result in Transaction.updates {
      guard let transaction = try? verified(result) else { continue }
      guard
        productCatalog.isPass(transaction.productID)
          || productCatalog.packID(for: transaction.productID) != nil
      else {
        logger.notice("Unknown StoreKit update ignored: \(transaction.productID, privacy: .public)")
        await transaction.finish()
        continue
      }
      await refreshEntitlements()
      await transaction.finish()
    }
  }
  private func verified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let value): return value
    case .unverified: throw StoreKitError.notEntitled
    }
  }
  private func saveCache() {
    defaults.set(
      try? SharedJSON.encoder().encode(entitlement),
      forKey: LockAndStudySharedConstants.Key.entitlementCache)
  }
  private static func loadCache(defaults: UserDefaults) -> CommerceEntitlementSnapshot {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.entitlementCache) else {
      return .empty
    }
    return (try? SharedJSON.decoder().decode(CommerceEntitlementSnapshot.self, from: data))
      ?? .empty
  }

  private static func loadKnownProductMappings(
    defaults: UserDefaults
  ) -> [String: StudyPackID] {
    guard let data = defaults.data(forKey: LockAndStudySharedConstants.Key.knownProductMappings),
      let stored = try? SharedJSON.decoder().decode([String: StudyPackID].self, from: data)
    else { return ProductCatalog.legacyProductMappings }
    return ProductCatalog.legacyProductMappings.merging(stored) { _, current in current }
  }

  #if DEBUG
    private static func uiTestProducts(catalog: ProductCatalog) -> [StoreProductPresentation] {
      catalog.descriptors.map { descriptor in
        .init(
          id: descriptor.productID,
          kind: descriptor.kind,
          packID: descriptor.packID,
          displayName: descriptor.kind.isSubscription
            ? (descriptor.kind == .passYearly ? "Study Pass 年額" : "Study Pass 月額")
            : (descriptor.packID == "english3000.v1" ? "英単語3,000語" : "宅建2026"),
          description: "UIテスト用StoreKit表示",
          displayPrice: "テスト価格",
          isFamilyShareable: true,
          isTrialEligible: descriptor.kind == .passYearly)
      }
    }
  #endif
}

#if DEBUG
  private enum CommerceUITestScenario: Equatable {
    case purchase, pending, activePass, ownedPack, restore

    init?(arguments: [String]) {
      if arguments.contains("-LockAndStudyUITestCommercePurchase") {
        self = .purchase
      } else if arguments.contains("-LockAndStudyUITestCommercePending") {
        self = .pending
      } else if arguments.contains("-LockAndStudyUITestCommerceActivePass") {
        self = .activePass
      } else if arguments.contains("-LockAndStudyUITestCommerceOwnedPack") {
        self = .ownedPack
      } else if arguments.contains("-LockAndStudyUITestCommerceRestore") {
        self = .restore
      } else {
        return nil
      }
    }

    func initialEntitlement(now: Date) -> CommerceEntitlementSnapshot {
      switch self {
      case .activePass:
        return .init(
          activePass: .init(
            productID: StoreProductKind.passYearly.productID,
            expirationDate: now.addingTimeInterval(31_536_000), state: .active,
            ownershipType: .purchased),
          ownedPacks: [], familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: now,
          cacheValidUntil: now.addingTimeInterval(21_600))
      case .ownedPack:
        return .init(
          activePass: nil,
          ownedPacks: [
            .init(
              packID: "english3000.v1", productID: StoreProductKind.english3000.productID,
              purchaseDate: now, ownershipType: .purchased, source: .appStore)
          ],
          familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: now,
          cacheValidUntil: now.addingTimeInterval(21_600))
      default: return .empty
      }
    }
  }
#endif
