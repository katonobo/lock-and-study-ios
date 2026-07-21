import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        statusCard
        currentPackCard
        if model.selectedPackID.rawValue == "english3000.v1" { VocabularyPreviewCard(packID: model.selectedPackID) }
        Button {
          Task { await model.beginUnlockStudy() }
        } label: {
          Label("学習して開く", systemImage: "lock.open.fill").font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).tint(LockAndStudyTheme.brand)
        .accessibilityIdentifier("home.unlockStudy")
        Button("通常練習を始める") { Task { await model.beginPractice(packID: model.selectedPackID) } }.buttonStyle(.bordered)
        if !lock.isAuthorized || !lock.hasSelection {
          Button("Screen Timeを設定する") { model.selectedTab = .settings }.buttonStyle(.bordered)
        }
      }.frame(maxWidth: 720).padding()
    }
    .navigationTitle("ホーム")
    .accessibilityIdentifier("home.screen")
  }

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack { Image(systemName: lock.isLockEnabled ? "lock.fill" : "lock.open"); Text(lock.isLockEnabled ? "ロック利用中" : "ロック未設定").font(.headline); Spacer() }
      if let end = lock.unlockUntil, end > Date() {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let seconds = max(0, Int(end.timeIntervalSince(context.date)))
          Text("一時解除 残り \(seconds / 60)分\(seconds % 60)秒").monospacedDigit()
            .accessibilityLabel("一時解除中").accessibilityValue("約\(max(1, seconds / 60))分")
        }
      } else { Text(lock.isLockEnabled ? "対象は保護されています" : "通常学習だけでも利用できます").foregroundStyle(.secondary) }
    }.studyCard()
  }

  private var currentPackCard: some View {
    let pack = model.manifests.first { $0.id == model.selectedPackID }
    return VStack(alignment: .leading, spacing: 8) {
      Text("現在の教材").font(.caption).foregroundStyle(.secondary)
      Text(pack?.title ?? "教材を読み込み中").font(.title2.bold())
      Text(pack?.subtitle ?? "").foregroundStyle(.secondary)
      Label("無料教材だけでも解除を継続できます", systemImage: "checkmark.shield.fill").font(.footnote).foregroundStyle(LockAndStudyTheme.brand)
    }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
  }
}

private struct VocabularyPreviewCard: View {
  @EnvironmentObject private var model: AppModel
  let packID: StudyPackID
  @State private var prompt: StudyPrompt?
  var body: some View {
    Group {
      if let prompt {
        VStack(alignment: .leading, spacing: 8) {
          Text("次回の予習").font(.caption).foregroundStyle(.secondary)
          Text(prompt.prompt).font(.title.bold())
          Text(prompt.choices[safe: prompt.correctChoiceID]?.text ?? "").font(.headline)
          if let example = prompt.exampleText { Text(example).font(.footnote).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
      }
    }.task { prompt = try? await model.dependencies.content.prompts(for: packID).first(where: \.isFreeSample) }
  }
}

extension Collection { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }

