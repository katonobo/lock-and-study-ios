import SwiftUI
import XCTest

@testable import LockAndStudy

@MainActor
final class PlatformCompletionV10Tests: XCTestCase {
  func testYojijukugoUsesFlashcardProfileRuntimePreviewHistoryAndReport() async throws {
    let fixture = try fixtureSource()
    let repository = ContentRepository(source: fixture)
    let manifest = try await manifest("yojijukugo.fixture.v1", in: repository)
    let profile = manifest.flashcardPresentation
    XCTAssertEqual(profile.subjectName, "四字熟語")
    XCTAssertEqual(profile.courseDefinitions.map(\.title), ["基礎"])
    XCTAssertEqual(profile.searchPlaceholder, "四字熟語・意味を検索")
    XCTAssertEqual(profile.itemCountUnit, "熟語")
    XCTAssertFalse(profile.supportsExamples)
    let encodedProfile = String(
      data: try SharedJSON.encoder().encode(profile), encoding: .utf8) ?? ""
    for forbidden in ["英単語", "中学1年", "高校基礎"] {
      XCTAssertFalse(encodedProfile.contains(forbidden))
    }

    let root = temporaryDirectory("yojijukugo-runtime")
    let dependencies = DependencyContainer(
      learningRootURL: root, contentSource: fixture)
    let now = Date(timeIntervalSince1970: 20_000_000)
    let runtime = FlashcardExperience()
    let context = StudyExperienceContext(
      manifest: manifest, dependencies: dependencies,
      reportProviders: [VocabularyReportProvider()], destination: .home,
      openMaterialSelection: {}, beginUnlockStudy: {}, completeFirstRun: {})
    _ = runtime.makeRootView(context: context)
    XCTAssertNotNil(runtime.makeFirstRunView(context: context))
    let normalLearning = VocabularyAppModel(context: context)
    await normalLearning.load()
    normalLearning.start(mode: .practice)
    XCTAssertFalse(try XCTUnwrap(normalLearning.session).questions.isEmpty)
    let request = UnlockChallengeRequest(
      requestID: UUID(), origin: .manual, policy: .initial(now: now),
      manifest: manifest, entitlement: .empty, progress: [:],
      learning: dependencies.learning, content: dependencies.content, now: now)
    let payload = try await runtime.createSession(request: request)
    var envelope = envelope(
      payload: payload, experienceID: runtime.experienceID, manifest: manifest, now: now)
    let session = try SharedJSON.decoder().decode(
      FlashcardUnlockSessionPayload.self, from: envelope.enginePayload)
    let question = try XCTUnwrap(session.questions.first)
    XCTAssertEqual(session.questions.count, 1)

    let transition = try await runtime.acceptAnswer(
      .choice(
        questionID: question.id.rawValue,
        choiceID: String(question.correctChoiceID)),
      envelope: envelope,
      dependencies: dependencies)
    envelope.enginePayload = transition.payload.data
    XCTAssertEqual(transition.submissionResult, .recordedCorrect)
    let proof = try runtime.completionProof(envelope: envelope)
    XCTAssertNotNil(proof)
    let answers = try await dependencies.learning.answers()
    XCTAssertEqual(answers.count, 1)
    XCTAssertEqual(answers.first?.packID, manifest.id)
    XCTAssertEqual(answers.first?.experienceID, .vocabulary)
    let progress = try await dependencies.learning.progress(
      for: .init(packID: manifest.id, itemID: question.id))
    XCTAssertEqual(progress.correctCount, 1)

    try await runtime.handleUnlockCompletion(.init(
      envelope: envelope, manifest: manifest, dependencies: dependencies, now: now))
    let preview = try await dependencies.learning.loadVocabularyPendingPreview(
      for: manifest.id, now: now)
    let storedPreview = try XCTUnwrap(preview)
    XCTAssertEqual(
      storedPreview.displayExpiresAt.timeIntervalSince(storedPreview.createdAt),
      VocabularyPendingPreview.displayDuration, accuracy: 0.001)

    let report = try VocabularyReportProvider().makeReportSection(
      snapshot: .init(
        answers: answers, events: [], progress: [progress.id.storageKey: progress],
        manifests: [manifest], entitlement: .empty),
      manifest: manifest,
      period: .init(
        startInclusive: .distantPast,
        endExclusive: .distantFuture),
      now: now,
      calendar: Calendar(identifier: .gregorian))
    XCTAssertEqual(report.title, manifest.title)
    XCTAssertEqual(report.metrics.first { $0.id == "vocabulary.answers" }?.value, "1問")
  }

