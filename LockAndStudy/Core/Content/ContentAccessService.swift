import Foundation

enum ContentAccessReason: String, Codable, Sendable {
  case freeSample, ownedNonConsumable, activeStudyPass, familySharing, verifiedLegacyMigration,
    internalTest, unavailable
}

struct ContentAccessDecision: Codable, Equatable, Sendable {
  let isAllowed: Bool
  let reason: ContentAccessReason
}

struct ContentAccessService: Sendable {
  func decision(
    for prompt: StudyPrompt,
    manifest: StudyPackManifest,
    entitlement: CommerceEntitlementSnapshot,
    internalTest: Bool = InternalContentReviewBuild.grantsFullContentAccess,
    now: Date = Date()
  ) -> ContentAccessDecision {
    decision(
      isFreeSample: prompt.isFreeSample,
      manifest: manifest,
      entitlement: entitlement,
      internalTest: internalTest,
      now: now)
  }

  func decision(
    isFreeSample: Bool,
    manifest: StudyPackManifest,
    entitlement: CommerceEntitlementSnapshot,
    internalTest: Bool = InternalContentReviewBuild.grantsFullContentAccess,
    now: Date = Date()
  ) -> ContentAccessDecision {
    if isFreeSample { return .init(isAllowed: true, reason: .freeSample) }
    if internalTest && InternalContentReviewBuild.isEnabled {
      return .init(isAllowed: true, reason: .internalTest)
    }
    if let owned = entitlement.ownedPacks.first(where: { $0.packID == manifest.id }) {
      switch owned.source {
      case .familySharing: return .init(isAllowed: true, reason: .familySharing)
      case .verifiedLegacyMigration: return .init(isAllowed: true, reason: .verifiedLegacyMigration)
      case .appStore: return .init(isAllowed: true, reason: .ownedNonConsumable)
      }
    }
    if manifest.passAccessPolicy.permitsAccess(storeState: manifest.storeState),
      let pass = entitlement.activePass, pass.permitsAccess,
      pass.expirationDate.map({ $0 > now }) ?? true
    {
      return .init(
        isAllowed: true,
        reason: entitlement.activePass?.ownershipType == .familyShared
          ? .familySharing : .activeStudyPass)
    }
    return .init(isAllowed: false, reason: .unavailable)
  }
}
