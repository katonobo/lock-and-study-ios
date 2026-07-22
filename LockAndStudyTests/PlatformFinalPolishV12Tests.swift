import CryptoKit
import XCTest

@testable import LockAndStudy

final class PlatformFinalPolishV12Tests: XCTestCase {
  @MainActor
  func testSafeFallbackOnlyCatalogUsesRecoveryStateAndNeverBecomesNormalMaterial() async throws {
    let root = temporaryDirectory("safe-only-root")
    let fallbackData = try await SafeFallbackContentSource().catalogData()
    let dependencies = DependencyContainer(
      learningRootURL: root,
      catalogDataOverride: fallbackData)
    let model = AppModel(dependencies: dependencies)

    await model.start()

    XCTAssertTrue(model.catalogRecoveryRequired)
    XCTAssertTrue(model.normalManifests.isEmpty)
    XCTAssertTrue(model.onboardingPackCandidates.isEmpty)
    XCTAssertNil(model.activeExperience)
    XCTAssertNotNil(RootView.self)
  }

  @MainActor
  func testShieldRecoveryCanStillCreateSafeFallbackChallenge() async throws {
    let root = temporaryDirectory("shield-safe-root")
    let fallbackData = try await SafeFallbackContentSource().catalogData()
    let dependencies = DependencyContainer(
      learningRootURL: root,
      catalogDataOverride: fallbackData)
    let model = AppModel(dependencies: dependencies)
    await model.start()

    await model.beginUnlockStudy(origin: .shield, forceSafeFallback: true)

    let envelope = try XCTUnwrap(model.unlockChallenge)
    XCTAssertEqual(envelope.packID, "safe-fallback.v1")
    XCTAssertEqual(envelope.experienceID, .safeFallbackV1)
    XCTAssertEqual(envelope.origin, .shield)
  }

  @MainActor
  func testOnboardingWithoutEnglishUsesAvailablePackAndCatalogPresentation() async throws {
    let snapshot = try fixtureCatalog()
    let custom = try XCTUnwrap(snapshot.packs.first { $0.id == "business-manners.fixture.v1" })
    let category = try XCTUnwrap(snapshot.categories.first { $0.id == custom.categoryID })
    let descriptor = StudyExperienceDescriptor(
      id: .init(rawValue: "custom.manners.v1"),
      title: "Custom",
      subtitle: "Custom experience",
      systemImage: "person.2.wave.2.fill",
      tintName: "green",
      supportedExperienceTypes: [.init(rawValue: "custom.manners.v1")])

    XCTAssertEqual(
      OnboardingPackSelector.initialSelection(
        saved: "english3000.v1",
        candidates: [custom]),
      custom.id)
    let presentation = OnboardingPackPresentation(
      manifest: custom,
      category: category,
      descriptor: descriptor)
    XCTAssertEqual(presentation.title, custom.title)
    XCTAssertEqual(presentation.systemImage, "person.2.wave.2.fill")
    XCTAssertEqual(presentation.themeToken, category.themeToken)
  }

  func testCreditsAreCatalogDrivenAndMissingCreditsFileIsSafe() async throws {
    let repository = ContentRepository(source: BundledContentSource(bundle: .main))
    let manifests = try await repository.releasedManifests()
    let values = await ContentCreditsLoader().load(manifests: manifests, content: repository)

    let takken = try XCTUnwrap(values.first { $0.id == "takken2026.v1" })
    XCTAssertEqual(takken.title, "宅建2026")
    XCTAssertEqual(takken.editionYear, 2026)
    XCTAssertEqual(takken.contentVersion, "takken-2026-free-v1")
    XCTAssertEqual(takken.lawBasisDate, "2026-04-01")
    XCTAssertFalse(takken.creditsLoadFailed)

    let custom = try XCTUnwrap(fixtureCatalog().packs.first {
      $0.id == "business-manners.fixture.v1"
    })
    XCTAssertNil(custom.creditsFile)
    let noCredits = await ContentCreditsLoader().load(
      manifests: [custom],
      content: ContentRepository(source: BundledContentSource(bundle: .main)))
    XCTAssertEqual(noCredits.first?.creditsText, "この教材には個別の出典ファイルが登録されていません。")
  }