  func testBusinessMannersUsesCertificationWithoutTakkenLabels() async throws {
    let fixture = try fixtureSource()
    let repository = ContentRepository(source: fixture)
    let manifest = try await manifest("business-manners.fixture.v1", in: repository)
    let profile = manifest.certificationPresentation
    XCTAssertEqual(profile.subjectName, "ビジネスマナー")
    XCTAssertFalse(profile.showsEditionYear)
    XCTAssertFalse(profile.showsLawBasisDate)
    XCTAssertFalse(profile.supportsFinalSprint)
    let profileText = String(
      data: try SharedJSON.encoder().encode(profile), encoding: .utf8) ?? ""
    XCTAssertFalse(profileText.contains("宅建"))

    let root = temporaryDirectory("manners-runtime")
    let dependencies = DependencyContainer(
      learningRootURL: root, contentSource: fixture)
    let now = Date(timeIntervalSince1970: 21_000_000)
    var policy = LockPolicy.initial(now: now)
    policy.accessPacePreset = .extended30
    let runtime = CertificationExperience()
    let context = StudyExperienceContext(
      manifest: manifest, dependencies: dependencies,
      reportProviders: [TakkenReportProvider()], destination: .home,
      openMaterialSelection: {}, beginUnlockStudy: {}, completeFirstRun: {})
    _ = runtime.makeRootView(context: context)
    XCTAssertNotNil(runtime.makeFirstRunView(context: context))
    let normalLearning = TakkenAppModel(context: context)
    await normalLearning.load()
    normalLearning.start(mode: .practice)
    XCTAssertFalse(try XCTUnwrap(normalLearning.session).questions.isEmpty)
    let payload = try await runtime.createSession(request: .init(
      requestID: UUID(), origin: .manual, policy: policy, manifest: manifest,
      entitlement: .empty, progress: [:], learning: dependencies.learning,
      content: dependencies.content, now: now))
    var envelope = envelope(
      payload: payload, experienceID: runtime.experienceID, manifest: manifest, now: now)
    let initial = try SharedJSON.decoder().decode(
      CertificationUnlockSessionPayload.self, from: envelope.enginePayload)
    XCTAssertEqual(
      Set(initial.questions.map(\.format)),
      ["true_false", "wording_contrast", "case_study"])

    let first = try XCTUnwrap(initial.questions.first)
    let wrong = try XCTUnwrap(first.choices.first { $0.id != first.correctChoiceID })
    var transition = try await runtime.acceptAnswer(
      .choice(questionID: first.id.rawValue, choiceID: String(wrong.id)),
      envelope: envelope, dependencies: dependencies)
    envelope.enginePayload = transition.payload.data
    guard case .recordedIncorrect(let required, _) = transition.submissionResult else {
      return XCTFail("誤答は学び直しへ遷移する必要があります")
    }
    transition = try await runtime.activeReviewTick(
      seconds: TimeInterval(required), envelope: envelope)
    envelope.enginePayload = transition.payload.data
    transition = try await runtime.acceptAnswer(
      .choice(questionID: first.id.rawValue, choiceID: String(first.correctChoiceID)),
      envelope: envelope, dependencies: dependencies)
    envelope.enginePayload = transition.payload.data
    XCTAssertEqual(transition.submissionResult, .recordedCorrect)

    var current = try SharedJSON.decoder().decode(
      CertificationUnlockSessionPayload.self, from: envelope.enginePayload)
    for question in current.questions where !current.completedQuestionIDs.contains(question.id) {
      transition = try await runtime.acceptAnswer(
        .choice(questionID: question.id.rawValue, choiceID: String(question.correctChoiceID)),
        envelope: envelope, dependencies: dependencies)
      envelope.enginePayload = transition.payload.data
      current = try SharedJSON.decoder().decode(
        CertificationUnlockSessionPayload.self, from: envelope.enginePayload)
    }
    let proof = try runtime.completionProof(envelope: envelope)
    XCTAssertNotNil(proof)
    let answers = try await dependencies.learning.answers()
    XCTAssertEqual(answers.count, 4)
    let report = try TakkenReportProvider().makeReportSection(
      snapshot: .init(
        answers: answers, events: [], progress: [:], manifests: [manifest],
        entitlement: .empty),
      manifest: manifest,
      period: .init(
        startInclusive: .distantPast,
        endExclusive: .distantFuture),
      now: Date(), calendar: Calendar(identifier: .gregorian))
    XCTAssertEqual(report.title, "ビジネスマナー 基礎")
    XCTAssertNil(report.footer)
    XCTAssertEqual(Set(report.currentMetrics.map(\.id)), [
      "takken.format.true_false", "takken.format.wording_contrast",
      "takken.format.case_study",
    ])
  }

