import SwiftUI

struct PurchaseView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService
  @Environment(\.dismiss) private var dismiss
  var focusedPackID: StudyPackID? = nil
  @State private var showPermanentPurchase = false

  var body: some View {
    Group {
      if InternalContentReviewBuild.isEnabled {
        internalReviewNotice
      } else {
        purchaseContent
      }
    }
    .internalContentReviewBanner()
    .accessibilityIdentifier("purchase.screen")
    .task {
      if !InternalContentReviewBuild.isEnabled && commerce.products.isEmpty {
        await commerce.loadProducts()
      }
    }
  }

  private var purchaseContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Text("学び方を選ぶ").font(.largeTitle.bold())
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill").font(.title2)
          }.accessibilityLabel("閉じる")
        }
        purchaseSection(title: "一つの目標に集中", subtitle: "教材を個別に買い切り。サブスクリプション不要で、購入教材を永久利用できます。") {
          ForEach(availablePackProducts) { product in productButton(product) }
          if commerce.entitlement.activePass?.permitsAccess == true, !showPermanentPurchase {
            Label("対象教材はStudy Passに含まれています", systemImage: "checkmark.seal.fill").foregroundStyle(
              LockAndStudyTheme.brand
            )
            .accessibilityIdentifier("purchase.passIncluded")
            Button("解約後も使うため永久購入する") { showPermanentPurchase = true }.buttonStyle(.bordered)
              .accessibilityIdentifier("purchase.showPermanent")
          }
        }
        purchaseSection(
          title: "複数の目標・最新版を利用", subtitle: "Study Passは対象教材、新教材、最新年度版、横断学習サービスを利用できます。"
        ) {
          ForEach(passProducts) { product in
            productButton(product, recommended: product.kind == .passYearly)
          }
        }
        Button("購入を復元") { Task { await commerce.restore() } }.buttonStyle(.bordered)
          .accessibilityIdentifier("purchase.restore")
        Link("サブスクリプションを管理", destination: AppConfiguration.subscriptionManagementURL)
        if let message = commerce.state.message {
          Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier(
            "purchase.state")
        }
        Text("自動更新はApp Storeのアカウント設定から、更新日の24時間以上前までに解約できます。表示価格・期間はApp Storeの商品情報が正本です。").font(
          .footnote
        ).foregroundStyle(.secondary)
        HStack {
          Link("利用規約", destination: AppConfiguration.termsOfUseURL)
          Link("プライバシーポリシー", destination: AppConfiguration.privacyPolicyURL)
        }.font(.footnote)
      }.frame(maxWidth: 720).padding()
    }
  }

  private var internalReviewNotice: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.system(size: 52))
          .foregroundStyle(.red)
        Text("購入機能は無効です")
          .font(.title2.bold())
          .accessibilityIdentifier("purchase.internalReviewDisabled")
        Text("このBuildは未校閲教材の内部確認専用です。商品価格、買い切り、Study Pass、購入復元は利用できません。")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("閉じる") { dismiss() }
          .secondaryActionStyle()
      }
      .frame(maxWidth: 520)
      .padding(24)
      .navigationTitle("内部レビュー")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var passProducts: [StoreProductPresentation] {
    commerce.products.filter { $0.kind.isSubscription }
  }
  private var availablePackProducts: [StoreProductPresentation] {
    commerce.products.filter { product in
      guard let packID = product.packID,
        let manifest = model.manifests.first(where: { $0.id == packID }),
        manifest.saleReady
      else { return false }
      if let focusedPackID, packID != focusedPackID { return false }
      if commerce.entitlement.ownedPacks.contains(where: { $0.packID == packID }) { return false }
      return commerce.entitlement.activePass?.permitsAccess != true || showPermanentPurchase
    }
  }
  private func purchaseSection<Content: View>(
    title: String, subtitle: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.title2.bold())
      Text(subtitle).foregroundStyle(.secondary)
      content()
    }.studyCard()
  }
  private func productButton(_ product: StoreProductPresentation, recommended: Bool = false)
    -> some View
  {
    Button {
      Task { await commerce.purchase(productID: product.id) }
    } label: {
      HStack {
        VStack(alignment: .leading) {
          HStack {
            Text(product.displayName).font(.headline)
            if recommended {
              Text("おすすめ").font(.caption.bold()).padding(5).background(
                LockAndStudyTheme.accent.opacity(0.2), in: Capsule())
            }
          }
          Text(product.description).font(.caption).foregroundStyle(.secondary)
          if product.isTrialEligible {
            Text("7日間無料体験の対象です").font(.caption).foregroundStyle(LockAndStudyTheme.brand)
          }
        }
        Spacer()
        Text(product.displayPrice).font(.headline)
      }
    }.buttonStyle(.bordered).disabled(isPurchasing)
      .accessibilityIdentifier(productAccessibilityIdentifier(product))
  }
  private func productAccessibilityIdentifier(_ product: StoreProductPresentation) -> String {
    let suffix =
      product.packID?.rawValue.split(separator: ".").first.map(String.init)
      ?? product.kind.rawValue
    return "purchase.product.\(suffix)"
  }
  private var isPurchasing: Bool {
    if case .purchasing = commerce.state { return true }
    return false
  }
}
