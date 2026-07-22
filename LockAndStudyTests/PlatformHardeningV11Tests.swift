import XCTest

@testable import LockAndStudy

@MainActor
final class PlatformHardeningV11Tests: XCTestCase {
  func testUnlockRestorationRejectsEveryManifestRuntimeAndVersionMismatch() async throws {
    let manifest = try await fixtureManifest("yojijukugo.fixture.v1")
    let otherManifest = try await fixtureManifest("business-manners.fixture.v1")
    let validator = UnlockSessionRestorationValidator()
    let flashcard = FlashcardExperience()
    let certification = CertificationExperience()
    let valid = envelope(
      packID: manifest.id,
      experienceID: flashcard.experienceID,
      contentVersion: manifest.contentVersion,
      payloadSchemaID: FlashcardUnlockSessionPayload.schemaID)

    XCTAssertEqual(validator.failureReason(
      envelope: valid, manifest: nil, runtime: flashcard, availability: nil), .manifestMissing)
    XCTAssertEqual(validator.failureReason(
      envelope: valid, manifest: otherManifest, runtime: flashcard, availability: .available),
      .manifestPackMismatch)
    XCTAssertEqual(validator.failureReason(
      envelope: valid, manifest: manifest, runtime: flashcard,
      availability: .retiredUnavailable), .manifestUnavailable)

    let wrongExperience = envelope(
      packID: manifest.id,
      experienceID: certification.experienceID,
      contentVersion: manifest.contentVersion,
      payloadSchemaID: CertificationUnlockSessionPayload.schemaID)
    XCTAssertEqual(validator.failureReason(
      envelope: wrongExperience, manifest: manifest, runtime: certification,
      availability: .available), .experienceMismatch)
    XCTAssertEqual(validator.failureReason(
      envelope: valid, manifest: manifest, runtime: nil, availability: .available),
      .runtimeMissing)

    let unknownSchema = envelope(
      packID: manifest.id,
      experienceID: flashcard.experienceID,
      contentVersion: manifest.contentVersion,
      payloadSchemaID: "future.flashcard.payload.v99")
    XCTAssertEqual(validator.failureReason(
      envelope: unknownSchema, manifest: manifest, runtime: flashcard,
      availability: .available), .payloadSchemaUnsupported)

    let changedContent = envelope(
      packID: manifest.id,
      experienceID: flashcard.experienceID,
      contentVersion: "incompatible-content-version",
      payloadSchemaID: FlashcardUnlockSessionPayload.schemaID)
    XCTAssertEqual(validator.failureReason(
      envelope: changedContent, manifest: manifest, runtime: flashcard,
      availability: .available), .contentVersionIncompatible)
    XCTAssertNil(validator.failureReason(
      envelope: valid, manifest: manifest, runtime: flashcard, availability: .available))
  }

