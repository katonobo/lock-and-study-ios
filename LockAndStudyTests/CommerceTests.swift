import XCTest
@testable import LockAndStudy

final class CommerceTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000)
  func testFreeExpiredRevokedAndUnverifiedEquivalentCandidates() {
    let resolver = CommerceEntitlementResolver()
    let expired = EntitlementCandidate(productID: StoreProductKind.passMonthly.productID, purchaseDate: now, expirationDate: now, revocationDate: nil, isUpgraded: false, familyShared: false)
    let revoked = EntitlementCandidate(productID: StoreProductKind.english3000.productID, purchaseDate: now, expirationDate: nil, revocationDate: now, isUpgraded: false, familyShared: false)
    let result = resolver.resolve(candidates: [expired, revoked], legacy: [], now: now)
    XCTAssertNil(result.activePass); XCTAssertTrue(result.ownedPacks.isEmpty)
  }

  func testPassAndOwnedPackCoexistAndOwnedRemainsAfterPassEnds() {
    let pack = EntitlementCandidate(productID: StoreProductKind.english3000.productID, purchaseDate: now, expirationDate: nil, revocationDate: nil, isUpgraded: false, familyShared: false)
    let pass = EntitlementCandidate(productID: StoreProductKind.passYearly.productID, purchaseDate: now, expirationDate: now.addingTimeInterval(100), revocationDate: nil, isUpgraded: false, familyShared: false)
    let resolver = CommerceEntitlementResolver()
    let active = resolver.resolve(candidates: [pack, pass], legacy: [], now: now)
    XCTAssertTrue(active.activePass?.permitsAccess == true); XCTAssertEqual(active.ownedPacks.map(\.packID), ["english3000.v1"])
    let ended = resolver.resolve(candidates: [pack, pass], legacy: [], now: now.addingTimeInterval(101))
    XCTAssertNil(ended.activePass); XCTAssertEqual(ended.ownedPacks.map(\.packID), ["english3000.v1"])
  }

  func testFamilySharingIsPreserved() {
    let candidate = EntitlementCandidate(productID: StoreProductKind.english3000.productID, purchaseDate: now, expirationDate: nil, revocationDate: nil, isUpgraded: false, familyShared: true)
    let value = CommerceEntitlementResolver().resolve(candidates: [candidate], legacy: [], now: now)
    XCTAssertEqual(value.ownedPacks.first?.ownershipType, .familyShared)
    XCTAssertTrue(value.familySharedProductIDs.contains(candidate.productID))
  }

  func testLegacyPackAndExpiringPass() {
    let grants = [
      LegacyGrant(id: UUID(), sourceBundleID: "com.ameneko.eitangolock", destinationPackID: "english3000.v1", passExpiration: nil, importedAt: now),
      LegacyGrant(id: UUID(), sourceBundleID: "com.ameneko.eitangolock", destinationPackID: nil, passExpiration: now.addingTimeInterval(50), importedAt: now)
    ]
    let value = CommerceEntitlementResolver().resolve(candidates: [], legacy: grants, now: now)
    XCTAssertEqual(value.ownedPacks.first?.source, .verifiedLegacyMigration)
    XCTAssertTrue(value.activePass?.permitsAccess == true)
    XCTAssertNil(CommerceEntitlementResolver().resolve(candidates: [], legacy: grants, now: now.addingTimeInterval(51)).activePass)
  }
}

