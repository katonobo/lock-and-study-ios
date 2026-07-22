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

          MyLibraryView()
          CategoryListView()
          VStack(alignment: .leading, spacing: 12) {
            Label("すべての教材", systemImage: "rectangle.stack.fill").font(.title2.bold())
            ForEach(model.manifests.sorted { $0.sortOrder < $1.sortOrder }) {
              PackSelectionCard(manifest: $0, showsDetailsLink: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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

}
