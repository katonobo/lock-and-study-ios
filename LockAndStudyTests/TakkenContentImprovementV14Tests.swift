import CryptoKit
import XCTest

@testable import LockAndStudy

final class TakkenContentImprovementV14Tests: XCTestCase {
  func testCertificationPackageValidatorAcceptsRuntimeEquivalentMultiFilePackage() async throws {
    let package = try certificationPackage(
      questionsByFile: [
        [certificationQuestion(id: "question-a")],
        [certificationQuestion(id: "question-b")],
      ],
      expectedCount: 2,
      label: "accepted")
    let store = ContentPackageStore(rootURL: temporaryDirectory("accepted-store"))

    let staged = try await store.stage(
      .init(manifest: package.manifest, sourceRootURL: package.root))
    let runtime = try TakkenQuestionRepository(packageRoot: staged.rootURL)
      .load(manifest: package.manifest)

    XCTAssertEqual(runtime.map(\.id), ["question-a", "question-b"])
  }

  func testCertificationPackageValidatorRejectsCrossFileFailuresBeforeActivation() async throws {
    let empty = try certificationPackage(
      questionsByFile: [], expectedCount: 0, label: "empty")
    await assertThrowsAsyncV14 {
      let store = ContentPackageStore(rootURL: self.temporaryDirectory("empty-store"))
      _ = try await store.stage(
        .init(manifest: empty.manifest, sourceRootURL: empty.root))
    }

    let duplicate = try certificationPackage(
      questionsByFile: [
        [certificationQuestion(id: "duplicate")],
        [certificationQuestion(id: "duplicate")],
      ],
      expectedCount: 2,
      label: "duplicate")
    await assertThrowsAsyncV14 {
      let store = ContentPackageStore(rootURL: self.temporaryDirectory("duplicate-store"))
      _ = try await store.stage(
        .init(manifest: duplicate.manifest, sourceRootURL: duplicate.root))
    }

    let wrongTotal = try certificationPackage(
      questionsByFile: [
        [certificationQuestion(id: "total-a")],
        [certificationQuestion(id: "total-b")],
      ],
      expectedCount: 3,
      label: "wrong-total")
    await assertThrowsAsyncV14 {
      let store = ContentPackageStore(rootURL: self.temporaryDirectory("total-store"))
      _ = try await store.stage(
        .init(manifest: wrongTotal.manifest, sourceRootURL: wrongTotal.root))
    }

    var unreviewedQuestion = certificationQuestion(id: "unreviewed-b")
    unreviewedQuestion["reviewStatus"] = "ai_draft"
    let unreviewed = try certificationPackage(
      questionsByFile: [
        [certificationQuestion(id: "unreviewed-a")],
        [unreviewedQuestion],
      ],
      expectedCount: 2,
      label: "unreviewed")
    await assertThrowsAsyncV14 {
      let store = ContentPackageStore(rootURL: self.temporaryDirectory("unreviewed-store"))
      _ = try await store.stage(
        .init(manifest: unreviewed.manifest, sourceRootURL: unreviewed.root))
    }

    var placeholderQuestion = certificationQuestion(id: "placeholder-b")
    placeholderQuestion["isPlaceholder"] = true
    let placeholder = try certificationPackage(
      questionsByFile: [
        [certificationQuestion(id: "placeholder-a")],
        [placeholderQuestion],
      ],
      expectedCount: 2,
      label: "placeholder")
    await assertThrowsAsyncV14 {
      let store = ContentPackageStore(rootURL: self.temporaryDirectory("placeholder-store"))
      _ = try await store.stage(
        .init(manifest: placeholder.manifest, sourceRootURL: placeholder.root))
    }
  }

  private func fixtureManifest(_ id: StudyPackID) throws -> StudyPackManifest {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(
        forResource: "study_pack_catalog_v9_fixtures", withExtension: "json"))
    let snapshot = try StudyCatalogDecoder().decode(Data(contentsOf: url))
    return try XCTUnwrap(snapshot.packs.first { $0.id == id })
  }

  private func certificationQuestion(id: String) -> [String: Any] {
    [
      "id": id,
      "category": "宅建業法",
      "difficulty": "基礎",
      "format": "true_false",
      "prompt": "正しいものを選んでください。",
      "choices": [
        ["id": "correct", "text": "正しい"],
        ["id": "wrong", "text": "誤り", "rationale": "法令の規則と異なります。"],
      ],
      "correctChoiceID": "correct",
      "correctIndex": 0,
      "shortExplanation": "規則を確認します。",
      "longExplanation": "規則の主体・時期・例外まで確認します。",
      "reviewStatus": "checked",
      "isPlaceholder": false,
    ]
  }

  private func certificationPackage(
    questionsByFile: [[[String: Any]]],
    expectedCount: Int,
    label: String
  ) throws -> (manifest: StudyPackManifest, root: URL) {
    let root = temporaryDirectory("package-\(label)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var descriptors: [[String: Any]] = []
    for (index, questions) in questionsByFile.enumerated() {
      let data = try JSONSerialization.data(withJSONObject: questions, options: [.sortedKeys])
      let path = "questions-\(index + 1).json"
      try data.write(to: root.appendingPathComponent(path), options: .atomic)
      descriptors.append([
        "path": path,
        "sha256": sha256(data),
        "itemCount": questions.count,
        "byteCount": data.count,
      ])
    }

    let base = try fixtureManifest("business-manners.fixture.v1")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: SharedJSON.encoder().encode(base))
        as? [String: Any])
    object["id"] = "certification.v14.\(label)"
    object["contentVersion"] = "v14-\(label)"
    object["expectedItemCount"] = expectedCount
    object["sampleDefinition"] = ["kind": "allReleased", "count": expectedCount]
    object["contentFiles"] = descriptors
    object["components"] = [
      [
        "id": "questions",
        "title": "資格問題",
        "experienceID": "certification.v1",
        "contentSchemaID": "certification.questions.v1",
        "sortOrder": 0,
        "contentFiles": descriptors,
      ]
    ]
    let manifest = try SharedJSON.decoder().decode(
      StudyPackManifest.self,
      from: JSONSerialization.data(withJSONObject: object))
    return (manifest, root)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lockandstudy-v14-\(label)-\(UUID().uuidString)", isDirectory: true)
  }
}

private func assertThrowsAsyncV14(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected error", file: file, line: line)
  } catch {}
}
