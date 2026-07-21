import SwiftUI

struct LibraryView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService

  var body: some View {
    List {
      Section("利用できる教材") {
        ForEach(model.manifests) { manifest in
          NavigationLink { PackDetailView(manifest: manifest) } label: { PackRow(manifest: manifest, entitlement: commerce.entitlement) }
            .accessibilityIdentifier("library.pack.\(manifest.id.rawValue)")
        }
      }
      Section {
        NavigationLink("教材の購入とStudy Pass") { PurchaseView() }
          .accessibilityIdentifier("library.purchase")
      } footer: { Text("ロック機能、安全機能、無料教材による解除は購入不要です。") }
    }.navigationTitle("教材").accessibilityIdentifier("library.screen")
  }
}

private struct PackRow: View {
  let manifest: StudyPackManifest
  let entitlement: CommerceEntitlementSnapshot
  var body: some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 12).fill(manifest.moduleType == .vocabulary ? LockAndStudyTheme.vocabulary.gradient : LockAndStudyTheme.takken.gradient)
        .frame(width: 54, height: 54).overlay(Image(systemName: manifest.moduleType == .vocabulary ? "character.book.closed.fill" : "building.columns.fill").foregroundStyle(.white))
      VStack(alignment: .leading, spacing: 3) {
        Text(manifest.title).font(.headline)
        Text(manifest.subtitle).font(.subheadline).foregroundStyle(.secondary)
        Text(status).font(.caption.bold()).foregroundStyle(statusColor)
      }
    }.padding(.vertical, 4)
  }
  private var status: String {
    if !manifest.saleReady { return "無料\(manifest.sampleDefinition.count)問・全範囲版は準備中" }
    if entitlement.ownedPacks.contains(where: { $0.packID == manifest.id }) { return "所有済み" }
    if manifest.passEligible && entitlement.activePass?.permitsAccess == true { return "Study Passに含まれています" }
    return "無料サンプルあり・個別購入可能"
  }
  private var statusColor: Color { !manifest.saleReady ? .orange : LockAndStudyTheme.brand }
}

struct PackDetailView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService
  let manifest: StudyPackManifest
  @State private var prompts: [StudyPrompt] = []
  @State private var showPurchase = false
  @State private var statusFilter = "すべて"

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(manifest.title).font(.largeTitle.bold())
          Text(manifest.description)
          LabeledContent("公開数", value: manifest.moduleType == .vocabulary ? "\(manifest.expectedItemCount)語" : "\(manifest.expectedItemCount)問")
          LabeledContent("コンテンツ版", value: manifest.contentVersion)
          if let q = manifest.qualification {
            if let year = q.examYear { LabeledContent("試験年度", value: "\(year)年度") }
            if let date = q.lawBasisDate { LabeledContent("法令基準日", value: date) }
          }
          if !manifest.saleReady { Label("全範囲版の販売は、人手校閲が完了するまで開始しません。", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
        }.padding(.vertical)
      }
      Section {
        Button("無料サンプルで練習") { model.choosePack(manifest.id); Task { await model.beginPractice(packID: manifest.id) } }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("pack.practice")
        if manifest.saleReady, !isOwned, !isIncludedByPass {
          Button("購入方法を見る") { showPurchase = true }
            .accessibilityIdentifier("pack.purchase")
        }
        if isIncludedByPass { Label("Study Passに含まれています", systemImage: "checkmark.seal.fill").foregroundStyle(LockAndStudyTheme.brand) }
      }
      if manifest.moduleType == .takken {
        Section("問題一覧") {
          Picker("表示", selection: $statusFilter) { Text("すべて").tag("すべて"); Text("未回答").tag("未回答"); Text("正解").tag("正解"); Text("不正解").tag("不正解") }.pickerStyle(.segmented)
          ForEach(prompts) { prompt in NavigationLink { StudyPromptDetailView(prompt: prompt) } label: { VStack(alignment: .leading) { Text(prompt.prompt).lineLimit(2); Text([prompt.category, prompt.subcategory].compactMap { $0 }.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary) } } }
        }
      } else {
        Section("レベル") { ForEach(["L0", "L1", "L2", "L3", "L4"], id: \.self) { level in LabeledContent(level, value: "\(prompts.filter { $0.category == level }.count)語") } }
      }
      if let credits = manifest.creditsFile { Section("クレジット") { Text(credits.replacingOccurrences(of: "_", with: " ")).font(.footnote) } }
    }
    .navigationTitle(manifest.title).navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("pack.detail")
    .sheet(isPresented: $showPurchase) { NavigationStack { PurchaseView(focusedPackID: manifest.id) } }
    .task { prompts = (try? await model.dependencies.content.prompts(for: manifest.id)) ?? [] }
  }
  private var isOwned: Bool { commerce.entitlement.ownedPacks.contains { $0.packID == manifest.id } }
  private var isIncludedByPass: Bool { manifest.passEligible && commerce.entitlement.activePass?.permitsAccess == true }
}

struct StudyPromptDetailView: View {
  let prompt: StudyPrompt
  var body: some View {
    List {
      Section("問題") { Text(prompt.prompt).font(.title3) }
      Section("選択肢") { ForEach(prompt.choices) { choice in Label(choice.text, systemImage: choice.id == prompt.correctChoiceID ? "checkmark.circle.fill" : "circle").foregroundStyle(choice.id == prompt.correctChoiceID ? .green : .primary) } }
      Section("解説") { Text(prompt.longExplanation) }
      Section("記録時点の情報") {
        LabeledContent("コンテンツ版", value: prompt.contentVersion)
        if let year = prompt.examYear { LabeledContent("年度", value: "\(year)") }
        if let date = prompt.lawBasisDate { LabeledContent("法令基準日", value: date) }
        if let note = prompt.sourceNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
      }
    }.navigationTitle("問題詳細").navigationBarTitleDisplayMode(.inline)
  }
}
