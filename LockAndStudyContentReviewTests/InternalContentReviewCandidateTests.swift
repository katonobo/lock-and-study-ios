import CryptoKit
import XCTest

@testable import LockAndStudyContentReview

final class InternalContentReviewCandidateTests: XCTestCase {
  private let questionSHA = "af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263"
  private let freeSHA = "52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e"

  func testReviewBuildLoadsExactCandidateAndAllFiveFormats() async throws {
    XCTAssertTrue(InternalContentReviewBuild.isEnabled)
    XCTAssertEqual(InternalContentReviewBuild.trustMode, .internalReviewCandidate)

    let repository = ContentRepository(
      source: BundledContentSource(bundle: .main),
      trustMode: .internalReviewCandidate)
    let manifests = try await repository.releasedManifests()
    let manifest = try XCTUnwrap(
      manifests.first { $0.id == "takken2026.v1" })
    let questions = try await repository.takkenQuestions(for: manifest.id)

    XCTAssertEqual(questions.count, 1_000)
    XCTAssertEqual(
      Set(questions.map(\.resolvedFormat.rawValue)),
      Set(TakkenQuestionFormat.allCases.map(\.rawValue)))
    XCTAssertEqual(questions.filter(\.unlockEligible).count, 680)
    XCTAssertTrue(
      questions.filter { $0.resolvedFormat == .caseStudy }.allSatisfy {
        !$0.unlockEligible
      })
    XCTAssertTrue(questions.allSatisfy { $0.reviewStatus == "ai_review_candidate" })
    XCTAssertTrue(
      questions.allSatisfy {
        $0.conceptID != nil && $0.variantID != nil && $0.preview != nil
          && $0.minimumReviewSeconds != nil
      })
    XCTAssertTrue(questions.flatMap(\.choices).contains { $0.misconceptionCode != nil })
    XCTAssertFalse(manifest.saleReady)
    XCTAssertEqual(
      manifest.contentQualityProfile,
      "takken-v26-distinct-variant-review-candidate")
  }

  func testReviewCandidateSHAsAndFreeWrapperRemainExact() async throws {
    let root = try XCTUnwrap(Bundle.main.resourceURL)
    let questionsURL = root.appendingPathComponent(
      "takken_2026_questions_v26_candidate.json")
    let freeURL = root.appendingPathComponent(
      "takken_2026_free_sample_100_v26_candidate.json")
    XCTAssertEqual(sha256(questionsURL), questionSHA)
    XCTAssertEqual(sha256(freeURL), freeSHA)

    let freeObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: freeURL)) as? [String: Any])
    XCTAssertEqual((freeObject["questions"] as? [[String: Any]])?.count, 100)

    let repository = ContentRepository(
      source: BundledContentSource(bundle: .main),
      trustMode: .internalReviewCandidate)
    let all = try await repository.takkenQuestions(for: "takken2026.v1")
    let sampleIDs = try await repository.sampleIDs(
      for: "takken2026.v1",
      itemIDs: Set(all.map(\.id)))
    XCTAssertEqual(sampleIDs.count, 100)
    XCTAssertTrue(sampleIDs.isSubset(of: Set(all.map(\.id))))
  }

  func testCandidateFailsClosedInProductionModeButPassesReviewMode() async throws {
    let production = ContentRepository(
      source: BundledContentSource(bundle: .main),
      trustMode: .production)
    do {
      _ = try await production.takkenQuestions(for: "takken2026.v1")
      XCTFail("Production mode accepted ai_review_candidate")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("未校閲"))
    }

    let review = ContentRepository(
      source: BundledContentSource(bundle: .main),
      trustMode: .internalReviewCandidate)
    let reviewedQuestions = try await review.takkenQuestions(for: "takken2026.v1")
    XCTAssertEqual(reviewedQuestions.count, 1_000)
  }

  func testReviewAccessCanSwitchBetweenFreeSampleAndFullCandidate() async throws {
    let repository = ContentRepository(
      source: BundledContentSource(bundle: .main),
      trustMode: .internalReviewCandidate)
    let manifests = try await repository.releasedManifests()
    let manifest = try XCTUnwrap(
      manifests.first { $0.id == "takken2026.v1" })

    let free = ContentAccessService().decision(
      isFreeSample: true,
      manifest: manifest,
      entitlement: .empty,
      internalTest: false)
    let paidInSampleMode = ContentAccessService().decision(
      isFreeSample: false,
      manifest: manifest,
      entitlement: .empty,
      internalTest: false)
    let paidInFullMode = ContentAccessService().decision(
      isFreeSample: false,
      manifest: manifest,
      entitlement: .empty,
      internalTest: true)

    XCTAssertEqual(free.reason, .freeSample)
    XCTAssertFalse(paidInSampleMode.isAllowed)
    XCTAssertEqual(paidInFullMode.reason, .internalTest)
    XCTAssertTrue(paidInFullMode.isAllowed)
  }

  private func sha256(_ url: URL) -> String {
    SHA256.hash(data: try! Data(contentsOf: url))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
