import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    rootContent
      .fullScreenCover(isPresented: $model.isMaterialSelectionPresented) {
        StudyMaterialSelectionView()
      }
      .fullScreenCover(item: $model.studySession) { session in
        StudySessionView(presentation: session)
      }
      .alert(
        "お知らせ",
        isPresented: Binding(
          get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
      ) {
        Button("閉じる", role: .cancel) { model.alertMessage = nil }
      } message: {
        Text(model.alertMessage ?? "")
      }
  }

  @ViewBuilder private var rootContent: some View {
    Group {
      if let envelope = model.unlockChallenge {
        unlockContent(envelope)
      } else if let recovery = model.unlockRecovery {
        unlockRecoveryContent(recovery)
      } else {
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestRoutePurchase") {
            NavigationStack { PurchaseView() }
          } else if ProcessInfo.processInfo.arguments.contains(
            "-LockAndStudyUITestRouteSampleReport")
          {
            NavigationStack { LearningReportSampleView() }
          } else if ProcessInfo.processInfo.arguments.contains(
            "-LockAndStudyUITestRouteEnglishDetail")
          {
            routedPackDetail("english3000.v1")
          } else if ProcessInfo.processInfo.arguments.contains(
            "-LockAndStudyUITestRouteTakkenDetail")
          {
            routedPackDetail("takken2026.v1")
          } else {
            standardContent
          }
        #else
          standardContent
        #endif
      }
    }
  }

  @ViewBuilder private var standardContent: some View {
    if !model.onboardingCompleted {
      OnboardingFlowView()
    } else if let presentation = model.activeExperience {
      experienceContent(presentation)
    } else {
      VStack(spacing: 12) {
        ProgressView()
        Text("選択した教材を準備しています").foregroundStyle(.secondary)
      }
      .task { model.ensureSelectedExperienceOpen() }
    }
  }

  @ViewBuilder private func experienceContent(_ presentation: ActiveStudyExperience) -> some View {
    if let factory = model.experienceRegistry.factory(for: presentation.experienceID),
      let context = model.experienceContext(for: presentation)
    {
      StudyExperienceHostView(
        factory: factory, context: context, requiresFirstRun: presentation.requiresFirstRun)
        .id(presentation.id)
    } else {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
        Text("教材を開けません").font(.headline)
        Button("教材を読み込み直す") { model.ensureSelectedExperienceOpen() }.primaryActionStyle()
      }.padding()
    }
  }

  @ViewBuilder private func unlockContent(_ envelope: UnlockChallengeSessionEnvelope) -> some View {
    if let factory = model.experienceRegistry.factory(forExperienceID: envelope.experienceID),
      let context = model.unlockViewContext(for: envelope)
    {
      UnlockChallengeHostView(
        factory: factory, envelope: envelope, context: context)
    } else {
      UnlockRecoveryView {
        await model.failClosedUnlockPresentation(envelope)
        await model.beginSafeRecoveryStudy()
      }
      .task { await model.failClosedUnlockPresentation(envelope) }
    }
  }

  private func unlockRecoveryContent(_ recovery: UnlockRecoveryPresentation) -> some View {
    UnlockRecoveryView {
      await model.beginSafeRecoveryStudy()
    }
    .accessibilityIdentifier("unlock.recovery.\(recovery.reason.rawValue)")
  }

  @ViewBuilder private func routedPackDetail(_ packID: StudyPackID) -> some View {
    if let manifest = model.manifests.first(where: { $0.id == packID }) {
      NavigationStack { PlatformPackDetailView(manifest: manifest) }
    } else {
      ProgressView("教材を読み込み中")
    }
  }
}

private struct UnlockRecoveryView: View {
  let beginSafeStudy: @MainActor () async -> Void
  @State private var isStarting = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 54))
          .foregroundStyle(LockAndStudyTheme.teal)
        Text("解除問題を復元できませんでした")
          .font(.title2.bold())
          .multilineTextAlignment(.center)
        Text("教材の更新またはデータの不整合を検出したため、安全のためロックを維持しています。安全な無料問題で学習をやり直せます。")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button {
          guard !isStarting else { return }
          isStarting = true
          Task {
            await beginSafeStudy()
            isStarting = false
          }
        } label: {
          if isStarting {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Label("安全な無料問題を始める", systemImage: "lifepreserver.fill")
              .frame(maxWidth: .infinity)
          }
        }
        .primaryActionStyle()
        .disabled(isStarting)
        .accessibilityIdentifier("unlock.recovery.beginSafeFallback")
      }
      .frame(maxWidth: 560)
      .padding(24)
      .navigationTitle("解除学習の回復")
      .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled()
  }
}
