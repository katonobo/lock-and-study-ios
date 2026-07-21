import Foundation

enum ContentAccessReason: String, Codable, Sendable {
  case freeSample, ownedNonConsumable, activeStudyPass, familySharing, verifiedLegacyMigration, internalTest, unavailable
}

struct ContentAccessDecision: Codable, Equatable, Sendable {
  let isAllowed: Bool
  let reason: ContentAccessReason
}

struct ContentAccessService: Sendable {
  func decision(for prompt: StudyPrompt, manifest: StudyPackManifest, entitlement: CommerceEntitlementSnapshot, internalTest: Bool = false) -> ContentAccessDecision {
    if prompt.isFreeSample { return .init(isAllowed: true, reason: .freeSample) }
    if internalTest { return .init(isAllowed: true, reason: .internalTest) }
    if let owned = entitlement.ownedPacks.first(where: { $0.packID == manifest.id }) {
      switch owned.source {
      case .familySharing: return .init(isAllowed: true, reason: .familySharing)
      case .verifiedLegacyMigration: return .init(isAllowed: true, reason: .verifiedLegacyMigration)
      case .appStore: return .init(isAllowed: true, reason: .ownedNonConsumable)
      }
    }
    if manifest.passEligible, entitlement.activePass?.permitsAccess == true {
      return .init(isAllowed: true, reason: entitlement.activePass?.ownershipType == .familyShared ? .familySharing : .activeStudyPass)
    }
    return .init(isAllowed: false, reason: .unavailable)
  }
}

