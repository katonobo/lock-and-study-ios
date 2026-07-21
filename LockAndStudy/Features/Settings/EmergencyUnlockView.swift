import Combine
import SwiftUI

struct EmergencyUnlockView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dismiss) private var dismiss
  @State private var reason = EmergencyUnlockReason.communication
  @State private var wait = ActiveWaitCounter(required: EmergencyUnlockPolicy().activeWaitDuration)
  @State private var showAlternativeConfirmation = false
  @State private var working = false
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    Form {
      Section { Text("安全のための無料機能です。rolling 24時間に1回、15分だけ解除します。ロック設定は削除しません。") }
      Section("理由") { Picker("理由", selection: $reason) { ForEach(EmergencyUnlockReason.allCases) { Text($0.title).tag($0) } } }
      Section("確認待ち") {
        ProgressView(value: wait.accumulated, total: wait.required)
        Text(wait.isComplete ? "確認できます" : "この画面を表示したまま、あと\(Int(ceil(wait.remaining)))秒お待ちください").monospacedDigit().accessibilityLabel(wait.isComplete ? "確認できます" : "安全確認の待機中です")
        Text("バックグラウンド中は進みません。").font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Button { } label: { Label("5秒間長押しして緊急解除", systemImage: "hand.tap.fill").frame(maxWidth: .infinity, minHeight: 44) }
          .buttonStyle(.borderedProminent).tint(.orange).disabled(!wait.isComplete || working)
          .simultaneousGesture(LongPressGesture(minimumDuration: 5).onEnded { _ in Task { await performUnlock() } })
          .accessibilityIdentifier("emergency.hold")
        Button("長押しが難しい場合の確認") { showAlternativeConfirmation = true }.disabled(!wait.isComplete || working)
      }
    }
    .navigationTitle("緊急解除")
    .onReceive(timer) { _ in if scenePhase == .active, !wait.isComplete { wait.addActiveTime(1) } }
    .confirmationDialog("15分の緊急解除を実行しますか？", isPresented: $showAlternativeConfirmation, titleVisibility: .visible) {
      Button("緊急解除を実行") { Task { await performUnlock() } }
      Button("キャンセル", role: .cancel) {}
    } message: { Text("これはVoiceOverやSwitch Controlでも利用できる長押しと同等の最終確認です。") }
  }
  private func performUnlock() async {
    guard wait.isComplete, !working else { return }; working = true
    if await model.emergencyUnlock(reason: reason) { dismiss() }
    working = false
  }
}