  @MainActor
  func testInstalledFixtureOpensThroughProductionDependencyAndAppModel() async throws {
    let fixture = try fixtureSource()
    let catalogData = try await fixture.catalogData()
    let manifest = try await manifest(
      "yojijukugo.fixture.v1", in: ContentRepository(source: fixture))
    let root = temporaryDirectory("production-installed")
    let dependencies = DependencyContainer(
      learningRootURL: root, catalogDataOverride: catalogData)
    let staged = try await dependencies.contentPackages.stage(.init(
      manifest: manifest, sourceRootURL: fixture.root))
    try await dependencies.contentPackages.activate(staged)

    let model = AppModel(dependencies: dependencies)
    await model.start()
    XCTAssertTrue(model.manifests.contains { $0.id == manifest.id })
    let cards = try await dependencies.content.vocabularyPackage(for: manifest.id)
    XCTAssertEqual(cards.items.count, 6)
    model.openExperience(packID: manifest.id)
    XCTAssertEqual(model.activeExperience?.packID, manifest.id)
    let presentation = try XCTUnwrap(model.activeExperience)
    let context = try XCTUnwrap(model.experienceContext(for: presentation))
    let factory = try XCTUnwrap(model.experienceRegistry.factory(for: manifest))
    _ = factory.makeRootView(context: context)
    await model.beginUnlockStudy(packID: manifest.id, origin: .manual)
    XCTAssertEqual(model.unlockChallenge?.experienceID, .flashcardV1)
    XCTAssertEqual(model.unlockChallenge?.enginePayloadSchemaID, FlashcardUnlockSessionPayload.schemaID)
  }

  @MainActor
  func testCustomFactoryConnectsToAppModelOpaqueRuntimeAndCompletesExactlyOnce() async throws {
    let fixture = try fixtureSource()
    let catalog = try fakeCustomCatalog(from: try await fixture.catalogData())
    let source = V10FixtureContentSource(catalog: catalog, root: fixture.root)
    let root = temporaryDirectory("custom-experience")
    let dependencies = DependencyContainer(learningRootURL: root, contentSource: source)
    let registry = StudyExperienceRegistry(factories: [
      FakeCustomExperience(), SafeFallbackExperience(),
    ])
    let model = AppModel(dependencies: dependencies, experienceRegistry: registry)
    await model.start()
    let manifest = try XCTUnwrap(model.manifests.first { $0.id == "fake.custom.fixture.v1" })
    XCTAssertTrue(model.availability(for: manifest).canOpen)
    model.openExperience(packID: manifest.id)
    XCTAssertEqual(model.activeExperience?.experienceID, FakeCustomExperience.id)

    await model.beginUnlockStudy(packID: manifest.id, origin: .manual)
    let started = try XCTUnwrap(model.unlockChallenge)
    XCTAssertEqual(started.enginePayloadSchemaID, FakeCustomExperience.payloadSchemaID)
    XCTAssertEqual(
      try SharedJSON.decoder().decode(FakeCustomState.self, from: started.enginePayload),
      .init(completed: false))
    let submission = await model.submitUnlockAnswer(.text("完了"))
    XCTAssertEqual(submission, .recordedCorrect)
    let answeredEnvelope = try await dependencies.learning.loadUnlockSessionEnvelope()
    let answered = try XCTUnwrap(answeredEnvelope)
    XCTAssertEqual(
      try SharedJSON.decoder().decode(FakeCustomState.self, from: answered.enginePayload),
      .init(completed: true))

    await model.completeUnlockChallenge()
    await model.completeUnlockChallenge()
    let completionEvents = try await dependencies.learning.events().filter {
      $0.id == started.completionEventID
    }
    XCTAssertEqual(completionEvents.count, 1)
    let cleared = try await dependencies.learning.loadUnlockSessionEnvelope()
    XCTAssertNil(cleared)
  }

