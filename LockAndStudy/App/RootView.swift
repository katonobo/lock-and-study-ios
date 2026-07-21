import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestRoutePurchase") {
        NavigationStack { PurchaseView() }
      } else if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestRouteEnglishDetail") {
        routedPackDetail("english3000.v1")
      } else if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestRouteTakkenDetail") {
        routedPackDetail("takken2026.v1")
      } else {
        standardContent
      }
      #else
      standardContent
      #endif
    }
    .fullScreenCover(item: $model.studySession) { session in StudySessionView(presentation: session) }
    .alert("お知らせ", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
      Button("閉じる", role: .cancel) { model.alertMessage = nil }
    } message: { Text(model.alertMessage ?? "") }
  }

  @ViewBuilder private var standardContent: some View {
      if model.onboardingCompleted {
        TabView(selection: $model.selectedTab) {
          NavigationStack { HomeView() }.tabItem { Label("ホーム", systemImage: "house.fill") }.tag(AppTab.home)
          NavigationStack { LibraryView() }.tabItem { Label("教材", systemImage: "books.vertical.fill") }.tag(AppTab.library)
          NavigationStack { RecordsView() }.tabItem { Label("記録", systemImage: "chart.bar.fill") }.tag(AppTab.records)
          NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .tint(LockAndStudyTheme.brand)
      } else {
        OnboardingFlowView()
      }
  }

  @ViewBuilder private func routedPackDetail(_ packID: StudyPackID) -> some View {
    if let manifest = model.manifests.first(where: { $0.id == packID }) {
      NavigationStack { PackDetailView(manifest: manifest) }
    } else {
      ProgressView("教材を読み込み中")
    }
  }
}
