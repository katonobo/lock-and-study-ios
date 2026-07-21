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
  @State private var settings = TakkenSettings.load()
  @State private var category = "宅建業法"
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(systemName: "building.columns.fill").font(.system(size: 58)).foregroundStyle(
            LockAndStudyTheme.takken)
          Text("宅建2026の学習方針").font(.largeTitle.bold()).multilineTextAlignment(.center)
          Text("現在は資格者レビュー済みの宅建業法100問を無料公開しています。追加900問と購入は準備中です。")
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
            settings.save()
            context.completeFirstRun()
          }
          .primaryActionStyle().accessibilityIdentifier("takken.firstRun.finish")
        }.frame(maxWidth: 640).padding()
      }.navigationTitle("宅建 初期設定").navigationBarTitleDisplayMode(.inline)
    }
  }
}

private struct TakkenHomeView: View {
  @EnvironmentObject private var model: TakkenAppModel
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("宅建2026").font(.title2.bold())
            Spacer()
            Text("無料100問").font(.caption.bold()).foregroundStyle(.green)
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
                Text(
                  [question.subCategory, question.difficulty].compactMap { $0 }.joined(
                    separator: "・")
                ).font(.caption).foregroundStyle(.secondary)
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
  private var viewModel: TakkenQuestionDetailViewModel {
    .init(question: question, answers: model.answers)
  }
  var body: some View {
    List {
      Section("問題") {
        Text(question.prompt).font(.title3.weight(.semibold))
        Label(question.format?.rawValue ?? "multiple_choice", systemImage: "list.number")
      }
      Section("選択肢") {
        ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
          Label(
            choice, systemImage: index == question.correctIndex ? "checkmark.circle.fill" : "circle"
          ).foregroundStyle(index == question.correctIndex ? .green : .primary)
        }
      }
      Section("解説") {
        Text(viewModel.explanation)
        if let key = question.keyPoint { Label(key, systemImage: "key.fill") }
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
        Label("無料100問を利用中", systemImage: "checkmark.circle.fill")
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
  @State private var selected: Int?
  @State private var attempt = 0
  @State private var waitRemaining = 0
  @State private var isSubmitting = false
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(value: Double(index), total: Double(max(1, presentation.questions.count)))
          if let question = presentation.questions[safe: index] {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(question.category).font(.caption.bold())
                Spacer()
                Text(question.difficulty).font(.caption)
              }
              Text(question.prompt).font(.title2.bold())
            }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            ForEach(Array(question.choices.enumerated()), id: \.offset) { choice in
              Button(choice.element) { submit(choice.offset, question: question) }
                .secondaryActionStyle().disabled(selected != nil || isSubmitting)
            }
            if let selected {
              let correct = selected == question.correctIndex
              VStack(alignment: .leading, spacing: 8) {
                Label(
                  correct ? "正解" : "学び直し",
                  systemImage: correct ? "checkmark.circle.fill" : "book.fill"
                ).font(.headline).foregroundStyle(correct ? .green : .orange)
                Text(question.longExplanation ?? question.explanation)
                if let key = question.keyPoint { Label(key, systemImage: "key.fill") }
                if !correct, waitRemaining > 0 { Text("あと\(waitRemaining)秒").monospacedDigit() }
                if correct {
                  Button(index + 1 == presentation.questions.count ? "完了" : "次へ") { advance() }
                    .primaryActionStyle()
                }
              }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            }
          }
        }.frame(maxWidth: 720).padding()
      }.navigationTitle("宅建演習").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
      }
    }.onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selected = nil }
    }.accessibilityIdentifier("takken.study.session")
  }
  private func submit(_ choice: Int, question: TakkenQuestion) {
    isSubmitting = true
    Task {
      let plan = await model.recordAnswer(
        question: question, selectedChoiceID: choice, sessionID: presentation.id, attempt: attempt)
      selected = choice
      if choice != question.correctIndex {
        attempt += 1
        waitRemaining = model.waitSeconds(for: plan)
      }
      isSubmitting = false
    }
  }
  private func advance() {
    if index + 1 < presentation.questions.count {
      index += 1
      selected = nil
      attempt = 0
      waitRemaining = 0
    } else {
      model.session = nil
      dismiss()
    }
  }
}

struct TakkenUnlockChallengeView: View {
  let bundle: ExperienceUnlockBundleSnapshot
  let context: UnlockChallengeViewContext
  @Environment(\.scenePhase) private var scenePhase
  @State private var index: Int
  @State private var selected: Int?
  @State private var attempts = 0
  @State private var waitRemaining = 0
  @State private var isSubmitting = false
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let feedbackPlanner = TakkenFeedbackPlanner()
  init(bundle: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) {
    self.bundle = bundle
    self.context = context
    _index = State(
      initialValue: bundle.challenge.questions.firstIndex {
        !bundle.completedQuestionIDs.contains($0.id)
      } ?? 0)
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          ProgressView(
            value: Double(bundle.completedQuestionIDs.count),
            total: Double(max(1, bundle.challenge.questions.count)))
          if let snapshot = bundle.challenge.questions[safe: index],
            case .takken(let question) = snapshot
          {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(question.category).font(.caption.bold())
                Spacer()
                Text(question.difficulty).font(.caption)
              }
              Text(question.prompt).font(.title2.bold())
              if let date = question.lawBasisDate {
                Text("法令基準日 \(date)").font(.caption).foregroundStyle(.secondary)
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
                Text(question.longExplanation)
                if let key = question.keyPoint { Label(key, systemImage: "key.fill") }
                if !correct, waitRemaining > 0 { Text("あと\(waitRemaining)秒").monospacedDigit() }
                if correct { Button("次へ") { advance() }.primaryActionStyle() }
              }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            }
          }
        }.frame(maxWidth: 720).padding()
      }.navigationTitle("宅建で解除").navigationBarTitleDisplayMode(.inline)
    }.interactiveDismissDisabled().onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selected = nil }
    }.accessibilityIdentifier("unlock.takken")
  }
  private func submit(_ question: UnlockQuestionSnapshot, choiceID: Int) {
    let correct = choiceID == question.correctChoiceID
    let plan = feedbackPlanner.plan(wrongAttemptCount: correct ? 0 : attempts + 1)
    isSubmitting = true
    Task {
      _ = await context.submit(question, choiceID, plan)
      selected = choiceID
      if !correct {
        attempts += 1
        waitRemaining = feedbackPlanner.waitSeconds(for: plan)
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
