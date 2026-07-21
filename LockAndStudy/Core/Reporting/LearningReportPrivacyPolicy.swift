import Foundation

struct LearningReportPrivacyPolicy: Sendable {
  static let excludedTerms = [
    "pendingUnlockRequest", "selectionData", "managementCode", "transactionID",
  ]

  static func validateShareText(_ text: String) -> Bool {
    excludedTerms.allSatisfy { !text.localizedCaseInsensitiveContains($0) }
  }
}
