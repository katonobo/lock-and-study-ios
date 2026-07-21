import SwiftUI

struct LearningReportEntryCard: View {
  @StateObject private var viewModel: LearningReportViewModel
  private let accessibilityID: String

  init(context: StudyExperienceContext, accessibilityID: String) {
    _viewModel = StateObject(wrappedValue: LearningReportViewModel(
      currentPackID: context.manifest.id,
      dependencies: context.dependencies,
      providers: context.reportProviders
    ))
    self.accessibilityID = accessibilityID
  }

  var body: some View {
    NavigationLink {
      LearningReportView(viewModel: viewModel)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label("今週の学習レポート", systemImage: "chart.bar.xaxis")
            .font(.headline)
          Spacer()
          Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        Text(viewModel.report?.headline ?? "7日間の学習成果を確認できます")
          .font(.subheadline.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(viewModel.report?.compactSummary ?? "回答・正答率・学習日数を集計")
          .font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
      .contentShape(Rectangle())
    }
    .accessibilityIdentifier(accessibilityID)
    .task { if viewModel.report == nil { await viewModel.load() } }
  }
}
