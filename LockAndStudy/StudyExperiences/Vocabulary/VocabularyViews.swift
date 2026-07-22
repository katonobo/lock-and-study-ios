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
        .tabItem { Label(model.profile.catalogTitle, systemImage: "character.book.closed.fill") }.tag(
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
      model.profile.subjectName,
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
  @State private var settings: VocabularySettings
  @State private var errorMessage: String?

  init(context: StudyExperienceContext) {
    self.context = context
    _settings = State(initialValue: .load(packID: context.manifest.id))
  }

  private var profile: FlashcardPresentationProfile { context.manifest.flashcardPresentation }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(systemName: "character.book.closed.fill")
            .font(.system(size: 58)).foregroundStyle(LockAndStudyTheme.vocabulary)
          Text(profile.firstRunTitle).font(.largeTitle.bold()).multilineTextAlignment(.center)
          Text(profile.firstRunDescription)
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
          if !profile.courseDefinitions.isEmpty {
            VStack(spacing: 10) {
            ForEach(profile.courseDefinitions) { course in
              Button {
                settings.selectedLevelCodes = [course.code]
              } label: {
                HStack {
                  Image(
                    systemName: settings.selectedLevelCodes.contains(course.code)
                      ? "checkmark.circle.fill" : "circle")
                  VStack(alignment: .leading) {
                    Text(course.title).font(.headline)
                    if let sampleLabel = course.sampleLabel {
                      Text(sampleLabel).font(.caption).foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                }
              }.secondaryActionStyle()
            }
            }.studyCard()
          }
          if profile.supportsSpeech {
            Toggle("読み上げる", isOn: $settings.speechEnabled).studyCard()
          }
          Stepper("1日の目標 \(settings.dailyGoal)問", value: $settings.dailyGoal, in: 5...30, step: 5)
            .studyCard()
          Button(profile.startButtonTitle) {
            do {
              try settings.save(packID: context.manifest.id)
              context.completeFirstRun()
            } catch {
              errorMessage = "設定を保存できませんでした。\n\(error.localizedDescription)"
            }
          }
          .primaryActionStyle().accessibilityIdentifier("vocabulary.firstRun.finish")
        }.frame(maxWidth: 640).padding()
      }.navigationTitle(profile.firstRunTitle).navigationBarTitleDisplayMode(.inline)
    }
    .alert(profile.subjectName, isPresented: .init(
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
          Text(model.profile.homeTitle).font(.title2.bold())
          HStack {
            metric("学習済み", value: "\(model.learnedCount)\(model.profile.itemCountUnit)")
            metric("復習期限", value: "\(model.dueCount)\(model.profile.itemCountUnit)")
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
              examplesEnabled: model.pendingPreviewExamplesEnabled,
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
    }.navigationTitle(model.profile.subjectName).accessibilityIdentifier("vocabulary.home")
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
        modeRow("期限到来復習", detail: "SRSで今日が期限の項目だけ", icon: "calendar.badge.clock", mode: .review)
        modeRow("新出", detail: "まだ答えていない項目", icon: "plus.circle.fill", mode: .newItems)
        modeRow(
          "誤答", detail: "間違えたことがある項目", icon: "arrow.counterclockwise.circle.fill", mode: .mistakes)
        modeRow("苦手", detail: "誤答が正答以上の項目", icon: "exclamationmark.triangle.fill", mode: .weakness)
      }
      Section("学習範囲") {
        ForEach(model.courseDefinitions) { course in
          let total = model.items.filter { $0.levelCode == course.code }.count
          let learned = model.items.filter {
            $0.levelCode == course.code && model.itemProgress($0).answerCount > 0
          }.count
          VStack(alignment: .leading) {
            HStack {
              Text(course.title)
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
  @State private var courseCode: String?
  private var filtered: [VocabularyItem] {
    model.items.filter { item in
      (courseCode == nil || item.levelCode == courseCode)
        && (search.isEmpty || item.displayWord.localizedCaseInsensitiveContains(search)
          || item.quizMeaningJa.localizedCaseInsensitiveContains(search))
    }
  }
  var body: some View {
    List {
      Section {
        Picker("コース", selection: $courseCode) {
          Text("すべて").tag(String?.none)
          ForEach(model.courseDefinitions) { Text($0.title).tag(Optional($0.code)) }
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
    }.searchable(text: $search, prompt: model.profile.searchPlaceholder)
      .navigationTitle(model.profile.catalogTitle)
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
      if model.profile.supportsExamples {
        Section("例") {
          if !item.exampleEn.isEmpty { Text(item.exampleEn) }
          if !item.exampleJa.isEmpty { Text(item.exampleJa).foregroundStyle(.secondary) }
        }
      }
      Section("学習") {
        let progress = model.itemProgress(item)
        LabeledContent("回答", value: "\(progress.answerCount)回")
        LabeledContent("正解", value: "\(progress.correctCount)回")
        if let due = progress.dueAt { LabeledContent("次回復習", value: due.formatted()) }
      }
      if model.profile.supportsSpeech {
        Button {
          speech.speak(item.speechText)
        } label: {
          Label("音声を聞く", systemImage: "speaker.wave.2.fill")
        }
      }
    }.navigationTitle(item.displayWord).navigationBarTitleDisplayMode(.inline)
  }
}

private struct VocabularyRecordsView: View {
  @EnvironmentObject private var model: VocabularyAppModel
  var body: some View {
    List {
      Section {
        LearningReportEntryCard(
          context: model.context,
          accessibilityID: "report.entry.vocabulary")
      }
      Section("今週") {
        LabeledContent("回答", value: "\(model.weeklyReport.answers)問")
        LabeledContent("正答率", value: "\(model.weeklyReport.accuracy)%")
        LabeledContent("学習済み", value: "\(model.weeklyReport.learned)\(model.profile.itemCountUnit)")
        LabeledContent("期限到来", value: "\(model.weeklyReport.due)\(model.profile.itemCountUnit)")
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
      Section("コース別") {
        ForEach(model.courseDefinitions) { course in
          let values = model.answers.filter { $0.category == course.code }
          LabeledContent(course.title, value: "\(values.count)問・\(accuracy(values))%")
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
    }.navigationTitle("\(model.profile.subjectName)の記録").accessibilityIdentifier("vocabulary.records")
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
        ForEach(model.courseDefinitions) { course in
          Toggle(
            course.title,
            isOn: Binding(
              get: { model.settings.selectedLevelCodes.contains(course.code) },
              set: { enabled in
                if enabled {
                  model.settings.selectedLevelCodes.insert(course.code)
                } else if model.settings.selectedLevelCodes.count > 1 {
                  model.settings.selectedLevelCodes.remove(course.code)
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
        if model.profile.supportsSpeech { Toggle(
          "音声",
          isOn: Binding(
            get: { model.settings.speechEnabled },
            set: {
              model.settings.speechEnabled = $0
              model.saveSettings()
            })) }
        if model.profile.supportsExamples { Toggle(
          "例",
          isOn: Binding(
            get: { model.settings.examplesEnabled },
            set: {
              model.settings.examplesEnabled = $0
              model.saveSettings()
            })) }
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
          Label("\(model.context.manifest.title)を永久購入済み", systemImage: "checkmark.circle.fill")
        } else {
          Text("無料\(model.context.manifest.sampleDefinition.count)\(model.profile.itemCountUnit)")
        }
      }
    }.navigationTitle("\(model.profile.subjectName)設定").accessibilityIdentifier("vocabulary.settings")
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
  @State private var submissionError: String?
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
              if model.profile.supportsSpeech && model.settings.speechEnabled {
                Button {
                  speech.speak(question.item.speechText)
                } label: {
                  Label("音声", systemImage: "speaker.wave.2.fill")
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
      .navigationTitle("\(model.profile.subjectName)学習")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
    }
    .onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selected = nil }
    }
    .accessibilityIdentifier("vocabulary.study.session")
    .alert("回答を保存できませんでした", isPresented: .init(
      get: { submissionError != nil },
      set: { if !$0 { submissionError = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(submissionError ?? "")
    }
  }

  @ViewBuilder private func feedback(question: VocabularyQuestion, selected: Int) -> some View {
    let correct = selected == question.correctChoiceID
    VStack(alignment: .leading, spacing: 10) {
      Label(correct ? "正解" : "学び直し", systemImage: correct ? "checkmark.circle.fill" : "book.fill")
        .font(.headline).foregroundStyle(correct ? .green : .orange)
      Text(question.item.explanationJa)
      if model.profile.supportsExamples && model.settings.examplesEnabled {
        Text(question.item.exampleEn)
        Text(question.item.exampleJa).foregroundStyle(.secondary)
      }
      if !correct, waitRemaining > 0 {
        Text("あと\(waitRemaining)秒、解説を確認してください。").monospacedDigit()
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
      let result = await model.recordAnswer(
        question: question, selectedChoiceID: choiceID, sessionID: presentation.id,
        attempt: attempts)
      switch result {
      case .recordedCorrect(let recordedPlan):
        plan = recordedPlan
        selected = choiceID
      case .recordedIncorrect(let recordedPlan):
        plan = recordedPlan
        selected = choiceID
        attempts += 1
        waitRemaining = model.waitSeconds(for: plan)
      case .failed(let message):
        submissionError = message
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
  let session: FlashcardUnlockSessionPayload
  let context: ExperienceChallengeViewContext
  @Environment(\.scenePhase) private var scenePhase
  @State private var index: Int
  @State private var completedQuestionIDs: Set<StudyItemID>
  @State private var selected: Int?
  @State private var attempts = 0
  @State private var waitRemaining = 0
  @State private var isReviewSyncing = false
  @State private var pendingReviewActiveState: Bool?
  @State private var isSubmitting = false
  @State private var submissionError: String?
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let planner = VocabularyFeedbackPlanner()
  private let speech = SpeechService()

  init(session: FlashcardUnlockSessionPayload, context: ExperienceChallengeViewContext) {
    self.session = session
    self.context = context
    let first =
      session.questions.firstIndex { !session.completedQuestionIDs.contains($0.id) } ?? 0
    _index = State(initialValue: first)
    _completedQuestionIDs = State(initialValue: session.completedQuestionIDs)
    if let question = session.questions[safe: first] {
      _selected = State(
        initialValue: session.lastSelectedChoiceIDByQuestionID[question.id.rawValue])
      _attempts = State(
        initialValue: session.attemptCountsByQuestionID[question.id.rawValue] ?? 0)
      _waitRemaining = State(initialValue: max(
        0,
        Int(ceil(
          session.reviewRemainingSecondsByQuestionID[question.id.rawValue] ?? 0))))
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(
            value: Double(completedQuestionIDs.count),
            total: Double(max(1, session.questions.count)))
            .accessibilityValue("\(completedQuestionIDs.count)/\(session.questions.count)")
            .accessibilityIdentifier("vocabulary.unlock.progress")
          if let question = session.questions[safe: index] {
            VStack(alignment: .leading, spacing: 10) {
              Text(question.courseCode).font(.caption).foregroundStyle(.secondary)
              Text(question.prompt).font(.title2.bold())
              if context.manifest.flashcardPresentation.supportsSpeech,
                let speechText = question.speechText
              {
                Button {
                  speech.speak(speechText)
                } label: {
                  Label("音声を聞く", systemImage: "speaker.wave.2.fill")
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            ForEach(question.choices) { choice in
              Button(choice.text) { submit(question, choiceID: choice.id) }.secondaryActionStyle()
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
                if context.manifest.flashcardPresentation.supportsExamples {
                  if let example = question.primaryExample { Text(example) }
                  if let example = question.secondaryExample {
                    Text(example).foregroundStyle(.secondary)
                  }
                }
                if !correct, waitRemaining > 0 { Text("あと\(waitRemaining)秒").monospacedDigit() }
                if !correct, waitRemaining == 0 {
                  Button("もう一度解く") { self.selected = nil }.primaryActionStyle()
                }
                if correct { Button(isLast ? "解除する" : "次へ") { advance() }.primaryActionStyle() }
              }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            }
          }
        }.frame(maxWidth: 720).padding()
      }.navigationTitle(context.manifest.flashcardPresentation.unlockTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled()
    .onReceive(timer) { _ in
      guard scenePhase == .active, isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: true) }
    }
    .onChange(of: scenePhase) { phase in
      guard isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: phase == .active) }
    }
    .onAppear {
      guard scenePhase == .active, isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: true) }
    }
    .onDisappear {
      guard isReviewingWrong else { return }
      Task { await synchronizeReviewExposure(isActive: false) }
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
    !session.questions.indices.contains {
      $0 > index && !completedQuestionIDs.contains(session.questions[$0].id)
    }
  }
  private var isReviewingWrong: Bool {
    guard let question = session.questions[safe: index], let selected else { return false }
    return selected != question.correctChoiceID
  }
  private func submit(_ question: FlashcardChallengeQuestion, choiceID: Int) {
    isSubmitting = true
    Task {
      switch await context.submit(
        .choice(questionID: question.id.rawValue, choiceID: String(choiceID)))
      {
      case .recordedCorrect:
        selected = choiceID
        completedQuestionIDs.insert(question.id)
      case .recordedIncorrect(let remainingActiveSeconds, let attemptNumber):
        selected = choiceID
        attempts = attemptNumber
        waitRemaining = remainingActiveSeconds
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
    if let next = session.questions.indices.first(where: {
      $0 > index && !completedQuestionIDs.contains(session.questions[$0].id)
    }) {
      index = next
      selected = nil
      attempts = 0
      waitRemaining = 0
    } else {
      Task { await context.complete() }
    }
  }

  @MainActor
  private func synchronizeReviewExposure(isActive: Bool) async {
    if isReviewSyncing {
      pendingReviewActiveState = isActive
      return
    }
    isReviewSyncing = true
    var desiredActiveState = isActive
    repeat {
      pendingReviewActiveState = nil
      switch await context.updateReviewExposure(desiredActiveState) {
      case .updated(let remainingActiveSeconds):
        waitRemaining = remainingActiveSeconds
      case .expired:
        submissionError = "解除問題の有効時間が終了しました。新しい問題でやり直してください。"
      case .failed(let message):
        submissionError = "解説確認時間を保存できませんでした。\n\(message)"
      }
      guard let pending = pendingReviewActiveState else { break }
      desiredActiveState = pending
    } while true
    isReviewSyncing = false
  }
}