  func testCustomEnvelopeExpiryAndUnknownSchemaFailClosed() async throws {
    let store = LearningDataStore(rootURL: temporaryDirectory("custom-expiry"))
    let now = Date(timeIntervalSince1970: 22_000_000)
    let expired = UnlockChallengeSessionEnvelope(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
      id: UUID(), requestID: UUID(), origin: .manual,
      experienceID: FakeCustomExperience.id, packID: "fake.custom.fixture.v1",
      contentVersion: "1", policyVersion: 1,
      createdAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(-1),
      completionState: .answering, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil,
      enginePayloadSchemaID: FakeCustomExperience.payloadSchemaID,
      enginePayload: try SharedJSON.encoder().encode(FakeCustomState(completed: false)))
    try await store.saveUnlockSessionEnvelope(expired)
    let restored = try await UnlockChallengeSessionCoordinator(store: store).restore(at: now)
    XCTAssertNil(restored)
    let savedEnvelope = try await store.loadUnlockSessionEnvelope()
    let saved = try XCTUnwrap(savedEnvelope)
    XCTAssertEqual(saved.completionState, .aborted)
    XCTAssertEqual(saved.abortReason, "challenge-expired-during-recovery")
  }

  func testStrictCatalogDecodeRollbackAndHierarchyAreFailClosed() async throws {
    let fixture = try fixtureSource()
    let good = try await fixture.catalogData()
    let source = MutableV10ContentSource(data: good, root: fixture.root)
    let repository = ContentRepository(source: source)
    let original = try await repository.catalogSnapshot()
    XCTAssertFalse(original.packs.isEmpty)
    await source.replace(with: Data("{\"schemaVersion\":99}".utf8))
    let rolledBack = try await repository.reloadCatalog()
    XCTAssertEqual(rolledBack, original)

    var malformed = try XCTUnwrap(
      JSONSerialization.jsonObject(with: good) as? [String: Any])
    var packs = try XCTUnwrap(malformed["packs"] as? [[String: Any]])
    packs.append(["id": "broken-without-required-fields"])
    malformed["packs"] = packs
    XCTAssertThrowsError(try StudyCatalogDecoder().decode(
      JSONSerialization.data(withJSONObject: malformed)))

    let hierarchyData = try hierarchyCatalog(from: good)
    let hierarchy = try StudyCatalogDecoder().decode(hierarchyData)
    XCTAssertTrue(StudyCatalogValidator().validate(hierarchy).isEmpty)
    let child = try XCTUnwrap(hierarchy.categories.first { $0.id == "language.japanese.idioms" })
    XCTAssertEqual(child.parentCategoryID, "language.japanese")
  }

  func testFixtureProfilesEditionsEntitlementsAndReleaseIsolation() async throws {
    let fixture = try fixtureSource()
    let snapshot = try await ContentRepository(source: fixture).catalogSnapshot()
    let yojijukugo = try XCTUnwrap(snapshot.packs.first { $0.id == "yojijukugo.fixture.v1" })
    let manners = try XCTUnwrap(snapshot.packs.first { $0.id == "business-manners.fixture.v1" })
    let takken2027 = try XCTUnwrap(snapshot.packs.first { $0.id == "takken2027.fixture.v1" })
    XCTAssertEqual(yojijukugo.flashcardPresentation.subjectName, "四字熟語")
    XCTAssertEqual(manners.certificationPresentation.subjectName, "ビジネスマナー")
    XCTAssertEqual(takken2027.editionYear, 2027)
    XCTAssertEqual(takken2027.supersedesPackID, "takken2026.v1")

    let now = Date()
    let owned2026 = CommerceEntitlementSnapshot(
      activePass: nil,
      ownedPacks: [.init(
        packID: "takken2026.v1", productID: "legacy-2026", purchaseDate: now,
        ownershipType: .purchased, source: .appStore)],
      familySharedProductIDs: [], legacyGrants: [], lastVerifiedAt: now,
      cacheValidUntil: now.addingTimeInterval(3_600))
    XCTAssertFalse(ContentAccessService().decision(
      isFreeSample: false, manifest: takken2027,
      entitlement: owned2026, now: now).isAllowed)
    var pass = owned2026
    pass.activePass = .init(
      productID: ProductCatalog.monthlyPassProductID,
      expirationDate: now.addingTimeInterval(3_600), state: .active,
      ownershipType: .purchased)
    XCTAssertTrue(ContentAccessService().decision(
      isFreeSample: false, manifest: takken2027, entitlement: pass, now: now).isAllowed)

    let released = try await ContentRepository(
      source: BundledContentSource(bundle: .main)).releasedManifests()
    XCTAssertTrue(released.allSatisfy { !$0.id.rawValue.contains("fixture") })
  }