  func testMissingSavedPackIsAbortedAndShowsRecoveryWithoutCreatingUnlock() async throws {
    let defaults = LockAndStudySharedConstants.defaults
    let key = LockAndStudySharedConstants.Key.onboardingCompleted
    let previous = defaults.object(forKey: key)
    defer {
      if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    defaults.set(true, forKey: key)

    let root = temporaryDirectory("missing-pack-recovery")
    let dependencies = DependencyContainer(
      learningRootURL: root,
      catalogDataOverride: try fixtureCatalogData())
    let missing = envelope(
      packID: "removed-pack.v1",
      experienceID: .flashcardV1,
      contentVersion: "removed-1.0",
      payloadSchemaID: FlashcardUnlockSessionPayload.schemaID)
    try await dependencies.learning.saveUnlockSessionEnvelope(missing)

    let model = AppModel(dependencies: dependencies)
    await model.start()

    let restoredEnvelope = try await dependencies.learning.loadUnlockSessionEnvelope()
    let stored = try XCTUnwrap(restoredEnvelope)
    XCTAssertEqual(stored.completionState, .aborted)
    XCTAssertEqual(stored.abortReason, UnlockRecoveryReason.manifestMissing.rawValue)
    XCTAssertEqual(model.unlockRecovery?.reason, .manifestMissing)
    XCTAssertNil(model.unlockChallenge)
    XCTAssertNil(dependencies.lockController.unlockUntil)
  }

  func testSavedExperienceSchemaAndContentMismatchesAreAllAborted() async throws {
    let manifest = try await fixtureManifest("yojijukugo.fixture.v1")
    let cases: [(UnlockChallengeSessionEnvelope, UnlockRecoveryReason)] = [
      (
        envelope(
          packID: manifest.id,
          experienceID: .certificationV1,
          contentVersion: manifest.contentVersion,
          payloadSchemaID: CertificationUnlockSessionPayload.schemaID),
        .experienceMismatch
      ),
      (
        envelope(
          packID: manifest.id,
          experienceID: .init(rawValue: "missing.runtime.v1"),
          contentVersion: manifest.contentVersion,
          payloadSchemaID: "missing.runtime.payload.v1"),
        .runtimeMissing
      ),
      (
        envelope(
          packID: manifest.id,
          experienceID: .flashcardV1,
          contentVersion: manifest.contentVersion,
          payloadSchemaID: "future.flashcard.payload.v99"),
        .payloadSchemaUnsupported
      ),
      (
        envelope(
          packID: manifest.id,
          experienceID: .flashcardV1,
          contentVersion: "incompatible-content-version",
          payloadSchemaID: FlashcardUnlockSessionPayload.schemaID),
        .contentVersionIncompatible
      ),
    ]
    for (saved, expected) in cases {
      try await assertAppModelRecovery(saved, expected: expected)
    }
  }

  func testFlashcardEmptyCopyAndPreviewExamplesAreProfileDriven() async throws {
    let yojijukugo = try await fixtureManifest("yojijukugo.fixture.v1")
    let dependencies = DependencyContainer(
      learningRootURL: temporaryDirectory("flashcard-copy"),
      contentSource: try fixtureSource())
    let context = StudyExperienceContext(
      manifest: yojijukugo,
      dependencies: dependencies,
      reportProviders: [VocabularyReportProvider()],
      destination: .home,
      openMaterialSelection: {},
      beginUnlockStudy: {},
      completeFirstRun: {})
    let model = VocabularyAppModel(context: context)
    let messages = [
      model.emptyStateMessage(for: .review),
      model.emptyStateMessage(for: .mistakes),
      model.emptyStateMessage(for: .weakness),
      model.emptyStateMessage(for: .newItems),
      model.emptyStateMessage(for: .practice),
    ]
    for message in messages {
      for forbidden in ["英単語", "単語", "中学1年", "高校基礎"] {
        XCTAssertFalse(message.contains(forbidden), "\(message) contains \(forbidden)")
      }
    }
    model.settings.examplesEnabled = true
    XCTAssertFalse(model.pendingPreviewExamplesEnabled)

    let english = try await bundledManifest("english3000.v1")
    XCTAssertEqual(
      english.flashcardPresentation.resolvedEmptyStateCopy.noWeakItems,
      "苦手として判定された単語はまだありません。")
    XCTAssertEqual(
      english.flashcardPresentation.resolvedEmptyStateCopy.noNewItems,
      "このコースの新出単語は一巡しました。期限到来復習を続けられます。")
  }

  func testGlobalCatalogErrorsRollbackWhilePackLocalErrorIsIsolated() async throws {
    let good = try fixtureCatalogData()
    let source = MutableV11ContentSource(data: good, root: try fixtureRoot())
    let repository = ContentRepository(source: source)
    let original = try await repository.catalogSnapshot()

    for mutation in [duplicateCategory, duplicateSeries, categoryCycle] {
      await source.replace(with: try mutation(good))
      let rolledBack = try await repository.reloadCatalog()
      XCTAssertEqual(rolledBack, original)
      let diagnostics = await repository.catalogDiagnostics()
      XCTAssertTrue(diagnostics.contains(where: \.isGlobalFatal))
    }

    let localData = try packLocalFailure(good, packID: "yojijukugo.fixture.v1")
    let local = try await ContentRepository(
      source: V11FixtureContentSource(catalog: localData, root: try fixtureRoot()))
      .catalogSnapshot()
    XCTAssertFalse(local.packs.contains { $0.id == "yojijukugo.fixture.v1" })
    XCTAssertTrue(local.packs.contains { $0.id == "business-manners.fixture.v1" })
  }

  func testPersistedLastKnownGoodSurvivesColdLaunchAndCorruptionFallsBack() async throws {
    let root = temporaryDirectory("catalog-lkg")
    let store = ValidatedCatalogStore(rootURL: root)
    let good = try fixtureCatalogData()
    let fixtureRoot = try fixtureRoot()
    let original = try await ContentRepository(
      source: V11FixtureContentSource(catalog: good, root: fixtureRoot),
      validatedCatalogStore: store).catalogSnapshot()
    let metadata = await store.metadata()
    XCTAssertNotNil(metadata)

    let broken = V11FixtureContentSource(
      catalog: Data("{\"schemaVersion\":99}".utf8), root: fixtureRoot)
    let cold = try await ContentRepository(
      source: broken,
      validatedCatalogStore: ValidatedCatalogStore(rootURL: root)).catalogSnapshot()
    XCTAssertEqual(cold, original)

    try Data("corrupt persisted catalog".utf8).write(to: store.primaryURL, options: .atomic)
    let fallbackSource = CompositeContentSource([
      broken,
      V11FixtureContentSource(catalog: good, root: fixtureRoot),
      SafeFallbackContentSource(),
    ])
    let bundledFallback = try await ContentRepository(
      source: fallbackSource,
      validatedCatalogStore: ValidatedCatalogStore(rootURL: root)).catalogSnapshot()
    XCTAssertEqual(bundledFallback, original)
  }

  func testAllInvalidCatalogCandidatesUseOnlySafeFallback() async throws {
    let invalid = V11FixtureContentSource(
      catalog: Data("{\"schemaVersion\":99}".utf8), root: try fixtureRoot())
    let snapshot = try await ContentRepository(
      source: CompositeContentSource([invalid, SafeFallbackContentSource()]))
      .catalogSnapshot()
    XCTAssertEqual(snapshot.packs.map(\.id), ["safe-fallback.v1"])
  }

  func testSafeFallbackAnswersDoNotMutateProgressOrNormalReport() async throws {
    let root = temporaryDirectory("safe-report")
    let dependencies = DependencyContainer(learningRootURL: root)
    let manifest = try SafeFallbackContentSource.builtInManifest()
    let runtime = SafeFallbackExperience()
    let now = Date()
    let payload = try await runtime.createSession(request: .init(
      requestID: UUID(),
      origin: .shield,
      policy: .initial(now: now),
      manifest: manifest,
      entitlement: .empty,
      progress: [:],
      learning: dependencies.learning,
      content: dependencies.content,
      now: now))
    var challenge = envelope(
      packID: manifest.id,
      experienceID: runtime.experienceID,
      contentVersion: manifest.contentVersion,
      payloadSchemaID: payload.schemaID,
      payload: payload.data,
      origin: .shield)
    let state = try SharedJSON.decoder().decode(
      SafeFallbackSessionPayload.self, from: challenge.enginePayload)
    let question = try XCTUnwrap(state.questions.first)
    let transition = try await runtime.acceptAnswer(
      .choice(
        questionID: question.id.rawValue,
        choiceID: String(question.correctChoiceID)),
      envelope: challenge,
      dependencies: dependencies)
    challenge.enginePayload = transition.payload.data
    try await dependencies.learning.record(.init(
      kind: .unlockSuccess,
      occurredAt: now,
      packID: manifest.id,
      sessionID: challenge.id,
      unlockOrigin: .shield))

    let answers = try await dependencies.learning.answers()
    XCTAssertEqual(answers.count, 1)
    XCTAssertTrue(try XCTUnwrap(answers.first).isSafeFallback)
    let progress = try await dependencies.learning.allProgress()
    XCTAssertTrue(progress.isEmpty)
    var legacyFallbackProgress = ItemProgress.initial(.init(
      packID: "english3000.v1", itemID: "safe-1"))
    legacyFallbackProgress.answerCount = 4
    legacyFallbackProgress.incorrectCount = 2
    XCTAssertTrue(legacyFallbackProgress.isSafeFallbackArtifact)
    let report = try LearningReportService(providers: []).makeReport(
      snapshot: .init(
        answers: answers,
        events: try await dependencies.learning.events(),
        progress: progress,
        manifests: [manifest],
        entitlement: .empty),
      scope: .allMaterials,
      now: now,
      calendar: Calendar(identifier: .gregorian))
    XCTAssertEqual(report.answerCount, 0)
    XCTAssertEqual(report.uniqueItemCount, 0)
    XCTAssertEqual(report.safeFallbackUnlockCount, 1)
  }

  func testArchivedPackIsOwnedOnlyEvenWithActivePass() async throws {
    let fixture = try await ContentRepository(source: try fixtureSource()).catalogSnapshot()
    let archived = try XCTUnwrap(fixture.packs.first { $0.storeState == .archivedOwnedOnly })
    XCTAssertEqual(archived.storeState, .archivedOwnedOnly)
    let now = Date()
    let passOnly = CommerceEntitlementSnapshot(
      activePass: .init(
        productID: ProductCatalog.monthlyPassProductID,
        expirationDate: now.addingTimeInterval(3_600),
        state: .active,
        ownershipType: .purchased),
      ownedPacks: [], familySharedProductIDs: [], legacyGrants: [],
      lastVerifiedAt: now, cacheValidUntil: now.addingTimeInterval(3_600))
    XCTAssertFalse(ContentAccessService().decision(
      isFreeSample: false, manifest: archived, entitlement: passOnly, now: now).isAllowed)
    XCTAssertEqual(PackAvailabilityResolver().resolve(
      manifest: archived, appVersion: "1.0", now: now, isOwned: false,
      supportsExperience: true), .retiredUnavailable)

    var owned = passOnly
    owned.ownedPacks = [.init(
      packID: archived.id,
      productID: archived.oneTimeProductID ?? "historical",
      purchaseDate: now,
      ownershipType: .purchased,
      source: .appStore)]
    XCTAssertTrue(ContentAccessService().decision(
      isFreeSample: false, manifest: archived, entitlement: owned, now: now).isAllowed)
    XCTAssertEqual(PackAvailabilityResolver().resolve(
      manifest: archived, appVersion: "1.0", now: now, isOwned: true,
      supportsExperience: true), .retiredOwned)
  }

  private func envelope(
    packID: StudyPackID,
    experienceID: StudyExperienceID,
    contentVersion: String,
    payloadSchemaID: String,
    payload: Data = Data(),
    origin: UnlockChallengeOrigin = .manual
  ) -> UnlockChallengeSessionEnvelope {
    let now = Date()
    return .init(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
      id: UUID(), requestID: UUID(), origin: origin,
      experienceID: experienceID, packID: packID,
      contentVersion: contentVersion, policyVersion: 1,
      createdAt: now, expiresAt: now.addingTimeInterval(1_800),
      completionState: .answering, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil,
      enginePayloadSchemaID: payloadSchemaID, enginePayload: payload)
  }

  private func assertAppModelRecovery(
    _ envelope: UnlockChallengeSessionEnvelope,
    expected: UnlockRecoveryReason
  ) async throws {
    let defaults = LockAndStudySharedConstants.defaults
    let key = LockAndStudySharedConstants.Key.onboardingCompleted
    let previous = defaults.object(forKey: key)
    defer {
      if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    defaults.set(true, forKey: key)
    let dependencies = DependencyContainer(
      learningRootURL: temporaryDirectory(expected.rawValue),
      catalogDataOverride: try fixtureCatalogData())
    try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
    let model = AppModel(dependencies: dependencies)
    await model.start()
    let persisted = try await dependencies.learning.loadUnlockSessionEnvelope()
    XCTAssertEqual(persisted?.completionState, .aborted)
    XCTAssertEqual(persisted?.abortReason, expected.rawValue)
    XCTAssertEqual(model.unlockRecovery?.reason, expected)
    XCTAssertNil(model.unlockChallenge)
    XCTAssertNil(dependencies.lockController.unlockUntil)
  }

  private func fixtureManifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let snapshot = try await ContentRepository(source: try fixtureSource()).catalogSnapshot()
    return try XCTUnwrap(snapshot.packs.first { $0.id == id })
  }

  private func bundledManifest(_ id: StudyPackID) async throws -> StudyPackManifest {
    let snapshot = try await ContentRepository(
      source: BundledContentSource(bundle: .main)).catalogSnapshot()
    return try XCTUnwrap(snapshot.packs.first { $0.id == id })
  }

  private func fixtureSource() throws -> V11FixtureContentSource {
    .init(catalog: try fixtureCatalogData(), root: try fixtureRoot())
  }

  private func fixtureCatalogData() throws -> Data {
    let bundle = Bundle(for: Self.self)
    let url = try XCTUnwrap(bundle.url(
      forResource: "study_pack_catalog_v9_fixtures", withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func fixtureRoot() throws -> URL {
    try XCTUnwrap(Bundle(for: Self.self).resourceURL)
  }

  private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-v11-\(label)-\(UUID().uuidString)", isDirectory: true)
  }

  private func duplicateCategory(_ data: Data) throws -> Data {
    var object = try catalogObject(data)
    var values = try XCTUnwrap(object["categories"] as? [[String: Any]])
    values.append(try XCTUnwrap(values.first))
    object["categories"] = values
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func duplicateSeries(_ data: Data) throws -> Data {
    var object = try catalogObject(data)
    var values = try XCTUnwrap(object["series"] as? [[String: Any]])
    values.append(try XCTUnwrap(values.first))
    object["series"] = values
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func categoryCycle(_ data: Data) throws -> Data {
    var object = try catalogObject(data)
    var values = try XCTUnwrap(object["categories"] as? [[String: Any]])
    guard values.count >= 2,
      let firstID = values[0]["id"] as? String,
      let secondID = values[1]["id"] as? String
    else { throw ContentRepositoryError.invalid("category fixture") }
    values[0]["parentCategoryID"] = secondID
    values[1]["parentCategoryID"] = firstID
    object["categories"] = values
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func packLocalFailure(_ data: Data, packID: StudyPackID) throws -> Data {
    var object = try catalogObject(data)
    var packs = try XCTUnwrap(object["packs"] as? [[String: Any]])
    let index = try XCTUnwrap(packs.firstIndex { ($0["id"] as? String) == packID.rawValue })
    packs[index]["seriesID"] = "missing.series"
    object["packs"] = packs
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func catalogObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}

private struct V11FixtureContentSource: ContentAssetSource {
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

private actor MutableV11ContentSource: ContentAssetSource {
  private var data: Data
  nonisolated let root: URL

  init(data: Data, root: URL) {
    self.data = data
    self.root = root
  }

  func replace(with data: Data) { self.data = data }
  func catalogData() throws -> Data { data }
  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) throws -> ContentPackageLocation? {
    .init(kind: .installed, rootURL: root)
  }
}
