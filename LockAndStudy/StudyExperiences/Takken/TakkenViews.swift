import SwiftUI

struct TakkenRootView: View {
  @StateObject private var model: TakkenAppModel
  @StateObject private var router: TakkenRouter
  init(context: StudyExperienceContext) {
    _model = StateObject(wrappedValue: TakkenAppModel(context: context))
    _router = StateObject(wrappedValue: TakkenRouter(destination: context.destination))
  }
  var body: some View {
    TabView(selection: $router.selectedTab) {
      NavigationStack { TakkenHomeView() }.tabItem { Label("ホーム", systemImage: "house.fill") }.tag(
        TakkenTab.home)
      NavigationStack { TakkenQuestionListView() }.tabItem {
        Label("問題", systemImage: "list.bullet.rectangle")
      }.tag(TakkenTab.questions)
      NavigationStack { TakkenPracticeMenuView() }.tabItem {
        Label("演習", systemImage: "pencil.and.list.clipboard")
      }.tag(TakkenTab.practice)
      NavigationStack { TakkenRecordsView() }.tabItem { Label("記録", systemImage: "chart.bar.fill") }
        .tag(TakkenTab.records)
      NavigationStack { TakkenSettingsView() }.tabItem {
        Label("設定", systemImage: "slider.horizontal.3")
      }.tag(TakkenTab.settings)
    }
    .tint(LockAndStudyTheme.takken)
    .environmentObject(model)
    .task { await model.load() }
    .fullScreenCover(item: $model.session) {
      TakkenStudySessionView(presentation: $0).environmentObject(model)
    }
    .alert(
      "宅建2026",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .accessibilityIdentifier("takken.root")
  }
}

struct TakkenFirstRunView: View {
  let context: StudyExperienceContext
  @State private var settings: TakkenSettings
  @State private var category = "宅建業法"
  @State private var errorMessage: String?

  init(context: StudyExperienceContext) {
    self.context = context
    _settings = State(initialValue: .load(packID: context.manifest.id))
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(systemName: "building.columns.fill").font(.system(size: 58)).foregroundStyle(
            LockAndStudyTheme.takken)
          Text("宅建2026の学習方針").font(.largeTitle.bold()).multilineTextAlignment(.center)
          Text(context.manifest.description)
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
          Picker("受験年度", selection: $settings.examYear) { Text("2026年度").tag(2026) }.pickerStyle(
            .segmented
          ).studyCard()
          VStack(alignment: .leading, spacing: 8) {
            Text("最初の分野").font(.headline)
            Picker("最初の分野", selection: $category) { Text("宅建業法").tag("宅建業法") }.pickerStyle(
              .segmented)
          }.studyCard()
          VStack(alignment: .leading, spacing: 8) {
            Text("学習方針").font(.headline)
            Toggle("直前期対象を優先", isOn: $settings.last30DaysFocus)
            Stepper(
              "1回 \(settings.questionCount)問", value: $settings.questionCount, in: 5...30, step: 5)
          }.studyCard()
          Button("宅建学習を始める") {
            settings.selectedCategories = [category]
            do {
              try settings.save(packID: context.manifest.id)
              context.completeFirstRun()
            } catch {
              errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)"
            }
          }
          .primaryActionStyle().accessibilityIdentifier("takken.firstRun.finish")
        }.frame(maxWidth: 640).padding()
      }.navigationTitle("宅建 初期設定").navigationBarTitleDisplayMode(.inline)
    }
    .alert("宅建", isPresented: .init(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }
}

