import XCTest

@testable import LockAndStudy

final class ContentPlatformScalabilityV7Tests: XCTestCase {
  func testBundledAndDirectorySourcesReturnCurrentTwoPacksAndCounts() async throws {
    let bundled = BundledContentSource(bundle: .main)
    let bundledRepository = ContentRepository(source: bundled)
    let manifests = try await bundledRepository.releasedManifests()
    XCTAssertEqual(Set(manifests.map(\.id)), ["english3000.v1", "takken2026.v1"])

    let root = temporaryRoot()
    try copyPackageFiles(for: manifests, to: root)
    let directoryRepository = ContentRepository(
      source: DirectoryContentSource(catalog: try await bundled.catalogData(), root: root))
    let englishPrompts = try await directoryRepository.prompts(for: "english3000.v1")
    let takkenPrompts = try await directoryRepository.prompts(for: "takken2026.v1")
    XCTAssertEqual(englishPrompts.count, 3_000)
    XCTAssertEqual(takkenPrompts.count, 100)
  }

  func testDirectorySourceRejectsHashMismatchAndPackageTraversal() async throws {
    let bundled = BundledContentSource(bundle: .main)
    let manifests = try await ContentRepository(source: bundled).releasedManifests()
    let root = temporaryRoot()
    try copyPackageFiles(for: manifests, to: root)
    let english = try XCTUnwrap(manifests.first { $0.id == "english3000.v1" })
    let firstFile = try XCTUnwrap(english.contentFiles.first)
    let damagedURL = root.appendingPathComponent(firstFile.path)
    var damaged = try Data(contentsOf: damagedURL)
    damaged.append(0)
    try damaged.write(to: damagedURL, options: .atomic)
    let repository = ContentRepository(
      source: DirectoryContentSource(catalog: try await bundled.catalogData(), root: root))
    do {
      _ = try await repository.vocabularyPackage(for: english.id)
      XCTFail("hash mismatch must be rejected")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("検証"))
    }

