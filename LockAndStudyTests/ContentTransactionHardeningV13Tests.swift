import CryptoKit
import XCTest

@testable import LockAndStudy

final class ContentTransactionHardeningV13Tests: XCTestCase {
  func testInterruptedActivationRecoversAtEveryStage() async throws {
    let rollbackPoints: Set<ContentActivationFaultPoint> = [
      .afterJournalPrepared,
      .afterMigrationApplied,
      .beforePointerWrite,
    ]
    let points: [ContentActivationFaultPoint] = [
      .afterJournalPrepared,
      .afterMigrationApplied,
      .beforePointerWrite,
      .afterPointerWrite,
      .beforeJournalRemoval,
    ]

    for point in points {
      let roots = TransactionRoots(label: point.rawValue)
      let learning = LearningDataStore(rootURL: roots.learning)
      let setupStore = ContentPackageStore(rootURL: roots.packages, progressStore: learning)
      let base = try fixtureManifest("business-manners.fixture.v1")
      let v1 = try versionedManifest(base, version: "1.0")
      let sourceV1 = try packageSource(for: base, label: "\(point.rawValue)-v1")
      let installedV1 = try await setupStore.stage(
        .init(manifest: v1, sourceRootURL: sourceV1))
      try await setupStore.activate(installedV1)
      try await learning.record(answer(packID: base.id, itemID: "old"))

      let migration = ProgressMigrationDocument(
        packID: base.id,
        fromContentVersion: "1.0",
        toContentVersion: "2.0",
        itemMigrations: [
          .init(oldItemID: "old", newItemID: "new", policy: .migrate)
        ])
      let migrationData = try SharedJSON.encoder().encode(migration)
      let sourceV2 = try packageSource(
        for: base,
        label: "\(point.rawValue)-v2",
        migrationData: migrationData)
      let v2 = try versionedManifest(base, version: "2.0", migrationData: migrationData)
      let installedV2 = try await setupStore.stage(
        .init(manifest: v2, sourceRootURL: sourceV2))

      let faultingStore = ContentPackageStore(
        rootURL: roots.packages,
        progressStore: learning,
        faultInjector: .init(failAt: point))
      await assertThrowsAsyncV13 { try await faultingStore.activate(installedV2) }

      let recoveredLearning = LearningDataStore(rootURL: roots.learning)
      let recoveredStore = ContentPackageStore(
        rootURL: roots.packages,
        progressStore: recoveredLearning)
      try await recoveredStore.recoverInterruptedActivations()
      let active = try await recoveredStore.activePackage(for: base.id)
      let old = try await recoveredLearning.progress(
        for: .init(packID: base.id, itemID: "old"))
      let new = try await recoveredLearning.progress(
        for: .init(packID: base.id, itemID: "new"))

      if rollbackPoints.contains(point) {
        XCTAssertEqual(active?.contentVersion, "1.0", point.rawValue)
        XCTAssertEqual(old.answerCount, 1, point.rawValue)
        XCTAssertEqual(new.answerCount, 0, point.rawValue)
      } else {
        XCTAssertEqual(active?.contentVersion, "2.0", point.rawValue)
        XCTAssertEqual(old.answerCount, 0, point.rawValue)
        XCTAssertEqual(new.answerCount, 1, point.rawValue)
      }

      try await recoveredStore.recoverInterruptedActivations()
      let activeAfterSecondRecovery = try await recoveredStore.activePackage(for: base.id)
      XCTAssertEqual(
        activeAfterSecondRecovery?.contentVersion,
        active?.contentVersion,
        "recovery must be idempotent at \(point.rawValue)")
    }
  }