  func testCustomBinarySchemaRequiresRegistrationWithoutCoreSwitch() async throws {
    let root = temporaryDirectory("binary-source")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
    try binary.write(to: root.appendingPathComponent("lesson.bin"), options: .atomic)
    let manifest = try customBinaryManifest(data: binary)

    let rejectingStore = ContentPackageStore(rootURL: temporaryDirectory("binary-reject"))
    await XCTAssertThrowsErrorAsync {
      _ = try await rejectingStore.stage(.init(manifest: manifest, sourceRootURL: root))
    }

    let registry = ContentFileValidatorRegistry(validators: [
      OpaqueBinaryContentValidator(
        schemaID: "custom.binary.v1",
        minimumByteCount: 4,
        allowedPathExtensions: ["bin"])
    ])
    let acceptingStore = ContentPackageStore(
      rootURL: temporaryDirectory("binary-accept"),
      validatorRegistry: registry)
    let staged = try await acceptingStore.stage(.init(manifest: manifest, sourceRootURL: root))
    XCTAssertEqual(staged.packID, manifest.id)
  }

  func testProgressMigrationPreservesMigratesResetsIsIdempotentAndRollsBack() async throws {
    let learningRoot = temporaryDirectory("migration-learning")
    let learning = LearningDataStore(rootURL: learningRoot)
    let packageStore = ContentPackageStore(
      rootURL: temporaryDirectory("migration-packages"),
      progressStore: learning)
    let base = try fixtureManifest("business-manners.fixture.v1")
    let sourceV1 = try packageSource(for: base, label: "migration-v1")
    let v1 = try versionedManifest(base, version: "1.0")
    let installedV1 = try await packageStore.stage(.init(manifest: v1, sourceRootURL: sourceV1))
    try await packageStore.activate(installedV1)

    for itemID in ["keep", "old", "changed"] as [StudyItemID] {
      try await learning.record(answer(packID: base.id, itemID: itemID))
    }
    let answersBefore = try await learning.answers()
    let originalOld = try await learning.progress(for: .init(packID: base.id, itemID: "old"))

    let migration = ProgressMigrationDocument(
      packID: base.id,
      fromContentVersion: "1.0",
      toContentVersion: "2.0",
      defaultPolicy: .preserve,
      itemMigrations: [
        .init(oldItemID: "old", newItemID: "new", policy: .migrate),
        .init(oldItemID: "changed", newItemID: "changed", policy: .resetChangedItems),
      ])
    let migrationData = try SharedJSON.encoder().encode(migration)
    let sourceV2 = try packageSource(
      for: base,
      label: "migration-v2",
      migrationData: migrationData)
    let v2 = try versionedManifest(
      base,
      version: "2.0",
      migrationData: migrationData)
    let installedV2 = try await packageStore.stage(.init(manifest: v2, sourceRootURL: sourceV2))
    try await packageStore.activate(installedV2)

    let preserved = try await learning.progress(for: .init(packID: base.id, itemID: "keep"))
    XCTAssertEqual(preserved.answerCount, 1)
    let migrated = try await learning.progress(for: .init(packID: base.id, itemID: "new"))
    XCTAssertEqual(migrated.answerCount, originalOld.answerCount)
    XCTAssertEqual(migrated.id.itemID, "new")
    let removedOld = try await learning.progress(for: .init(packID: base.id, itemID: "old"))
    let resetChanged = try await learning.progress(for: .init(packID: base.id, itemID: "changed"))
    let answersAfter = try await learning.answers()
    XCTAssertEqual(removedOld.answerCount, 0)
    XCTAssertEqual(resetChanged.answerCount, 0)
    XCTAssertEqual(answersAfter, answersBefore)

    let digest = sha256(migrationData)
    try await learning.applyProgressMigration(migration, documentDigest: digest)
    let migratedAgain = try await learning.progress(for: .init(packID: base.id, itemID: "new"))
    XCTAssertEqual(migratedAgain, migrated)

    try await packageStore.rollback(packID: base.id)
    let activeAfterRollback = try await packageStore.activePackage(for: base.id)
    let restoredOld = try await learning.progress(for: .init(packID: base.id, itemID: "old"))
    let restoredChanged = try await learning.progress(
      for: .init(packID: base.id, itemID: "changed"))
    XCTAssertEqual(activeAfterRollback?.contentVersion, "1.0")
    XCTAssertEqual(restoredOld, originalOld)
    XCTAssertEqual(restoredChanged.answerCount, 1)
  }

