import XCTest
@testable import LockAndStudy

final class EmergencyUnlockTests: XCTestCase {
  func testRollingTwentyFourHoursBoundary() {
    let policy = EmergencyUnlockPolicy(); let last = Date(timeIntervalSince1970: 1_000)
    XCTAssertFalse(policy.canUse(lastUsedAt: last, now: last.addingTimeInterval(86_399)))
    XCTAssertTrue(policy.canUse(lastUsedAt: last, now: last.addingTimeInterval(86_400)))
  }

  func testActiveWaitOnlyAdvancesWhenCallerAddsActiveTime() {
    var wait = ActiveWaitCounter(required: 30)
    wait.addActiveTime(12); XCTAssertEqual(wait.remaining, 18)
    XCTAssertFalse(wait.isComplete)
    wait.addActiveTime(18); XCTAssertTrue(wait.isComplete)
  }
}

