import StoreKit
import StoreKitTest
import XCTest
@testable import LockAndStudy

final class ContentAndStoreKitTests: XCTestCase {
  func testReleasedContentCountsAndSamples() async throws {
    let repository = ContentRepository(source: BundledContentSource(bundle: Bundle.main))
    let manifests = try await repository.releasedManifests()
    XCTAssertEqual(manifests.count, 2)
    let english = try await repository.prompts(for: "english3000.v1")
    XCTAssertEqual(english.count, 3_000); XCTAssertEqual(english.filter(\.isFreeSample).count, 250)
    let takken = try await repository.prompts(for: "takken2026.v1")
    XCTAssertEqual(takken.count, 100); XCTAssertTrue(takken.allSatisfy(\.isFreeSample))
    XCTAssertFalse(try XCTUnwrap(manifests.first { $0.id == "takken2026.v1" }).saleReady)
  }

  func testCatalogHasExactlyFourRequiredProductsAndTrial() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LockAndStudy", withExtension: "storekit"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let products = object["products"] as? [[String: Any]] ?? []
    let groups = object["subscriptionGroups"] as? [[String: Any]] ?? []
    let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
    let ids = Set((products + subscriptions).compactMap { $0["productID"] as? String })
    XCTAssertEqual(
      ids,
      Set([
        StoreProductKind.english3000.productID,
        StoreProductKind.takken2026.productID,
        StoreProductKind.passMonthly.productID,
        StoreProductKind.passYearly.productID,
      ]))
    XCTAssertEqual(groups.count, 1)
    let yearly = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == StoreProductKind.passYearly.productID })
    XCTAssertNotNil(yearly["introductoryOffer"] as? [String: Any])
    XCTAssertFalse(ids.contains { $0.contains("lifetime") })
  }

  @MainActor
  @available(iOS 17.0, *)
  func testStoreKitTestSessionLoadsAllProducts() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LockAndStudy", withExtension: "storekit"))
    let session = try SKTestSession(contentsOf: url)
    defer { session.clearTransactions() }
    session.disableDialogs = true
    let testOrder = [StoreProductKind.english3000.productID, StoreProductKind.takken2026.productID,
                     StoreProductKind.passMonthly.productID, StoreProductKind.passYearly.productID]
    for productID in testOrder {
      session.clearTransactions()
      do {
        let transaction = try await session.buyProduct(identifier: productID)
        XCTAssertEqual(transaction.productID, productID)
        XCTAssertEqual(session.allTransactions().last?.productIdentifier, productID)
      } catch {
        XCTFail("StoreKit Test purchase failed for \(productID): \(error)")
        return
      }
    }
  }
}