  private func fixtureSource() throws -> V10FixtureContentSource {
    let bundle = Bundle(for: Self.self)
    let catalogURL = try XCTUnwrap(bundle.url(
      forResource: "study_pack_catalog_v9_fixtures", withExtension: "json"))
    return .init(
      catalog: try Data(contentsOf: catalogURL),
      root: try XCTUnwrap(bundle.resourceURL))
  }

  private func manifest(
    _ id: StudyPackID, in repository: ContentRepository
  ) async throws -> StudyPackManifest {
    let values = try await repository.releasedManifests()
    return try XCTUnwrap(values.first { $0.id == id })
  }

  private func envelope(
    payload: ExperienceSessionPayload,
    experienceID: StudyExperienceID,
    manifest: StudyPackManifest,
    now: Date
  ) -> UnlockChallengeSessionEnvelope {
    .init(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
      id: UUID(), requestID: UUID(), origin: .manual, experienceID: experienceID,
      packID: manifest.id, contentVersion: manifest.contentVersion, policyVersion: 1,
      createdAt: now, expiresAt: now.addingTimeInterval(1_800),
      completionState: .answering, completionEventID: UUID(),
      createdUnlockSessionID: nil, abortReason: nil,
      enginePayloadSchemaID: payload.schemaID, enginePayload: payload.data)
  }

  private func fakeCustomCatalog(from data: Data) throws -> Data {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    var categories = try XCTUnwrap(object["categories"] as? [[String: Any]])
    categories.append([
      "schemaVersion": 1, "id": "custom", "title": "カスタム", "sortOrder": 90,
      "systemImage": "puzzlepiece", "isVisible": true,
    ])
    object["categories"] = categories
    var series = try XCTUnwrap(object["series"] as? [[String: Any]])
    series.append([
      "schemaVersion": 1, "id": "custom.fake", "categoryID": "custom",
      "title": "Fake", "description": "Unit Test", "sortOrder": 90,
      "editionPolicy": "evergreen", "defaultExperienceID": FakeCustomExperience.id.rawValue,
      "isVisible": true,
    ])
    object["series"] = series
    var packs = try XCTUnwrap(object["packs"] as? [[String: Any]])
    packs.append([
      "schemaVersion": 2,
      "id": "fake.custom.fixture.v1",
      "categoryID": "custom",
      "seriesID": "custom.fake",
      "experienceID": FakeCustomExperience.id.rawValue,
      "editionID": "fixture-v1",
      "editionPolicy": "evergreen",
      "storeState": "forSale",
      "deliveryMode": "downloadable",
      "passAccessPolicy": "included",
      "moduleType": "not-registered-module",
      "experienceType": FakeCustomExperience.id.rawValue,
      "title": "Fake Custom Experience",
      "subtitle": "Unit Test",
      "description": "Factory only integration proof",
      "contentVersion": "1",
      "minimumAppVersion": "1.0",
      "releaseStatus": "release",
      "isEnabled": true,
      "sortOrder": 90,
      "expectedItemCount": 0,
      "sampleDefinition": ["kind": "none", "count": 0],
      "passEligible": true,
      "saleReady": false,
      "contentFiles": [],
      "components": [[
        "id": "fake", "title": "Fake", "experienceID": FakeCustomExperience.id.rawValue,
        "contentSchemaID": FakeCustomExperience.contentSchemaID.rawValue,
        "sortOrder": 0, "contentFiles": [],
      ]],
      "locale": "ja-JP",
    ])
    object["packs"] = packs
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func hierarchyCatalog(from data: Data) throws -> Data {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    var categories = try XCTUnwrap(object["categories"] as? [[String: Any]])
    categories.append([
      "schemaVersion": 1, "id": "language.japanese.idioms",
      "parentCategoryID": "language.japanese", "title": "熟語",
      "systemImage": "text.book.closed", "sortOrder": 11, "isVisible": true,
    ])
    object["categories"] = categories
    return try JSONSerialization.data(withJSONObject: object)
  }

  private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-v10-\(label)-\(UUID().uuidString)", isDirectory: true)
  }
}

