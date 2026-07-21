import FamilyControls
import SwiftUI

struct OnboardingFlowView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController
  @State private var step = 0
  @State private var selectedPack: StudyPackID = "english3000.v1"
  @State private var pace = AccessPacePreset.balanced10
  @State private var review = ReviewLoadPreset.standard
  @State private var selection = FamilyActivitySelection()
  @State private var showPicker = false
  @State private var managementCode = ""
  @State private var managementCodeMessage: String?

  var body: some View {
    VStack(spacing: 20) {
      ProgressView(value: Double(step + 1), total: 9).tint(LockAndStudyTheme.brand).padding(.horizontal)
      ScrollView { content.frame(maxWidth: 660).padding(24) }
      HStack {
        if step > 0 { Button("戻る") { step -= 1 }.buttonStyle(.bordered) }
        Spacer()
        if step != 3 && step != 4 && step != 7 && step < 8 {
          Button("次へ") { step += 1 }.buttonStyle(.borderedProminent).tint(LockAndStudyTheme.brand)
        }
      }.padding()
    }
    .familyActivityPicker(isPresented: $showPicker, selection: $selection)
    .onChange(of: showPicker) { visible in
      if !visible, !selection.lockAndStudyIsEmpty { try? lock.saveSelection(selection) }
    }
  }

  @ViewBuilder private var content: some View {
    switch step {
    case 0:
      VStack(spacing: 20) {
        Image(systemName: "lock.open.rotation").font(.system(size: 64)).foregroundStyle(LockAndStudyTheme.brand)
        Text("ロックンスタディ").font(.largeTitle.bold())
        Text("開きたい気持ちを、短い学びに変える。\nロック機能と安全機能は無料です。").font(.title3).multilineTextAlignment(.center)
      }.accessibilityElement(children: .combine)
    case 1:
      OnboardingPage(title: "最初の学習目標", systemImage: "target") {
        packChoice("英単語3,000語", subtitle: "無料250語", id: "english3000.v1", color: .indigo)
        packChoice("宅建2026", subtitle: "品質確認済みの無料100問", id: "takken2026.v1", color: .orange)
      }
    case 2:
      OnboardingPage(title: "ロックとプライバシー", systemImage: "hand.raised.fill") {
        Text("AppleのScreen Time機能を使い、この端末で選んだアプリ・カテゴリ・Webサイトを一時的に制限します。選択内容や利用データを外部へ送信しません。許可しなくても通常学習は利用できます。")
        Label("遠隔監視や法人端末管理は行いません", systemImage: "person.crop.circle.badge.checkmark")
      }
    case 3:
      OnboardingPage(title: "Screen Timeの許可", systemImage: "hourglass") {
        Text("次のボタンを押すとAppleの許可画面が表示されます。")
        Button("Appleの許可画面へ進む") { Task { try? await lock.requestAuthorization(); step += 1 } }
          .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("onboarding.authorization")
        Button("今は設定せず学習を使う") { step += 1 }.buttonStyle(.bordered)
      }
    case 4:
      OnboardingPage(title: "ロック対象", systemImage: "apps.iphone") {
        if lock.isAuthorized {
          Button("アプリ・カテゴリ・Webサイトを選ぶ") { showPicker = true }.buttonStyle(.borderedProminent)
        } else { Text("Screen Timeを許可していないため、この設定は後から行えます。") }
        #if targetEnvironment(simulator)
        Button("シミュレータ用の対象を設定") { lock.markMockSelectionCompleted(); step += 1 }.buttonStyle(.bordered)
        #endif
        Button("後で設定する") { step += 1 }.buttonStyle(.bordered)
        if lock.hasSelection { Button("この対象で次へ") { step += 1 }.buttonStyle(.borderedProminent) }
      }
    case 5:
      OnboardingPage(title: "解除ペース", systemImage: "timer") {
        Picker("解除ペース", selection: $pace) { ForEach(AccessPacePreset.allCases) { Text($0.title + ($0.isRecommended ? "（推奨）" : "")).tag($0) } }.pickerStyle(.inline)
        Picker("復習量", selection: $review) { ForEach(ReviewLoadPreset.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Text("期限が来た復習だけを追加します。不足時の水増しはしません。").font(.footnote).foregroundStyle(.secondary)
      }
    case 6:
      OnboardingPage(title: "任意の管理コード", systemImage: "number.square.fill") {
        Text("弱い設定への変更を6桁コードで保護できます。設定しない場合は24時間の待機と二度目の確認が必要です。")
        SecureField("6桁", text: $managementCode).keyboardType(.numberPad).textContentType(.oneTimeCode)
          .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        if let warning = ManagementCodeStore.codeWarning(managementCode), !managementCode.isEmpty { Text(warning).font(.footnote).foregroundStyle(.orange) }
        Button("管理コードを設定して次へ") {
          do { try model.dependencies.managementCode.setCode(managementCode); step += 1 }
          catch { managementCodeMessage = error.localizedDescription }
        }.disabled(managementCode.count != 6).buttonStyle(.borderedProminent)
        Button("設定せず次へ") { step += 1 }.buttonStyle(.bordered)
        if let managementCodeMessage { Text(managementCodeMessage).foregroundStyle(.red) }
      }
    case 7:
      OnboardingPage(title: "通知", systemImage: "bell.badge.fill") {
        Text("Shieldからの学習案内と再ロック完了を通知できます。通知を許可しなくても、ロックンスタディを手動で開けば解除学習へ進めます。")
        Button("Appleの通知許可画面へ進む") { Task { _ = await NotificationService().requestAuthorization(); step += 1 } }.buttonStyle(.borderedProminent)
        Button("今は許可しない") { step += 1 }.buttonStyle(.bordered)
      }
    default:
      OnboardingPage(title: "準備できました", systemImage: "checkmark.seal.fill") {
        Text("購入なしで始められます。無料教材は期限なく、ロック解除にも繰り返し使えます。")
        Button("はじめる") { model.finishOnboarding(selectedPack: selectedPack, pace: pace, review: review) }
          .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("onboarding.finish")
      }
    }
  }

  private func packChoice(_ title: String, subtitle: String, id: StudyPackID, color: Color) -> some View {
    Button { selectedPack = id } label: {
      HStack { Circle().fill(color).frame(width: 12, height: 12); VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: selectedPack == id ? "checkmark.circle.fill" : "circle") }
        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain)
  }
}

private struct OnboardingPage<Content: View>: View {
  let title: String; let systemImage: String; let content: Content
  init(title: String, systemImage: String, @ViewBuilder content: () -> Content) { self.title = title; self.systemImage = systemImage; self.content = content() }
  var body: some View { VStack(alignment: .leading, spacing: 18) { Image(systemName: systemImage).font(.system(size: 42)).foregroundStyle(LockAndStudyTheme.brand); Text(title).font(.largeTitle.bold()); content }.frame(maxWidth: .infinity, alignment: .leading) }
}
