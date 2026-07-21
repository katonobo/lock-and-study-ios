import SwiftUI

struct StudyMaterialSelectionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("学習する教材を選んでください").font(.title2.bold())
            Text("選択すると、その教材専用のホーム・学習・記録・設定へ切り替わります。教材ごとの学習履歴は保持されます。")
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          ForEach(model.manifests.sorted { $0.sortOrder < $1.sortOrder }) { manifest in
            materialCard(manifest)
          }
        }
        .frame(maxWidth: 720)
        .padding()
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle("教材の選択")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
    }
    .accessibilityIdentifier("materialSelection.screen")
  }

  private func materialCard(_ manifest: StudyPackManifest) -> some View {
    let descriptor = model.experienceRegistry.factory(for: manifest.id)?.descriptor
    let isCurrent = model.selectedPackID == manifest.id
    let tint =
      manifest.moduleType == .vocabulary ? LockAndStudyTheme.vocabulary : LockAndStudyTheme.takken

    return Button {
      model.selectStudyMaterial(manifest.id)
    } label: {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 14) {
          RoundedRectangle(cornerRadius: 16)
            .fill(tint.gradient)
            .frame(width: 68, height: 68)
            .overlay {
              Image(systemName: descriptor?.systemImage ?? "book.fill")
                .font(.title2)
                .foregroundStyle(.white)
            }
          VStack(alignment: .leading, spacing: 4) {
            Text(manifest.title).font(.title3.bold()).foregroundStyle(.primary)
            Text(manifest.subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text(freeStatus(manifest)).font(.caption.bold()).foregroundStyle(tint)
          }
          Spacer(minLength: 0)
        }

        HStack {
          if isCurrent {
            Label("選択中", systemImage: "checkmark.circle.fill")
          } else {
            Label("この教材を選択", systemImage: "arrow.right.circle.fill")
          }
          Spacer()
        }
        .font(.headline)
        .foregroundStyle(isCurrent ? LockAndStudyTheme.teal : tint)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .studyCard()
    }
    .buttonStyle(.plain)
    .disabled(isCurrent)
    .accessibilityIdentifier("materialSelection.option.\(manifest.id.rawValue)")
    .accessibilityHint(isCurrent ? "現在使用している教材です" : "選択するとこの教材へ切り替わります")
  }

  private func freeStatus(_ manifest: StudyPackManifest) -> String {
    let unit = manifest.moduleType == .vocabulary ? "語" : "問"
    let base = "無料\(manifest.sampleDefinition.count)\(unit)"
    return manifest.saleReady ? base : "\(base)・全範囲版は準備中"
  }
}
