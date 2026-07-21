import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      if let bundle = model.unlockChallenge {
        unlockContent(bundle)
      } else if let presentation = model.activeExperience {
        experienceContent(presentation)
      } else {
        platformContent
      }
    }
    .fullScreenCover(item: $model.studySession) { session in StudySessionView(presentation: session) }
    .alert("お知らせ", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
      Button("閉じる", role: .cancel) { model.alertMessage = nil }
    } message: { Text(model.alertMessage ?? "") }
  }

  @ViewBuilder private var platformContent: some View {
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

  @ViewBuilder private var standardContent: some View {
      if model.onboardingCompleted {
        TabView(selection: $model.selectedTab) {
          NavigationStack { PlatformHomeView() }.tabItem { Label("ホーム", systemImage: "house.fill") }.tag(AppTab.home)
          NavigationStack { PlatformLibraryView() }.tabItem { Label("教材", systemImage: "books.vertical.fill") }.tag(AppTab.library)
          NavigationStack { PlatformRecordsView() }.tabItem { Label("記録", systemImage: "chart.bar.fill") }.tag(AppTab.records)
          NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .tint(LockAndStudyTheme.brand)
      } else {
        OnboardingFlowView()
      }
  }

  @ViewBuilder private func experienceContent(_ presentation: ActiveStudyExperience) -> some View {
    if let factory = model.experienceRegistry.factory(for: presentation.experienceID),
       let context = model.experienceContext(for: presentation) {
      StudyExperienceHostView(factory: factory, context: context, requiresFirstRun: presentation.requiresFirstRun)
    } else {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
        Text("教材を開けません").font(.headline)
        Button("Platformへ戻る") { model.closeExperience() }.primaryActionStyle()
      }.padding()
    }
  }

  @ViewBuilder private func unlockContent(_ bundle: ExperienceUnlockBundleSnapshot) -> some View {
    let factory = model.experienceRegistry.factory(for: bundle.challenge.experienceID)
      ?? model.experienceRegistry.factory(for: .safeFallback)
    if let factory {
      UnlockChallengeHostView(factory: factory, bundle: bundle, context: model.unlockViewContext(for: bundle))
    }
  }

  @ViewBuilder private func routedPackDetail(_ packID: StudyPackID) -> some View {
    if let manifest = model.manifests.first(where: { $0.id == packID }) {
      NavigationStack { PlatformPackDetailView(manifest: manifest) }
    } else {
      ProgressView("教材を読み込み中")
    }
  }
}