private struct TakkenHomeView: View {
  @EnvironmentObject private var model: TakkenAppModel
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("宅建2026").font(.title2.bold())
            Spacer()
            Text(model.context.manifest.publishedCountLabel)
              .font(.caption.bold()).foregroundStyle(.green)
          }
          LabeledContent("試験年度", value: "2026年度")
          LabeledContent(
            "法令基準日", value: model.context.manifest.qualification?.lawBasisDate ?? "2026-04-01")
          Text("全範囲版は準備中です。校閲前の900問はこのアプリに公開していません。").font(.footnote).foregroundStyle(.orange)
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
        HStack {
          metric("回答", "\(model.summary.answerCount)問")
          metric("正答率", "\(model.summary.accuracy)%")
          metric("連続", "\(model.summary.streak)日")
        }.studyCard()
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          if let preview = model.pendingPreview,
            let question = model.visiblePendingPreviewQuestion(at: timeline.date)
          {
            TakkenPendingPreviewCard(
              question: question, payload: question.resolvedPreview, preview: preview,
              now: timeline.date, scenePhase: scenePhase)
          }
        }
        Button("おすすめ演習") { model.start(mode: .practice) }.primaryActionStyle()
          .accessibilityIdentifier("takken.start.practice")
        Button {
          Task { await model.context.beginUnlockStudy() }
        } label: {
          Label("宅建問題でロックを開く", systemImage: "lock.open.fill")
        }
        .secondaryActionStyle().accessibilityIdentifier("takken.start.unlock")
        VStack(alignment: .leading, spacing: 10) {
          Text("分野別").font(.headline)
          ForEach(model.categories, id: \.self) { category in
            let questions = model.questions.filter { $0.category == category }
            let answered = questions.filter { model.itemProgress($0).answerCount > 0 }.count
            VStack(alignment: .leading) {
              HStack {
                Text(category)
                Spacer()
                Text("\(answered)/\(questions.count)")
              }
              ProgressView(value: Double(answered), total: Double(max(1, questions.count)))
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
      }.frame(maxWidth: 720).padding()
    }.navigationTitle("宅建").accessibilityIdentifier("takken.home")
  }
  private func metric(_ title: String, _ value: String) -> some View {
    VStack {
      Text(value).font(.headline).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity)
  }
}

private struct TakkenPendingPreviewCard: View {
  @EnvironmentObject private var model: TakkenAppModel
  let question: TakkenQuestion
  let payload: TakkenPreviewPayload
  let preview: TakkenPendingPreview
  let now: Date
  let scenePhase: ScenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Label("次回の予習", systemImage: "lightbulb.fill").font(.caption.bold())
        Spacer(minLength: 8)
        Text(countdownText).font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("予習の表示はあと\(remainingSeconds)秒です")
          .accessibilityIdentifier("takken.preview.remaining")
      }
      Text(payload.title).font(.title3.bold())
      LabeledContent("分野", value: question.category)
      if let subcategory = question.subCategory {
        LabeledContent("小分野", value: subcategory)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("覚えるルール").font(.caption.bold()).foregroundStyle(.secondary)
        Text(payload.rule)
      }
      if let contrast = payload.contrast ?? question.contrastNote {
        VStack(alignment: .leading, spacing: 3) {
          Text("混同しやすい違い").font(.caption.bold()).foregroundStyle(.secondary)
          Text(contrast)
        }
      }
      if let mnemonic = payload.mnemonic {
        Label(mnemonic, systemImage: "brain.head.profile")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .studyCard()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("takken.preview.card")
    .task(id: "\(preview.id.uuidString)-\(scenePhase == .active)") {
      guard scenePhase == .active, preview.confirmedAt == nil else { return }
      do {
        try await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        await model.confirmPendingPreviewVisible(seconds: 2)
      } catch {}
    }
    .onChange(of: scenePhase) { phase in
      if phase != .active {
        Task { await model.clearPendingPreviewExposureIfUnconfirmed() }
      }
    }
  }

  private var remainingSeconds: Int {
    max(0, Int(preview.displayRemainingSeconds(at: now).rounded(.down)))
  }
  private var countdownText: String {
    String(format: "あと %d:%02d", remainingSeconds / 60, remainingSeconds % 60)
  }
}

