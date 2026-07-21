import SwiftUI

struct VocabularyRootView: View {
  @StateObject private var model: VocabularyAppModel
  @StateObject private var router: VocabularyRouter

  init(context: StudyExperienceContext) {
    _model = StateObject(wrappedValue: VocabularyAppModel(context: context))
    _router = StateObject(wrappedValue: VocabularyRouter(destination: context.destination))
  }

  var body: some View {
    TabView(selection: $router.selectedTab) {
      NavigationStack { VocabularyHomeView() }
        .tabItem { Label("ホーム", systemImage: "house.fill") }.tag(VocabularyTab.home)
      NavigationStack { VocabularyLearningView() }
        .tabItem { Label("学習", systemImage: "brain.head.profile") }.tag(VocabularyTab.learning)
      NavigationStack { VocabularyWordbookView() }
        .tabItem { Label("単語帳", systemImage: "character.book.closed.fill") }.tag(
          VocabularyTab.words)
      NavigationStack { VocabularyRecordsView() }
        .tabItem { Label("記録", systemImage: "chart.bar.fill") }.tag(VocabularyTab.records)
      NavigationStack { VocabularySettingsView() }
        .tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(VocabularyTab.settings)
    }
    .tint(LockAndStudyTheme.vocabulary)
    .environmentObject(model)
    .task { await model.load() }
    .fullScreenCover(item: $model.session) { session in
      VocabularyStudySessionView(presentation: session).environmentObject(model)
    }
    .alert(
      "英単語",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .accessibilityIdentifier("vocabulary.root")
  }
}

struct VocabularyFirstRunView: View {
  let context: StudyExperienceContext
  @State private var settings = VocabularySettings.load()
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(systemName: "character.book.closed.fill")
            .font(.system(size: 58)).foregroundStyle(LockAndStudyTheme.vocabulary)
          Text("英単語の学習コース").font(.largeTitle.bold()).multilineTextAlignment(.center)
          Text("5レベルから最初の範囲を選びます。無料250語は各レベル50語で、あとから変更できます。")
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
          VStack(spacing: 10) {
            ForEach(VocabularyLevel.allCases) { level in
              Button {
                settings.selectedLevelCodes = [level.rawValue]
              } label: {
                HStack {
                  Image(
                    systemName: settings.selectedLevelCodes.contains(level.rawValue)
                      ? "checkmark.circle.fill" : "circle")
                  VStack(alignment: .leading) {
                    Text(level.title).font(.headline)
                    Text("無料50語").font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                }
              }.secondaryActionStyle()
            }
          }.studyCard()
          Toggle("問題文と単語を読み上げる", isOn: $settings.speechEnabled).studyCard()
          Stepper("1日の目標 \(settings.dailyGoal)問", value: $settings.dailyGoal, in: 5...30, step: 5)
            .studyCard()
          Button("英単語を始める") {
            do {
              try settings.save()
              context.completeFirstRun()
            } catch {
              errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)"
            }
          }
          .primaryActionStyle().accessibilityIdentifier("vocabulary.firstRun.finish")
        }.frame(maxWidth: 640).padding()
      }.navigationTitle("英単語 初期設定").navigationBarTitleDisplayMode(.inline)
    }
    .alert("英単語", isPresented: .init(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }
}

