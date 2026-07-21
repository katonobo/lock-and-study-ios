import XCTest

final class LockAndStudyUITests: XCTestCase {
  func testSelectedVocabularyLaunchesAsStandaloneExperience() {
    let app = launch()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 15))
    for label in ["ホーム", "学習", "単語帳", "記録", "設定"] {
      XCTAssertTrue(app.tabBars.buttons[label].exists)
    }
    XCTAssertFalse(app.tabBars.buttons["教材"].exists)
    XCTAssertFalse(app.buttons["experience.close"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["platform.home"].exists)
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testTakkenSelectionLaunchesAsStandaloneExperience() {
    let app = launch(extraArguments: ["-LockAndStudyUITestSelectedTakken"])
    XCTAssertTrue(app.buttons["takken.start.practice"].waitForExistence(timeout: 15))
    for label in ["ホーム", "問題", "演習", "記録", "設定"] {
      XCTAssertTrue(app.tabBars.buttons[label].exists)
    }
    XCTAssertFalse(app.tabBars.buttons["単語帳"].exists)
    XCTAssertFalse(app.tabBars.buttons["教材"].exists)
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testMaterialSelectionInSettingsReplacesTheEntireExperience() {
    let app = launch()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 15))
    app.tabBars.buttons["設定"].tap()
    XCTAssertTrue(app.buttons["vocabulary.settings.materialSelection"].waitForExistence(timeout: 5))
    app.buttons["vocabulary.settings.materialSelection"].tap()

    XCTAssertTrue(
      app.descendants(matching: .any)["materialSelection.screen"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["materialSelection.option.english3000.v1"].exists)
    XCTAssertFalse(app.buttons["materialSelection.option.english3000.v1"].isEnabled)
    XCTAssertTrue(app.buttons["materialSelection.option.takken2026.v1"].exists)
    app.buttons["materialSelection.option.takken2026.v1"].tap()

    XCTAssertTrue(app.buttons["takken.start.practice"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.tabBars.buttons["単語帳"].exists)
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testFreeVocabularyUnlockUsesVocabularyRenderer() {
    let app = launch()
    XCTAssertTrue(app.buttons["vocabulary.start.unlock"].waitForExistence(timeout: 15))
    app.buttons["vocabulary.start.unlock"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["unlock.vocabulary"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.descendants(matching: .any)["unlock.takken"].exists)
  }

  func testFreeTakkenUnlockUsesTakkenRenderer() {
    let app = launch(extraArguments: ["-LockAndStudyUITestSelectedTakken"])
    XCTAssertTrue(app.buttons["takken.start.unlock"].waitForExistence(timeout: 15))
    app.buttons["takken.start.unlock"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["unlock.takken"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.descendants(matching: .any)["unlock.vocabulary"].exists)
  }

  func testOnboardingFinishesOnlyAfterStartingTheLock() {
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

    app.tabBars.buttons["設定"].tap()
    XCTAssertTrue(app.buttons["ロックと共通設定"].waitForExistence(timeout: 5))
    app.buttons["ロックと共通設定"].tap()
    XCTAssertTrue(app.buttons["ロック利用終了を申請"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["settings.enableLock"].exists)
  }

  func testManagementCodeMismatchCannotAdvance() {
    let app = launch(skipOnboarding: false)
    advanceToManagementCode(app)
    let first = app.secureTextFields["onboarding.managementCode"]
    let confirmation = app.secureTextFields["onboarding.managementCodeConfirmation"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    first.tap()
    first.typeText("123456")
    confirmation.tap()
    confirmation.typeText("654321")
    XCTAssertTrue(app.staticTexts["onboarding.managementCodeMismatch"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["onboarding.managementCodeSet"].isEnabled)
  }

  func testTakkenPurchaseCTAIsHiddenWhileEnglishPurchaseIsAvailable() {
    let takken = launch(route: "-LockAndStudyUITestRouteTakkenDetail")
    XCTAssertTrue(
      takken.descendants(matching: .any)["platform.pack.detail"].waitForExistence(timeout: 15))
    XCTAssertFalse(takken.buttons["platform.pack.purchase"].exists)
    XCTAssertTrue(takken.staticTexts["準備中のため購入操作は表示されません。"].exists)

    takken.terminate()
    let english = launch(
      route: "-LockAndStudyUITestRouteEnglishDetail",
      extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    XCTAssertTrue(english.buttons["platform.pack.purchase"].waitForExistence(timeout: 15))
  }

  func testPassPurchaseAndPermanentPackPurchaseDisplay() {
    let app = launch(
      route: "-LockAndStudyUITestRoutePurchase",
      extraArguments: ["-LockAndStudyUITestCommercePurchase"])
    XCTAssertTrue(app.descendants(matching: .any)["purchase.screen"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["purchase.product.passMonthly"].exists)
    XCTAssertTrue(app.buttons["purchase.product.english3000"].exists)
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
  }

  func testAskToBuyRestoreAndActivePassStates() {
    var app = launch(
      route: "-LockAndStudyUITestRoutePurchase",
      extraArguments: ["-LockAndStudyUITestCommercePending"])
    XCTAssertTrue(app.buttons["purchase.product.passMonthly"].waitForExistence(timeout: 15))
    app.buttons["purchase.product.passMonthly"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "承認待ちです。承認後に自動反映されます。")
    app.terminate()

    app = launch(
      route: "-LockAndStudyUITestRoutePurchase",
      extraArguments: ["-LockAndStudyUITestCommerceRestore"])
    XCTAssertTrue(app.buttons["purchase.restore"].waitForExistence(timeout: 15))
    app.buttons["purchase.restore"].tap()
    XCTAssertEqual(app.descendants(matching: .any)["purchase.state"].label, "購入を確認しました。")
    app.terminate()

    app = launch(
      route: "-LockAndStudyUITestRoutePurchase",
      extraArguments: ["-LockAndStudyUITestCommerceActivePass"])
    XCTAssertTrue(
      app.descendants(matching: .any)["purchase.passIncluded"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["purchase.showPermanent"].exists)
  }

  func testOwnedPackRemainsAvailableWithoutPass() {
    let app = launch(
      route: "-LockAndStudyUITestRouteEnglishDetail",
      extraArguments: ["-LockAndStudyUITestCommerceOwnedPack"])
    XCTAssertTrue(
      app.descendants(matching: .any)["platform.pack.detail"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["platform.pack.open"].exists)
    XCTAssertFalse(app.buttons["platform.pack.purchase"].exists)
  }

  func testVoiceOverIdentifiersAndMaximumDynamicType() {
    let app = launch(extraArguments: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    XCTAssertTrue(app.buttons["vocabulary.start.unlock"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.buttons["vocabulary.start.unlock"].label, "学習してロックを開く")
    app.tabBars.buttons["設定"].tap()
    XCTAssertTrue(app.buttons["vocabulary.settings.materialSelection"].exists)
  }

  func testVocabularyPreviewDisappearsWhenPersistedDisplayDeadlinePasses() {
    let app = launch(extraArguments: ["-LockAndStudyUITestVocabularyPreview"])
    let card = app.descendants(matching: .any)["vocabulary.nextWordPreviewCard"]
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    let hidden = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: card)
    XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 6), .completed)
  }

  func testIPadMaterialLineupLayout() {
    let app = launch()
    XCTAssertTrue(app.buttons["vocabulary.start.practice"].waitForExistence(timeout: 15))
    let settingsTab = app.buttons["設定"].firstMatch
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
    settingsTab.tap()
    app.buttons["vocabulary.settings.materialSelection"].tap()
    XCTAssertTrue(
      app.buttons["materialSelection.option.english3000.v1"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["materialSelection.option.takken2026.v1"].exists)
  }

  func testVocabularyRecordsOpenFreeWeeklyReportWithCoreSections() {
    let app = launch(extraArguments: ["-LockAndStudyUITestReportData"])
    openWeeklyReport(app, entryID: "report.entry.vocabulary")
    XCTAssertTrue(app.descendants(matching: .any)["report.hero"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["report.chart"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["report.learningSummary"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["report.material.english3000.v1"].exists)
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testTakkenRecordsOpenFreeWeeklyReportWithMaterialMetrics() {
    let app = launch(extraArguments: [
      "-LockAndStudyUITestSelectedTakken", "-LockAndStudyUITestReportData",
    ])
    openWeeklyReport(app, entryID: "report.entry.takken")
    XCTAssertTrue(app.descendants(matching: .any)["report.hero"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["report.material.takken2026.v1"].exists)
    let newItemMetric = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "初めて解いた 1問")
    ).firstMatch
    scrollUntilVisible(newItemMetric, app: app)
    XCTAssertTrue(newItemMetric.exists)
    XCTAssertEqual(app.tabBars.count, 1)
  }

  func testWeeklyReportCanSwitchBetweenCurrentAndAllMaterials() {
    let app = launch(extraArguments: ["-LockAndStudyUITestReportData"])
    openWeeklyReport(app, entryID: "report.entry.vocabulary")
    let scope = app.segmentedControls["report.scope"]
    XCTAssertTrue(scope.waitForExistence(timeout: 10))
    XCTAssertTrue(scope.buttons["この教材"].isSelected)
    scope.buttons["すべての教材"].tap()
    XCTAssertTrue(scope.buttons["すべての教材"].isSelected)
    scrollUntilVisible(app.descendants(matching: .any)["report.material.takken2026.v1"], app: app)
    XCTAssertTrue(app.descendants(matching: .any)["report.material.takken2026.v1"].exists)
  }

  func testWeeklyReportShareAndPrivacyExplanationAreReachable() {
    let app = launch(extraArguments: ["-LockAndStudyUITestReportData"])
    openWeeklyReport(app, entryID: "report.entry.vocabulary")
    scrollUntilVisible(app.buttons["report.share"], app: app)
    XCTAssertTrue(app.buttons["report.share"].exists)
    scrollUntilVisible(app.descendants(matching: .any)["report.privacy"], app: app)
    XCTAssertTrue(app.descendants(matching: .any)["report.privacy"].exists)
  }

  func testOnboardingCanOpenSampleReportWithoutCompletingSetup() {
    let app = launch(skipOnboarding: false)
    XCTAssertTrue(app.buttons["onboarding.sampleReport"].waitForExistence(timeout: 10))
    app.buttons["onboarding.sampleReport"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["report.sample.screen"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["report.sample.badge"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
  }

  func testDebugSampleRouteUsesSharedReportComponents() {
    let app = launch(route: "-LockAndStudyUITestRouteSampleReport")
    XCTAssertTrue(
      app.descendants(matching: .any)["report.sample.screen"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["report.sample.badge"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["report.hero"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["report.chart"].exists)
  }

  func testWeeklyReportSupportsMaximumDynamicTypeAndCombinedMetricLabels() {
    let app = launch(extraArguments: [
      "-LockAndStudyUITestReportData",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    openWeeklyReport(app, entryID: "report.entry.vocabulary")
    XCTAssertTrue(app.descendants(matching: .any)["report.hero"].waitForExistence(timeout: 10))
    let opportunityMetric = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "使う前の学習チャンス 1回")
    ).firstMatch
    scrollUntilVisible(opportunityMetric, app: app)
    XCTAssertTrue(opportunityMetric.exists)
    let chart = app.descendants(matching: .any)["report.chart"]
    scrollUntilVisible(chart, app: app)
    XCTAssertTrue(chart.exists)
  }

  private func launch(
    skipOnboarding: Bool = true, route: String? = nil, extraArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      ["-LockAndStudyUITestResetData", "-LockAndStudyUseMock"]
      + (skipOnboarding ? ["-SkipOnboarding"] : ["-ResetOnboarding"])
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

    XCTAssertTrue(app.buttons["onboarding.authorization"].waitForExistence(timeout: 5))
    app.buttons["onboarding.authorization"].tap()
    XCTAssertTrue(app.buttons["onboarding.mockSelection"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["onboarding.selection.continue"].isEnabled)
    app.buttons["onboarding.mockSelection"].tap()
    XCTAssertTrue(app.buttons["onboarding.selection.continue"].isEnabled)
    app.buttons["onboarding.selection.continue"].tap()

    app.buttons["onboarding.next.5"].tap()
    XCTAssertTrue(app.secureTextFields["onboarding.managementCode"].waitForExistence(timeout: 5))
  }

  private func openWeeklyReport(_ app: XCUIApplication, entryID: String) {
    XCTAssertTrue(app.tabBars.buttons["記録"].waitForExistence(timeout: 15))
    app.tabBars.buttons["記録"].tap()
    XCTAssertTrue(app.buttons[entryID].waitForExistence(timeout: 10))
    app.buttons[entryID].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["report.weekly.screen"].waitForExistence(timeout: 10))
  }

  private func scrollUntilVisible(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<8 where !element.isHittable { app.swipeUp() }
  }
}
