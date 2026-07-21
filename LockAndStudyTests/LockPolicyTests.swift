import FamilyControls
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

  func testEarlyCallbackReschedulesAndFailureFallsBackToImmediateRelock() {
    let now = Date(timeIntervalSince1970: 10_000)
    let endsAt = now.addingTimeInterval(600)
    var scheduled: Date?
    let success = RelockRecoveryExecutor().execute(now: now, endsAt: endsAt) { scheduled = $0 }
    XCTAssertEqual(success, .rescheduled(endsAt))
    XCTAssertEqual(scheduled, endsAt)

    enum SchedulingFailure: Error { case failed }
    let failSafe = RelockRecoveryExecutor().execute(now: now, endsAt: endsAt) { _ in throw SchedulingFailure.failed }
    XCTAssertEqual(failSafe, .relockNow(afterScheduleFailure: true))
    XCTAssertEqual(RelockRecoveryExecutor().execute(now: endsAt, endsAt: endsAt) { _ in XCTFail() }, .relockNow(afterScheduleFailure: false))
  }

  func testActiveSessionRefreshRebuildsMonitorAndExpiredSessionRelocks() {
    let now = Date(timeIntervalSince1970: 20_000)
    let session = UnlockSession(id: UUID(), kind: .earnedByStudy, startedAt: now, endsAt: now.addingTimeInterval(600), reasonCode: "bundle:test", policyVersion: 1)
    let planner = ActiveLockRefreshPlanner()
    XCTAssertEqual(planner.action(isLockEnabled: true, isAuthorized: true, session: session, now: now), .restoreTemporaryUnlock(session.endsAt))
    XCTAssertEqual(planner.action(isLockEnabled: true, isAuthorized: true, session: session, now: session.endsAt), .relockNow)
    XCTAssertEqual(planner.action(isLockEnabled: true, isAuthorized: false, session: session, now: now), .authorizationLost)
    XCTAssertEqual(planner.action(isLockEnabled: false, isAuthorized: true, session: session, now: now), .disabled)
  }

  func testRecoveryUsesAbsoluteDeadlineAcrossTimeZoneAndDSTChanges() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let beforeDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 55)))
    let endsAt = beforeDST.addingTimeInterval(600)
    XCTAssertEqual(RelockRecoveryPlanner().action(now: beforeDST, endsAt: endsAt), .reschedule(endsAt))

    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    let sameInstant = beforeDST.addingTimeInterval(300)
    XCTAssertEqual(RelockRecoveryPlanner().action(now: sameInstant, endsAt: endsAt), .reschedule(endsAt))
    XCTAssertEqual(RelockRecoveryPlanner().action(now: endsAt, endsAt: endsAt), .relockNow)
  }

  func testOldTokenRemovalIsWeakerEvenWhenTotalCountIncreases() {
    var old = LockPolicy.initial(now: .distantPast)
    old.selectionSummary = .init(
      applicationCount: 2, categoryCount: 0, webDomainCount: 0, digest: "old",
      tokenSnapshot: .init(applicationTokenDigests: ["a", "b"], categoryTokenDigests: [], webDomainTokenDigests: [])
    )
    var proposed = old
    proposed.selectionSummary = .init(
      applicationCount: 3, categoryCount: 0, webDomainCount: 0, digest: "new",
      tokenSnapshot: .init(applicationTokenDigests: ["b", "c", "d"], categoryTokenDigests: [], webDomainTokenDigests: [])
    )
    XCTAssertEqual(PolicyChangeClassifier().classify(from: old, to: proposed), .weaker)
  }

  @MainActor
  func testEmptySelectionIsRejectedAndLockStateIsShared() async throws {
    let suiteName = "lockandstudy-lock-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let first = MockLockController(defaults: defaults)
    let second = MockLockController(defaults: defaults)
    do {
      try await first.saveSelection(FamilyActivitySelection())
      XCTFail("空の選択が保存されました")
    } catch {
      XCTAssertEqual(error as? LockControllerError, .selectionRequired)
    }
    try await first.requestAuthorization()
    first.markMockSelectionCompleted()
    try await first.setLockEnabled(true)
    XCTAssertTrue(second.isAuthorized)
    XCTAssertTrue(second.hasSelection)
    XCTAssertTrue(second.isLockEnabled)
  }

  func testSelectionUpdatesApplyImmediatelyExceptDuringTemporaryUnlock() {
    let now = Date(timeIntervalSince1970: 25_000)
    let planner = SelectionShieldUpdatePlanner()
    XCTAssertEqual(
      planner.action(isLockEnabled: false, session: nil, now: now),
      .persistOnly)
    XCTAssertEqual(
      planner.action(isLockEnabled: true, session: nil, now: now),
      .applyImmediately)
    let active = UnlockSession(
      id: UUID(), kind: .earnedByStudy, startedAt: now,
      endsAt: now.addingTimeInterval(600), reasonCode: nil, policyVersion: 1)
    XCTAssertEqual(
      planner.action(isLockEnabled: true, session: active, now: now),
      .deferUntilRelock)
    XCTAssertEqual(
      planner.action(
        isLockEnabled: true, session: active,
        now: active.endsAt),
      .applyImmediately)
  }

  func testEarnedUnlockCompletionRetryReusesSessionForSameBundle() {
    let now = Date(timeIntervalSince1970: 30_000)
    let coordinator = UnlockSessionCoordinator()
    let first = coordinator.make(kind: .earnedByStudy, duration: 600, reasonCode: "bundle:fixed", policyVersion: 1, existing: nil, now: now)
    let retried = coordinator.make(kind: .earnedByStudy, duration: 600, reasonCode: "bundle:fixed", policyVersion: 1, existing: first, now: now.addingTimeInterval(1))
    XCTAssertEqual(first.id, retried.id)
    XCTAssertEqual(first.endsAt, retried.endsAt)
  }

  func testOnboardingLockActivationPlannerRepairsOnlyIntendedActiveStates() {
    let planner = OnboardingLockActivationPlanner()
    XCTAssertTrue(planner.shouldActivate(
      onboardingCompleted: true,
      isAuthorized: true,
      hasSelection: true,
      isLockEnabled: false,
      lifecycleState: .notConfigured
    ))
    XCTAssertTrue(planner.shouldActivate(
      onboardingCompleted: true,
      isAuthorized: true,
      hasSelection: true,
      isLockEnabled: false,
      lifecycleState: .active
    ))
    XCTAssertFalse(planner.shouldActivate(
      onboardingCompleted: true,
      isAuthorized: true,
      hasSelection: true,
      isLockEnabled: false,
      lifecycleState: .ended
    ))
    XCTAssertFalse(planner.shouldActivate(
      onboardingCompleted: true,
      isAuthorized: false,
      hasSelection: true,
      isLockEnabled: false,
      lifecycleState: .notConfigured
    ))
  }
}