  func testRollbackCannotToggleForwardOnSecondCall() async throws {
    let roots = TransactionRoots(label: "one-way-rollback")
    let learning = LearningDataStore(rootURL: roots.learning)
    let store = ContentPackageStore(rootURL: roots.packages, progressStore: learning)
    let base = try fixtureManifest("business-manners.fixture.v1")
    let v1 = try versionedManifest(base, version: "1.0")
    let sourceV1 = try packageSource(for: base, label: "rollback-v1")
    try await store.activate(try await store.stage(.init(manifest: v1, sourceRootURL: sourceV1)))
    try await learning.record(answer(packID: base.id, itemID: "old"))

    let migration = ProgressMigrationDocument(
      packID: base.id,
      fromContentVersion: "1.0",
      toContentVersion: "2.0",
      itemMigrations: [.init(oldItemID: "old", newItemID: "new", policy: .migrate)])
    let migrationData = try SharedJSON.encoder().encode(migration)
    let sourceV2 = try packageSource(
      for: base, label: "rollback-v2", migrationData: migrationData)
    let v2 = try versionedManifest(base, version: "2.0", migrationData: migrationData)
    let installedV2 = try await store.stage(.init(manifest: v2, sourceRootURL: sourceV2))
    try await store.activate(installedV2)

    let pointerFaultStore = ContentPackageStore(
      rootURL: roots.packages,
      progressStore: learning,
      faultInjector: .init(failAt: .beforeRollbackPointerWrite))
    await assertThrowsAsyncV13 { try await pointerFaultStore.rollback(packID: base.id) }
    let activeAfterPointerFailure = try await pointerFaultStore.activePackage(for: base.id)
    XCTAssertEqual(activeAfterPointerFailure?.contentVersion, "2.0")
    try await assertProgress(learning, packID: base.id, itemID: "new", equals: 1)

    let cleanStore = ContentPackageStore(rootURL: roots.packages, progressStore: learning)
    try await cleanStore.rollback(packID: base.id)
    let activeAfterRollback = try await cleanStore.activePackage(for: base.id)
    XCTAssertEqual(activeAfterRollback?.contentVersion, "1.0")
    try await assertProgress(learning, packID: base.id, itemID: "old", equals: 1)
    await assertThrowsAsyncV13 { try await cleanStore.rollback(packID: base.id) }
    let activeAfterSecondRollback = try await cleanStore.activePackage(for: base.id)
    XCTAssertEqual(activeAfterSecondRollback?.contentVersion, "1.0")

    try await cleanStore.activate(installedV2)
    let activeAfterReactivation = try await cleanStore.activePackage(for: base.id)
    XCTAssertEqual(activeAfterReactivation?.contentVersion, "2.0")
    try await assertProgress(learning, packID: base.id, itemID: "new", equals: 1)
  }

  func testCertificationValidatorMatchesRuntimeDecoder() async throws {
    let accepted: [[String: Any]] = [
      certificationQuestion(correctID: "a", correctIndex: nil),
      certificationQuestion(correctID: nil, correctIndex: 0),
      certificationQuestion(correctID: "a", correctIndex: 0),
    ]
    for (index, question) in accepted.enumerated() {
      let package = try certificationPackage(question: question, label: "accepted-\(index)")
      let store = ContentPackageStore(rootURL: temporaryDirectory("cert-store-\(index)"))
      let staged = try await store.stage(
        .init(manifest: package.manifest, sourceRootURL: package.root))
      let runtime = try TakkenQuestionRepository(packageRoot: staged.rootURL)
        .load(manifest: package.manifest)
      XCTAssertEqual(runtime.count, 1)
      XCTAssertEqual(runtime[0].correctChoiceID, "a")
      XCTAssertEqual(runtime[0].correctIndex, 0)
    }

    let mismatch = certificationQuestion(correctID: "a", correctIndex: 1)
    let missingID = certificationQuestion(correctID: "missing", correctIndex: nil)
    var duplicateChoices = certificationQuestion(correctID: "a", correctIndex: nil)
    duplicateChoices["choices"] = [
      ["id": "a", "text": "正しい"],
      ["id": "a", "text": "誤り"],
    ]
    var correctRationale = certificationQuestion(correctID: "a", correctIndex: nil)
    correctRationale["wrongChoiceRationales"] = ["a": "正解へ誤答理由"]

    for (index, question) in [mismatch, missingID, duplicateChoices, correctRationale].enumerated()
    {
      let package = try certificationPackage(question: question, label: "rejected-\(index)")
      let store = ContentPackageStore(rootURL: temporaryDirectory("cert-reject-\(index)"))
      await assertThrowsAsyncV13 {
        _ = try await store.stage(.init(manifest: package.manifest, sourceRootURL: package.root))
      }
    }
  }

