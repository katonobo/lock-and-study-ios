import FamilyControls
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController
  @EnvironmentObject private var commerce: StoreKitCommerceService
  @State private var selection = FamilyActivitySelection()
  @State private var showPicker = false
  @State private var protectedChange: ProtectedChange?
  @State private var exportURL: URL?
  @State private var showDeleteConfirmation = false
  @State private var showPendingConfirmation = false

  var body: some View {
    List {
      Section("Screen Time") {
        LabeledContent(
          "認可", value: lock.isAuthorized ? "許可済み" : (lock.authorizationLost ? "再認可が必要" : "未許可"))
        if !lock.isAuthorized {
          Button("Appleの許可画面へ進む") { Task { try? await lock.requestAuthorization() } }
        }
        Button("ロック対象を選ぶ") { showPicker = true }.disabled(!lock.isAuthorized)
        LabeledContent("選択", value: lock.hasSelection ? "設定済み" : "未設定")
        if lock.isAuthorized && lock.hasSelection && !lock.isLockEnabled {
          Button("基本ロックを開始") {
            Task {
              do { try await lock.setLockEnabled(true) } catch {
                model.alertMessage = error.localizedDescription
              }
            }
          }
          .accessibilityIdentifier("settings.enableLock")
        }
        if lock.isLockEnabled { Button("ロック利用終了を申請", role: .destructive) { requestEndLock() } }
      }

      Section("解除ルール") {
        Picker("解除ペース", selection: paceBinding) {
          ForEach(AccessPacePreset.allCases) { Text($0.title).tag($0) }
        }
        Picker("復習量", selection: reviewBinding) {
          ForEach(ReviewLoadPreset.allCases) { Text($0.title).tag($0) }
        }
        if let pending = model.dependencies.policyStore.loadPendingChange() {
          VStack(alignment: .leading, spacing: 6) {
            Label("弱い変更は待機中です", systemImage: "hourglass")
            Text("確認可能：\(pending.availableAt.formatted())").font(.caption).foregroundStyle(
              .secondary)
            Button("二度目の確認へ") { showPendingConfirmation = true }.disabled(
              Date() < pending.availableAt)
          }
        }
      }

      Section("安全") {
        NavigationLink("管理コード") { ManagementCodeSettingsView() }
        NavigationLink("緊急解除") { EmergencyUnlockView() }
        Text("緊急解除は購入状態に関係なく、rolling 24時間に1回・15分です。").font(.footnote).foregroundStyle(.secondary)
      }

      Section("教材と購入") {
        Button {
          model.presentMaterialSelection()
        } label: {
          HStack {
            Label("教材の選択", systemImage: "books.vertical.fill")
            Spacer()
            Text(currentMaterialTitle).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
          }
        }
        .accessibilityIdentifier("settings.materialSelection")
        NavigationLink("教材の購入とStudy Pass") { PurchaseView() }
        Button("購入を復元") { Task { await commerce.restore() } }
        Link("サブスクリプションを管理", destination: AppConfiguration.subscriptionManagementURL)
      }

      Section("データ") {
        Button("旧アプリからデータを移行") { Task { await model.importLegacyData() } }
          .disabled(model.isBusy)
        Button("学習データを書き出す") { Task { exportURL = await model.exportLearningData() } }
        if let exportURL {
          ShareLink(item: exportURL) { Label("書き出しファイルを共有", systemImage: "square.and.arrow.up") }
        }
        Button("学習履歴を削除", role: .destructive) { showDeleteConfirmation = true }
        Button("すべてを初期化", role: .destructive) { requestEndLock(resetAfterEnd: true) }
      }

      Section("情報") {
        NavigationLink("コンテンツと出典") { ContentCreditsView() }
        Link("プライバシーポリシー", destination: AppConfiguration.privacyPolicyURL)
        Link("利用規約", destination: AppConfiguration.termsOfUseURL)
        Link("問い合わせ", destination: supportMailURL)
        Text("問い合わせにはロック対象、管理コード、購入取引、学習履歴を自動記入しません。").font(.caption).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("設定").accessibilityIdentifier("settings.screen")
    .familyActivityPicker(isPresented: $showPicker, selection: $selection)
    .onAppear { selection = lock.loadSelection() ?? .init() }
    .onChange(of: showPicker) { if !$0 { requestSelectionChange() } }
    .sheet(item: $protectedChange) { change in ManagementApprovalView(change: change) }
    .confirmationDialog(
      "学習履歴を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible
    ) {
      Button("学習履歴だけを削除", role: .destructive) { Task { await model.deleteLearningHistory() } }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("ロック設定、購入権利、管理コードは残ります。")
    }
    .confirmationDialog(
      "待機した変更を適用しますか？", isPresented: $showPendingConfirmation, titleVisibility: .visible
    ) {
      Button("変更を適用") { confirmPending() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("これは二度目の明示確認です。")
    }
  }

  private var paceBinding: Binding<AccessPacePreset> {
    Binding(
      get: { model.dependencies.policyStore.loadPolicy()?.accessPacePreset ?? .balanced10 },
      set: { value in
        var p = model.dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
        p.accessPacePreset = value
        p.policyVersion += 1
        p.updatedAt = Date()
        requestPolicyChange(p)
      })
  }
  private var reviewBinding: Binding<ReviewLoadPreset> {
    Binding(
      get: { model.dependencies.policyStore.loadPolicy()?.reviewLoadPreset ?? .standard },
      set: { value in
        var p = model.dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
        p.reviewLoadPreset = value
        p.policyVersion += 1
        p.updatedAt = Date()
        requestPolicyChange(p)
      })
  }
  private var currentMaterialTitle: String {
    model.manifests.first(where: { $0.id == model.selectedPackID })?.title ?? "未選択"
  }

  private func requestPolicyChange(
    _ proposed: LockPolicy, selectionData: Data? = nil, resetAfterEnd: Bool = false
  ) {
    let service = PolicyProtectionService(
      store: model.dependencies.policyStore, managementCode: model.dependencies.managementCode)
    switch service.request(proposed: proposed, selectionData: selectionData, now: Date()) {
    case .applied:
      Task {
        do {
          if let selectionData {
            let newSelection = try JSONDecoder().decode(
              FamilyActivitySelection.self, from: selectionData)
            if !newSelection.lockAndStudyIsEmpty {
              try await lock.saveSelection(newSelection)
              model.dependencies.policyStore.savePolicy(proposed)
            } else if proposed.lifecycleState != .ended {
              throw LockControllerError.selectionRequired
            }
          }
          if proposed.lifecycleState == .ended {
            try await lock.setLockEnabled(false)
            if resetAfterEnd { await resetAllAfterLockEnds() }
          }
        } catch {
          model.alertMessage = "ロック設定を適用できませんでした。以前の対象を維持します。\n\(error.localizedDescription)"
        }
      }
    case .managementCodeRequired:
      protectedChange = .init(
        proposed: proposed, selectionData: selectionData, resetAfterEnd: resetAfterEnd)
    case .cooldownScheduled(let date):
      model.alertMessage = "弱い変更は\(date.formatted())以降に、もう一度確認すると適用できます。"
    default: model.alertMessage = "変更を適用できませんでした。"
    }
  }
  private func requestSelectionChange() {
    guard let data = try? JSONEncoder().encode(selection) else {
      model.alertMessage = "選択内容を検証できませんでした。"
      return
    }
    var proposed = model.dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
    proposed.selectionSummary = selection.lockAndStudySummary(encoded: data)
    if selection.lockAndStudyIsEmpty {
      proposed.lifecycleState = .ended
      model.alertMessage = "空の選択はロック利用終了として保護されます。管理コード、または24時間待機後の確認が必要です。"
    }
    proposed.policyVersion += 1
    proposed.updatedAt = Date()
    if !lock.isLockEnabled {
      if selection.lockAndStudyIsEmpty {
        model.alertMessage = "ロック対象は1件以上選んでください。"
      } else {
        Task {
          do { try await lock.saveSelection(selection) }
          catch { model.alertMessage = error.localizedDescription }
        }
      }
    } else {
      requestPolicyChange(proposed, selectionData: data)
    }
  }
  private func requestEndLock(resetAfterEnd: Bool = false) {
    var proposed = model.dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
    proposed.lifecycleState = .ended
    proposed.policyVersion += 1
    proposed.updatedAt = Date()
    requestPolicyChange(proposed, resetAfterEnd: resetAfterEnd)
  }
  private func confirmPending() {
    let service = PolicyProtectionService(
      store: model.dependencies.policyStore, managementCode: model.dependencies.managementCode)
    guard let pending = service.validatedPending(now: Date(), secondConfirmation: true) else {
      model.alertMessage = "待機中の変更を確認できませんでした。"
      return
    }
    Task {
      do {
        if let data = pending.pendingSelectionData {
          let pendingSelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
          if !pendingSelection.lockAndStudyIsEmpty {
            try await lock.saveSelection(pendingSelection)
          } else if pending.proposedPolicy.lifecycleState != .ended {
            throw LockControllerError.selectionRequired
          }
        }
        service.commitPending(pending)
        if pending.proposedPolicy.lifecycleState == .ended {
          try await lock.setLockEnabled(false)
        }
      } catch {
        model.alertMessage = "待機中のロック設定を適用できませんでした。\n\(error.localizedDescription)"
      }
    }
  }
  private func resetAllAfterLockEnds() async {
    await model.deleteLearningHistory()
    LockAndStudySharedConstants.defaults.removePersistentDomain(
      forName: LockAndStudySharedConstants.appGroupID)
    try? model.dependencies.managementCode.removeCode()
  }
  private var supportMailURL: URL {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let body =
      "App: Lock and Study \(version)\nOS: \(os)\nLanguage: \(Locale.current.identifier)\nTime zone: \(TimeZone.current.identifier)"
    return URL(
      string:
        "mailto:support@katonobo.com?subject=Lock%20and%20Study&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    )!
  }
}

struct ProtectedChange: Identifiable {
  let id = UUID()
  let proposed: LockPolicy
  let selectionData: Data?
  let resetAfterEnd: Bool
}

private struct ManagementApprovalView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var lock: LockController
  @Environment(\.dismiss) private var dismiss
  let change: ProtectedChange
  @State private var code = ""
  @State private var errorMessage: String?
  var body: some View {
    NavigationStack {
      Form {
        Section { SecureField("6桁の管理コード", text: $code).keyboardType(.numberPad) }
        if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        Button("承認して適用") { approve() }.disabled(code.count != 6)
      }.navigationTitle("管理コードで承認").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
      }
    }
  }
  private func approve() {
    Task {
      do {
        guard try model.dependencies.managementCode.verify(code) else {
          errorMessage = "管理コードが違います。"
          return
        }
        if let data = change.selectionData {
          let selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
          if !selection.lockAndStudyIsEmpty {
            try await lock.saveSelection(selection)
          } else if change.proposed.lifecycleState != .ended {
            throw LockControllerError.selectionRequired
          }
        }
        model.dependencies.policyStore.savePolicy(change.proposed)
        if change.proposed.lifecycleState == .ended {
          try await lock.setLockEnabled(false)
          if change.resetAfterEnd {
            await model.deleteLearningHistory()
            try model.dependencies.managementCode.removeCode()
          }
        }
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct ManagementCodeSettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var current = ""
  @State private var newCode = ""
  @State private var newCodeConfirmation = ""
  @State private var message: String?
  @State private var showResetConfirmation = false
  var body: some View {
    Form {
      if model.dependencies.managementCode.hasManagementCode {
        SecureField("現在のコード", text: $current).keyboardType(.numberPad)
        SecureField("新しい6桁", text: $newCode).keyboardType(.numberPad)
        SecureField("新しい6桁をもう一度", text: $newCodeConfirmation).keyboardType(.numberPad)
        if !newCodeConfirmation.isEmpty && newCode != newCodeConfirmation {
          Text("確認入力が一致しません。").foregroundStyle(.red)
        }
        Button("コードを変更") {
          do {
            guard newCode == newCodeConfirmation else {
              message = "確認入力が一致しません。"
              return
            }
            try model.dependencies.managementCode.changeCode(currentCode: current, newCode: newCode)
            message = "変更しました"
          } catch { message = error.localizedDescription }
        }
        .disabled(newCode.count != 6 || newCode != newCodeConfirmation)
        Button("現在のコードで削除", role: .destructive) { removeWithCurrentCode() }
        if let pending = model.dependencies.policyStore.loadPendingManagementReset() {
          Text("リセット確認可能：\(pending.availableAt.formatted())").font(.footnote)
          Button("待機後の二度目確認", role: .destructive) { showResetConfirmation = true }
            .disabled(Date() < pending.availableAt)
        } else {
          Button("コードを忘れたためリセットを申請") { scheduleReset() }
        }
        Text("コードの削除・忘れた場合のリセットも弱化変更です。現在のコードで承認するか、24時間待機後に二度目の確認が必要です。").font(.footnote)
      } else {
        SecureField("新しい6桁", text: $newCode).keyboardType(.numberPad)
        SecureField("確認のためもう一度", text: $newCodeConfirmation).keyboardType(.numberPad)
        if let warning = ManagementCodeStore.codeWarning(newCode), !newCode.isEmpty {
          Text(warning).foregroundStyle(.orange)
        }
        if !newCodeConfirmation.isEmpty && newCode != newCodeConfirmation {
          Text("確認入力が一致しません。").foregroundStyle(.red)
        }
        Button("管理コードを設定") {
          do {
            guard newCode == newCodeConfirmation else {
              message = "確認入力が一致しません。"
              return
            }
            try model.dependencies.managementCode.setCode(newCode)
            message = "設定しました"
          } catch { message = error.localizedDescription }
        }
        .disabled(newCode.count != 6 || newCode != newCodeConfirmation)
      }
      if let message { Text(message) }
    }
    .navigationTitle("管理コード")
    .confirmationDialog(
      "管理コードを削除しますか？", isPresented: $showResetConfirmation, titleVisibility: .visible
    ) {
      Button("管理コードを削除", role: .destructive) { confirmReset() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("24時間の待機後に行う二度目の明示確認です。")
    }
  }

  private var resetService: ManagementCodeResetService {
    .init(codeStore: model.dependencies.managementCode, policyStore: model.dependencies.policyStore)
  }
  private func removeWithCurrentCode() {
    do {
      _ = try resetService.removeImmediately(currentCode: current)
      message = "管理コードを削除しました。"
    } catch { message = error.localizedDescription }
  }
  private func scheduleReset() {
    if case .scheduled(let date) = resetService.schedule(now: Date()) {
      message = "\(date.formatted())以降に、もう一度確認してください。"
    }
  }
  private func confirmReset() {
    do {
      switch try resetService.confirm(now: Date(), secondConfirmation: true) {
      case .removed: message = "管理コードを削除しました。"
      case .tooEarly(let date): message = "\(date.formatted())まで待つ必要があります。"
      default: message = "二度目の確認が必要です。"
      }
    } catch { message = error.localizedDescription }
  }
}

private struct ContentCreditsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var entries: [ContentCreditPresentation] = []
  @State private var isLoading = true

  var body: some View {
    List {
      if isLoading {
        ProgressView("出典を読み込み中")
      } else if entries.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.secondary)
          Text("表示できる教材がありません").font(.headline)
          Text("教材Catalogを読み込み直してください。")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
      } else {
        ForEach(entries) { entry in
          Section(entry.title) {
            LabeledContent("コンテンツ版", value: entry.contentVersion)
            if let editionYear = entry.editionYear {
              LabeledContent("年度", value: "\(editionYear)年度")
            }
            if let lawBasisDate = entry.lawBasisDate {
              LabeledContent("法令基準日", value: lawBasisDate)
            }
            if let statisticsYear = entry.statisticsYear {
              LabeledContent("統計基準年", value: "\(statisticsYear)年")
            }
            if let creditsFile = entry.creditsFile {
              LabeledContent("出典ファイル", value: creditsFile)
            }
            Text(entry.creditsText)
              .foregroundStyle(entry.creditsLoadFailed ? .secondary : .primary)
          }
        }
      }
    }
    .navigationTitle("コンテンツと出典")
    .task {
      entries = await ContentCreditsLoader().load(
        manifests: model.normalManifests,
        content: model.dependencies.content)
      isLoading = false
    }
  }
}

struct ContentCreditPresentation: Identifiable, Equatable, Sendable {
  let id: StudyPackID
  let title: String
  let editionYear: Int?
  let contentVersion: String
  let creditsFile: String?
  let lawBasisDate: String?
  let statisticsYear: Int?
  let creditsText: String
  let creditsLoadFailed: Bool
}

struct ContentCreditsLoader: Sendable {
  func load(
    manifests: [StudyPackManifest],
    content: ContentRepository
  ) async -> [ContentCreditPresentation] {
    var values: [ContentCreditPresentation] = []
    for manifest in manifests.sorted(by: { $0.sortOrder < $1.sortOrder }) {
      let credits: (text: String, failed: Bool)
      if let path = manifest.creditsFile {
        do {
          credits = (try await content.text(resourcePath: path, for: manifest.id), false)
        } catch {
          credits = ("出典情報を読み込めませんでした。教材の再読込後にもう一度確認してください。", true)
        }
      } else {
        credits = ("この教材には個別の出典ファイルが登録されていません。", false)
      }
      values.append(.init(
        id: manifest.id,
        title: manifest.title,
        editionYear: manifest.editionYear,
        contentVersion: manifest.contentVersion,
        creditsFile: manifest.creditsFile,
        lawBasisDate: manifest.qualification?.lawBasisDate,
        statisticsYear: manifest.qualification?.statisticsYear,
        creditsText: credits.text,
        creditsLoadFailed: credits.failed))
    }
    return values
  }
}
