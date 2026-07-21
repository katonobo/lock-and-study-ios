import SwiftUI

struct StudySessionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let presentation: StudySessionPresentation
  @State private var index = 0
  @State private var selectedChoice: Int?
  @State private var acceptingAnswer = true
  @State private var wrongAttempts = 0
  @State private var feedbackPlan = StudyFeedbackPlan.immediate
  @State private var waitRemaining = 0
  @State private var completed = false
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let speech = SpeechService()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          ProgressView(value: Double(index), total: Double(max(1, presentation.prompts.count))).tint(LockAndStudyTheme.brand)
          if let item = currentPrompt {
            VStack(alignment: .leading, spacing: 12) {
              HStack { Text(item.category).font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Text("\(index + 1) / \(presentation.prompts.count)").font(.caption).monospacedDigit() }
              Text(item.prompt).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
              if let speechText = item.speechText { Button { speech.speak(speechText) } label: { Label("発音を聞く", systemImage: "speaker.wave.2.fill") }.buttonStyle(.bordered) }
              if let example = item.exampleText { Text(example).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
            VStack(spacing: 10) {
              ForEach(item.choices) { choice in choiceButton(choice, item: item) }
            }
            if selectedChoice != nil { feedback(item) }
          }
        }.frame(maxWidth: 720).padding()
      }
      .navigationTitle(presentation.mode == .unlock ? "解除学習" : presentation.packTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
      .interactiveDismissDisabled(presentation.mode == .unlock && !completed)
    }
    .onReceive(timer) { _ in
      guard scenePhase == .active, waitRemaining > 0 else { return }
      waitRemaining -= 1
      if waitRemaining == 0 { selectedChoice = nil; acceptingAnswer = true }
    }
    .accessibilityIdentifier("study.screen")
  }

  private var currentPrompt: StudyPrompt? { presentation.prompts[safe: index] }

  private func choiceButton(_ choice: StudyChoice, item: StudyPrompt) -> some View {
    Button { submit(choice.id, item: item) } label: {
      HStack {
        Image(systemName: symbol(for: choice.id, item: item))
        Text(choice.text).font(.body).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        Spacer()
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
    }
    .buttonStyle(.plain).background(background(for: choice.id, item: item), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
    .disabled(!acceptingAnswer)
    .accessibilityLabel(choice.text)
    .accessibilityValue(accessibilityValue(for: choice.id, item: item))
  }

  @ViewBuilder private func feedback(_ item: StudyPrompt) -> some View {
    let correct = selectedChoice == item.correctChoiceID
    VStack(alignment: .leading, spacing: 10) {
      Label(correct ? "正解です" : "ここで学び直しましょう", systemImage: correct ? "checkmark.circle.fill" : "book.fill")
        .font(.headline).foregroundStyle(correct ? .green : .orange)
      Text(item.shortExplanation).fixedSize(horizontal: false, vertical: true)
      if !correct, waitRemaining > 0 {
        Text("内容を確認する時間：あと\(waitRemaining)秒").monospacedDigit().accessibilityHidden(true)
        ProgressView(value: Double(requiredWait - waitRemaining), total: Double(requiredWait)).tint(.orange)
        Text("カウントが終わると、同じ問題をもう一度選べます。").font(.footnote).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).studyCard()
      .accessibilityElement(children: .combine)
      .accessibilityLabel(correct ? "正解です。\(item.shortExplanation)" : "学び直しです。\(item.shortExplanation)。確認後に同じ問題へ答えます。")
  }

  private var requiredWait: Int {
    switch feedbackPlan { case .relearn6: return 6; case .relearn12: return 12; case .guided20: return 20; case .immediate: return 0 }
  }

  private func submit(_ choiceID: Int, item: StudyPrompt) {
    guard acceptingAnswer else { return }
    acceptingAnswer = false; selectedChoice = choiceID
    let correct = choiceID == item.correctChoiceID
    if correct {
      let plan = wrongAttempts == 0 ? StudyFeedbackPlan.immediate : feedbackPlan
      Task {
        await model.recordAnswer(item: item, selectedChoiceID: choiceID, mode: presentation.mode, sessionID: presentation.id, feedback: plan)
        if let bundleID = presentation.bundleID { await model.markUnlockUnitComplete(itemID: item.itemID, bundleID: bundleID) }
        try? await Task.sleep(nanoseconds: 650_000_000)
        await MainActor.run { advance() }
      }
    } else {
      wrongAttempts += 1
      feedbackPlan = wrongAttempts == 1 ? .relearn6 : (wrongAttempts == 2 ? .relearn12 : .guided20)
      waitRemaining = requiredWait
      Task { await model.recordAnswer(item: item, selectedChoiceID: choiceID, mode: presentation.mode, sessionID: presentation.id, feedback: feedbackPlan) }
    }
  }

  private func advance() {
    if index + 1 < presentation.prompts.count {
      index += 1; selectedChoice = nil; acceptingAnswer = true; wrongAttempts = 0; feedbackPlan = .immediate; waitRemaining = 0
    } else {
      completed = true
      Task { await model.completeStudySession(presentation) }
    }
  }
  private func symbol(for choiceID: Int, item: StudyPrompt) -> String {
    guard let selectedChoice else { return "circle" }
    if choiceID == item.correctChoiceID { return "checkmark.circle.fill" }
    return choiceID == selectedChoice ? "xmark.circle.fill" : "circle"
  }
  private func background(for choiceID: Int, item: StudyPrompt) -> Color {
    guard let selectedChoice else { return Color.secondary.opacity(0.08) }
    if choiceID == item.correctChoiceID { return .green.opacity(0.14) }
    return choiceID == selectedChoice ? .orange.opacity(0.14) : Color.secondary.opacity(0.05)
  }
  private func accessibilityValue(for choiceID: Int, item: StudyPrompt) -> String {
    guard let selectedChoice else { return "未選択" }
    if choiceID == item.correctChoiceID { return "正解の選択肢" }
    return choiceID == selectedChoice ? "選択した不正解" : "未選択"
  }
}
