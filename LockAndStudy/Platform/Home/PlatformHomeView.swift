import SwiftUI

struct PlatformHomeView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController
  @EnvironmentObject private var commerce: StoreKitCommerceService
  @State private var summaries: [StudyPackID: StudyExperienceSummary] = [:]

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        lockStatusCard
        currentUnlockMaterialCard
        Button { Task { await model.beginUnlockStudy() } } label: {
          Label("学習して開く", systemImage: "lock.open.fill")
        }.primaryActionStyle().accessibilityIdentifier("platform.home.unlock")
        if !lock.isAuthorized || !lock.hasSelection {
          Button("Screen Timeを設定する") { model.selectedTab = .settings }.secondaryActionStyle()
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("マイ教材").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
          ForEach(model.manifests) { manifest in
            if let descriptor = model.experienceRegistry.factory(for: manifest.id)?.descriptor {
              experienceCard(manifest: manifest, descriptor: descriptor)
            }
          }
        }
      }.frame(maxWidth: 720).padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("ホーム")
    .task { await loadSummaries() }
    .accessibilityIdentifier("platform.home")
  }

  private var lockStatusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack { Image(systemName: lock.isLockEnabled ? "lock.fill" : "lock.open"); Text(lock.isLockEnabled ? "ロック利用中" : "ロック未設定").font(.headline); Spacer() }
      if let end = lock.unlockUntil, end > Date() {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let seconds = max(0, Int(end.timeIntervalSince(context.date)))
          Text("一時解除 残り \(seconds / 60)分\(seconds % 60)秒").monospacedDigit()
        }
      } else { Text(lock.isLockEnabled ? "対象は保護されています" : "通常学習はロック未設定でも使えます").foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
  }

  private var currentUnlockMaterialCard: some View {
    let manifest = model.manifests.first { $0.id == model.selectedPackID }
    let descriptor = manifest.flatMap { model.experienceRegistry.factory(for: $0.id)?.descriptor }
    return VStack(alignment: .leading, spacing: 8) {
      Text("解除に使う教材").font(.caption).foregroundStyle(.secondary)
      Label(manifest?.title ?? "教材を読み込み中", systemImage: descriptor?.systemImage ?? "book.fill").font(.title2.bold())
      Text(manifest?.subtitle ?? "").foregroundStyle(.secondary)
      Label("無料教材だけでも解除を継続できます", systemImage: "checkmark.shield.fill").font(.footnote).foregroundStyle(LockAndStudyTheme.teal)
    }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
  }

  private func experienceCard(manifest: StudyPackManifest, descriptor: StudyExperienceDescriptor) -> some View {
    let summary = summaries[manifest.id]
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: descriptor.systemImage).font(.title2).foregroundStyle(manifest.moduleType == .vocabulary ? LockAndStudyTheme.vocabulary : LockAndStudyTheme.takken)
        VStack(alignment: .leading) { Text(descriptor.title).font(.headline); Text(descriptor.subtitle).font(.caption).foregroundStyle(.secondary) }
        Spacer()
        Text(ownershipText(manifest)).font(.caption.bold()).foregroundStyle(.secondary)
      }
      if let summary {
        HStack { Text("学習済み \(summary.learnedItemCount)"); Spacer(); Text("正答率 \(Int(summary.accuracy * 100))%"); Spacer(); Text("復習 \(summary.dueCount)") }.font(.caption).monospacedDigit()
      }
      Button("開く") { model.openExperience(packID: manifest.id) }.primaryActionStyle()
        .accessibilityIdentifier("platform.open.\(descriptor.id.rawValue)")
    }.studyCard()
  }

  private func ownershipText(_ manifest: StudyPackManifest) -> String {
    if commerce.entitlement.ownedPacks.contains(where: { $0.packID == manifest.id }) { return "所有済み" }
    if manifest.passEligible && commerce.entitlement.activePass?.permitsAccess == true { return "Pass" }
    if !manifest.saleReady { return "無料公開中" }
    return "無料範囲"
  }

  private func loadSummaries() async {
    var values: [StudyPackID: StudyExperienceSummary] = [:]
    for manifest in model.manifests {
      guard let factory = model.experienceRegistry.factory(for: manifest.id),
            let context = model.experienceContext(for: .init(experienceID: factory.descriptor.id, packID: manifest.id)) else { continue }
      values[manifest.id] = try? await factory.makeProgressSummary(context: context)
    }
    summaries = values
  }
}
