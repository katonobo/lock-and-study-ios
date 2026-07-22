import SwiftUI

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
          LabeledContent("公開数", value: manifest.publishedCountLabel)
          LabeledContent("コンテンツ版", value: manifest.contentVersion)
          if let q = manifest.qualification { if let year = q.examYear { LabeledContent("試験年度", value: "\(year)年度") }; if let date = q.lawBasisDate { LabeledContent("法令基準日", value: date) } }
          if let summary { LabeledContent("学習済み", value: "\(summary.learnedItemCount)"); LabeledContent("正答率", value: "\(Int(summary.accuracy * 100))%") }
          if !manifest.saleReady { Label("全範囲版は準備中です。校閲完了まで購入できません。", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
        }.padding(.vertical)
      }
      Section {
        if !availability.canOpen {
          Label(availability.message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          if let successor = model.successorManifest(for: manifest.id) {
            Button("後継教材「\(successor.title)」を開く") {
              model.selectStudyMaterial(successor.id)
            }
            .secondaryActionStyle()
          }
        } else {
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
            Button("この教材を開く") { model.openExperience(packID: manifest.id) }
              .primaryActionStyle()
              .accessibilityIdentifier("platform.pack.open")
          } else {
            Button("無料範囲を試す") {
              model.openExperience(
                packID: manifest.id, destination: .learning, requiresFirstRun: true)
            }
            .primaryActionStyle()
            .accessibilityIdentifier("platform.pack.openFree")
            if manifest.saleReady {
              Button("購入方法を見る") { showPurchase = true }.secondaryActionStyle()
                .accessibilityIdentifier("platform.pack.purchase")
            } else {
              Text("準備中のため購入操作は表示されません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          if isIncludedByPass {
            Label("Study Passで利用中", systemImage: "checkmark.seal.fill")
              .foregroundStyle(LockAndStudyTheme.teal)
          }
        }
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
  private var availability: PackAvailability { model.availability(for: manifest) }
  private func load() async {
    if let file = manifest.creditsFile {
      credits = (try? await model.dependencies.content.text(
        resourcePath: file,
        for: manifest.id)) ?? ""
    }
    if let factory = model.experienceRegistry.factory(for: manifest),
       let context = model.experienceContext(for: .init(experienceID: factory.descriptor.id, packID: manifest.id)) {
      summary = try? await factory.makeProgressSummary(context: context)
    }
  }
}