private struct VocabularyHomeView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          Text("今日の英単語").font(.title2.bold())
          HStack {
            metric("学習済み", value: "\(model.learnedCount)語")
            metric("復習期限", value: "\(model.dueCount)語")
            metric("連続", value: "\(model.weeklyReport.streak)日")
          }
        }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          if let preview = model.pendingPreview,
            let item = model.visiblePendingPreviewItem(at: timeline.date)
          {
            VocabularyPendingPreviewCard(
              item: item,
              preview: preview,
              now: timeline.date,
              examplesEnabled: model.settings.examplesEnabled,
              scenePhase: scenePhase
            )
          }
        }
        Button("自動で10問学ぶ") { model.start(mode: .practice) }.primaryActionStyle()
          .accessibilityIdentifier("vocabulary.start.practice")
        Button {
          Task { await model.context.beginUnlockStudy() }
        } label: {
          Label("学習してロックを開く", systemImage: "lock.open.fill")
        }.secondaryActionStyle().accessibilityIdentifier("vocabulary.start.unlock")
      }.frame(maxWidth: 720).padding()
    }.navigationTitle("英単語").accessibilityIdentifier("vocabulary.home")
  }
  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.headline).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct VocabularyPendingPreviewCard: View {
  @EnvironmentObject private var model: VocabularyAppModel
  let item: VocabularyItem
  let preview: VocabularyPendingPreview
  let now: Date
  let examplesEnabled: Bool
  let scenePhase: ScenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("次回の予習").font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(countdownText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel(countdownAccessibilityLabel)
      }
      Text(item.displayWord).font(.largeTitle.bold())
      Text(item.quizMeaningJa).font(.title3.weight(.semibold))
      if examplesEnabled {
        Text(item.exampleEn)
        Text(item.exampleJa).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .studyCard()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("vocabulary.nextWordPreviewCard")
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
  private var countdownAccessibilityLabel: String {
    let minutes = remainingSeconds / 60
    let seconds = remainingSeconds % 60
    if minutes == 0 { return "予習の表示はあと\(seconds)秒です" }
    return "予習の表示はあと\(minutes)分\(seconds)秒です"
  }
}

private struct VocabularyLearningView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  var body: some View {
    List {
      Section("学習モード") {
        modeRow("おすすめ", detail: "期限到来復習→新出→定着確認", icon: "sparkles", mode: .practice)
        modeRow("期限到来復習", detail: "SRSで今日が期限の単語だけ", icon: "calendar.badge.clock", mode: .review)
        modeRow("新出", detail: "まだ答えていない単語", icon: "plus.circle.fill", mode: .newItems)
        modeRow(
          "誤答", detail: "間違えたことがある単語", icon: "arrow.counterclockwise.circle.fill", mode: .mistakes)
        modeRow("苦手", detail: "誤答が正答以上の単語", icon: "exclamationmark.triangle.fill", mode: .weakness)
      }
      Section("学習範囲") {
        ForEach(VocabularyLevel.allCases) { level in
          let total = model.items.filter { $0.levelCode == level.rawValue }.count
          let learned = model.items.filter {
            $0.levelCode == level.rawValue && model.itemProgress($0).answerCount > 0
          }.count
          VStack(alignment: .leading) {
            HStack {
              Text(level.title)
              Spacer()
              Text("\(learned)/\(total)").monospacedDigit()
            }
            ProgressView(value: Double(learned), total: Double(max(1, total)))
          }
        }
      }
    }.navigationTitle("学習").accessibilityIdentifier("vocabulary.learning")
  }
  private func modeRow(_ title: String, detail: String, icon: String, mode: StudyMode) -> some View
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
        Image(systemName: icon).foregroundStyle(LockAndStudyTheme.vocabulary)
      }
    }.buttonStyle(.plain).frame(minHeight: 48)
  }
}

private struct VocabularyWordbookView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  @State private var search = ""
  @State private var level: VocabularyLevel?
  private var filtered: [VocabularyItem] {
    model.items.filter { item in
      (level == nil || item.levelCode == level?.rawValue)
        && (search.isEmpty || item.displayWord.localizedCaseInsensitiveContains(search)
          || item.quizMeaningJa.localizedCaseInsensitiveContains(search))
    }
  }
  var body: some View {
    List {
      Section {
        Picker("レベル", selection: $level) {
          Text("すべて").tag(VocabularyLevel?.none)
          ForEach(VocabularyLevel.allCases) { Text($0.title).tag(Optional($0)) }
        }
      }
      ForEach(filtered, id: \.id) { item in
        NavigationLink {
          VocabularyWordDetailView(item: item)
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(item.displayWord).font(.headline)
              Text(item.quizMeaningJa).foregroundStyle(.secondary)
            }
            Spacer()
            Image(
              systemName: model.itemProgress(item).answerCount == 0
                ? "circle" : "checkmark.circle.fill"
            )
            .foregroundStyle(
              model.itemProgress(item).answerCount == 0 ? Color.secondary : Color.green)
          }
        }
      }
    }.searchable(text: $search, prompt: "英単語・意味を検索").navigationTitle("単語帳")
      .accessibilityIdentifier("vocabulary.wordbook")
  }
}

