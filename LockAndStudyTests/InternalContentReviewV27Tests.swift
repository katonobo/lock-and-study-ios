import XCTest

@testable import LockAndStudy

final class InternalContentReviewV27Tests: XCTestCase {
  func testSampleIndexAcceptsTopLevelQuestionsWrapper() throws {
    let questions = (0..<100).map { ["id": "sample-\($0)"] }
    let data = try JSONSerialization.data(
      withJSONObject: ["schemaVersion": 1, "questions": questions])

    XCTAssertNoThrow(
      try validator.validate(
        data: data,
        descriptor: descriptor(itemCount: 100),
        packageRoot: FileManager.default.temporaryDirectory))
  }

  func testSampleIndexRejectsDuplicateQuestionID() throws {
    let data = try JSONSerialization.data(
      withJSONObject: ["questions": [["id": "duplicate"], ["id": "duplicate"]]])

    XCTAssertThrowsError(
      try validator.validate(
        data: data,
        descriptor: descriptor(itemCount: 2),
        packageRoot: FileManager.default.temporaryDirectory))
  }

  func testSampleIndexRejectsItemCountMismatch() throws {
    let data = try JSONSerialization.data(
      withJSONObject: ["questions": [["id": "sample-1"]]])

    XCTAssertThrowsError(
      try validator.validate(
        data: data,
        descriptor: descriptor(itemCount: 2),
        packageRoot: FileManager.default.temporaryDirectory))
  }

  func testSampleIndexRejectsUnknownRootFormat() throws {
    let data = try JSONSerialization.data(
      withJSONObject: ["items": [["id": "sample-1"]]])

    XCTAssertThrowsError(
      try validator.validate(
        data: data,
        descriptor: descriptor(itemCount: 1),
        packageRoot: FileManager.default.temporaryDirectory))
  }

  func testProductionModeRejectsV26CandidateWithoutWeakeningStatusPolicy() throws {
    let bundle = Bundle(for: Self.self)
    let manifest = try candidateManifest(in: bundle)
    let root = try XCTUnwrap(bundle.resourceURL)

    XCTAssertThrowsError(
      try TakkenQuestionRepository(
        packageRoot: root,
        trustMode: .production
      ).load(manifest: manifest)
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("未校閲"))
    }
  }

  func testProductionBuildCannotUseInternalTestAccessOverride() throws {
    XCTAssertFalse(InternalContentReviewBuild.isEnabled)
    let manifest = try candidateManifest(in: Bundle(for: Self.self))
    let decision = ContentAccessService().decision(
      isFreeSample: false,
      manifest: manifest,
      entitlement: .empty,
      internalTest: true)

    XCTAssertFalse(decision.isAllowed)
    XCTAssertEqual(decision.reason, .unavailable)
  }

  private let validator = SampleIndexV1Validator()

  private func descriptor(itemCount: Int) -> ContentFileDescriptor {
    .init(path: "sample.json", sha256: String(repeating: "0", count: 64), itemCount: itemCount)
  }

  private func candidateManifest(in bundle: Bundle) throws -> StudyPackManifest {
    let url = try XCTUnwrap(
      bundle.url(
        forResource: "study_pack_catalog_takken_v26_review",
        withExtension: "json"))
    let catalog = try StudyCatalogDecoder().decode(Data(contentsOf: url))
    return try XCTUnwrap(catalog.packs.first { $0.id == "takken2026.v1" })
  }
}