private struct TakkenQuestionListView: View {
  @EnvironmentObject private var model: TakkenAppModel
  @State private var status = TakkenQuestionStatus.all
  @State private var category: String?
  @State private var subCategory: String?
  @State private var difficulties: Set<String> = []
  @State private var search = ""
  private var rows: [TakkenQuestion] {
    TakkenQuestionListViewModel(
      questions: model.questions, progress: model.progress, packID: model.context.manifest.id
    )
    .rows(
      status: status, category: category, subCategory: subCategory, difficulty: difficulties,
      search: search)
  }
  var body: some View {
    List {
      Section {
        Picker("状態", selection: $status) {
          ForEach(TakkenQuestionStatus.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
        Picker("分野", selection: $category) {
          Text("すべて").tag(String?.none)
          ForEach(model.categories, id: \.self) { Text($0).tag(Optional($0)) }
        }
        Picker("小分野", selection: $subCategory) {
          Text("すべて").tag(String?.none)
          ForEach(model.subCategories(category: category), id: \.self) {
            Text($0).tag(Optional($0))
          }
        }
        HStack {
          ForEach(["基礎", "標準", "応用"], id: \.self) { value in
            Button(value) {
              if difficulties.contains(value) {
                difficulties.remove(value)
              } else {
                difficulties.insert(value)
              }
            }
            .buttonStyle(.bordered).tint(
              difficulties.contains(value) ? LockAndStudyTheme.takken : .secondary)
          }
        }
      }
      Section("\(rows.count)問") {
        ForEach(rows) { question in
          NavigationLink {
            TakkenQuestionDetailView(question: question)
          } label: {
            HStack(alignment: .top) {
              Image(systemName: statusSymbol(model.itemProgress(question))).foregroundStyle(
                statusColor(model.itemProgress(question)))
              VStack(alignment: .leading, spacing: 4) {
                Text(question.prompt).lineLimit(2)
                HStack(spacing: 6) {
                  Text(question.resolvedFormat.displayName)
                    .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LockAndStudyTheme.takken.opacity(0.14), in: Capsule())
                  Text(
                    [question.subCategory, question.difficulty].compactMap { $0 }.joined(
                      separator: "・")
                  ).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }.searchable(text: $search, prompt: "問題・解説を検索").navigationTitle("問題一覧")
      .accessibilityIdentifier("takken.questions")
  }
  private func statusSymbol(_ progress: ItemProgress) -> String {
    progress.answerCount == 0
      ? "circle"
      : (progress.consecutiveCorrect > 0
        ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
  }
  private func statusColor(_ progress: ItemProgress) -> Color {
    progress.answerCount == 0 ? .secondary : (progress.consecutiveCorrect > 0 ? .green : .orange)
  }
}

private struct TakkenQuestionDetailView: View {
  @EnvironmentObject private var model: TakkenAppModel
  let question: TakkenQuestion
  @State private var isAnswerVisible = false
  private var viewModel: TakkenQuestionDetailViewModel {
    .init(question: question, answers: model.answers, packID: model.context.manifest.id)
  }
  var body: some View {
    List {
      Section("問題") {
        Text(question.prompt).font(.title3.weight(.semibold))
        Label(question.resolvedFormat.displayName, systemImage: "list.number")
      }
      Section("選択肢") {
        ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
          Label(choice.text, systemImage: "circle")
        }
      }
      if !isAnswerVisible {
        Section {
          Button("答えと解説を表示") { isAnswerVisible = true }
            .accessibilityIdentifier("takken.detail.revealAnswer")
        }
      } else {
        Section("答えと解説") {
          Label(viewModel.correctChoiceText, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityIdentifier("takken.detail.correctAnswer")
          if let short = question.shortExplanation { Text(short).font(.headline) }
          Text(viewModel.explanation)
          if let contrast = question.contrastNote {
            LabeledContent("混同しやすい違い", value: contrast)
          }
          ForEach(question.choices.filter { $0.id != question.correctChoiceID }) { choice in
            if let reason = choice.rationale ?? question.wrongChoiceRationales?[choice.id] {
              VStack(alignment: .leading, spacing: 3) {
                Text(choice.text).font(.subheadline.bold())
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
          if let key = question.keyPoint { Label(key, systemImage: "key.fill") }
        }
      }
      Section("教材情報") {
        LabeledContent("分野", value: question.category)
        if let sub = question.subCategory { LabeledContent("小分野", value: sub) }
        LabeledContent("難易度", value: question.difficulty)
        if let year = question.examYear { LabeledContent("年度", value: "\(year)") }
        if let basis = question.lawBasisDate { LabeledContent("法令基準日", value: basis) }
        if let importance = question.importance { LabeledContent("重要度", value: importance) }
        if question.requiresAnnualReview || question.requiresAnnualUpdate {
          Label("年度更新確認が必要な論点", systemImage: "calendar.badge.exclamationmark").foregroundStyle(
            .orange)
        }
        if let source = question.sourceNote {
          Text(source).font(.footnote).foregroundStyle(.secondary)
        }
      }
      Section("回答履歴") {
        if viewModel.answerHistory.isEmpty { Text("まだ回答していません").foregroundStyle(.secondary) }
        ForEach(viewModel.answerHistory) { answer in
          LabeledContent(answer.answeredAt.formatted(), value: answer.isCorrect ? "正解" : "不正解")
        }
      }
    }.navigationTitle("問題詳細").navigationBarTitleDisplayMode(.inline)
      .accessibilityIdentifier("takken.detail.screen")
  }
}

private struct TakkenPracticeMenuView: View {
  @EnvironmentObject private var model: TakkenAppModel
  var body: some View {
    List {
      Section("演習モード") {
        row("おすすめ", "未回答を優先して出題", "sparkles", .practice)
        row("未回答", "まだ解いていない問題", "circle.dashed", .newItems)
        row("誤答復習", "間違えた問題を再確認", "arrow.counterclockwise.circle.fill", .mistakes)
        row("苦手優先", "誤答率と重要度から選択", "exclamationmark.triangle.fill", .weakness)
      }
      Section("現在の条件") {
        LabeledContent("問題数", value: "\(model.settings.questionCount)問")
        LabeledContent(
          "難易度",
          value: model.settings.selectedDifficulties.isEmpty
            ? "すべて" : model.settings.selectedDifficulties.sorted().joined(separator: "・"))
        LabeledContent(
          "分野",
          value: model.settings.selectedCategories.isEmpty
            ? "すべて" : model.settings.selectedCategories.sorted().joined(separator: "・"))
        LabeledContent("直前期", value: model.settings.last30DaysFocus ? "対象問題を優先" : "通常")
      }
    }.navigationTitle("演習").accessibilityIdentifier("takken.practice")
  }
  private func row(_ title: String, _ detail: String, _ icon: String, _ mode: StudyMode)
    -> some View
  {
    Button {
      model.start(mode: mode)
    } label: {
      Label {
        VStack(alignment: .leading) {
          Text(title).font(.headline)
          Text(detail).font(.caption).foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: icon).foregroundStyle(LockAndStudyTheme.takken)
      }
    }.buttonStyle(.plain).frame(minHeight: 48)
  }
}

private struct TakkenRecordsView: View {
  @EnvironmentObject private var model: TakkenAppModel
  var body: some View {
    List {
      Section {
        LearningReportEntryCard(
          context: model.context,
          accessibilityID: "report.entry.takken")
      }
      Section("概要") {
        LabeledContent("回答", value: "\(model.summary.answerCount)問")
        LabeledContent("正答率", value: "\(model.summary.accuracy)%")
        LabeledContent("誤答", value: "\(model.summary.wrongCount)問")
        LabeledContent("連続学習", value: "\(model.summary.streak)日")
      }
      Section("分野別") {
        ForEach(model.summary.byCategory.keys.sorted(), id: \.self) { category in
          let value = model.summary.byCategory[category] ?? (0, 0)
          let rate =
            value.answered == 0 ? 0 : Int(Double(value.correct) / Double(value.answered) * 100)
          LabeledContent(category, value: "\(value.answered)問・\(rate)%")
        }
      }
      Section("小分野別") {
        ForEach(model.summary.bySubCategory.keys.sorted(), id: \.self) { subCategory in
          let value = model.summary.bySubCategory[subCategory] ?? (0, 0)
          let rate =
            value.answered == 0 ? 0 : Int(Double(value.correct) / Double(value.answered) * 100)
          LabeledContent(subCategory, value: "\(value.answered)問・\(rate)%")
        }
      }
      Section("最近の誤答") {
        ForEach(model.answers.filter { !$0.isCorrect }.suffix(30).reversed()) { answer in
          NavigationLink {
            if let question = model.questions.first(where: { $0.id == answer.itemID.rawValue }) {
              TakkenQuestionDetailView(question: question)
            }
          } label: {
            VStack(alignment: .leading) {
              Text(answer.prompt).lineLimit(2)
              Text(answer.answeredAt.formatted()).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }.navigationTitle("宅建の記録").accessibilityIdentifier("takken.records")
  }
}

private struct TakkenSettingsView: View {
  @EnvironmentObject private var model: TakkenAppModel
  var body: some View {
    Form {
      Section("教材") {
        Button {
          model.context.openMaterialSelection()
        } label: {
          HStack {
            Label("教材の選択", systemImage: "books.vertical.fill")
            Spacer()
            Text(model.context.manifest.title).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
          }
        }
        .accessibilityIdentifier("takken.settings.materialSelection")
      }
      Section("受験") {
        Picker("受験年度", selection: binding(\.examYear)) { Text("2026年度").tag(2026) }
        Toggle("直前期対象だけを優先", isOn: binding(\.last30DaysFocus))
      }
      Section("分野") {
        ForEach(model.categories, id: \.self) { category in
          Toggle(
            category,
            isOn: Binding(
              get: { model.settings.selectedCategories.contains(category) },
              set: { enabled in
                if enabled {
                  model.settings.selectedCategories.insert(category)
                } else {
                  model.settings.selectedCategories.remove(category)
                }
                model.saveSettings()
              }))
        }
      }
      Section("難易度") {
        ForEach(["基礎", "標準", "応用"], id: \.self) { difficulty in
          Toggle(
            difficulty,
            isOn: Binding(
              get: { model.settings.selectedDifficulties.contains(difficulty) },
              set: { enabled in
                if enabled {
                  model.settings.selectedDifficulties.insert(difficulty)
                } else {
                  model.settings.selectedDifficulties.remove(difficulty)
                }
                model.saveSettings()
              }))
        }
        Stepper(
          "1回 \(model.settings.questionCount)問", value: binding(\.questionCount), in: 5...30,
          step: 5)
      }
      Section("ロックンスタディ") {
        NavigationLink("ロックと共通設定") { SettingsView() }
        Text("Screen Timeと解除ルールはすべての教材で共通です。").font(.footnote).foregroundStyle(.secondary)
      }
      Section("販売状態") {
        Label(
          "\(model.context.manifest.publishedStructureDescription)を利用中",
          systemImage: "checkmark.circle.fill")
        Text("全範囲版は準備中です。購入操作は表示しません。").foregroundStyle(.orange)
      }
    }.navigationTitle("宅建設定").accessibilityIdentifier("takken.settings")
  }
  private func binding<Value>(_ keyPath: WritableKeyPath<TakkenSettings, Value>) -> Binding<Value> {
    .init(
      get: { model.settings[keyPath: keyPath] },
      set: {
        model.settings[keyPath: keyPath] = $0
        model.saveSettings()
      })
  }
}

private struct TakkenStudySessionView: View {
  @EnvironmentObject private var model: TakkenAppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let presentation: TakkenSessionPresentation
  @State private var index = 0
  @State private var machine = TakkenAnswerStateMachine()
  @State private var isSubmitting = false
  @State private var submissionError: String?
  @State private var inactiveAt: Date?
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(
            value: Double(index + 1), total: Double(max(1, presentation.questions.count)))
          Text("\(index + 1) / \(presentation.questions.count)")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
          if let question = presentation.questions[safe: index] {
            questionHeader(
              category: question.source.category, difficulty: question.source.difficulty,
              format: question.source.resolvedFormat, prompt: question.source.prompt,
              lawBasisDate: question.source.lawBasisDate)
            ForEach(question.presentedChoices) { choice in
              TakkenAnswerChoiceButton(
                choice: choice, phase: machine.phase,
                action: { submit(choice.id, question: question) })
                .disabled(!isAnswering || isSubmitting)
            }
            if !isAnswering {
              TakkenAnswerReviewCard(
                phase: machine.phase,
                remainingSeconds: machine.remainingSeconds(at: Date()),
                retry: { _ = machine.retry() },
                nextTitle: index + 1 == presentation.questions.count ? "完了" : "次へ",
                nextAction: advance)
            }
          }
        }.frame(maxWidth: 720).padding()
      }
      .navigationTitle("宅建演習").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
      }
    }
    .onReceive(timer) { now in
      guard scenePhase == .active else { return }
      machine.update(at: now)
    }
    .onChange(of: scenePhase, perform: handleScenePhase)
    .accessibilityIdentifier("takken.study.session")
    .answerSubmissionAlert(message: $submissionError)
  }

  private var isAnswering: Bool {
    if case .answering = machine.phase { return true }
    return false
  }

  private func submit(_ choiceID: Int, question: TakkenPresentedQuestion) {
    guard isAnswering else { return }
    isSubmitting = true
    let date = Date()
    Task {
      let result = await model.recordAnswer(
        question: question, selectedChoiceID: choiceID, sessionID: presentation.id,
        attempt: machine.wrongAttemptCount)
      switch result {
      case .recordedCorrect, .recordedIncorrect:
        machine.record(selectedChoiceID: choiceID, question: question, at: date)
      case .failed(let message):
        submissionError = message
      }
      isSubmitting = false
    }
  }

  private func advance() {
    if index + 1 < presentation.questions.count {
      index += 1
      machine = .init()
    } else {
      model.session = nil
      dismiss()
    }
  }

  private func handleScenePhase(_ phase: ScenePhase) {
    if phase == .active {
      if let inactiveAt { machine.delayReview(by: Date().timeIntervalSince(inactiveAt)) }
      inactiveAt = nil
    } else if inactiveAt == nil {
      inactiveAt = Date()
    }
  }
}

struct TakkenUnlockChallengeView: View {
  let bundle: ExperienceUnlockBundleSnapshot
  let context: UnlockChallengeViewContext
  @Environment(\.scenePhase) private var scenePhase
  @State private var index: Int
  @State private var completedQuestionIDs: Set<StudyItemID>
  @State private var machine = TakkenAnswerStateMachine()
  @State private var reviewRemainingSeconds = 0
  @State private var isReviewSyncing = false
  @State private var pendingReviewActiveState: Bool?
  @State private var isSubmitting = false
  @State private var submissionError: String?
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let feedbackPlanner = TakkenFeedbackPlanner()

  init(bundle: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) {
    self.bundle = bundle
    self.context = context
    let initialIndex = bundle.challenge.questions.firstIndex {
      !bundle.completedQuestionIDs.contains($0.id)
    } ?? 0
    _index = State(initialValue: initialIndex)
    _completedQuestionIDs = State(initialValue: bundle.completedQuestionIDs)
    if let snapshot = bundle.challenge.questions[safe: initialIndex],
      case .takken(let question) = snapshot,
      let selectedChoiceID = bundle.lastSelectedChoiceIDByQuestionID?[question.id.rawValue]
    {
      let now = Date()
      let remaining = bundle.reviewRemainingActiveSecondsByQuestionID?[question.id.rawValue]
        ?? bundle.reviewRequiredUntilByQuestionID?[question.id.rawValue]
          .map { max(0, $0.timeIntervalSince(now)) }
        ?? 0
      _machine = State(initialValue: .init(
        restoring: question,
        selectedChoiceID: selectedChoiceID,
        wrongAttemptCount: bundle.attemptCountsByQuestionID?[question.id.rawValue] ?? 1,
        reviewRemainingActiveSeconds: remaining,
        now: now))
      _reviewRemainingSeconds = State(initialValue: max(0, Int(ceil(remaining))))
    } else {
      _machine = State(initialValue: .init())
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(
            value: Double(completedQuestionIDs.count),
            total: Double(max(1, bundle.challenge.questions.count)))
            .accessibilityValue("\(completedQuestionIDs.count)/\(bundle.challenge.questions.count)")
            .accessibilityIdentifier("takken.unlock.progress")
          if let snapshot = bundle.challenge.questions[safe: index],
            case .takken(let question) = snapshot
          {
            questionHeader(
              category: question.category, difficulty: question.difficulty,
              format: TakkenQuestionFormat(rawValue: question.format) ?? .multipleChoice,
              prompt: question.prompt, lawBasisDate: question.lawBasisDate)
            ForEach(question.choices) { choice in
              TakkenAnswerChoiceButton(
                choice: choice, phase: machine.phase,
                action: { submit(snapshot, question: question, choiceID: choice.id) })
                .disabled(!isAnswering || isSubmitting)
            }
            if !isAnswering {
              TakkenAnswerReviewCard(
                phase: machine.phase,
                remainingSeconds: reviewRemainingSeconds,
                retry: { _ = machine.retry() },
                nextTitle: isLast ? "解除する" : "次へ",
                nextAction: advance)
            }
          }
        }.frame(maxWidth: 720).padding()
      }.navigationTitle("宅建で解除").navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled()
    .onReceive(timer) { _ in
      guard scenePhase == .active, isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: true) }
    }
    .onChange(of: scenePhase, perform: handleScenePhase)
    .onAppear {
      guard scenePhase == .active, isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: true) }
    }
    .onDisappear {
      guard isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: false) }
    }
    .accessibilityIdentifier("unlock.takken")
    .answerSubmissionAlert(message: $submissionError, title: "解除問題")
  }

  private var isAnswering: Bool {
    if case .answering = machine.phase { return true }
    return false
  }
  private var isLast: Bool {
    !bundle.hasLaterUncompletedQuestion(
      after: index, completedQuestionIDs: completedQuestionIDs)
  }
  private var isReviewingWrong: Bool {
    if case .reviewingWrong = machine.phase { return true }
    return false
  }

  private func submit(
    _ snapshot: UnlockQuestionSnapshot, question: TakkenUnlockQuestionSnapshot, choiceID: Int
  ) {
    guard isAnswering else { return }
    let correct = choiceID == question.correctChoiceID
    let ordinal = machine.wrongAttemptCount + (correct ? 0 : 1)
    let plan = feedbackPlanner.plan(wrongAttemptCount: correct ? 0 : ordinal)
    let date = Date()
    isSubmitting = true
    Task {
      switch await context.submit(snapshot, choiceID, plan) {
      case .recordedCorrect:
        machine.record(selectedChoiceID: choiceID, question: question, at: date)
        completedQuestionIDs.insert(question.id)
        reviewRemainingSeconds = 0
      case .recordedIncorrect(let remainingActiveSeconds, let attemptNumber):
        machine.record(
          selectedChoiceID: choiceID,
          question: question,
          authoritativeRemainingActiveSeconds: remainingActiveSeconds,
          attemptNumber: attemptNumber,
          at: date)
        reviewRemainingSeconds = remainingActiveSeconds
        await synchronizeReviewExposure(isActive: scenePhase == .active)
      case .expired:
        submissionError = "解除問題の有効時間が終了しました。新しい問題でやり直してください。"
      case .failed(let message):
        submissionError = "回答を保存できませんでした。\n\(message)"
      }
      isSubmitting = false
    }
  }

  private func advance() {
    if let next = bundle.nextUncompletedQuestionIndex(
      after: index, completedQuestionIDs: completedQuestionIDs)
    {
      index = next
      machine = .init()
      reviewRemainingSeconds = 0
    } else {
      Task { await context.complete() }
    }
  }

  private func handleScenePhase(_ phase: ScenePhase) {
    guard isReviewingWrong else { return }
    Task { await synchronizeReviewExposure(isActive: phase == .active) }
  }

  @MainActor
  private func synchronizeReviewExposure(isActive: Bool) async {
    if isReviewSyncing {
      pendingReviewActiveState = isActive
      return
    }
    guard let question = bundle.challenge.questions[safe: index] else { return }
    isReviewSyncing = true
    var desiredActiveState = isActive
    repeat {
      pendingReviewActiveState = nil
      switch await context.updateReviewExposure(question.id, desiredActiveState) {
      case .updated(let remainingActiveSeconds):
        reviewRemainingSeconds = remainingActiveSeconds
        machine.updateReviewRemaining(activeSeconds: remainingActiveSeconds, at: Date())
      case .expired:
        submissionError = "解除問題の有効時間が終了しました。新しい問題でやり直してください。"
      case .failed(let message):
        submissionError = "解説確認時間を保存できませんでした。\n\(message)"
      }
      guard let pending = pendingReviewActiveState else { break }
      desiredActiveState = pending
    } while true
    isReviewSyncing = false
    if let pending = pendingReviewActiveState {
      pendingReviewActiveState = nil
      await synchronizeReviewExposure(isActive: pending)
    }
  }
}

private struct TakkenAnswerChoiceButton: View {
  let choice: StudyChoice
  let phase: TakkenAnswerPhase
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
        Text(choice.text).multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        if let statusText { Text(statusText).font(.caption.bold()) }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    .secondaryActionStyle()
    .foregroundStyle(color)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier(identifier ?? "takken.answer.choice.\(choice.id)")
  }

  private var reviewIDs: (selected: Int?, correct: Int?) {
    switch phase {
    case .reviewingWrong(let value), .readyToRetry(let value):
      return (value.selectedChoiceID, value.correctChoiceID)
    case .answeredCorrect(let value):
      return (value.selectedChoiceID, value.correctChoiceID)
    case .answering: return (nil, nil)
    }
  }
  private var isSelectedWrong: Bool {
    reviewIDs.selected == choice.id && reviewIDs.correct != choice.id
  }
  private var isCorrect: Bool { reviewIDs.correct == choice.id }
  private var icon: String {
    isSelectedWrong ? "xmark.circle.fill" : (isCorrect ? "checkmark.circle.fill" : "circle")
  }
  private var color: Color { isSelectedWrong ? .orange : (isCorrect ? .green : .primary) }
  private var statusText: String? {
    isSelectedWrong ? "あなたの回答・不正解" : (isCorrect ? "正しい回答" : nil)
  }
  private var accessibilityText: String {
    [choice.text, statusText].compactMap { $0 }.joined(separator: "、")
  }
  private var identifier: String? {
    isSelectedWrong ? "takken.answer.selectedWrong" : (isCorrect ? "takken.answer.correct" : nil)
  }
}

private struct TakkenAnswerReviewCard: View {
  let phase: TakkenAnswerPhase
  let remainingSeconds: Int
  let retry: () -> Void
  let nextTitle: String
  let nextAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch phase {
      case .reviewingWrong(let state):
        wrongReview(state, canRetry: false)
      case .readyToRetry(let state):
        wrongReview(state, canRetry: true)
      case .answeredCorrect(let state):
        correctReview(state)
      case .answering:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .studyCard()
  }

  @ViewBuilder
  private func wrongReview(_ state: TakkenWrongReviewState, canRetry: Bool) -> some View {
    Label("不正解", systemImage: "xmark.circle.fill")
      .font(.title3.bold()).foregroundStyle(.orange)
    explanation(state.explanation)
    if canRetry {
      Button("もう一度解く", action: retry).primaryActionStyle()
        .accessibilityIdentifier("takken.review.retry")
    } else {
      Text("解説を確認してください　あと\(remainingSeconds)秒")
        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        .accessibilityLabel("解説確認中です")
        .accessibilityIdentifier("takken.review.remaining")
    }
  }

  @ViewBuilder
  private func correctReview(_ state: TakkenCorrectReviewState) -> some View {
    Label(
      state.wasRelearned ? "学び直し完了" : "正解",
      systemImage: "checkmark.circle.fill")
      .font(.title3.bold()).foregroundStyle(.green)
      .accessibilityIdentifier(state.wasRelearned ? "takken.review.completed" : "takken.review.correct")
    if state.wasRelearned {
      textBlock("正しいルール", state.explanation.rule)
    } else {
      textBlock("ポイント", state.explanation.whyWrong)
      if let key = state.explanation.keyPoint { Label(key, systemImage: "key.fill") }
    }
    Button(nextTitle, action: nextAction).primaryActionStyle()
      .accessibilityIdentifier(nextTitle == "解除する" ? "takken.review.unlock" : "takken.review.next")
  }

  @ViewBuilder
  private func explanation(_ value: TakkenExplanationPresentation) -> some View {
    textBlock("あなたの回答", value.selectedText)
      .accessibilityIdentifier("takken.review.selectedAnswer")
    textBlock("正しい回答", value.correctText)
      .accessibilityIdentifier("takken.review.correctAnswer")
    textBlock("なぜ違うか", value.whyWrong)
    textBlock("正しいルール", value.rule)
    if let contrast = value.contrast { textBlock("混同しやすい違い", contrast) }
    if let key = value.keyPoint { Label(key, systemImage: "key.fill") }
    if value.lawBasisDate != nil || value.sourceNote != nil {
      Text([value.lawBasisDate.map { "法令基準日 \($0)" }, value.sourceNote]
        .compactMap { $0 }.joined(separator: "・"))
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func textBlock(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.caption.bold()).foregroundStyle(.secondary)
      Text(value)
    }
  }
}

private func questionHeader(
  category: String, difficulty: String, format: TakkenQuestionFormat, prompt: String,
  lawBasisDate: String?
) -> some View {
  VStack(alignment: .leading, spacing: 8) {
    HStack {
      Text(category).font(.caption.bold())
      Text(format.displayName).font(.caption.bold())
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(LockAndStudyTheme.takken.opacity(0.14), in: Capsule())
      Spacer()
      Text(difficulty).font(.caption)
    }
    Text(prompt).font(.title2.bold())
    if let lawBasisDate {
      Text("法令基準日 \(lawBasisDate)").font(.caption).foregroundStyle(.secondary)
    }
  }
  .frame(maxWidth: .infinity, alignment: .leading)
  .studyCard()
}

private extension View {
  func answerSubmissionAlert(
    message: Binding<String?>, title: String = "回答を保存できませんでした"
  ) -> some View {
    alert(title, isPresented: .init(
      get: { message.wrappedValue != nil },
      set: { if !$0 { message.wrappedValue = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(message.wrappedValue ?? "")
    }
  }
}