private struct VocabularyWordDetailView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  let item: VocabularyItem
  private let speech = SpeechService()
  var body: some View {
    List {
      Section {
        Text(item.displayWord).font(.largeTitle.bold())
        Text(item.fullMeaningJa).font(.title3)
        Text(item.partOfSpeechJa).foregroundStyle(.secondary)
      }
      Section("例文") {
        Text(item.exampleEn)
        Text(item.exampleJa).foregroundStyle(.secondary)
      }
      Section("学習") {
        let progress = model.itemProgress(item)
        LabeledContent("回答", value: "\(progress.answerCount)回")
        LabeledContent("正解", value: "\(progress.correctCount)回")
        if let due = progress.dueAt { LabeledContent("次回復習", value: due.formatted()) }
      }
      Button {
        speech.speak(item.speechText)
      } label: {
        Label("発音を聞く", systemImage: "speaker.wave.2.fill")
      }
    }.navigationTitle(item.displayWord).navigationBarTitleDisplayMode(.inline)
  }
}

private struct VocabularyRecordsView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  var body: some View {
    List {
      Section("今週") {
        LabeledContent("回答", value: "\(model.weeklyReport.answers)問")
        LabeledContent("正答率", value: "\(model.weeklyReport.accuracy)%")
        LabeledContent("学習済み", value: "\(model.weeklyReport.learned)語")
        LabeledContent("期限到来", value: "\(model.weeklyReport.due)語")
        LabeledContent("連続学習", value: "\(model.weeklyReport.streak)日")
      }
      Section("最近の回答") {
        ForEach(model.answers.suffix(50).reversed()) { answer in
          HStack {
            Image(systemName: answer.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
              .foregroundStyle(answer.isCorrect ? .green : .orange)
            VStack(alignment: .leading) {
              Text(answer.prompt).lineLimit(1)
              Text(answer.answeredAt.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
          }
        }
      }
      Section("レベル別") {
        ForEach(VocabularyLevel.allCases) { level in
          let values = model.answers.filter { $0.category == level.rawValue }
          LabeledContent(level.title, value: "\(values.count)問・\(accuracy(values))%")
        }
      }
      Section("品詞別") {
        ForEach(
          Dictionary(
            grouping: model.answers.compactMap { answer in answer.subcategory.map { ($0, answer) }
            }, by: { $0.0 }
          ).keys.sorted(), id: \.self
        ) { part in
          let values = model.answers.filter { $0.subcategory == part }
          LabeledContent(part, value: "\(values.count)問・\(accuracy(values))%")
        }
      }
    }.navigationTitle("英単語の記録").accessibilityIdentifier("vocabulary.records")
  }
  private func accuracy(_ answers: [StudyAnswerRecord]) -> Int {
    answers.isEmpty
      ? 0 : Int(Double(answers.filter(\.isCorrect).count) / Double(answers.count) * 100)
  }
}

private struct VocabularySettingsView: View {
  @EnvironmentObject private var model: VocabularyAppModel
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
        .accessibilityIdentifier("vocabulary.settings.materialSelection")
      }
      Section("コース") {
        ForEach(VocabularyLevel.allCases) { level in
          Toggle(
            level.title,
            isOn: Binding(
              get: { model.settings.selectedLevelCodes.contains(level.rawValue) },
              set: { enabled in
                if enabled {
                  model.settings.selectedLevelCodes.insert(level.rawValue)
                } else if model.settings.selectedLevelCodes.count > 1 {
                  model.settings.selectedLevelCodes.remove(level.rawValue)
                }
                model.saveSettings()
              }
            ))
        }
      }
      Section("学習") {
        Stepper(
          "1日の目標 \(model.settings.dailyGoal)問",
          value: Binding(
            get: { model.settings.dailyGoal },
            set: {
              model.settings.dailyGoal = $0
              model.saveSettings()
            }), in: 5...30, step: 5)
        Toggle(
          "発音",
          isOn: Binding(
            get: { model.settings.speechEnabled },
            set: {
              model.settings.speechEnabled = $0
              model.saveSettings()
            }))
        Toggle(
          "例文",
          isOn: Binding(
            get: { model.settings.examplesEnabled },
            set: {
              model.settings.examplesEnabled = $0
              model.saveSettings()
            }))
      }
      Section("ロックンスタディ") {
        NavigationLink("ロックと共通設定") { SettingsView() }
        Text("Screen Time、解除ペース、管理コードはすべての教材で共通です。").font(.footnote).foregroundStyle(.secondary)
      }
      Section("利用状態") {
        if model.context.dependencies.commerce.entitlement.activePass?.permitsAccess == true {
          Label("Study Passで利用中", systemImage: "checkmark.seal.fill")
        } else if model.context.dependencies.commerce.entitlement.ownedPacks.contains(where: {
          $0.packID == model.context.manifest.id
        }) {
          Label("英単語3,000語を永久購入済み", systemImage: "checkmark.circle.fill")
        } else {
          Text("無料250語")
        }
      }
    }.navigationTitle("英単語設定").accessibilityIdentifier("vocabulary.settings")
  }
}

