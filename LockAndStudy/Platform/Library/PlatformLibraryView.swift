import SwiftUI

struct PlatformLibraryView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService
  var body: some View {
    List {
      Section("教材ストア・ライブラリ") {
        ForEach(model.manifests) { manifest in
          NavigationLink { PlatformPackDetailView(manifest: manifest) } label: {
            HStack(spacing: 14) {
              let descriptor = model.experienceRegistry.factory(for: manifest.id)?.descriptor
              RoundedRectangle(cornerRadius: 12).fill(manifest.moduleType == .vocabulary ? LockAndStudyTheme.vocabulary.gradient : LockAndStudyTheme.takken.gradient)
                .frame(width: 54, height: 54).overlay(Image(systemName: descriptor?.systemImage ?? "book.fill").foregroundStyle(.white))
              VStack(alignment: .leading, spacing: 3) { Text(manifest.title).font(.headline); Text(manifest.subtitle).font(.subheadline).foregroundStyle(.secondary); Text(status(manifest)).font(.caption.bold()).foregroundStyle(manifest.saleReady ? LockAndStudyTheme.teal : .orange) }
            }.padding(.vertical, 4)
          }.accessibilityIdentifier("platform.library.pack.\(manifest.id.rawValue)")
        }
      }
      Section { NavigationLink("教材の購入とStudy Pass") { PurchaseView() } } footer: { Text("基本ロック、安全機能、無料教材での解除は購入不要です。") }
    }.navigationTitle("教材").accessibilityIdentifier("platform.library")
  }
  private func status(_ manifest: StudyPackManifest) -> String {
    if !manifest.saleReady { return "無料\(manifest.sampleDefinition.count)問・全範囲版は準備中" }
    if commerce.entitlement.ownedPacks.contains(where: { $0.packID == manifest.id }) { return "所有済み" }
    if manifest.passEligible && commerce.entitlement.activePass?.permitsAccess == true { return "Study Pass対象" }
    return "無料範囲あり・購入可能"
  }
}

struct PlatformPackDetailView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService
  let manifest: StudyPackManifest
  @State private var credits = ""
  @State private var summary: StudyExperienceSummary?
  @State private var showPurchase = false

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(manifest.title).font(.largeTitle.bold())
          Text(manifest.description)
          LabeledContent("公開数", value: manifest.moduleType == .vocabulary ? "\(manifest.expectedItemCount)語" : "\(manifest.expectedItemCount)問")
          LabeledContent("コンテンツ版", value: manifest.contentVersion)
          if let q = manifest.qualification { if let year = q.examYear { LabeledContent("試験年度", value: "\(year)年度") }; if let date = q.lawBasisDate { LabeledContent("法令基準日", value: date) } }
          if let summary { LabeledContent("学習済み", value: "\(summary.learnedItemCount)"); LabeledContent("正答率", value: "\(Int(summary.accuracy * 100))%") }
          if !manifest.saleReady { Label("全範囲版は準備中です。校閲完了まで購入できません。", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
        }.padding(.vertical)
      }
      Section {
        if model.selectedPackID == manifest.id {
          Label("解除教材に設定済み", systemImage: "checkmark.circle.fill")
            .foregroundStyle(LockAndStudyTheme.teal)
            .accessibilityIdentifier("platform.pack.selectedForUnlock")
        } else {
          Button("解除教材に設定") { model.choosePack(manifest.id) }
            .secondaryActionStyle()
            .accessibilityIdentifier("platform.pack.selectForUnlock")
        }
        if isOwned || isIncludedByPass {
          Button("この教材を開く") { model.openExperience(packID: manifest.id) }.primaryActionStyle()
            .accessibilityIdentifier("platform.pack.open")
        } else {
          Button("無料範囲を試す") { model.openExperience(packID: manifest.id, destination: .learning, requiresFirstRun: true) }.primaryActionStyle()
            .accessibilityIdentifier("platform.pack.openFree")
          if manifest.saleReady {
            Button("購入方法を見る") { showPurchase = true }.secondaryActionStyle()
              .accessibilityIdentifier("platform.pack.purchase")
          }
          else { Text("準備中のため購入操作は表示されません。").font(.footnote).foregroundStyle(.secondary) }
        }
        if isIncludedByPass { Label("Study Passで利用中", systemImage: "checkmark.seal.fill").foregroundStyle(LockAndStudyTheme.teal) }
      }
      if !credits.isEmpty { Section("クレジット・出典") { Text(credits).font(.footnote).textSelection(.enabled) } }
    }
    .navigationTitle(manifest.title).navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showPurchase) { NavigationStack { PurchaseView(focusedPackID: manifest.id) } }
    .task { await load() }
    .accessibilityIdentifier("platform.pack.detail")
  }
  private var isOwned: Bool { commerce.entitlement.ownedPacks.contains { $0.packID == manifest.id } }
  private var isIncludedByPass: Bool { manifest.passEligible && commerce.entitlement.activePass?.permitsAccess == true }
  private func load() async {
    if let file = manifest.creditsFile { credits = (try? VerifiedContentLoader().text(resourcePath: file)) ?? "" }
    if let factory = model.experienceRegistry.factory(for: manifest.id),
       let context = model.experienceContext(for: .init(experienceID: factory.descriptor.id, packID: manifest.id)) {
      summary = try? await factory.makeProgressSummary(context: context)
    }
  }
}
