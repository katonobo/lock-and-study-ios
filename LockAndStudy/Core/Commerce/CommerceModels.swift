import Foundation

enum StoreProductKind: String, Codable, CaseIterable, Sendable {
  case passMonthly, passYearly, english3000, takken2026
  var productID: String {
    switch self {
    case .passMonthly: return "com.ameneko.lockandstudy.pass.monthly"
    case .passYearly: return "com.ameneko.lockandstudy.pass.yearly"
    case .english3000: return "com.ameneko.lockandstudy.pack.english3000.v1"
    case .takken2026: return "com.ameneko.lockandstudy.pack.takken2026.v1"
    }
  }
  var packID: StudyPackID? {
    switch self { case .english3000: return "english3000.v1"; case .takken2026: return "takken2026.v1"; default: return nil }
  }
  var isSubscription: Bool { self == .passMonthly || self == .passYearly }
}

enum StudyPassState: String, Codable, Sendable { case inactive, active, gracePeriod, billingRetry, expired, revoked }
enum OwnershipType: String, Codable, Sendable { case purchased, familyShared, legacy }
enum EntitlementSource: String, Codable, Sendable { case appStore, familySharing, verifiedLegacyMigration }

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

  static let empty = CommerceEntitlementSnapshot(activePass: nil, ownedPacks: [], familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: nil, cacheValidUntil: nil)
  func sanitized(at date: Date) -> CommerceEntitlementSnapshot {
    var copy = self
    if let pass = copy.activePass, let expiration = pass.expirationDate, expiration <= date { copy.activePass = nil }
    return copy
  }
}

struct StoreProductPresentation: Identifiable, Equatable, Sendable {
  let id: String
  let kind: StoreProductKind
  let displayName: String
  let description: String
  let displayPrice: String
  let isFamilyShareable: Bool
  let isTrialEligible: Bool
}

enum PurchaseState: Equatable, Sendable {
  case idle, loading, purchasing(String), pending, purchased, cancelled, failed(String)
  var message: String? {
    switch self { case .pending: return "承認待ちです。承認後に自動反映されます。"; case .purchased: return "購入を確認しました。"; case .cancelled: return "購入はキャンセルされました。"; case .failed(let value): return value; default: return nil }
  }
}

enum ProductCatalog {
  static let allIDs = StoreProductKind.allCases.map(\.productID)
  static func kind(for productID: String) -> StoreProductKind? { StoreProductKind.allCases.first { $0.productID == productID } }
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
  func resolve(candidates: [EntitlementCandidate], legacy: [LegacyGrant], now: Date) -> CommerceEntitlementSnapshot {
    let valid = candidates.filter { $0.revocationDate == nil && !$0.isUpgraded && ($0.expirationDate.map { $0 > now } ?? true) }
    let passCandidate = valid.filter { ProductCatalog.kind(for: $0.productID)?.isSubscription == true }
      .max { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    let pass = passCandidate.map { StudyPassEntitlement(productID: $0.productID, expirationDate: $0.expirationDate, state: .active, ownershipType: $0.familyShared ? .familyShared : .purchased) }
    var packs = valid.compactMap { candidate -> OwnedPackEntitlement? in
      guard let packID = ProductCatalog.kind(for: candidate.productID)?.packID else { return nil }
      return .init(packID: packID, productID: candidate.productID, purchaseDate: candidate.purchaseDate,
                   ownershipType: candidate.familyShared ? .familyShared : .purchased,
                   source: candidate.familyShared ? .familySharing : .appStore)
    }
    for grant in legacy where grant.destinationPackID != nil {
      let packID = grant.destinationPackID!
      if !packs.contains(where: { $0.packID == packID }) {
        packs.append(.init(packID: packID, productID: "legacy-grant", purchaseDate: grant.importedAt,
                           ownershipType: .legacy, source: .verifiedLegacyMigration))
      }
    }
    let legacyPass = legacy.compactMap(\.passExpiration).filter { $0 > now }.max()
    let effectivePass = pass ?? legacyPass.map { .init(productID: "legacy-pass", expirationDate: $0, state: .active, ownershipType: .legacy) }
    return .init(activePass: effectivePass, ownedPacks: packs,
                 familySharedProductIDs: Set(valid.filter(\.familyShared).map(\.productID)), legacyGrants: legacy,
                 lastVerifiedAt: now, cacheValidUntil: now.addingTimeInterval(21_600))
  }
}

