import FamilyControls
import SwiftUI
import UIKit

struct OnboardingFlowView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController
  @State private var step = 0
  @State private var selectedPack: StudyPackID = "english3000.v1"
  @State private var pace = AccessPacePreset.balanced10
  @State private var review = ReviewLoadPreset.standard
  @State private var managementCode = ""
  @State private var managementCodeConfirmation = ""
  @State private var managementCodeMessage: String?
  @State private var showPicker = false
  @State private var selection = FamilyActivitySelection()
  @State private var isRequestingAuthorization = false
  @State private var isFinishing = false
  @State private var completionError: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        ProgressView(value: Double(step + 1), total: 9)
          .tint(LockAndStudyTheme.teal)
          .accessibilityLabel("初期設定 \(step + 1) / 9")
        ScrollView {
          VStack(spacing: 20) { content }
            .frame(maxWidth: 640)
            .padding(.vertical, 12)
        }
      }
      .padding()
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(step == 0 ? "ロックンスタディ" : "初期設定")
      .navigationBarTitleDisplayMode(.inline)
      .familyActivityPicker(isPresented: $showPicker, selection: $selection)
      .onChange(of: selection) { value in
        guard !value.lockAndStudyIsEmpty else { return }
        Task {
          do { try await lock.saveSelection(value) }
          catch { model.alertMessage = error.localizedDescription }
        }
      }
    }
  }

  @ViewBuilder private var content: some View {
    switch step {
    case 0:
      page(
        icon: "lock.open.trianglebadge.exclamationmark", title: "SNSを開くたび、\n学びが進む。",
        body: "SNSやゲームを開く前に、選んだ教材を1問。毎日のスマホ習慣を、そのまま学習のきっかけにします。")
      Button("はじめる") { step += 1 }.primaryActionStyle().accessibilityIdentifier("onboarding.start")
      NavigationLink("このアプリのしくみと管理について") { PlatformManagementInfoView() }
    case 1:
      page(
        icon: "books.vertical.fill", title: "最初の教材を選ぶ",
        body: "ロック解除に使う教材を選びます。どちらも無料範囲から始められ、教材固有の設定はこの初期設定の後に行います。")
      VStack(spacing: 12) {
        ForEach(model.manifests) { manifest in
          let descriptor = model.experienceRegistry.factory(for: manifest.id)?.descriptor
          Button {
            selectedPack = manifest.id
          } label: {
            HStack(spacing: 12) {
              Image(systemName: selectedPack == manifest.id ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(
                  selectedPack == manifest.id ? LockAndStudyTheme.teal : .secondary)
              Image(systemName: descriptor?.systemImage ?? "book.fill").foregroundStyle(
                manifest.moduleType == .vocabulary
                  ? LockAndStudyTheme.vocabulary : LockAndStudyTheme.takken)
              VStack(alignment: .leading) {
                Text(manifest.title).font(.headline)
                Text(manifest.subtitle).font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
            }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
          }.buttonStyle(.plain).studyCard()
        }
      }
      nextButton()
    case 2:
      page(
        icon: "lock.shield.fill", title: "選んだ対象だけを制限",
        body: "AppleのScreen Timeの仕組みを使い、あなたが選んだアプリ・カテゴリ・Webサイトを一時的に制限します。選択内容、管理コード、学習履歴は外部へ送信しません。"
      )
      VStack(alignment: .leading, spacing: 10) {
        Label("個人利用のScreen Time認可を使用", systemImage: "person.crop.circle.badge.checkmark")
        Label("遠隔監視や法人端末管理は行いません", systemImage: "network.slash")
        Label("無料教材だけでも解除できます", systemImage: "checkmark.shield.fill")
      }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
      nextButton()
    case 3:
      page(
        icon: "hand.raised.fill", title: "Screen Timeを許可",
        body: "オンボーディング完了と同時に、選んだ対象へロックを開始します。そのため、AppleのScreen Time許可が必要です。")
      Button(isRequestingAuthorization ? "許可を確認中…" : "Appleの許可画面へ進む") {
        Task { await requestScreenTimeAuthorization() }
      }
      .primaryActionStyle()
      .disabled(isRequestingAuthorization)
      .accessibilityIdentifier("onboarding.authorization")
      Text("許可されるまでは初期設定を完了しません。学習履歴や選択内容を外部へ送信することはありません。")
        .font(.footnote).foregroundStyle(.secondary)
    case 4:
      page(
        icon: "apps.iphone", title: "ロック対象を選ぶ",
        body: "SNS、ゲーム、カテゴリ、Webサイトから、学習のきっかけにしたい対象を選びます。空に戻す操作は、ロック終了と同じ保護対象です。")
      if lock.isAuthorized {
        if lock.isMockMode {
          Button(lock.hasSelection ? "対象を選択済み" : "シミュレータ用の対象を設定") {
            lock.markMockSelectionCompleted()
          }.primaryActionStyle().accessibilityIdentifier("onboarding.mockSelection")
        } else {
          Button("アプリ・カテゴリ・Webサイトを選ぶ") { showPicker = true }.primaryActionStyle()
        }
        Button("この対象で次へ") { step += 1 }
          .primaryActionStyle()
          .disabled(!lock.hasSelection)
          .accessibilityIdentifier("onboarding.selection.continue")
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Label("Screen Timeの再許可が必要です", systemImage: "exclamationmark.shield.fill")
          Text("許可後に、ロックする対象を1件以上選んでください。")
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
        Button("Appleの許可画面へ戻る") { step = 3 }.primaryActionStyle()
      }
    case 5:
      page(
        icon: "slider.horizontal.3", title: "解除ペースと復習量",
        body: "使える時間を長くするほど、先に解く問題数も増えます。期限が来た復習だけを設定量まで追加し、不足分を水増ししません。")
      VStack(alignment: .leading, spacing: 12) {
        Picker("解除ペース", selection: $pace) {
          ForEach(AccessPacePreset.allCases) {
            Text($0.title + ($0.isRecommended ? "（推奨）" : "")).tag($0)
          }
        }.pickerStyle(.inline)
        Text("1回の復習量").font(.headline)
        Picker("復習量", selection: $review) {
          ForEach(ReviewLoadPreset.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
      }.studyCard()
      nextButton()
    case 6:
      page(
        icon: "key.fill", title: "設定変更を管理コードで守る",
        body: "ロック対象を減らす、解除を長くする、ロックを終了するなどの弱化変更を6桁コードで保護できます。重要な暗証番号の使い回しは避けてください。")
      VStack(alignment: .leading, spacing: 12) {
        secureCodeField(
          title: "管理コードを入力", placeholder: "6桁の数字", text: $managementCode,
          identifier: "onboarding.managementCode", contentType: .oneTimeCode)
        secureCodeField(
          title: "確認のためもう一度入力", placeholder: "同じ6桁の数字", text: $managementCodeConfirmation,
          identifier: "onboarding.managementCodeConfirmation", contentType: nil)
        if let warning = ManagementCodeStore.codeWarning(managementCode), !managementCode.isEmpty {
          Text(warning).font(.footnote).foregroundStyle(.orange)
        }
        if !managementCodeConfirmation.isEmpty && managementCode != managementCodeConfirmation {
          Text("確認入力が一致しません。").font(.footnote).foregroundStyle(.red).accessibilityIdentifier(
            "onboarding.managementCodeMismatch")
        }
        if let managementCodeMessage {
          Text(managementCodeMessage).font(.footnote).foregroundStyle(.red)
        }
        Button("管理コードを設定する") {
          do {
            try model.dependencies.managementCode.setCode(managementCode)
            step += 1
          } catch { managementCodeMessage = error.localizedDescription }
        }.primaryActionStyle().disabled(
          managementCode.count != 6 || managementCode != managementCodeConfirmation
        ).accessibilityIdentifier("onboarding.managementCodeSet")
        Button("設定せずに続ける") { step += 1 }.secondaryActionStyle()
      }.studyCard()
    case 7:
      page(
        icon: "bell.badge.fill", title: "学習へ戻りやすくする",
        body: "Shieldから学習へ戻る案内と、再ロックの通知に使います。許可しなくてもロックンスタディを手動で開けば解除学習へ進めます。")
      Button("Appleの通知許可画面へ進む") {
        Task {
          _ = await NotificationService().requestAuthorization()
          step += 1
        }
      }.primaryActionStyle()
      Button("許可せずに続ける") { step += 1 }.secondaryActionStyle()
    default:
      page(
        icon: "lock.shield.fill", title: "ロックを開始する準備ができました",
        body: "完了すると選んだ対象へすぐにロックをかけ、選択した教材専用の画面を開きます。教材はあとから設定画面で変更できます。")
      if let completionError {
        Label(completionError, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote).foregroundStyle(.red).studyCard()
      }
      Button(isFinishing ? "ロックを開始中…" : "ロックを開始して教材へ") {
        Task { await completeOnboarding() }
      }
      .primaryActionStyle()
      .disabled(isFinishing)
      .accessibilityIdentifier("onboarding.finish")
    }
  }

  private func page(icon: String, title: String, body: String) -> some View {
    VStack(spacing: 20) {
      Image(systemName: icon).font(.system(size: 58)).foregroundStyle(LockAndStudyTheme.teal)
        .accessibilityHidden(true)
      Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
      Text(body).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(
        horizontal: false, vertical: true)
    }.padding(.vertical, 12)
  }
  private func nextButton() -> some View {
    Button("次へ") { step += 1 }.primaryActionStyle().accessibilityIdentifier(
      "onboarding.next.\(step)")
  }
  private func requestScreenTimeAuthorization() async {
    isRequestingAuthorization = true
    defer { isRequestingAuthorization = false }
    do {
      try await lock.requestAuthorization()
      step += 1
    } catch {
      model.alertMessage = error.localizedDescription
    }
  }
  private func completeOnboarding() async {
    isFinishing = true
    completionError = nil
    defer { isFinishing = false }
    do {
      try await model.finishOnboarding(selectedPack: selectedPack, pace: pace, review: review)
    } catch {
      completionError = error.localizedDescription
    }
  }
  private func secureCodeField(
    title: String, placeholder: String, text: Binding<String>, identifier: String,
    contentType: UITextContentType?
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline.weight(.semibold))
      SecureField(placeholder, text: text).keyboardType(.numberPad).textContentType(contentType)
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(
          Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(
            Color.secondary.opacity(0.25))
        )
        .accessibilityIdentifier(identifier)
    }
  }
}

private struct PlatformManagementInfoView: View {
  var body: some View {
    List {
      Section("しくみ") {
        Text("選択したアプリやWebサイトにAppleのShieldを表示し、教材固有の問題に正解すると決めた時間だけ一時解除します。再ロック予約に失敗した場合は解除しません。")
      }
      Section("管理") { Text("ロック対象の削減、解除時間の増加、管理コード削除などは弱化変更です。管理コード、または24時間待機後の二度目の確認で保護します。") }
      Section("プライバシー") {
        Text("教材、回答、選択対象、管理コード、購入権利は端末内とAppleの仕組みで管理します。広告・分析SDKや独自サーバー送信はありません。")
      }
      Section("解除不能への備え") { Text("固定無料教材、教材読み込み失敗時の安全な無料fallback問題、rolling 24時間に1回の緊急解除を用意しています。") }
    }.navigationTitle("しくみと管理")
  }
}
