import XCTest

@testable import LockAndStudy

final class PlatformFoundationV9Tests: XCTestCase {
  func testCatalogV2LoadsCategorySeriesPackAndComponentRelationships() async throws {
    let repository = ContentRepository(source: BundledContentSource(bundle: .main))
    let snapshot = try await repository.catalogSnapshot()

    XCTAssertEqual(snapshot.schemaVersion, 2)
    XCTAssertEqual(Set(snapshot.categories.map(\.id)), [.english, .qualification])
    XCTAssertEqual(Set(snapshot.series.map(\.id)), [.englishVocabulary, .takken])
    XCTAssertEqual(Set(snapshot.packs.map(\.id)), ["english3000.v1", "takken2026.v1"])
    XCTAssertTrue(StudyCatalogValidator().validate(snapshot).isEmpty)

    let english = try XCTUnwrap(snapshot.packs.first { $0.id == "english3000.v1" })
    XCTAssertEqual(english.categoryID, .english)
    XCTAssertEqual(english.seriesID, .englishVocabulary)
    XCTAssertEqual(english.experienceID, .flashcardV1)
    XCTAssertEqual(english.components.first?.contentSchemaID, .flashcardItemsV1)

    let takken = try XCTUnwrap(snapshot.packs.first { $0.id == "takken2026.v1" })
    XCTAssertEqual(takken.editionPolicy, .annual)
    XCTAssertEqual(takken.editionYear, 2026)
    XCTAssertEqual(takken.experienceID, .certificationV1)
    XCTAssertEqual(takken.components.first?.contentSchemaID, .certificationQuestionsV1)
  }

  func testLegacyV1PackMigratesToOpenCatalogIDs() async throws {
    let base = try await manifest("english3000.v1")
    var object = try encodedObject(base)
    object["schemaVersion"] = 1
    object["experienceType"] = "vocabulary.v1"
    for key in [
      "categoryID", "seriesID", "experienceID", "editionID", "editionYear",
      "editionPolicy", "storeState", "deliveryMode", "passAccessPolicy", "components",
    ] {
      object.removeValue(forKey: key)
    }
    let data = try JSONSerialization.data(withJSONObject: [object])
    let snapshot = try StudyCatalogDecoder().decode(data)
    let migrated = try XCTUnwrap(snapshot.packs.first)

    XCTAssertEqual(migrated.id, base.id)
    XCTAssertEqual(migrated.categoryID, .english)
    XCTAssertEqual(migrated.seriesID, .englishVocabulary)
    XCTAssertEqual(migrated.experienceID, .flashcardV1)
    XCTAssertEqual(migrated.components.first?.contentSchemaID, .flashcardItemsV1)
  }

  @MainActor
  func testFactoryResolutionUsesTemplateIDAndContentSchemaNotPackID() async throws {
    let base = try await manifest("english3000.v1")
    var object = try encodedObject(base)
    object["id"] = "japanese.yojijukugo.test.v1"
    object["categoryID"] = "language.japanese"
    object["seriesID"] = "japanese.yojijukugo"
    let pack = try decodeManifest(object)
    let registry = StudyExperienceRegistry.standard()
    let factory = try XCTUnwrap(registry.factory(for: pack))

    XCTAssertEqual(factory.experienceID, .flashcardV1)
    XCTAssertEqual(factory.descriptor.id, .vocabulary)
    XCTAssertTrue(factory.validateCompatibility(with: pack).isEmpty)

    var incompatibleObject = object
    var components = try XCTUnwrap(incompatibleObject["components"] as? [[String: Any]])
    components[0]["contentSchemaID"] = "future.flashcard.v9"
    incompatibleObject["components"] = components
    let incompatible = try decodeManifest(incompatibleObject)
    XCTAssertFalse(factory.validateCompatibility(with: incompatible).isEmpty)
  }

