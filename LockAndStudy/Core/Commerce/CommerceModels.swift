import Foundation

struct StoreProductKind: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }

  static let passMonthly = Self(rawValue: "passMonthly")
  static let passYearly = Self(rawValue: "passYearly")
  static let english3000 = Self(rawValue: "english3000")
  static let takken2026 = Self(rawValue: "takken2026")

  static func pack(_ packID: StudyPackID) -> Self {
    switch packID.rawValue {
    case "english3000.v1": return .english3000
    case "takken2026.v1": return .takken2026
    default: return .init(rawValue: "pack.\(packID.rawValue)")
    }
  }

  var productID: String {
    switch self {
    case .passMonthly: return ProductCatalog.monthlyPassProductID
    case .passYearly: return ProductCatalog.yearlyPassProductID
    case .english3000: return "com.ameneko.lockandstudy.pack.english3000.v1"
    case .takken2026: return "com.ameneko.lockandstudy.pack.takken2026.v1"
    default: return rawValue
    }
  }

  var packID: StudyPackID? {
    switch self {
    case .english3000: return "english3000.v1"
    case .takken2026: return "takken2026.v1"
    default:
      guard rawValue.hasPrefix("pack.") else { return nil }
      return .init(rawValue: String(rawValue.dropFirst("pack.".count)))
    }
  }

  var isSubscription: Bool { self == .passMonthly || self == .passYearly }
}

enum StudyPassState: String, Codable, Sendable {
  case inactive, active, gracePeriod, billingRetry, expired, revoked
}
enum OwnershipType: String, Codable, Sendable { case purchased, familyShared, legacy }
enum EntitlementSource: String, Codable, Sendable {
  case appStore, familySharing, verifiedLegacyMigration
}

struct StudyPassEntitlement: Codable, Equatable, Sendable {
  let productID: String
  let expirationDate: Date?
  let state: StudyPassState
  let ownershipType: OwnershipType
  var permitsAccess: Bool { state == .active || state == .gracePeriod }
}

struct OwnedPackEntitlement: Codable, Equatable, Identifiable, Sendable {
  var id: StudyPackID { packID }
  let packID: StudyPackID
  let productID: String
  let purchaseDate: Date
  let ownershipType: OwnershipType
  let source: EntitlementSource
}

struct LegacyGrant: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let sourceBundleID: String
  let destinationPackID: StudyPackID?
  let passExpiration: Date?
  let importedAt: Date
}

struct CommerceEntitlementSnapshot: Codable, Equatable, Sendable {
  var activePass: StudyPassEntitlement?
  var ownedPacks: [OwnedPackEntitlement]
  var familySharedProductIDs: Set<String>
  var legacyGrants: [LegacyGrant]
  var lastVerifiedAt: Date?
  var cacheValidUntil: Date?

  static let empty = CommerceEntitlementSnapshot(
    activePass: nil, ownedPacks: [], familySharedProductIDs: [], legacyGrants: [],
    lastVerifiedAt: nil, cacheValidUntil: nil)
  func sanitized(at date: Date) -> CommerceEntitlementSnapshot {
    var copy = self
    if let pass = copy.activePass, let expiration = pass.expirationDate, expiration <= date {
      copy.activePass = nil
    }
    return copy
  }
}

struct StoreProductPresentation: Identifiable, Equatable, Sendable {
  let id: String
  let kind: StoreProductKind
  let packID: StudyPackID?
  let displayName: String
  let description: String
  let displayPrice: String
  let isFamilyShareable: Bool
  let isTrialEligible: Bool
}

enum PurchaseState: Equatable, Sendable {
  case idle, loading
  case purchasing(String)
  case pending, purchased, cancelled
  case failed(String)
  var message: String? {
    switch self {
    case .pending: return "承認待ちです。承認後に自動反映されます。"
    case .purchased: return "購入を確認しました。"
    case .cancelled: return "購入はキャンセルされました。"
    case .failed(let value): return value
    default: return nil
    }
  }
}

struct StoreProductDescriptor: Equatable, Sendable {
  let productID: String
  let kind: StoreProductKind
  let packID: StudyPackID?
  let displayOrder: Int
  var isSubscription: Bool { kind.isSubscription }
}

struct ProductCatalog: Equatable, Sendable {
  static let monthlyPassProductID = "com.ameneko.lockandstudy.pass.monthly"
  static let yearlyPassProductID = "com.ameneko.lockandstudy.pass.yearly"
  static let passProductIDs: Set<String> = [monthlyPassProductID, yearlyPassProductID]
  static let legacyProductMappings: [String: StudyPackID] = [
    StoreProductKind.english3000.productID: "english3000.v1",
    StoreProductKind.takken2026.productID: "takken2026.v1",
  ]