  func testMigrationFailureKeepsOldActivePackage() async throws {
    let learning = LearningDataStore(rootURL: temporaryDirectory("migration-failure-learning"))
    let store = ContentPackageStore(
      rootURL: temporaryDirectory("migration-failure-packages"),
      progressStore: learning)
    let base = try fixtureManifest("business-manners.fixture.v1")
    let sourceV1 = try packageSource(for: base, label: "failure-v1")
    let v1 = try versionedManifest(base, version: "1.0")
    try await store.activate(try await store.stage(.init(manifest: v1, sourceRootURL: sourceV1)))

    let document = ProgressMigrationDocument(
      packID: base.id,
      fromContentVersion: "wrong-from",
      toContentVersion: "2.0",
      itemMigrations: [])
    let data = try SharedJSON.encoder().encode(document)
    let sourceV2 = try packageSource(for: base, label: "failure-v2", migrationData: data)
    let v2 = try versionedManifest(base, version: "2.0", migrationData: data)
    let stagedV2 = try await store.stage(.init(manifest: v2, sourceRootURL: sourceV2))

    await XCTAssertThrowsErrorAsync { try await store.activate(stagedV2) }
    let active = try await store.activePackage(for: base.id)
    XCTAssertEqual(active?.contentVersion, "1.0")
  }

  private func fixtureCatalog() throws -> StudyCatalogSnapshot {
    let bundle = Bundle(for: Self.self)
    let url = try XCTUnwrap(bundle.url(
      forResource: "study_pack_catalog_v9_fixtures", withExtension: "json"))
    return try StudyCatalogDecoder().decode(Data(contentsOf: url))
  }

  private func fixtureManifest(_ id: StudyPackID) throws -> StudyPackManifest {
    try XCTUnwrap(fixtureCatalog().packs.first { $0.id == id })
  }

  private func packageSource(
    for manifest: StudyPackManifest,
    label: String,
    migrationData: Data? = nil
  ) throws -> URL {
    let root = temporaryDirectory(label)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bundleRoot = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
    for descriptor in manifest.contentFiles {
      try FileManager.default.copyItem(
        at: bundleRoot.appendingPathComponent(descriptor.path),
        to: root.appendingPathComponent(descriptor.path))
    }
    if let migrationData {
      try migrationData.write(to: root.appendingPathComponent("progress-migration-v1.json"))
    }
    return root
  }

  private func versionedManifest(
    _ manifest: StudyPackManifest,
    version: String,
    migrationData: Data? = nil
  ) throws -> StudyPackManifest {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(manifest))
        as? [String: Any])
    object["contentVersion"] = version
    if let migrationData {
      object["progressMigrationFile"] = "progress-migration-v1.json"
      object["progressMigrationSHA256"] = sha256(migrationData)
    } else {
      object.removeValue(forKey: "progressMigrationFile")
      object.removeValue(forKey: "progressMigrationSHA256")
    }
    return try SharedJSON.decoder().decode(
      StudyPackManifest.self,
      from: JSONSerialization.data(withJSONObject: object))
  }

  private func customBinaryManifest(data: Data) throws -> StudyPackManifest {
    let base = try fixtureManifest("business-manners.fixture.v1")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(base))
        as? [String: Any])
    object["id"] = "custom.binary.fixture.v1"
    object["contentVersion"] = "binary-1.0"
    let descriptor: [String: Any] = [
      "path": "lesson.bin",
      "sha256": sha256(data),
      "itemCount": 0,
      "byteCount": data.count,
    ]
    var components = try XCTUnwrap(object["components"] as? [[String: Any]])
    components[0]["contentSchemaID"] = "custom.binary.v1"
    components[0]["contentFiles"] = [descriptor]
    object["components"] = components
    object["contentFiles"] = [descriptor]
    return try SharedJSON.decoder().decode(
      StudyPackManifest.self,
      from: JSONSerialization.data(withJSONObject: object))
  }

  private func answer(packID: StudyPackID, itemID: StudyItemID) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString,
      experienceID: .certificationV1,
      packID: packID,
      moduleType: .takken,
      itemID: itemID,
      prompt: "進捗移行テスト",
      choices: [.init(id: 0, text: "正解"), .init(id: 1, text: "誤り")],
      selectedChoiceID: 0,
      correctChoiceID: 0,
      shortExplanation: "説明",
      longExplanation: "説明",
      sourceNote: nil,
      category: "テスト",
      subcategory: nil,
      contentVersion: "1.0",
      questionVersion: 1,
      examYear: nil,
      lawBasisDate: nil,
      answeredAt: Date(),
      mode: .practice,
      sessionID: UUID(),
      feedbackPlan: .immediate)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-v12-\(label)-\(UUID().uuidString)", isDirectory: true)
  }
}

private func XCTAssertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected error", file: file, line: line)
  } catch {}
}
