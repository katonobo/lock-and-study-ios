import XCTest

final class LockAndStudyUITests: XCTestCase {
  func testLaunchesHomeWithoutPermissionAndDoesNotForcePaywall() {
    let app = launch()
    XCTAssertTrue(app.buttons["home.unlockStudy"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.staticTexts["学び方を選ぶ"].exists)
  }

  func testFourPrimaryTabs() {
    let app = launch()
    XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.tabBars.buttons["教材"].exists)
    XCTAssertTrue(app.tabBars.buttons["記録"].exists)
    XCTAssertTrue(app.tabBars.buttons["設定"].exists)
  }

  func testFreeVocabularyUnlockStudyOpens() {
    let app = launch()
    XCTAssertTrue(app.buttons["home.unlockStudy"].waitForExistence(timeout: 15))
    app.buttons["home.unlockStudy"].tap()
    XCTAssertTrue(app.otherElements["study.screen"].waitForExistence(timeout: 15))
  }

  func testFreeTakkenPracticeOpensFromPackDetail() {
    let app = launch(route: "-LockAndStudyUITestRouteTakkenDetail")
    XCTAssertTrue(app.buttons["pack.practice"].waitForExistence(timeout: 10))
    app.buttons["pack.practice"].tap()
    XCTAssertTrue(app.otherElements["study.screen"].waitForExistence(timeout: 15))
  }

  func testOnboardingCanSkipScreenTime() {
    let app = launch(skipOnboarding: false)
    advanceToAuthorization(app)
    app.buttons["今は設定せず学習を使う"].tap()
    XCTAssertTrue(app.buttons["後で設定する"].waitForExistence(timeout: 5))
    app.buttons["後で設定する"].tap()
    finishOnboarding(app)
  }

  func testOnboardingWithMockAuthorizationAndSelection() {
    let app = launch(skipOnboarding: false)
    advanceToAuthorization(app)
    app.buttons["onboarding.authorization"].tap()
    XCTAssertTrue(app.buttons["シミュレータ用の対象を設定"].waitForExistence(timeout: 5))
    app.buttons["シミュレータ用の対象を設定"].tap()
    finishOnboarding(app)
  }

  func testPackDetailOffersIndividualPurchaseAndCompletes() {
    let app = launch(route: "-LockAndStudyUITestRouteEnglishDetail", extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    XCTAssertTrue(app.buttons["pack.purchase"].waitForExistence(timeout: 10))
    app.buttons["pack.purchase"].tap()
    XCTAssertTrue(app.buttons["purchase.product.english3000"].waitForExistence(timeout: 10))
    app.buttons["purchase.product.english3000"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["purchase.state"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
  }

  func testPassPurchaseCompletes() {
    let app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    openPurchase(app)
    XCTAssertTrue(app.buttons["purchase.product.passMonthly"].waitForExistence(timeout: 10))
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["purchase.state"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
  }

  func testAskToBuyPendingMessage() {
    let app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommercePending"])
    openPurchase(app)
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["purchase.state"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "承認待ちです。承認後に自動反映されます。")
  }

  func testRestoreShowsPurchasedState() {
    let app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommerceRestore"])
    openPurchase(app)
    app.buttons["purchase.restore"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["purchase.state"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
  }

  func testActivePassShowsIncludedAndPermanentPurchaseAsSecondAction() {
    let app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommerceActivePass"])
    openPurchase(app)
    XCTAssertTrue(app.descendants(matching: .any)["purchase.passIncluded"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["purchase.showPermanent"].exists)
  }

  func testOwnedPackRemainsWithoutPass() {
    let app = launch(startInLibrary: true, extraArguments: ["-LockAndStudyUITestCommerceOwnedPack"])
    openLibrary(app)
    XCTAssertTrue(app.staticTexts["所有済み"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Study Passに含まれています"].exists)
  }

  func testEmergencyScreenAndVoiceOverIdentifier() {
    let app = launch()
    app.tabBars.buttons["設定"].tap()
    XCTAssertTrue(app.buttons["緊急解除"].waitForExistence(timeout: 10))
    app.buttons["緊急解除"].tap()
    XCTAssertTrue(app.buttons["emergency.hold"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["emergency.hold"].label, "5秒間長押しして緊急解除")
  }

  func testAccessibilityDynamicTypeHome() {
    let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    XCTAssertTrue(app.buttons["home.unlockStudy"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["通常練習を始める"].exists)
  }

  func testIPadPrimaryLayout() {
    let app = launch(startInLibrary: true)
    XCTAssertTrue(app.buttons["library.purchase"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["library.pack.english3000.v1"].exists)
  }

  private func launch(skipOnboarding: Bool = true, startInLibrary: Bool = false, route: String? = nil, extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-LockAndStudyUITestResetData", "-LockAndStudyUseMock"]
      + (skipOnboarding ? ["-SkipOnboarding"] : ["-ResetOnboarding"])
      + (startInLibrary ? ["-LockAndStudyUITestStartInLibrary"] : [])
      + (route.map { [$0] } ?? [])
      + extraArguments
    app.launch()
    return app
  }

  private func openLibrary(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["library.purchase"].waitForExistence(timeout: 15))
  }

  private func openPurchase(_ app: XCUIApplication) {
    XCTAssertTrue(app.descendants(matching: .any)["purchase.screen"].waitForExistence(timeout: 15))
  }

  private func advanceToAuthorization(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["次へ"].waitForExistence(timeout: 10))
    for _ in 0..<3 { app.buttons["次へ"].tap() }
    XCTAssertTrue(app.buttons["onboarding.authorization"].waitForExistence(timeout: 5))
  }

  private func finishOnboarding(_ app: XCUIApplication) {
    app.buttons["次へ"].tap()
    app.buttons["設定せず次へ"].tap()
    app.buttons["今は許可しない"].tap()
    XCTAssertTrue(app.buttons["onboarding.finish"].waitForExistence(timeout: 5))
    app.buttons["onboarding.finish"].tap()
    XCTAssertTrue(app.buttons["home.unlockStudy"].waitForExistence(timeout: 15))
  }
}