private struct VocabularyStudySessionView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let presentation: VocabularySessionPresentation
  @State private var index = 0
  @State private var selected: Int?
  @State private var attempts = 0
  @State private var waitRemaining = 0
  @State private var plan = StudyFeedbackPlan.immediate
  @State private var isSubmitting = false
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let speech = SpeechService()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(value: Double(index + 1), total: Double(max(1, presentation.questions.count)))
          Text("\(index + 1) / \(presentation.questions.count)")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
          if let question = presentation.questions[safe: index] {
            VStack(alignment: .leading, spacing: 10) {
              Text(question.item.instructionJa).font(.caption).foregroundStyle(.secondary)
              Text(question.item.prompt).font(.title2.bold())
              if model.settings.speechEnabled {
                Button {
                  speech.speak(question.item.speechText)
                } label: {
                  Label("発音", systemImage: "speaker.wave.2.fill")
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            ForEach(question.choices) { choice in
              Button {
                submit(choice.id, question: question)
              } label: {
                HStack {
                  Text(choice.text)
                  Spacer()
                  Image(systemName: choiceSymbol(choice.id, question: question))
                }
              }.secondaryActionStyle().disabled(selected != nil || isSubmitting)
            }
            if let selected {
              feedback(question: question, selected: selected)
            }
          }
        }.frame(maxWidth: 720).padding()
      }
      .navigationTitle("英単語学習")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
    }
    .onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selected = nil }
    }
    .accessibilityIdentifier("vocabulary.study.session")
  }

  @ViewBuilder private func feedback(question: VocabularyQuestion, selected: Int) -> some View {
    let correct = selected == question.correctChoiceID
    VStack(alignment: .leading, spacing: 10) {
      Label(correct ? "正解" : "学び直し", systemImage: correct ? "checkmark.circle.fill" : "book.fill")
        .font(.headline).foregroundStyle(correct ? .green : .orange)
      Text(question.item.explanationJa)
      if model.settings.examplesEnabled {
        Text(question.item.exampleEn)
        Text(question.item.exampleJa).foregroundStyle(.secondary)
      }
      if !correct, waitRemaining > 0 {
        Text("あと\(waitRemaining)秒、意味と例文を確認してください。").monospacedDigit()
      }
      if correct {
        Button(index + 1 == presentation.questions.count ? "完了" : "次へ") { advance() }
          .primaryActionStyle()
      }
    }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
  }

  private func submit(_ choiceID: Int, question: VocabularyQuestion) {
    isSubmitting = true
    Task {
      plan = await model.recordAnswer(
        question: question, selectedChoiceID: choiceID, sessionID: presentation.id,
        attempt: attempts)
      selected = choiceID
      if choiceID != question.correctChoiceID {
        attempts += 1
        waitRemaining = model.waitSeconds(for: plan)
      }
      isSubmitting = false
    }
  }
  private func advance() {
    if index + 1 < presentation.questions.count {
      index += 1
      selected = nil
      attempts = 0
      waitRemaining = 0
    } else {
      model.session = nil
      dismiss()
    }
  }
  private func choiceSymbol(_ id: Int, question: VocabularyQuestion) -> String {
    guard let selected else { return "circle" }
    if id == question.correctChoiceID { return "checkmark.circle.fill" }
    return id == selected ? "xmark.circle.fill" : "circle"
  }
}