  func testDefaultProgressPoliciesApplyToUnmappedItems() async throws {
    let packID: StudyPackID = "progress-policy.v13"

    let preserveStore = LearningDataStore(rootURL: temporaryDirectory("policy-preserve"))
    try await seed(preserveStore, packID: packID, itemIDs: ["keep", "old", "changed"])
    let preserve = ProgressMigrationDocument(
      packID: packID,
      fromContentVersion: "1",
      toContentVersion: "2",
      defaultPolicy: .preserve,
      itemMigrations: [
        .init(oldItemID: "old", newItemID: "new", policy: .migrate),
        .init(oldItemID: "changed", newItemID: "changed", policy: .resetChangedItems),
      ])
    try await preserveStore.applyProgressMigration(preserve, documentDigest: "preserve")
    try await assertProgress(preserveStore, packID: packID, itemID: "keep", equals: 1)
    try await assertProgress(preserveStore, packID: packID, itemID: "new", equals: 1)
    try await assertProgress(preserveStore, packID: packID, itemID: "changed", equals: 0)
    try await preserveStore.applyProgressMigration(preserve, documentDigest: "preserve")
    try await assertProgress(preserveStore, packID: packID, itemID: "new", equals: 1)
    try await preserveStore.rollbackProgressMigration(
      packID: packID, fromContentVersion: "1", toContentVersion: "2")
    try await assertProgress(preserveStore, packID: packID, itemID: "old", equals: 1)
    try await assertProgress(preserveStore, packID: packID, itemID: "changed", equals: 1)

    let resetStore = LearningDataStore(rootURL: temporaryDirectory("policy-reset"))
    try await seed(resetStore, packID: packID, itemIDs: ["keep", "old", "unmapped"])
    let reset = ProgressMigrationDocument(
      packID: packID,
      fromContentVersion: "1",
      toContentVersion: "2",
      defaultPolicy: .resetChangedItems,
      itemMigrations: [
        .init(oldItemID: "keep", newItemID: "keep", policy: .preserve),
        .init(oldItemID: "old", newItemID: "new", policy: .migrate),
      ])
    try await resetStore.applyProgressMigration(reset, documentDigest: "reset")
    try await assertProgress(resetStore, packID: packID, itemID: "keep", equals: 1)
    try await assertProgress(resetStore, packID: packID, itemID: "new", equals: 1)
    try await assertProgress(resetStore, packID: packID, itemID: "unmapped", equals: 0)

    let migrateStore = LearningDataStore(rootURL: temporaryDirectory("policy-migrate"))
    try await seed(migrateStore, packID: packID, itemIDs: ["keep", "old"])
    let completeMigrate = ProgressMigrationDocument(
      packID: packID,
      fromContentVersion: "1",
      toContentVersion: "2",
      defaultPolicy: .migrate,
      itemMigrations: [
        .init(oldItemID: "keep", newItemID: "keep", policy: .preserve),
        .init(oldItemID: "old", newItemID: "new", policy: .migrate),
      ])
    try await migrateStore.applyProgressMigration(completeMigrate, documentDigest: "complete")
    try await assertProgress(migrateStore, packID: packID, itemID: "keep", equals: 1)
    try await assertProgress(migrateStore, packID: packID, itemID: "new", equals: 1)

    let incompleteStore = LearningDataStore(rootURL: temporaryDirectory("policy-incomplete"))
    try await seed(incompleteStore, packID: packID, itemIDs: ["keep", "missing"])
    let incomplete = ProgressMigrationDocument(
      packID: packID,
      fromContentVersion: "1",
      toContentVersion: "2",
      defaultPolicy: .migrate,
      itemMigrations: [
        .init(oldItemID: "keep", newItemID: "keep", policy: .preserve)
      ])
    await assertThrowsAsyncV13 {
      try await incompleteStore.applyProgressMigration(incomplete, documentDigest: "incomplete")
    }
    try await assertProgress(incompleteStore, packID: packID, itemID: "missing", equals: 1)
  }

