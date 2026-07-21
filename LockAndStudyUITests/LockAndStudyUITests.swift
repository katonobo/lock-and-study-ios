import XCTest

final class LockAndStudyUITests: XCTestCase {
  func testPlatformLaunchesWithoutPermissionAndHasFourTabs() {
    let app = launch()
    XCTAssertTrue(app.buttons["platform.home.unlock"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.tabBars.buttons["ホーム"].exists)
    XCTAssertTrue(app.tabBars.buttons["教材"].exists)
    XCTAssertTrue(app.tabBars.buttons["記録"].exists)
    XCTAssertTrue(app.tabBars.buttons["設定"].exists)
    XCTAssertFalse(app.staticTexts["学び方を選ぶ"].exists)
  }

  func testVocabularyExperienceHasFiveTabsWithoutTakkenTabsAndReturnsToPlatform() {
    let app = launch()
    XCTAssertTrue(app.buttons["platform.open.vocabulary"].waitForExistence(timeout: 15))
    app.buttons["platform.open.vocabulary"].tap()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 15))
    for label in ["ホーム", "学習", "単語帳", "記録", "設定"] { XCTAssertTrue(app.tabBars.buttons[label].exists) }
    XCTAssertFalse(app.tabBars.buttons["問題"].exists)
    XCTAssertFalse(app.tabBars.buttons["演習"].exists)
    app.buttons["experience.close"].tap()
    XCTAssertTrue(app.buttons["platform.home.unlock"].waitForExistence(timeout: 10))
  }

  func testTakkenExperienceHasFiveTabsWithoutVocabularyTab() {
    let app = launch()
    XCTAssertTrue(app.buttons["platform.open.takken"].waitForExistence(timeout: 15))
    app.buttons["platform.open.takken"].tap()
    XCTAssertTrue(app.buttons["takken.start.practice"].waitForExistence(timeout: 15))
    for label in ["ホーム", "問題", "演習", "記録", "設定"] { XCTAssertTrue(app.tabBars.buttons[label].exists) }
    XCTAssertFalse(app.tabBars.buttons["単語帳"].exists)
  }

  func testSwitchingExperiencesDoesNotStackTabBars() {
    let app = launch()
    XCTAssertTrue(app.buttons["platform.open.takken"].waitForExistence(timeout: 15))
    app.buttons["platform.open.takken"].tap()
    XCTAssertTrue(app.buttons["takken.start.practice"].waitForExistence(timeout: 10))
    app.buttons["experience.close"].tap()
    XCTAssertTrue(app.buttons["platform.open.vocabulary"].waitForExistence(timeout: 10))
    app.buttons["platform.open.vocabulary"].tap()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testFreeVocabularyUnlockUsesVocabularyRenderer() {
    let app = launch()
    XCTAssertTrue(app.buttons["platform.home.unlock"].waitForExistence(timeout: 15))
    app.buttons["platform.home.unlock"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["unlock.vocabulary"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.descendants(matching: .any)["unlock.takken"].exists)
  }

  func testFreeTakkenUnlockUsesTakkenRenderer() {
    let app = launch(extraArguments: ["-LockAndStudyUITestSelectedTakken"])
    XCTAssertTrue(app.buttons["platform.home.unlock"].waitForExistence(timeout: 15))
    app.buttons["platform.home.unlock"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["unlock.takken"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.descendants(matching: .any)["unlock.vocabulary"].exists)
  }

  func testOnboardingCanSkipScreenTimeAndContinuesIntoVocabularyFirstRun() {
    let app = launch(skipOnboarding: false)
    advanceToManagementCode(app)
    app.buttons["設定せずに続ける"].tap()
    XCTAssertTrue(app.buttons["許可せずに続ける"].waitForExistence(timeout: 5))
    app.buttons["許可せずに続ける"].tap()
    XCTAssertTrue(app.buttons["onboarding.finish"].waitForExistence(timeout: 5))
    app.buttons["onboarding.finish"].tap()
    XCTAssertTrue(app.buttons["vocabulary.firstRun.finish"].waitForExistence(timeout: 15))
    app.buttons["vocabulary.firstRun.finish"].tap()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 15))
  }

  func testManagementCodeMismatchCannotAdvance() {
    let app = launch(skipOnboarding: false)
    advanceToManagementCode(app)
    let first = app.secureTextFields["onboarding.managementCode"]
    let confirmation = app.secureTextFields["onboarding.managementCodeConfirmation"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    first.tap(); first.typeText("123456")
    confirmation.tap(); confirmation.typeText("654321")
    XCTAssertTrue(app.staticTexts["onboarding.managementCodeMismatch"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["onboarding.managementCodeSet"].isEnabled)
  }

  func testTakkenPurchaseCTAIsHiddenWhileEnglishPurchaseIsAvailable() {
    let takken = launch(route: "-LockAndStudyUITestRouteTakkenDetail")
    XCTAssertTrue(takken.descendants(matching: .any)["platform.pack.detail"].waitForExistence(timeout: 15))
    XCTAssertFalse(takken.buttons["platform.pack.purchase"].exists)
    XCTAssertTrue(takken.staticTexts["準備中のため購入操作は表示されません。"].exists)

    takken.terminate()
    let english = launch(route: "-LockAndStudyUITestRouteEnglishDetail", extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    XCTAssertTrue(english.buttons["platform.pack.purchase"].waitForExistence(timeout: 15))
  }

  func testPassPurchaseAndPermanentPackPurchaseDisplay() {
    let app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    XCTAssertTrue(app.descendants(matching: .any)["purchase.screen"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["purchase.product.passMonthly"].exists)
    XCTAssertTrue(app.buttons["purchase.product.english3000"].exists)
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
  }

  func testAskToBuyRestoreAndActivePassStates() {
    var app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommercePending"])
    XCTAssertTrue(app.buttons["purchase.product.passMonthly"].waitForExistence(timeout: 15))
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "承認待ちです。承認後に自動反映されます。")
    app.terminate()

    app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommerceRestore"])
    XCTAssertTrue(app.buttons["purchase.restore"].waitForExistence(timeout: 15))
    app.buttons["purchase.restore"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
    app.terminate()

    app = launch(route: "-LockAndStudyUITestRoutePurchase", extraArguments: ["-LockAndStudyUITestCommerceActivePass"])
    XCTAssertTrue(app.descendants(matching: .any)["purchase.passIncluded"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["purchase.showPermanent"].exists)
  }

  func testOwnedPackRemainsWithoutPass() {
    let app = launch(startInLibrary: true, extraArguments: ["-LockAndStudyUITestCommerceOwnedPack"])
    XCTAssertTrue(app.tabBars.buttons["教材"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["所有済み"].exists)
    XCTAssertFalse(app.staticTexts["Study Passに含まれています"].exists)
  }

  func testVoiceOverIdentifiersAndMaximumDynamicType() {
    let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    XCTAssertTrue(app.buttons["platform.home.unlock"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.buttons["platform.home.unlock"].label, "学習して開く")
    XCTAssertTrue(app.buttons["platform.open.vocabulary"].exists)
  }

  func testIPadPrimaryLayout() {
    let app = launch(startInLibrary: true)
    XCTAssertTrue(app.buttons["platform.library.pack.english3000.v1"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["platform.library.pack.takken2026.v1"].exists)
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

  private func advanceToManagementCode(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
    app.buttons["onboarding.start"].tap()
    app.buttons["onboarding.next.1"].tap()
    app.buttons["onboarding.next.2"].tap()
    XCTAssertTrue(app.buttons["onboarding.authorization.skip"].waitForExistence(timeout: 5))
    app.buttons["onboarding.authorization.skip"].tap()
    app.buttons["onboarding.next.4"].tap()
    app.buttons["onboarding.next.5"].tap()
    XCTAssertTrue(app.secureTextFields["onboarding.managementCode"].waitForExistence(timeout: 5))
  }
}
