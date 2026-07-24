import XCTest

final class InternalContentReviewUITests: XCTestCase {
  func testReviewBuildShowsPermanentWarningAndLoadsTakken() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-LockAndStudyUITestResetData",
      "-LockAndStudyUseMock",
      "-SkipOnboarding",
      "-LockAndStudyUITestSelectedTakken",
    ]
    app.launch()

    XCTAssertTrue(
      app.descendants(matching: .any)["contentReview.banner"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["内部コンテンツレビュー"].exists)
    XCTAssertTrue(app.staticTexts["未校閲・販売禁止"].exists)
    XCTAssertTrue(app.buttons["takken.start.practice"].waitForExistence(timeout: 15))
  }

  func testPurchaseRouteIsDisabledInReviewBuild() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-LockAndStudyUITestResetData",
      "-LockAndStudyUseMock",
      "-SkipOnboarding",
      "-LockAndStudyUITestRoutePurchase",
    ]
    app.launch()

    XCTAssertTrue(
      app.staticTexts["購入機能は無効です"].waitForExistence(timeout: 15))
    XCTAssertFalse(
      app.buttons.matching(identifier: "purchase.product.passMonthly").firstMatch.exists)
  }
}