  @MainActor
  func testUnknownExperienceRemainsIsolatedFromKnownPacks() async throws {
    let base = try await manifest("english3000.v1")
    var object = try encodedObject(base)
    object["id"] = "future.unknown-experience.v1"
    object["experienceID"] = "future.experience.v1"
    var components = try XCTUnwrap(object["components"] as? [[String: Any]])
    components[0]["experienceID"] = "future.experience.v1"
    components[0]["contentSchemaID"] = "future.schema.v1"
    object["components"] = components
    let unknown = try decodeManifest(object)
    let registry = StudyExperienceRegistry.standard()

    XCTAssertNil(registry.factory(for: unknown))
    XCTAssertNotNil(registry.factory(for: base))
    XCTAssertEqual(
      PackAvailabilityResolver().resolve(
        manifest: unknown, appVersion: "1.0", now: Date(), isOwned: false,
        supportsExperience: false),
      .updateAppRequired)
  }

  func testCatalogValidatorRejectsCategoryAndSupersedesCycles() async throws {
    let baseSnapshot = try await ContentRepository(
      source: BundledContentSource(bundle: .main)).catalogSnapshot()
    let cyclicCategories = [
      StudyCategoryManifest(
        schemaVersion: 1, id: "a", parentCategoryID: "b", title: "A",
        subtitle: nil, systemImage: "book", sortOrder: 1, isVisible: true,
        availableFrom: nil, themeToken: nil),
      StudyCategoryManifest(
        schemaVersion: 1, id: "b", parentCategoryID: "a", title: "B",
        subtitle: nil, systemImage: "book", sortOrder: 2, isVisible: true,
        availableFrom: nil, themeToken: nil),
    ]
    let snapshot = StudyCatalogSnapshot(
      schemaVersion: 2, generatedAt: nil,
      categories: baseSnapshot.categories + cyclicCategories,
      series: baseSnapshot.series, packs: baseSnapshot.packs)
    let issues = StudyCatalogValidator().validate(snapshot)
    XCTAssertTrue(issues.contains { $0.code == "category-cycle" })
  }

  func testLegacyUnlockBundleMigratesToGenericEnvelopeWithoutLosingPayload() async throws {
    let root = temporaryDirectory("unlock-envelope-migration")
    let store = LearningDataStore(rootURL: root)
    let bundle = safeBundle()
    try await store.saveExperienceUnlockBundle(bundle)

    let envelopeURL = root.appendingPathComponent("unlock-session-envelope.v3.json")
    try FileManager.default.removeItem(at: envelopeURL)
    let loaded = try await store.loadUnlockSessionEnvelope()
    let migrated = try XCTUnwrap(loaded)

    XCTAssertEqual(migrated.id, bundle.id)
    XCTAssertEqual(migrated.requestID, bundle.challenge.requestID)
    XCTAssertEqual(migrated.experienceID, .safeFallbackV1)
    XCTAssertEqual(migrated.packID, bundle.challenge.packID)
    XCTAssertEqual(migrated.enginePayloadSchemaID, "safe-fallback.unlock-session.v1")
    XCTAssertEqual(try migrated.decodeLegacyBundle(), bundle)
    XCTAssertTrue(FileManager.default.fileExists(atPath: envelopeURL.path))
  }

  func testGenericUnlockCompletionProofIsIdempotentAndRejectsMismatches() async throws {
    let store = LearningDataStore(rootURL: temporaryDirectory("unlock-proof"))
    let bundle = safeBundle()
    try await store.saveExperienceUnlockBundle(bundle)
    let coordinator = UnlockChallengeSessionCoordinator(store: store)
    let proof = ExperienceCompletionProof(
      sessionID: bundle.id, packID: bundle.challenge.packID,
      completedAt: bundle.challenge.createdAt.addingTimeInterval(10), evidenceVersion: 1)

    let accepted = try await coordinator.acceptCompletionProof(
      proof, now: bundle.challenge.createdAt.addingTimeInterval(11))
    let resumed = try await coordinator.acceptCompletionProof(
      proof, now: bundle.challenge.createdAt.addingTimeInterval(12))
    let savedAfterProof = try await store.loadUnlockSessionEnvelope()
    XCTAssertEqual(accepted, .accepted)
    XCTAssertEqual(resumed, .resuming)
    XCTAssertEqual(savedAfterProof?.completionState, .proofAccepted)

    let wrongPack = ExperienceCompletionProof(
      sessionID: bundle.id, packID: "another.pack",
      completedAt: proof.completedAt, evidenceVersion: 1)
    let rejected = try await coordinator.acceptCompletionProof(
      wrongPack, now: bundle.challenge.createdAt.addingTimeInterval(13))
    XCTAssertEqual(rejected, .rejected("completion-proof-mismatch"))
  }

  func testGenericUnlockRecoveryExpiresFailClosed() async throws {
    let store = LearningDataStore(rootURL: temporaryDirectory("unlock-expired"))
    let now = Date(timeIntervalSince1970: 9_000_000)
    let bundle = safeBundle(createdAt: now, expiresAt: now.addingTimeInterval(30))
    try await store.saveExperienceUnlockBundle(bundle)
    let coordinator = UnlockChallengeSessionCoordinator(store: store)

    let restored = try await coordinator.restore(at: now.addingTimeInterval(31))
    let loaded = try await store.loadUnlockSessionEnvelope()
    let saved = try XCTUnwrap(loaded)
    XCTAssertNil(restored)
    XCTAssertEqual(saved.completionState, .aborted)
    XCTAssertEqual(saved.abortReason, "challenge-expired-during-recovery")
  }

  func testUnsupportedUnlockEnvelopeSchemaAbortsFailClosed() async throws {
    let store = LearningDataStore(rootURL: temporaryDirectory("unlock-future-schema"))
    let bundle = safeBundle()
    let current = try UnlockChallengeSessionEnvelope.wrapping(bundle)
    let future = UnlockChallengeSessionEnvelope(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion + 1,
      id: current.id,
      requestID: current.requestID,
      origin: current.origin,
      experienceID: current.experienceID,
      packID: current.packID,
      contentVersion: current.contentVersion,
      policyVersion: current.policyVersion,
      createdAt: current.createdAt,
      expiresAt: current.expiresAt,
      completionState: current.completionState,
      completionEventID: current.completionEventID,
      createdUnlockSessionID: current.createdUnlockSessionID,
      abortReason: nil,
      enginePayloadSchemaID: "future.engine.v99",
      enginePayload: current.enginePayload)
    try await store.saveUnlockSessionEnvelope(future)

    let restored = try await UnlockChallengeSessionCoordinator(store: store).restore(
      at: bundle.challenge.createdAt.addingTimeInterval(1))
    let loaded = try await store.loadUnlockSessionEnvelope()
    let saved = try XCTUnwrap(loaded)
    XCTAssertNil(restored)
    XCTAssertEqual(saved.completionState, .aborted)
    XCTAssertEqual(saved.abortReason, "unsupported-envelope-schema")
  }

