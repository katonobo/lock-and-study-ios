import XCTest
@testable import LockAndStudy

final class LockPolicyTests: XCTestCase {
  func testInitialPolicyAndPaceContract() {
    let policy = LockPolicy.initial(now: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(policy.lifecycleState, .notConfigured)
    XCTAssertEqual(AccessPacePreset.frequent5.requiredLearningUnits, 1)
    XCTAssertEqual(AccessPacePreset.balanced10.unlockDurationMinutes, 10)
    XCTAssertEqual(AccessPacePreset.bundled20.requiredLearningUnits, 2)
    XCTAssertEqual(AccessPacePreset.extended30.requiredLearningUnits, 3)
    XCTAssertFalse(AccessPacePreset.allCases.contains { $0.unlockDurationMinutes == 60 })
  }

  func testSameCountSelectionDigestChangeIsWeaker() {
    var old = LockPolicy.initial(now: .distantPast)
    old.selectionSummary = .init(applicationCount: 2, categoryCount: 0, webDomainCount: 0, digest: "a")
    var new = old; new.selectionSummary.digest = "b"
    XCTAssertEqual(PolicyChangeClassifier().classify(from: old, to: new), .weaker)
  }

  func testReviewReductionAndLongerPaceAreWeaker() {
    var old = LockPolicy.initial(now: .distantPast); old.reviewLoadPreset = .reviewIntensive
    var reduced = old; reduced.reviewLoadPreset = .standard
    XCTAssertEqual(PolicyChangeClassifier().classify(from: old, to: reduced), .weaker)
    var longer = old; longer.accessPacePreset = .extended30
    XCTAssertEqual(PolicyChangeClassifier().classify(from: old, to: longer), .weaker)
  }

  func testCooldownHonorsCommitment() {
    let start = Date(timeIntervalSince1970: 1_000)
    let commitment = start.addingTimeInterval(200_000)
    XCTAssertEqual(ProtectedChangeCooldownPolicy().availableAt(requestedAt: start, commitmentEndsAt: commitment), commitment)
  }

  func testStudyUnlockAlwaysCreatesOneNewSession() {
    let now = Date(timeIntervalSince1970: 1_000)
    let first = UnlockSessionCoordinator().make(kind: .earnedByStudy, duration: 600, reasonCode: nil, policyVersion: 1, existing: nil, now: now)
    let second = UnlockSessionCoordinator().make(kind: .earnedByStudy, duration: 600, reasonCode: nil, policyVersion: 1, existing: first, now: now)
    XCTAssertNotEqual(first.id, second.id)
  }

  func testEmergencySessionExtendsExistingIdempotently() {
    let now = Date(timeIntervalSince1970: 1_000)
    let first = UnlockSessionCoordinator().make(kind: .emergency, duration: 900, reasonCode: "health", policyVersion: 1, existing: nil, now: now)
    let second = UnlockSessionCoordinator().make(kind: .emergency, duration: 900, reasonCode: "health", policyVersion: 1, existing: first, now: now.addingTimeInterval(10))
    XCTAssertEqual(first.id, second.id)
  }
}

