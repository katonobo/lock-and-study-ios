import SwiftUI

extension View {
  @ViewBuilder
  func internalContentReviewBanner() -> some View {
    if InternalContentReviewBuild.isEnabled {
      safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 2) {
          Text(InternalContentReviewBuild.bannerTitle)
            .font(.caption.bold())
          Text(InternalContentReviewBuild.bannerSubtitle)
            .font(.caption2.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.red)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contentReview.banner")
      }
    } else {
      self
    }
  }
}
