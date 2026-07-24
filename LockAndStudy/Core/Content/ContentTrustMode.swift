import Foundation

enum ContentTrustMode: Equatable, Sendable {
  case production
  case internalReviewCandidate
}

enum InternalContentReviewBuild {
  static let bannerTitle = "内部コンテンツレビュー"
  static let bannerSubtitle = "未校閲・販売禁止"
  static let freeSampleOnlyArgument = "-LockAndStudyContentReviewFreeSampleOnly"

  static var isEnabled: Bool {
    #if LOCKANDSTUDY_INTERNAL_CONTENT_REVIEW
      true
    #else
      false
    #endif
  }

  static var trustMode: ContentTrustMode {
    isEnabled ? .internalReviewCandidate : .production
  }

  static var catalogResourceName: String {
    isEnabled ? "study_pack_catalog_takken_v26_review" : "study_pack_catalog"
  }

  static var grantsFullContentAccess: Bool {
    isEnabled
      && !ProcessInfo.processInfo.arguments.contains(freeSampleOnlyArgument)
  }
}