  private struct TransactionRoots {
    let learning: URL
    let packages: URL

    init(label: String) {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "lockandstudy-v13-\(label)-\(UUID().uuidString)", isDirectory: true)
      learning = root.appendingPathComponent("Learning", isDirectory: true)
      packages = root.appendingPathComponent("Packages", isDirectory: true)
    }
  }

  private func fixtureCatalog() throws -> StudyCatalogSnapshot {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(
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
      let destination = root.appendingPathComponent(descriptor.path)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(
        at: bundleRoot.appendingPathComponent(descriptor.path),
        to: destination)
    }
    if let migrationData {
      try migrationData.write(
        to: root.appendingPathComponent("progress-migration-v1.json"), options: .atomic)
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

  private func certificationQuestion(
    correctID: String?,
    correctIndex: Int?
  ) -> [String: Any] {
    var value: [String: Any] = [
      "id": UUID().uuidString,
      "category": "資格試験",
      "difficulty": "基礎",
      "format": "true_false",
      "prompt": "正しいものを選んでください。",
      "choices": [
        ["id": "a", "text": "正しい"],
        ["id": "b", "text": "誤り", "rationale": "規則と異なります。"],
      ],
      "explanation": "正解を説明します。",
      "reviewStatus": "checked",
      "isPlaceholder": false,
    ]
    if let correctID { value["correctChoiceID"] = correctID }
    if let correctIndex { value["correctIndex"] = correctIndex }
    return value
  }

  private func certificationPackage(
    question: [String: Any],
    label: String
  ) throws -> (manifest: StudyPackManifest, root: URL) {
    let data = try JSONSerialization.data(withJSONObject: [question], options: [.sortedKeys])
    let root = temporaryDirectory("certification-\(label)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let path = "questions.json"
    try data.write(to: root.appendingPathComponent(path), options: .atomic)

    let base = try fixtureManifest("business-manners.fixture.v1")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(base))
        as? [String: Any])
    object["id"] = "certification.\(label).v13"
    object["contentVersion"] = "v13-\(label)"
    object["expectedItemCount"] = 1
    object["experienceID"] = "certification.v1"
    object["experienceType"] = "certification.v1"
    let descriptor: [String: Any] = [
      "path": path,
      "sha256": sha256(data),
      "itemCount": 1,
      "byteCount": data.count,
    ]
    object["contentFiles"] = [descriptor]
    object["components"] = [
      [
        "id": "questions",
        "title": "資格問題",
        "experienceID": "certification.v1",
        "contentSchemaID": "certification.questions.v1",
        "sortOrder": 0,
        "contentFiles": [descriptor],
      ]
    ]
    let manifest = try SharedJSON.decoder().decode(
      StudyPackManifest.self,
      from: JSONSerialization.data(withJSONObject: object))
    return (manifest, root)
  }

  private func seed(
    _ store: LearningDataStore,
    packID: StudyPackID,
    itemIDs: [StudyItemID]
  ) async throws {
    for itemID in itemIDs {
      try await store.record(answer(packID: packID, itemID: itemID))
    }
  }

  private func progressCount(
    _ store: LearningDataStore,
    _ packID: StudyPackID,
    _ itemID: StudyItemID
  ) async throws -> Int {
    try await store.progress(for: .init(packID: packID, itemID: itemID)).answerCount
  }

  private func assertProgress(
    _ store: LearningDataStore,
    packID: StudyPackID,
    itemID: StudyItemID,
    equals expected: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let actual = try await progressCount(store, packID, itemID)
    XCTAssertEqual(actual, expected, file: file, line: line)
  }

  private func answer(packID: StudyPackID, itemID: StudyItemID) -> StudyAnswerRecord {
    .init(
      submissionID: UUID().uuidString,
      experienceID: .certificationV1,
      packID: packID,
      moduleType: .takken,
      itemID: itemID,
      prompt: "v13 transaction test",
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
      "lockandstudy-v13-\(label)-\(UUID().uuidString)", isDirectory: true)
  }
}

private func assertThrowsAsyncV13(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected error", file: file, line: line)
  } catch {}
}