  func testPendingPreviewStoreScopesSameSchemaToPackAndRejectsTraversal() async throws {
    struct Preview: Codable, Equatable, Sendable { let itemID: String; let prompt: String }
    let store = PendingPreviewStore(rootURL: temporaryDirectory("pending-preview"))
    let english = Preview(itemID: "same", prompt: "English")
    let japanese = Preview(itemID: "same", prompt: "四字熟語")

    try await store.save(english, packID: "english3000.v1", schemaID: "flashcard.v1")
    try await store.save(japanese, packID: "yojijukugo.v1", schemaID: "flashcard.v1")

    let restoredEnglish = try await store.load(
      packID: "english3000.v1", schemaID: "flashcard.v1", as: Preview.self)
    let restoredJapanese = try await store.load(
      packID: "yojijukugo.v1", schemaID: "flashcard.v1", as: Preview.self)
    XCTAssertEqual(restoredEnglish, english)
    XCTAssertEqual(restoredJapanese, japanese)
    do {
      try await store.save(english, packID: "../escape", schemaID: "flashcard.v1")
      XCTFail("path traversal must be rejected")
    } catch let error as LearningDataStoreError {
      guard case .corrupted = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testPlatformMigrationV9SplitsPackRolesAndCopiesLegacyDataIdempotently() throws {
    let suiteName = "PlatformFoundationV9Tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacySettings = Data("legacy-settings".utf8)
    defaults.set("takken2026.v1", forKey: LockAndStudySharedConstants.Key.selectedPackID)
    defaults.set(true, forKey: "lockandstudy.experience.takken.first-run.completed")
    defaults.set(legacySettings, forKey: "lockandstudy.experience.takken.settings.v1")

    PlatformMigrationV9().run(defaults: defaults)

    for key in [
      LockAndStudySharedConstants.Key.activeUnlockPackID,
      LockAndStudySharedConstants.Key.openedPackID,
      LockAndStudySharedConstants.Key.lastStudiedPackID,
    ] {
      XCTAssertEqual(defaults.string(forKey: key), "takken2026.v1")
    }
    XCTAssertTrue(defaults.bool(forKey: "lockandstudy.pack.takken2026.v1.first-run.completed.v2"))
    XCTAssertEqual(
      defaults.data(forKey: "lockandstudy.pack.takken2026.v1.takken.settings.v2"),
      legacySettings)

    defaults.set("keep-existing", forKey: LockAndStudySharedConstants.Key.openedPackID)
    defaults.set(Data("new-settings".utf8),
      forKey: "lockandstudy.experience.takken.settings.v1")
    PlatformMigrationV9().run(defaults: defaults)
    XCTAssertEqual(
      defaults.string(forKey: LockAndStudySharedConstants.Key.openedPackID),
      "keep-existing")
    XCTAssertEqual(
      defaults.data(forKey: "lockandstudy.pack.takken2026.v1.takken.settings.v2"),
      legacySettings)
  }

  func testTakken2026And2027SettingsPreviewAndHistoryRemainPackScoped() async throws {
    let suiteName = "PlatformFoundationV9Tests.TakkenScope.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var settings2026 = TakkenSettings.standard
    settings2026.examYear = 2026
    settings2026.selectedCategories = ["宅建業法"]
    var settings2027 = TakkenSettings.standard
    settings2027.examYear = 2027
    settings2027.selectedCategories = ["権利関係"]
    try settings2026.save(packID: "takken2026.v1", defaults: defaults)
    try settings2027.save(packID: "takken2027.fixture.v1", defaults: defaults)
    XCTAssertEqual(
      TakkenSettings.load(packID: "takken2026.v1", defaults: defaults), settings2026)
    XCTAssertEqual(
      TakkenSettings.load(packID: "takken2027.fixture.v1", defaults: defaults), settings2027)

    let now = Date(timeIntervalSince1970: 10_000_000)
    let store = LearningDataStore(rootURL: temporaryDirectory("takken-edition-scope"))
    func preview(packID: StudyPackID, contentVersion: String) -> TakkenPendingPreview {
      .init(
        id: UUID(), packID: packID, sourceUnlockBundleID: UUID(),
        conceptID: "same-concept", sourceQuestionID: "same-item",
        preferredVariantID: nil, contentVersion: contentVersion, createdAt: now,
        recallExpiresAt: now.addingTimeInterval(3_600), confirmedAt: now,
        consumedAt: nil, foregroundExposureSeconds: 2)
    }
    let preview2026 = preview(packID: "takken2026.v1", contentVersion: "2026")
    let preview2027 = preview(packID: "takken2027.fixture.v1", contentVersion: "2027")
    try await store.saveTakkenPendingPreview(preview2026, for: preview2026.packID)
    try await store.saveTakkenPendingPreview(preview2027, for: preview2027.packID)
    let restoredPreview2026 = try await store.loadTakkenPendingPreview(
      for: preview2026.packID, now: now)
    let restoredPreview2027 = try await store.loadTakkenPendingPreview(
      for: preview2027.packID, now: now)
    XCTAssertEqual(restoredPreview2026, preview2026)
    XCTAssertEqual(restoredPreview2027, preview2027)

    func prompt(packID: StudyPackID, year: Int) -> StudyPrompt {
      .init(
        packID: packID, moduleType: .takken, itemID: "same-item", prompt: "共通IDの問題",
        choices: [.init(id: 0, text: "誤り"), .init(id: 1, text: "正しい")],
        correctChoiceID: 1, shortExplanation: "短い解説", longExplanation: "長い解説",
        sourceNote: nil, category: "fixture", subcategory: nil,
        contentVersion: "\(year)", questionVersion: 1, examYear: year,
        lawBasisDate: "\(year)-04-01", isFreeSample: true, speechText: nil,
        exampleText: nil)
    }
    _ = try await store.recordUnique(.init(
      prompt: prompt(packID: "takken2026.v1", year: 2026), selectedChoiceID: 1,
      answeredAt: now, mode: .practice, sessionID: UUID(), feedbackPlan: .immediate))
    _ = try await store.recordUnique(.init(
      prompt: prompt(packID: "takken2027.fixture.v1", year: 2027), selectedChoiceID: 0,
      answeredAt: now, mode: .practice, sessionID: UUID(), feedbackPlan: .relearn6))
    let progress2026 = try await store.progress(
      for: .init(packID: "takken2026.v1", itemID: "same-item"))
    let progress2027 = try await store.progress(
      for: .init(packID: "takken2027.fixture.v1", itemID: "same-item"))
    XCTAssertEqual(progress2026.correctCount, 1)
    XCTAssertEqual(progress2026.incorrectCount, 0)
    XCTAssertEqual(progress2027.correctCount, 0)
    XCTAssertEqual(progress2027.incorrectCount, 1)
  }

  @MainActor
  func testFixtureCatalogAddsYojijukugoTakken2027AndUnknownCategoryUsingExistingFactories()
    async throws
  {
    let repository = try fixtureRepository()
    let snapshot = try await repository.catalogSnapshot()
    XCTAssertEqual(
      Set(snapshot.categories.map(\.id)),
      ["language.japanese", "qualification", "life.manners"])
    XCTAssertEqual(
      Set(snapshot.series.map(\.id)),
      ["japanese.yojijukugo", "qualification.takken", "life.business-manners"])

    let yojijukugo = try XCTUnwrap(snapshot.packs.first { $0.id == "yojijukugo.fixture.v1" })
    let takken2027 = try XCTUnwrap(snapshot.packs.first { $0.id == "takken2027.fixture.v1" })
    let manners = try XCTUnwrap(snapshot.packs.first { $0.id == "business-manners.fixture.v1" })
    let registry = StudyExperienceRegistry.standard()
    XCTAssertEqual(registry.factory(for: yojijukugo)?.experienceID, .flashcardV1)
    XCTAssertEqual(registry.factory(for: takken2027)?.experienceID, .certificationV1)
    XCTAssertEqual(registry.factory(for: manners)?.experienceID, .certificationV1)
    let cards = try await repository.vocabularyPackage(for: yojijukugo.id)
    let cardPrompts = try await repository.prompts(for: yojijukugo.id)
    let certification = try await repository.takkenQuestions(for: takken2027.id)
    let mannersPrompts = try await repository.prompts(for: manners.id)
    XCTAssertEqual(cards.items.count, 6)
    XCTAssertEqual(cardPrompts.count, 6)
    XCTAssertEqual(certification.count, 3)
    XCTAssertEqual(mannersPrompts.count, 3)
    _ = CatalogTheme.color(for: "not-registered-in-swift")

    let releaseIDs = Set(try await ContentRepository(
      source: BundledContentSource(bundle: .main)).releasedManifests().map(\.id))
    let fixtureIDs = Set(snapshot.packs.map(\.id)).filter { $0.rawValue.contains("fixture") }
    XCTAssertTrue(releaseIDs.isDisjoint(with: fixtureIDs))
  }

  func testDynamicCommerceSeparatesTakkenEditionsArchivedSaleAndPassAccess() async throws {
    let snapshot = try await fixtureRepository().catalogSnapshot()
    let takken2027 = try XCTUnwrap(snapshot.packs.first { $0.id == "takken2027.fixture.v1" })
    let productID = try XCTUnwrap(takken2027.oneTimeProductID)
    let catalog = ProductCatalog(manifests: snapshot.packs, knownProductMappings: [:])

    XCTAssertTrue(catalog.purchasableProductIDs.contains(productID))
    XCTAssertEqual(catalog.packID(for: productID), takken2027.id)
    XCTAssertTrue(catalog.allIDs.contains(productID))
    XCTAssertTrue(catalog.allIDs.contains(ProductCatalog.monthlyPassProductID))
    XCTAssertTrue(catalog.allIDs.contains(ProductCatalog.yearlyPassProductID))

    let now = Date()
    let owned2026 = CommerceEntitlementSnapshot(
      activePass: nil,
      ownedPacks: [.init(
        packID: "takken2026.v1",
        productID: "com.ameneko.lockandstudy.pack.takken2026.v1",
        purchaseDate: now, ownershipType: .purchased, source: .appStore)],
      familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: now,
      cacheValidUntil: now.addingTimeInterval(3_600))
    XCTAssertFalse(ContentAccessService().decision(
      isFreeSample: false, manifest: takken2027, entitlement: owned2026, now: now).isAllowed)

    var passSnapshot = owned2026
    passSnapshot.activePass = .init(
      productID: ProductCatalog.monthlyPassProductID,
      expirationDate: now.addingTimeInterval(3_600), state: .active,
      ownershipType: .purchased)
    XCTAssertTrue(ContentAccessService().decision(
      isFreeSample: false, manifest: takken2027, entitlement: passSnapshot, now: now).isAllowed)

    let release2026 = try await manifest("takken2026.v1")
    var archivedObject = try encodedObject(release2026)
    archivedObject["releaseStatus"] = "retired"
    archivedObject["isEnabled"] = false
    archivedObject["saleReady"] = false
    archivedObject["storeState"] = "archivedOwnedOnly"
    archivedObject["passAccessPolicy"] = "excluded"
    let archived = try decodeManifest(archivedObject)
    let archivedCatalog = ProductCatalog(manifests: [archived], knownProductMappings: [:])
    let archivedProductID = try XCTUnwrap(archived.oneTimeProductID)
    XCTAssertFalse(archivedCatalog.purchasableProductIDs.contains(archivedProductID))
    XCTAssertTrue(archivedCatalog.allIDs.contains(archivedProductID))
    XCTAssertEqual(
      PackAvailabilityResolver().resolve(
        manifest: archived, appVersion: "1.0", now: now, isOwned: true,
        supportsExperience: true),
      .retiredOwned)
    XCTAssertEqual(
      PackAvailabilityResolver().resolve(
        manifest: archived, appVersion: "1.0", now: now, isOwned: false,
        supportsExperience: true),
      .retiredUnavailable)
  }

  func testInstalledPackageStagesValidatesFallsBackAndRollsBack() async throws {
    let fixture = try fixtureSource()
    let catalogData = try await fixture.catalogData()
    let snapshot = try StudyCatalogDecoder().decode(catalogData)
    let original = try XCTUnwrap(snapshot.packs.first { $0.id == "yojijukugo.fixture.v1" })
    let storeRoot = temporaryDirectory("installed-pack-store")
    let store = ContentPackageStore(rootURL: storeRoot, appVersion: "1.0")

    let installedV1 = try await store.stage(.init(
      manifest: original, sourceRootURL: fixture.root))
    try await store.activate(installedV1)
    let activeV1 = try await store.activePackage(for: original.id)
    XCTAssertEqual(activeV1?.contentVersion, "yojijukugo-1.0")

    var v2Object = try encodedObject(original)
    v2Object["contentVersion"] = "yojijukugo-1.1"
    let v2 = try decodeManifest(v2Object)
    let installedV2 = try await store.stage(.init(manifest: v2, sourceRootURL: fixture.root))
    try await store.activate(installedV2)
    let activeV2 = try await store.activePackage(for: original.id)
    XCTAssertEqual(activeV2?.contentVersion, "yojijukugo-1.1")
    try await store.rollback(packID: original.id)
    let rolledBack = try await store.activePackage(for: original.id)
    XCTAssertEqual(rolledBack?.contentVersion, "yojijukugo-1.0")

    let activeFile = installedV1.rootURL.appendingPathComponent("yojijukugo_items_v1.json")
    var damaged = try Data(contentsOf: activeFile)
    damaged.append(0)
    try damaged.write(to: activeFile, options: .atomic)
    let installedSource = InstalledContentSource(fallbackCatalogData: catalogData, store: store)
    let composite = CompositeContentSource([installedSource, fixture])
    let fallbackRepository = ContentRepository(source: composite)
    let fallbackCards = try await fallbackRepository.vocabularyPackage(for: original.id)
    XCTAssertEqual(fallbackCards.items.count, 6)

    var invalidObject = try encodedObject(original)
    invalidObject["contentVersion"] = "yojijukugo-1.2"
    let invalid = try decodeManifest(invalidObject)
    do {
      _ = try await store.stage(.init(manifest: invalid, sourceRootURL: installedV1.rootURL))
      XCTFail("hash mismatch must not be staged")
    } catch {}
    let activeAfterFailure = try await store.activePackage(for: original.id)
    XCTAssertEqual(activeAfterFailure?.contentVersion, "yojijukugo-1.0")
  }

  func testProgressMigrationDescriptorSupportsDefaultAndChangedItemPolicies() throws {
    let data = Data("""
      {
        "fromContentVersion": "2026.1",
        "toContentVersion": "2026.2",
        "defaultPolicy": "preserve",
        "itemMigrations": [
          {"oldItemID": "q001", "newItemID": "q001", "policy": "resetChangedItems"}
        ]
      }
      """.utf8)
    let document = try SharedJSON.decoder().decode(ProgressMigrationDocument.self, from: data)
    XCTAssertEqual(document.defaultPolicy, .preserve)
    XCTAssertEqual(document.itemMigrations.first?.policy, .resetChangedItems)
  }

  private func manifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let manifests = try await ContentRepository(
      source: BundledContentSource(bundle: .main)).releasedManifests()
    return try XCTUnwrap(manifests.first { $0.id == id })
  }

  private func encodedObject(_ manifest: StudyPackManifest) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(manifest))
        as? [String: Any])
  }

  private func decodeManifest(_ object: [String: Any]) throws -> StudyPackManifest {
    try SharedJSON.decoder().decode(
      StudyPackManifest.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("lockandstudy-v9-\(label)-\(UUID().uuidString)", isDirectory: true)
  }

  private func safeBundle(
    createdAt: Date = Date(timeIntervalSince1970: 8_000_000),
    expiresAt: Date? = nil
  ) -> ExperienceUnlockBundleSnapshot {
    let question = UnlockQuestionSnapshot.safeFallback(.init(
      id: "safe-1", prompt: "安全に学習を続けるには？",
      choices: [.init(id: 0, text: "少しずつ続ける"), .init(id: 1, text: "やめる")],
      correctChoiceID: 0, explanation: "少しずつ継続します。"))
    return .init(
      schemaVersion: 3,
      challenge: .init(
        schemaVersion: 3, id: UUID(), requestID: UUID(), origin: .manual,
        experienceID: .safeFallback, packID: "english3000.v1", policyVersion: 1,
        pace: .balanced10, reviewLoad: .standard, questions: [question],
        access: .init(packID: "english3000.v1", reason: .freeSample, verifiedAt: nil),
        createdAt: createdAt,
        expiresAt: expiresAt ?? createdAt.addingTimeInterval(1_800)),
      completedQuestionIDs: [], completionState: .answering,
      completionEventID: UUID(), createdUnlockSessionID: nil, abortReason: nil)
  }

  private func fixtureRepository() throws -> ContentRepository {
    ContentRepository(source: try fixtureSource())
  }

  private func fixtureSource() throws -> FixtureDirectoryContentSource {
    let bundle = Bundle(for: Self.self)
    let catalogURL = try XCTUnwrap(bundle.url(
      forResource: "study_pack_catalog_v9_fixtures", withExtension: "json"))
    let root = try XCTUnwrap(bundle.resourceURL)
    return .init(catalog: try Data(contentsOf: catalogURL), root: root)
  }
}

private struct FixtureDirectoryContentSource: ContentAssetSource {
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