private struct V10FixtureContentSource: ContentAssetSource {
  let catalog: Data
  let root: URL

  func catalogData() async throws -> Data { catalog }
  func packageLocation(
    for packID: StudyPackID, contentVersion: String
  ) async throws -> ContentPackageLocation? {
    .init(kind: .installed, rootURL: root)
  }
}

private actor MutableV10ContentSource: ContentAssetSource {
  private var data: Data
  nonisolated let root: URL

  init(data: Data, root: URL) {
    self.data = data
    self.root = root
  }
  func replace(with data: Data) { self.data = data }
  func catalogData() throws -> Data { data }
  func packageLocation(
    for packID: StudyPackID, contentVersion: String
  ) throws -> ContentPackageLocation? {
    .init(kind: .installed, rootURL: root)
  }
}

private struct FakeCustomState: Codable, Equatable, Sendable {
  var completed: Bool
}

@MainActor
private struct FakeCustomExperience: StudyExperienceFactory {
  static let id = StudyExperienceID(rawValue: "test.custom.v1")
  static let payloadSchemaID = "test.custom.session.v1"
  static let contentSchemaID = ContentSchemaID(rawValue: "test.custom.items.v1")

  let experienceID = Self.id
  let supportedPayloadSchemaIDs: Set<String> = [Self.payloadSchemaID]
  let supportedContentSchemas: Set<ContentSchemaID> = [Self.contentSchemaID]
  let descriptor = StudyExperienceDescriptor(
    id: Self.id, title: "Fake Custom", subtitle: "Unit Test",
    systemImage: "puzzlepiece", tintName: "blue", supportedExperienceTypes: [])

  func makeRootView(context: StudyExperienceContext) -> AnyView {
    AnyView(Text(context.manifest.title))
  }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? { nil }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    .init(
      experienceID: experienceID, packID: context.manifest.id,
      answeredCount: 0, correctCount: 0, learnedItemCount: 0, dueCount: 0)
  }
  func createSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    .init(
      schemaID: Self.payloadSchemaID,
      data: try SharedJSON.encoder().encode(FakeCustomState(completed: false)))
  }
  func makeChallengeView(
    envelope: UnlockChallengeSessionEnvelope,
    context: ExperienceChallengeViewContext
  ) -> AnyView {
    AnyView(Text("Fake challenge"))
  }
  func restoreState(payload: Data, schemaID: String) throws -> ExperienceSessionState {
    guard schemaID == Self.payloadSchemaID else { throw ContentRepositoryError.unsupported }
    let state = try SharedJSON.decoder().decode(FakeCustomState.self, from: payload)
    return .init(
      completedUnitCount: state.completed ? 1 : 0,
      totalUnitCount: 1, reviewRemainingSeconds: 0)
  }
  func acceptAnswer(
    _ answer: StudyAnswerValue,
    envelope: UnlockChallengeSessionEnvelope,
    dependencies: DependencyContainer
  ) async throws -> ExperienceSessionTransition {
    guard case .text = answer else { throw ContentRepositoryError.invalid("text required") }
    let data = try SharedJSON.encoder().encode(FakeCustomState(completed: true))
    return .init(
      payload: .init(schemaID: Self.payloadSchemaID, data: data),
      submissionResult: .recordedCorrect, reviewResult: nil)
  }
  func activeReviewTick(
    seconds: TimeInterval,
    envelope: UnlockChallengeSessionEnvelope
  ) async throws -> ExperienceSessionTransition {
    .init(
      payload: .init(
        schemaID: envelope.enginePayloadSchemaID, data: envelope.enginePayload),
      submissionResult: nil, reviewResult: .updated(remainingActiveSeconds: 0))
  }
  func completionProof(
    envelope: UnlockChallengeSessionEnvelope
  ) throws -> ExperienceCompletionProof? {
    let state = try SharedJSON.decoder().decode(FakeCustomState.self, from: envelope.enginePayload)
    guard state.completed else { return nil }
    return .init(
      sessionID: envelope.id, packID: envelope.packID,
      completedAt: Date(), evidenceVersion: 1, unlockDuration: 1)
  }
}
