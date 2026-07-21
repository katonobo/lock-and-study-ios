import SwiftUI

struct LearningReportView: View {
  @ObservedObject var viewModel: LearningReportViewModel

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if viewModel.availableScopes.count > 1 {
          Picker("表示範囲", selection: Binding(
            get: { viewModel.scope },
            set: { viewModel.selectScope($0) }
          )) {
            Text("この教材").tag(LearningReportScope.pack(viewModel.currentPackID))
            Text("すべての教材").tag(LearningReportScope.allMaterials)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("report.scope")
        }
        if let report = viewModel.report {
          LearningReportBody(report: report, shareText: viewModel.shareText)
        } else if viewModel.isLoading {
          ProgressView("レポートを集計中")
            .frame(maxWidth: .infinity, minHeight: 240)
        }
      }
      .frame(maxWidth: 780)
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("今週のレポート")
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.load() }
    .refreshable { await viewModel.load() }
    .accessibilityIdentifier("report.weekly.screen")
    .alert("レポート", isPresented: .init(
      get: { viewModel.errorMessage != nil },
      set: { if !$0 { viewModel.errorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage ?? "")
    }
  }
}
