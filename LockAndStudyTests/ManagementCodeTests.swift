import XCTest
@testable import LockAndStudy

final class ManagementCodeTests: XCTestCase {
  func testSaltedPBKDFAndNoPlaintextStorage() throws {
    let backing1 = InMemoryManagementCodeBackingStore()
    let backing2 = InMemoryManagementCodeBackingStore()
    let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_000))
    let first = ManagementCodeStore(backing: backing1, dateProvider: clock, iterations: 10)
    let second = ManagementCodeStore(backing: backing2, dateProvider: clock, iterations: 10)
    try first.setCode("294815"); try second.setCode("294815")
    XCTAssertNotEqual(try first.credentialSnapshotForTests()?.codeSalt, try second.credentialSnapshotForTests()?.codeSalt)
    XCTAssertFalse(String(data: try XCTUnwrap(backing1.loadCredentialData()), encoding: .utf8)?.contains("294815") == true)
    XCTAssertTrue(try first.verify("294815"))
  }

  func testFormatAndWarnings() {
    let store = ManagementCodeStore(backing: InMemoryManagementCodeBackingStore(), iterations: 1)
    XCTAssertThrowsError(try store.setCode("12345"))
    XCTAssertNotNil(ManagementCodeStore.codeWarning("111111"))
    XCTAssertNotNil(ManagementCodeStore.codeWarning("123456"))
    XCTAssertNil(ManagementCodeStore.codeWarning("294815"))
  }

  func testFiveAndTenAttemptLockouts() throws {
    let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_000))
    let store = ManagementCodeStore(backing: InMemoryManagementCodeBackingStore(), dateProvider: clock, iterations: 1)
    try store.setCode("294815")
    for _ in 0..<4 { XCTAssertThrowsError(try store.verify("000000")) }
    XCTAssertThrowsError(try store.verify("000000")) { error in
      guard case ManagementCodeError.lockedOut(let until) = error else { return XCTFail("expected lockout") }
      XCTAssertEqual(until, clock.date.addingTimeInterval(300))
    }
    clock.date = clock.date.addingTimeInterval(301)
    for _ in 0..<4 { XCTAssertThrowsError(try store.verify("000000")) }
    XCTAssertThrowsError(try store.verify("000000")) { error in
      guard case ManagementCodeError.lockedOut(let until) = error else { return XCTFail("expected lockout") }
      XCTAssertEqual(until, clock.date.addingTimeInterval(1_800))
    }
  }

  func testClockRollbackDoesNotBypassLockout() throws {
    let clock = FixedDateProvider(Date(timeIntervalSince1970: 2_000))
    let store = ManagementCodeStore(backing: InMemoryManagementCodeBackingStore(), dateProvider: clock, iterations: 1)
    try store.setCode("294815")
    for _ in 0..<5 { _ = try? store.verify("000000") }
    clock.date = Date(timeIntervalSince1970: 100)
    XCTAssertThrowsError(try store.verify("294815"))
  }

  func testForgottenCodeResetRequiresFullCooldownAndSecondConfirmation() throws {
    let suite = "management-reset-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let code = ManagementCodeStore(backing: InMemoryManagementCodeBackingStore(), iterations: 1)
    try code.setCode("294815")
    let service = ManagementCodeResetService(codeStore: code, policyStore: LockPolicyStore(defaults: defaults))
    let now = Date(timeIntervalSince1970: 5_000)
    XCTAssertEqual(service.schedule(now: now), .scheduled(now.addingTimeInterval(86_400)))
    XCTAssertEqual(try service.confirm(now: now.addingTimeInterval(86_399), secondConfirmation: true),
                   .tooEarly(now.addingTimeInterval(86_400)))
    XCTAssertEqual(try service.confirm(now: now.addingTimeInterval(86_400), secondConfirmation: false),
                   .secondConfirmationRequired)
    XCTAssertTrue(code.hasManagementCode)
    XCTAssertEqual(try service.confirm(now: now.addingTimeInterval(86_400), secondConfirmation: true), .removed)
    XCTAssertFalse(code.hasManagementCode)
  }
}