  let descriptors: [StoreProductDescriptor]
  let productMappings: [String: StudyPackID]

  init(
    manifests: [StudyPackManifest],
    knownProductMappings: [String: StudyPackID] = ProductCatalog.legacyProductMappings,
    now: Date = Date()
  ) {
    var mappings = knownProductMappings
    for manifest in manifests {
      if let productID = manifest.oneTimeProductID { mappings[productID] = manifest.id }
    }
    productMappings = mappings
    let passes = [
      StoreProductDescriptor(
        productID: Self.monthlyPassProductID,
        kind: .passMonthly,
        packID: nil,
        displayOrder: Int.max - 1),
      StoreProductDescriptor(
        productID: Self.yearlyPassProductID,
        kind: .passYearly,
        packID: nil,
        displayOrder: Int.max),
    ]
    let packs = manifests.compactMap { manifest -> StoreProductDescriptor? in
      guard manifest.schemaVersion <= StudyPackManifest.supportedSchemaVersion,
        manifest.releaseStatus == .release,
        manifest.isEnabled,
        manifest.retiredAt.map({ $0 > now }) ?? true
      else { return nil }
      guard let productID = manifest.oneTimeProductID else { return nil }
      return .init(
        productID: productID,
        kind: .pack(manifest.id),
        packID: manifest.id,
        displayOrder: manifest.sortOrder)
    }
    descriptors = (packs + passes).sorted { $0.displayOrder < $1.displayOrder }
  }

  var allIDs: [String] { descriptors.map(\.productID) }
  func descriptor(for productID: String) -> StoreProductDescriptor? {
    descriptors.first { $0.productID == productID }
      ?? productMappings[productID].map {
        .init(
          productID: productID,
          kind: .pack($0),
          packID: $0,
          displayOrder: 0)
      }
  }
  func packID(for productID: String) -> StudyPackID? { productMappings[productID] }
  func isPass(_ productID: String) -> Bool { Self.passProductIDs.contains(productID) }
}

struct EntitlementCandidate: Sendable {
  let productID: String
  let purchaseDate: Date
  let expirationDate: Date?
  let revocationDate: Date?
  let isUpgraded: Bool
  let familyShared: Bool
}

struct CommerceEntitlementResolver: Sendable {
  func resolve(
    candidates: [EntitlementCandidate],
    legacy: [LegacyGrant],
    productMappings: [String: StudyPackID] = ProductCatalog.legacyProductMappings,
    now: Date
  ) -> CommerceEntitlementSnapshot {
    let valid = candidates.filter {
      $0.revocationDate == nil && !$0.isUpgraded
        && ($0.expirationDate.map { $0 > now } ?? true)
    }
    let passCandidate = valid.filter { ProductCatalog.passProductIDs.contains($0.productID) }
      .max { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    let pass = passCandidate.map {
      StudyPassEntitlement(
        productID: $0.productID,
        expirationDate: $0.expirationDate,
        state: .active,
        ownershipType: $0.familyShared ? .familyShared : .purchased)
    }
    var packs = valid.compactMap { candidate -> OwnedPackEntitlement? in
      guard let packID = productMappings[candidate.productID] else { return nil }
      return .init(
        packID: packID,
        productID: candidate.productID,
        purchaseDate: candidate.purchaseDate,
        ownershipType: candidate.familyShared ? .familyShared : .purchased,
        source: candidate.familyShared ? .familySharing : .appStore)
    }
    for grant in legacy where grant.destinationPackID != nil {
      let packID = grant.destinationPackID!
      if !packs.contains(where: { $0.packID == packID }) {
        packs.append(
          .init(
            packID: packID,
            productID: "legacy-grant",
            purchaseDate: grant.importedAt,
            ownershipType: .legacy,
            source: .verifiedLegacyMigration))
      }
    }
    let legacyPass = legacy.compactMap(\.passExpiration).filter { $0 > now }.max()
    let effectivePass =
      pass
      ?? legacyPass.map {
        .init(
          productID: "legacy-pass", expirationDate: $0, state: .active,
          ownershipType: .legacy)
      }
    return .init(
      activePass: effectivePass,
      ownedPacks: packs,
      familySharedProductIDs: Set(valid.filter(\.familyShared).map(\.productID)),
      legacyGrants: legacy,
      lastVerifiedAt: now,
      cacheValidUntil: now.addingTimeInterval(21_600))
  }
}