    let location = ContentPackageLocation(kind: .installed, rootURL: root)
    XCTAssertThrowsError(try location.fileURL(for: "../outside.json"))
    XCTAssertThrowsError(try location.fileURL(for: "/tmp/outside.json"))
    let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    try Data("outside".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    let link = root.appendingPathComponent("linked.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    XCTAssertThrowsError(try location.fileURL(for: "linked.json"))
  }

  func testPackageStoreActivatesAtomicallyAndRejectsUnsafeComponents() async throws {
    let root = temporaryRoot()
    let packID: StudyPackID = "future.pack.v1"
    let version1 = root.appendingPathComponent(packID.rawValue).appendingPathComponent("1.0.0")
    let version2 = root.appendingPathComponent(packID.rawValue).appendingPathComponent("2.0.0")
    try FileManager.default.createDirectory(at: version1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: version2, withIntermediateDirectories: true)
    let store = ContentPackageStore(rootURL: root)
    try await store.activate(.init(packID: packID, contentVersion: "1.0.0", rootURL: version1))
    let active = try await store.activePackage(for: packID)
    let initialVersions = try await store.installedVersions(for: packID)
    XCTAssertEqual(active?.contentVersion, "1.0.0")
    XCTAssertEqual(initialVersions, ["1.0.0", "2.0.0"])
    do {
      try await store.remove(packID: packID, version: "1.0.0")
      XCTFail("active package must not be removed")
    } catch {}
    try await store.remove(packID: packID, version: "2.0.0")
    let remainingVersions = try await store.installedVersions(for: packID)
    XCTAssertEqual(remainingVersions, ["1.0.0"])
    do {
      _ = try await store.installedVersions(for: "../unsafe")
      XCTFail("unsafe pack ID must be rejected")
    } catch {}
    do {
      try await store.remove(packID: packID, version: "nested/unsafe")
      XCTFail("unsafe content version must be rejected")
    } catch {}
  }

  @MainActor
  func testRegistryUsesExperienceTypeForNewPackID() async throws {
    let base = try await manifest("english3000.v1")
    let newPack = try replacing(base, with: ["id": "toeic.words.v1"])
    let factory = StudyExperienceRegistry.standard().factory(for: newPack)
    XCTAssertEqual(factory?.descriptor.id, .vocabulary)
  }

  @MainActor
  func testUnknownTypesAndNewSchemaDoNotBreakKnownCatalogEntries() async throws {
    let bundled = BundledContentSource(bundle: .main)
    let data = try await bundled.catalogData()
    var entries = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    var unknownModule = try XCTUnwrap(entries.first)
    unknownModule["id"] = "future.module.v1"
    unknownModule["moduleType"] = "future-module"
    unknownModule["experienceType"] = StudyExperienceType.vocabularyV1.rawValue
    var unknownExperience = try XCTUnwrap(entries.first)
    unknownExperience["id"] = "future.experience.v1"
    unknownExperience["experienceType"] = "future-experience.v1"
    unknownExperience["schemaVersion"] = StudyPackManifest.supportedSchemaVersion + 1
    entries.append(contentsOf: [unknownModule, unknownExperience])
    let source = DirectoryContentSource(
      catalog: try JSONSerialization.data(withJSONObject: entries),
      root: try XCTUnwrap(Bundle.main.resourceURL))
    let repository = ContentRepository(source: source)
    let decoded = try await repository.releasedManifests()
    XCTAssertEqual(decoded.count, 4)
    let englishPrompts = try await repository.prompts(for: "english3000.v1")
    XCTAssertEqual(englishPrompts.count, 3_000)
    let modulePack = try XCTUnwrap(decoded.first { $0.id == "future.module.v1" })
    XCTAssertNotNil(StudyExperienceRegistry.standard().factory(for: modulePack))
    XCTAssertNil(StudyModuleRegistry.standard.module(for: modulePack.moduleType))
    XCTAssertEqual(
      PackAvailabilityResolver().resolve(
        manifest: modulePack, appVersion: "1.0", now: Date(), isOwned: false,
        supportsExperience: false),
      .updateAppRequired)
    let experiencePack = try XCTUnwrap(decoded.first { $0.id == "future.experience.v1" })
    XCTAssertNil(StudyExperienceRegistry.standard().factory(for: experiencePack))
    XCTAssertEqual(
      PackAvailabilityResolver().resolve(
        manifest: experiencePack, appVersion: "1.0", now: Date(), isOwned: false,
        supportsExperience: false),
      .updateAppRequired)
  }

  func testPackScopedSettingsFirstRunAndPreviewStateDoNotMix() async throws {
    let suiteName = "lockandstudy-v7-pack-state-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let first: StudyPackID = "words.first.v1"
    let second: StudyPackID = "words.second.v1"
    var firstSettings = VocabularySettings.standard
    firstSettings.dailyGoal = 5
    var secondSettings = VocabularySettings.standard
    secondSettings.dailyGoal = 30
    try firstSettings.save(packID: first, defaults: defaults)
    try secondSettings.save(packID: second, defaults: defaults)
    XCTAssertEqual(VocabularySettings.load(packID: first, defaults: defaults).dailyGoal, 5)
    XCTAssertEqual(VocabularySettings.load(packID: second, defaults: defaults).dailyGoal, 30)

    let firstRun = PackFirstRunStore(defaults: defaults)
    firstRun.setCompleted(packID: first)
    XCTAssertTrue(firstRun.isCompleted(packID: first, legacyExperienceID: .vocabulary))
    XCTAssertFalse(firstRun.isCompleted(packID: second, legacyExperienceID: .vocabulary))

    defaults.set(true, forKey: "lockandstudy.experience.vocabulary.first-run.completed")
    XCTAssertTrue(
      firstRun.isCompleted(packID: "english3000.v1", legacyExperienceID: .vocabulary))
    XCTAssertFalse(
      firstRun.isCompleted(packID: "new-vocabulary.v1", legacyExperienceID: .vocabulary))

    let store = LearningDataStore(rootURL: temporaryRoot())
    let now = Date()
    let firstPreview = vocabularyPreview(packID: first, itemID: "same", now: now)
    let secondPreview = vocabularyPreview(packID: second, itemID: "same", now: now)
    try await store.saveVocabularyPendingPreview(firstPreview, for: first)
    try await store.saveVocabularyPendingPreview(secondPreview, for: second)
    let loadedFirst = try await store.loadVocabularyPendingPreview(for: first, now: now)
    let loadedSecond = try await store.loadVocabularyPendingPreview(for: second, now: now)
    XCTAssertEqual(loadedFirst?.id, firstPreview.id)
    XCTAssertEqual(loadedSecond?.id, secondPreview.id)
    do {
      try await store.saveVocabularyPendingPreview(firstPreview, for: second)
      XCTFail("preview with a different pack ID must be rejected")
    } catch {}
  }

  func testSameItemIDHistoryAndAnalysisRemainPackScoped() async throws {
    let first: StudyPackID = "takken2026.v1"
    let second: StudyPackID = "takken2027.v1"
    let now = Date()
    let firstAnswer = answer(packID: first, correct: true, at: now)
    let secondAnswer = answer(packID: second, correct: false, at: now)
    let store = LearningDataStore(rootURL: temporaryRoot())
    try await store.record(firstAnswer)
    try await store.record(secondAnswer)
    let progress = try await store.allProgress()
    XCTAssertEqual(progress["takken2026.v1::q001"]?.correctCount, 1)
    XCTAssertEqual(progress["takken2027.v1::q001"]?.incorrectCount, 1)
    let summary = TakkenRecordsAnalyzer().summary(
      answers: try await store.answers(), packID: first, now: now)
    XCTAssertEqual(summary.answerCount, 1)
    XCTAssertEqual(summary.correctCount, 1)
    XCTAssertEqual(summary.wrongCount, 0)
  }

  func testCatalogDrivenCommerceResolvesDynamicRetiredAndPassProducts() async throws {
    let base = try await manifest("english3000.v1")
    let packID: StudyPackID = "toeic.words.v1"
    let productID = "com.ameneko.lockandstudy.pack.toeic.words.v1"
    let dynamic = try replacing(
      base,
      with: ["id": packID.rawValue, "oneTimeProductID": productID, "sortOrder": 99])
    let catalog = ProductCatalog(manifests: [dynamic], knownProductMappings: [:])
    XCTAssertTrue(catalog.allIDs.contains(productID))
    XCTAssertTrue(catalog.allIDs.contains(StoreProductKind.passMonthly.productID))
    XCTAssertTrue(catalog.allIDs.contains(StoreProductKind.passYearly.productID))
    let now = Date()
    let result = CommerceEntitlementResolver().resolve(
      candidates: [
        .init(
          productID: productID, purchaseDate: now, expirationDate: nil,
          revocationDate: nil, isUpgraded: false, familyShared: false)
      ],
      legacy: [], productMappings: catalog.productMappings, now: now)
    XCTAssertEqual(result.ownedPacks.map(\.packID), [packID])

    let retiredProductID = "com.ameneko.lockandstudy.pack.retired.v1"
    let retainedCatalog = ProductCatalog(
      manifests: [], knownProductMappings: [retiredProductID: "retired.v1"])
    let restored = CommerceEntitlementResolver().resolve(
      candidates: [
        .init(
          productID: retiredProductID, purchaseDate: now, expirationDate: nil,
          revocationDate: nil, isUpgraded: false, familyShared: false)
      ],
      legacy: [], productMappings: retainedCatalog.productMappings, now: now)
    XCTAssertEqual(restored.ownedPacks.first?.packID, "retired.v1")

    let retiredManifest = try replacing(
      dynamic, with: ["releaseStatus": "retired", "isEnabled": false])
    let retiredCatalog = ProductCatalog(
      manifests: [retiredManifest], knownProductMappings: [:], now: now)
    XCTAssertFalse(retiredCatalog.allIDs.contains(productID))
    XCTAssertEqual(retiredCatalog.packID(for: productID), packID)

    let pass = CommerceEntitlementResolver().resolve(
      candidates: [
        .init(
          productID: StoreProductKind.passMonthly.productID, purchaseDate: now,
          expirationDate: now.addingTimeInterval(3_600), revocationDate: nil,
          isUpgraded: false, familyShared: false)
      ],
      legacy: [], productMappings: catalog.productMappings, now: now)
    XCTAssertTrue(pass.activePass?.permitsAccess == true)
  }

  func testAvailabilityCompatibilityReleaseDatesAndRetirement() async throws {
    let base = try await manifest("english3000.v1")
    let resolver = PackAvailabilityResolver()
    let now = Date()
    let futureVersion = try replacing(base, with: ["minimumAppVersion": "99.0"])
    XCTAssertEqual(
      resolver.resolve(
        manifest: futureVersion, appVersion: "1.0", now: now, isOwned: false,
        supportsExperience: true),
      .updateAppRequired)
    let availableFrom = Date(
      timeIntervalSince1970: floor(now.addingTimeInterval(3_600).timeIntervalSince1970))
    let comingSoon = try replacing(
      base, with: ["availableFrom": ISO8601DateFormatter().string(from: availableFrom)])
    XCTAssertEqual(
      resolver.resolve(
        manifest: comingSoon, appVersion: "1.0", now: now, isOwned: false,
        supportsExperience: true),
      .comingSoon(availableFrom))
    let retired = try replacing(base, with: ["releaseStatus": "retired", "isEnabled": false])
    XCTAssertEqual(
      resolver.resolve(
        manifest: retired, appVersion: "1.0", now: now, isOwned: true,
        supportsExperience: true),
      .retiredOwned)
    XCTAssertEqual(
      resolver.resolve(
        manifest: retired, appVersion: "1.0", now: now, isOwned: false,
        supportsExperience: true),
      .retiredUnavailable)
  }

  func testTakkenAccessReturnsToSampleAfterPassExpiry() async throws {
    let takken = try await manifest("takken2026.v1")
    let service = ContentAccessService()
    XCTAssertTrue(
      service.decision(isFreeSample: true, manifest: takken, entitlement: .empty).isAllowed)
    XCTAssertFalse(
      service.decision(isFreeSample: false, manifest: takken, entitlement: .empty).isAllowed)
    let owned = CommerceEntitlementSnapshot(
      activePass: nil,
      ownedPacks: [
        .init(
          packID: takken.id, productID: "pack", purchaseDate: Date(),
          ownershipType: .purchased, source: .appStore)
      ],
      familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: Date(),
      cacheValidUntil: nil)
    XCTAssertTrue(
      service.decision(isFreeSample: false, manifest: takken, entitlement: owned).isAllowed)
    let expiry = Date()
    let pass = CommerceEntitlementSnapshot(
      activePass: .init(
        productID: StoreProductKind.passMonthly.productID, expirationDate: expiry,
        state: .active, ownershipType: .purchased),
      ownedPacks: [], familySharedProductIDs: [], legacyGrants: [],
      lastVerifiedAt: expiry, cacheValidUntil: nil)
    XCTAssertFalse(
      service.decision(
        isFreeSample: false, manifest: takken, entitlement: pass,
        now: expiry.addingTimeInterval(1)
      ).isAllowed)
  }

  @MainActor
  func testSafeFallbackWrongRetryMultipleQuestionsExpiryAndSaveFailure() async throws {
    let root = temporaryRoot()
    let dependencies = DependencyContainer(learningRootURL: root)
    let questions = [safeQuestion(id: "safe-1"), safeQuestion(id: "safe-2")]
    var bundle = safeBundle(questions: questions)
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    let model = AppModel(dependencies: dependencies)

    for question in questions {
      let wrong = await model.submitUnlockAnswer(
        question: question, selectedChoiceID: 1, feedback: .relearn6)
      XCTAssertEqual(wrong, .recordedIncorrect(remainingActiveSeconds: 6, attemptNumber: 1))
      let loadedWrong = try await dependencies.learning.loadExperienceUnlockBundle()
      bundle = try XCTUnwrap(loadedWrong)
      XCTAssertFalse(bundle.completedQuestionIDs.contains(question.id))
      bundle.reviewRemainingActiveSecondsByQuestionID?[question.id.rawValue] = nil
      try await dependencies.learning.saveExperienceUnlockBundle(bundle)
      let correct = await model.submitUnlockAnswer(
        question: question, selectedChoiceID: 0, feedback: .immediate)
      XCTAssertEqual(correct, .recordedCorrect)
    }
    let loadedComplete = try await dependencies.learning.loadExperienceUnlockBundle()
    bundle = try XCTUnwrap(loadedComplete)
    XCTAssertTrue(bundle.isComplete)
    await model.completeUnlockChallenge()
    let removedBundle = try await dependencies.learning.loadExperienceUnlockBundle()
    XCTAssertNil(removedBundle)

    var expired = safeBundle(questions: [safeQuestion(id: "expired")])
    expired = safeBundle(
      questions: expired.challenge.questions,
      createdAt: Date().addingTimeInterval(-3_600),
      expiresAt: Date().addingTimeInterval(-1))
    try await dependencies.learning.saveExperienceUnlockBundle(expired)
    let expiredResult = await model.submitUnlockAnswer(
      question: expired.challenge.questions[0], selectedChoiceID: 0, feedback: .immediate)
    XCTAssertEqual(
      expiredResult,
      .expired)
    let loadedExpired = try await dependencies.learning.loadExperienceUnlockBundle()
    XCTAssertEqual(loadedExpired?.completionState, .aborted)

    let failureRoot = temporaryRoot()
    let failureDependencies = DependencyContainer(learningRootURL: failureRoot)
    let failureQuestion = safeQuestion(id: "save-failure")
    try await failureDependencies.learning.saveExperienceUnlockBundle(
      safeBundle(questions: [failureQuestion]))
    try FileManager.default.createDirectory(
      at: failureRoot.appendingPathComponent("answer-transactions.v1.json"),
      withIntermediateDirectories: true)
    let failureModel = AppModel(dependencies: failureDependencies)
    guard
      case .failed = await failureModel.submitUnlockAnswer(
        question: failureQuestion, selectedChoiceID: 0, feedback: .immediate)
    else { return XCTFail("save failure must not be treated as correct") }
    let loadedFailure = try await failureDependencies.learning.loadExperienceUnlockBundle()
    XCTAssertFalse(
      try XCTUnwrap(loadedFailure).completedQuestionIDs.contains(failureQuestion.id))
  }

  private func manifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(source: BundledContentSource(bundle: .main))
      .releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == id })
  }

  private func replacing(
    _ manifest: StudyPackManifest,
    with values: [String: Any]
  ) throws -> StudyPackManifest {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(manifest))
        as? [String: Any])
    values.forEach { object[$0.key] = $0.value }
    return try SharedJSON.decoder().decode(
      StudyPackManifest.self,
      from: JSONSerialization.data(withJSONObject: object))
  }

  private func copyPackageFiles(
    for manifests: [StudyPackManifest],
    to root: URL
  ) throws {
    let sourceRoot = try XCTUnwrap(Bundle.main.resourceURL)
    let paths = Set(
      manifests.flatMap { manifest in
        manifest.contentFiles.map(\.path)
          + [manifest.metadataFile, manifest.creditsFile, manifest.sampleDefinition.catalogFile]
          .compactMap { $0 }
      })
    for path in paths {
      let source = sourceRoot.appendingPathComponent(path)
      let destination = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      if !FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.copyItem(at: source, to: destination)
      }
    }
  }

  private func temporaryRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func vocabularyPreview(
    packID: StudyPackID,
    itemID: String,
    now: Date
  ) -> VocabularyPendingPreview {
    .init(
      id: UUID(), packID: packID, sourceUnlockBundleID: UUID(), itemID: itemID,
      contentVersion: "1", createdAt: now, recallExpiresAt: now.addingTimeInterval(3_600),
      confirmedAt: nil, consumedAt: nil, foregroundExposureSeconds: 0)
  }

  private func answer(
    packID: StudyPackID,
    correct: Bool,
    at date: Date
  ) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString, experienceID: .takken, packID: packID,
      moduleType: .takken, itemID: "q001", prompt: "同一IDの問題",
      choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤答")],
      selectedChoiceID: correct ? 0 : 1, correctChoiceID: 0,
      shortExplanation: "解説", longExplanation: "詳しい解説", sourceNote: nil,
      category: "宅建業法", subcategory: "免許", contentVersion: "1",
      questionVersion: 1, examYear: 2026, lawBasisDate: "2026-04-01",
      answeredAt: date, mode: .practice, sessionID: UUID(),
      feedbackPlan: correct ? .immediate : .relearn6)
  }

  private func safeQuestion(id: StudyItemID) -> UnlockQuestionSnapshot {
    .safeFallback(
      .init(
        id: id, prompt: "安全に学習を続けるには？",
        choices: [.init(id: 0, text: "少しずつ続ける"), .init(id: 1, text: "やめる")],
        correctChoiceID: 0, explanation: "少しずつ継続します。"))
  }

  private func safeBundle(
    questions: [UnlockQuestionSnapshot],
    createdAt: Date = Date(),
    expiresAt: Date? = nil
  ) -> ExperienceUnlockBundleSnapshot {
    .init(
      schemaVersion: 3,
      challenge: .init(
        schemaVersion: 3, id: UUID(), requestID: UUID(), origin: .manual,
        experienceID: .safeFallback, packID: "english3000.v1", policyVersion: 1,
        pace: .balanced10, reviewLoad: .standard, questions: questions,
        access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
        createdAt: createdAt,
        expiresAt: expiresAt ?? createdAt.addingTimeInterval(1_800)),
      completedQuestionIDs: [], completionState: .answering,
      completionEventID: UUID(), createdUnlockSessionID: nil, abortReason: nil)
  }
}

private struct DirectoryContentSource: ContentAssetSource {
  let catalog: Data
  let root: URL

  func catalogData() async throws -> Data { catalog }

  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? {
    .init(kind: .installed, rootURL: root)
  }
}