struct VocabularyUnlockChallengeView: View {
  let bundle: ExperienceUnlockBundleSnapshot
  let context: UnlockChallengeViewContext
  @Environment(\.scenePhase) private var scenePhase
  @State private var index: Int
  @State private var selected: Int?
  @State private var attempts = 0
  @State private var waitRemaining = 0
  @State private var isSubmitting = false
  @State private var submissionError: String?
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let planner = VocabularyFeedbackPlanner()
  private let speech = SpeechService()

  init(bundle: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) {
    self.bundle = bundle
    self.context = context
    let first =
      bundle.challenge.questions.firstIndex { !bundle.completedQuestionIDs.contains($0.id) } ?? 0
    _index = State(initialValue: first)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(
            value: Double(bundle.completedQuestionIDs.count),
            total: Double(max(1, bundle.challenge.questions.count)))
          if let snapshot = bundle.challenge.questions[safe: index],
            case .vocabulary(let question) = snapshot
          {
            VStack(alignment: .leading, spacing: 10) {
              Text(question.levelCode).font(.caption).foregroundStyle(.secondary)
              Text(question.prompt).font(.title2.bold())
              Button {
                speech.speak(question.speechText)
              } label: {
                Label("発音を聞く", systemImage: "speaker.wave.2.fill")
              }
            }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            ForEach(question.choices) { choice in
              Button(choice.text) { submit(snapshot, choiceID: choice.id) }.secondaryActionStyle()
                .disabled(selected != nil || isSubmitting)
            }
            if let selected {
              let correct = selected == question.correctChoiceID
              VStack(alignment: .leading, spacing: 8) {
                Label(
                  correct ? "正解" : "学び直し",
                  systemImage: correct ? "checkmark.circle.fill" : "book.fill"
                ).font(.headline).foregroundStyle(correct ? .green : .orange)
                Text(question.explanation)
                Text(question.exampleEnglish)
                Text(question.exampleJapanese).foregroundStyle(.secondary)
                if !correct, waitRemaining > 0 { Text("あと\(waitRemaining)秒").monospacedDigit() }
                if correct { Button(isLast ? "解除する" : "次へ") { advance() }.primaryActionStyle() }
              }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            }
          }
        }.frame(maxWidth: 720).padding()
      }.navigationTitle("英単語で解除").navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled()
    .onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selected = nil }
    }
    .accessibilityIdentifier("unlock.vocabulary")
    .alert("解除問題", isPresented: .init(
      get: { submissionError != nil },
      set: { if !$0 { submissionError = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(submissionError ?? "")
    }
  }
  private var isLast: Bool {
    !bundle.challenge.questions.indices.contains { candidate in
      candidate != index
        && !bundle.completedQuestionIDs.contains(bundle.challenge.questions[candidate].id)
    }
  }
  private func submit(_ question: UnlockQuestionSnapshot, choiceID: Int) {
    let correct = choiceID == question.correctChoiceID
    let plan = planner.plan(wrongAttemptCount: correct ? 0 : attempts + 1)
    isSubmitting = true
    Task {
      switch await context.submit(question, choiceID, plan) {
      case .recordedCorrect:
        selected = choiceID
      case .recordedIncorrect:
        selected = choiceID
        attempts += 1
        waitRemaining = planner.waitSeconds(for: plan)
      case .expired:
        submissionError = "解除問題の有効時間が終了しました。新しい問題でやり直してください。"
      case .failed(let message):
        submissionError = "回答を保存できませんでした。\n\(message)"
      }
      isSubmitting = false
    }
  }
  private func advance() {
    if let next = bundle.challenge.questions.indices.first(where: {
      $0 > index && !bundle.completedQuestionIDs.contains(bundle.challenge.questions[$0].id)
    }) {
      index = next
      selected = nil
      attempts = 0
      waitRemaining = 0
    } else {
      Task { await context.complete() }
    }
  }
}
