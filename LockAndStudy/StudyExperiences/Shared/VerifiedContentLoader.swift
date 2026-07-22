import CryptoKit
import Foundation
import SwiftUI

struct VerifiedContentLoader: Sendable {
  let packageRoot: URL

  init(packageRoot: URL) { self.packageRoot = packageRoot }

  func data(for descriptor: ContentFileDescriptor) throws -> Data {
    let url = try resourceURL(for: descriptor.path)
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == descriptor.sha256 else {
      throw ContentRepositoryError.invalid("\(descriptor.path) のSHA-256不一致")
    }
    return data
  }

  func data(resourcePath: String) throws -> Data {
    try Data(contentsOf: resourceURL(for: resourcePath))
  }

  func text(resourcePath: String) throws -> String {
    let data = try data(resourcePath: resourcePath)
    guard let value = String(data: data, encoding: .utf8) else {
      throw ContentRepositoryError.invalid("\(resourcePath) をUTF-8として読めません")
    }
    return value
  }

  private func resourceURL(for path: String) throws -> URL {
    let location = ContentPackageLocation(kind: .bundled, rootURL: packageRoot)
    let url = try location.fileURL(for: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw ContentRepositoryError.missing(path)
    }
    return url
  }
}

struct SafeFallbackChallengeQuestion: Codable, Equatable, Identifiable, Sendable {
  let id: StudyItemID
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let explanation: String
}

struct SafeFallbackSessionPayload: Codable, Equatable, Sendable {
  static let schemaID = "safe-fallback.unlock-session.v1"
  let pace: AccessPacePreset
  let questions: [SafeFallbackChallengeQuestion]
  var completedQuestionIDs: Set<StudyItemID>
  var attemptCountsByQuestionID: [String: Int]
  var reviewRemainingSecondsByQuestionID: [String: TimeInterval]
  var lastSelectedChoiceIDByQuestionID: [String: Int]
  var activeReviewQuestionID: String?
}

struct SafeFallbackUnlockSessionBuilder: Sendable {
  func makeSession(request: UnlockChallengeRequest) throws -> ExperienceSessionPayload {
    let count = request.policy.accessPacePreset.requiredLearningUnits
    let templates: [(String, [String], Int, String)] = [
      ("study の意味を選んでください。", ["学ぶ", "眠る", "走る", "忘れる"], 0, "study は『学ぶ・勉強する』という意味です。"),
      ("毎日の学習で大切な行動を選んでください。", ["短くても続ける", "答えだけ覚える", "記録を消す", "復習を避ける"], 0, "短時間でも継続し、間違いを復習することが定着につながります。"),
      ("復習に適したタイミングはどれですか。", ["忘れかけた頃", "一度も学ぶ前", "正解直後だけ", "一年後だけ"], 0, "忘れかけた頃の復習は記憶の定着に役立ちます。")
    ]
    let questions = (0..<count).map { index -> SafeFallbackChallengeQuestion in
      let template = templates[index % templates.count]
      return .init(
        id: .init(rawValue: "safe-fallback-\(index + 1)"),
        prompt: template.0,
        choices: template.1.enumerated().map { .init(id: $0.offset, text: $0.element) },
        correctChoiceID: template.2,
        explanation: template.3
      )
    }
    let state = SafeFallbackSessionPayload(
      pace: request.policy.accessPacePreset,
      questions: questions,
      completedQuestionIDs: [], attemptCountsByQuestionID: [:],
      reviewRemainingSecondsByQuestionID: [:], lastSelectedChoiceIDByQuestionID: [:],
      activeReviewQuestionID: nil)
    return .init(
      schemaID: SafeFallbackSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }
}

@MainActor
struct SafeFallbackExperience: StudyExperienceFactory {
  let experienceID = StudyExperienceID.safeFallbackV1
  let supportedPayloadSchemaIDs: Set<String> = [SafeFallbackSessionPayload.schemaID]
  let supportedContentSchemas: Set<ContentSchemaID> = [.safeFallbackV1]
  let descriptor = StudyExperienceDescriptor(
    id: .safeFallback,
    title: "安全な無料問題",
    subtitle: "教材を読み込めない場合の解除用",
    systemImage: "lifepreserver.fill",
    tintName: "teal",
    supportedExperienceTypes: []
  )
  func makeRootView(context: StudyExperienceContext) -> AnyView { AnyView(EmptyView()) }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? { nil }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    .init(experienceID: .safeFallback, packID: context.manifest.id, answeredCount: 0, correctCount: 0, learnedItemCount: 0, dueCount: 0)
  }
  func createSession(request: UnlockChallengeRequest) async throws -> ExperienceSessionPayload {
    try SafeFallbackUnlockSessionBuilder().makeSession(request: request)
  }
  func makeChallengeView(
    envelope: UnlockChallengeSessionEnvelope,
    context: ExperienceChallengeViewContext
  ) -> AnyView {
    guard let state = try? decode(envelope) else {
      return AnyView(ExperienceSessionUnavailableView(context: context))
    }
    return AnyView(SafeFallbackUnlockChallengeView(session: state, context: context))
  }
  func restoreState(payload: Data, schemaID: String) throws -> ExperienceSessionState {
    guard supportedPayloadSchemaIDs.contains(schemaID) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "safe fallback payload")
    }
    let state = try SharedJSON.decoder().decode(SafeFallbackSessionPayload.self, from: payload)
    return .init(
      completedUnitCount: state.completedQuestionIDs.count,
      totalUnitCount: state.questions.count,
      reviewRemainingSeconds: state.reviewRemainingSecondsByQuestionID.values.max() ?? 0)
  }
  func acceptAnswer(
    _ answer: StudyAnswerValue,
    envelope: UnlockChallengeSessionEnvelope,
    dependencies: DependencyContainer
  ) async throws -> ExperienceSessionTransition {
    var state = try decode(envelope)
    let pair: (String, String)
    switch answer {
    case .choice(let questionID, let choiceID): pair = (questionID, choiceID)
    case .choiceID(let choiceID):
      guard let question = state.questions.first(where: {
        !state.completedQuestionIDs.contains($0.id)
      }) else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "safe fallback question") }
      pair = (question.id.rawValue, choiceID)
    default: throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "safe fallback choice")
    }
    guard let question = state.questions.first(where: { $0.id.rawValue == pair.0 }),
      let selectedChoiceID = Int(pair.1)
    else { throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "safe fallback question") }
    let key = question.id.rawValue
    let remaining = state.reviewRemainingSecondsByQuestionID[key] ?? 0
    guard remaining <= 0 else {
      return try transition(state, submission: .failed("解説を確認してから再挑戦してください。"))
    }
    let answeredAt = Date()
    let priorProgress = try await dependencies.learning.progress(
      for: .init(packID: envelope.packID, itemID: question.id))
    let attempt = (state.attemptCountsByQuestionID[key] ?? 0) + 1
    let correct = selectedChoiceID == question.correctChoiceID
    let feedback: StudyFeedbackPlan = correct ? .immediate : .relearn6
    let record = StudyAnswerRecord(
      submissionID: "unlock::\(envelope.id.uuidString)::\(key)::attempt::\(attempt)::choice::\(selectedChoiceID)",
      experienceID: .safeFallback,
      packID: envelope.packID,
      moduleType: .vocabulary,
      itemID: question.id,
      prompt: question.prompt,
      choices: question.choices,
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      shortExplanation: question.explanation,
      longExplanation: question.explanation,
      sourceNote: "built-in-safe-fallback",
      category: "安全な無料問題",
      subcategory: nil,
      contentVersion: "built-in-v1",
      questionVersion: 1,
      examYear: nil,
      lawBasisDate: nil,
      answeredAt: answeredAt,
      mode: .unlock,
      sessionID: envelope.id,
      feedbackPlan: feedback,
      learningRole: AnswerLearningRole.classify(mode: .unlock, progress: priorProgress, at: answeredAt),
      wasNewAtSubmission: priorProgress.answerCount == 0,
      wasDueAtSubmission: priorProgress.dueAt.map { $0 <= answeredAt } ?? false,
      attemptNumber: attempt,
      wasFirstAttempt: attempt == 1
    )
    _ = try await dependencies.learning.recordUnique(record)
    state.attemptCountsByQuestionID[key] = attempt
    state.lastSelectedChoiceIDByQuestionID[key] = selectedChoiceID
    if correct {
      state.completedQuestionIDs.insert(question.id)
      state.reviewRemainingSecondsByQuestionID.removeValue(forKey: key)
      state.activeReviewQuestionID = nil
      return try transition(state, submission: .recordedCorrect)
    }
    state.reviewRemainingSecondsByQuestionID[key] = 6
    state.activeReviewQuestionID = key
    return try transition(
      state, submission: .recordedIncorrect(remainingActiveSeconds: 6, attemptNumber: attempt))
  }
  func activeReviewTick(
    seconds: TimeInterval,
    envelope: UnlockChallengeSessionEnvelope
  ) async throws -> ExperienceSessionTransition {
    var state = try decode(envelope)
    guard let key = state.activeReviewQuestionID else {
      return try transition(state, review: .updated(remainingActiveSeconds: 0))
    }
    let remaining = max(0, (state.reviewRemainingSecondsByQuestionID[key] ?? 0) - max(0, seconds))
    if remaining == 0 {
      state.reviewRemainingSecondsByQuestionID.removeValue(forKey: key)
      state.activeReviewQuestionID = nil
    } else { state.reviewRemainingSecondsByQuestionID[key] = remaining }
    return try transition(
      state, review: .updated(remainingActiveSeconds: max(0, Int(ceil(remaining)))))
  }
  func completionProof(
    envelope: UnlockChallengeSessionEnvelope
  ) throws -> ExperienceCompletionProof? {
    let state = try decode(envelope)
    guard !state.questions.isEmpty,
      state.completedQuestionIDs.count >= state.questions.count
    else { return nil }
    return .init(
      sessionID: envelope.id, packID: envelope.packID,
      completedAt: Date(), evidenceVersion: 1,
      unlockDuration: state.pace.unlockDuration)
  }

  private func decode(_ envelope: UnlockChallengeSessionEnvelope) throws -> SafeFallbackSessionPayload {
    guard supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID) else {
      throw StudyExperienceRuntimeError.incompatibleQuestion(expected: "safe fallback payload")
    }
    return try SharedJSON.decoder().decode(SafeFallbackSessionPayload.self, from: envelope.enginePayload)
  }
  private func transition(
    _ state: SafeFallbackSessionPayload,
    submission: UnlockAnswerSubmissionResult? = nil,
    review: UnlockReviewExposureResult? = nil
  ) throws -> ExperienceSessionTransition {
    .init(
      payload: .init(
        schemaID: SafeFallbackSessionPayload.schemaID,
        data: try SharedJSON.encoder().encode(state)),
      submissionResult: submission, reviewResult: review)
  }
}

private struct SafeFallbackUnlockChallengeView: View {
  let session: SafeFallbackSessionPayload
  let context: ExperienceChallengeViewContext
  @Environment(\.scenePhase) private var scenePhase
  @State private var index: Int
  @State private var completedQuestionIDs: Set<StudyItemID>
  @State private var selected: Int?
  @State private var waitRemaining = 0
  @State private var isReviewSyncing = false
  @State private var pendingReviewActiveState: Bool?
  @State private var isSubmitting = false
  @State private var submissionError: String?
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  init(session: SafeFallbackSessionPayload, context: ExperienceChallengeViewContext) {
    self.session = session
    self.context = context
    let first = session.questions.firstIndex {
      !session.completedQuestionIDs.contains($0.id)
    } ?? 0
    _index = State(initialValue: first)
    _completedQuestionIDs = State(initialValue: session.completedQuestionIDs)
    if let question = session.questions[safe: first] {
      _selected = State(
        initialValue: session.lastSelectedChoiceIDByQuestionID[question.id.rawValue])
      _waitRemaining = State(initialValue: max(
        0,
        Int(ceil(
          session.reviewRemainingSecondsByQuestionID[question.id.rawValue] ?? 0))))
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        ProgressView(
          value: Double(completedQuestionIDs.count),
          total: Double(max(1, session.questions.count)))
          .accessibilityIdentifier("safeFallback.unlock.progress")
        if let question = session.questions[safe: index] {
          Text(question.prompt).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).studyCard()
          ForEach(question.choices) { choice in
            Button(choice.text) { submit(question: question, choiceID: choice.id) }
              .secondaryActionStyle()
              .disabled(isSubmitting || selected != nil)
          }
          if let selected {
            Text(selected == question.correctChoiceID ? "正解です" : question.explanation)
              .frame(maxWidth: .infinity, alignment: .leading).studyCard()
            if selected == question.correctChoiceID {
              Button(isLast ? "解除する" : "次へ") { advance() }
                .primaryActionStyle()
            } else if waitRemaining > 0 {
              Text("あと\(waitRemaining)秒、解説を確認してください。")
                .monospacedDigit()
            } else {
              Button("もう一度解く") { self.selected = nil }
                .primaryActionStyle()
                .accessibilityIdentifier("safeFallback.unlock.retry")
            }
          }
        }
        Spacer()
      }
      .padding()
      .navigationTitle("解除学習")
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
    .alert("解除問題", isPresented: .init(
      get: { submissionError != nil },
      set: { if !$0 { submissionError = nil } }
    )) {
      Button("新しい問題でやり直す") {
        Task { await context.restart() }
      }
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(submissionError ?? "")
    }
  }

  private var isReviewingWrong: Bool {
    guard let question = session.questions[safe: index], let selected else { return false }
    return selected != question.correctChoiceID
  }

  private var isLast: Bool {
    !session.questions.indices.contains {
      $0 > index && !completedQuestionIDs.contains(session.questions[$0].id)
    }
  }

  private func submit(question: SafeFallbackChallengeQuestion, choiceID: Int) {
    isSubmitting = true
    Task {
      switch await context.submit(
        .choice(questionID: question.id.rawValue, choiceID: String(choiceID))
      ) {
      case .recordedCorrect:
        selected = choiceID
        completedQuestionIDs.insert(question.id)
        waitRemaining = 0
      case .recordedIncorrect(let remainingActiveSeconds, _):
        selected = choiceID
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
        submissionError = "有効時間が終了しました。教材画面へ戻って新しい解除問題を開始してください。"
      case .failed(let message):
        submissionError = "解説確認時間を保存できませんでした。もう一度お試しください。\n\(message)"
      }
      guard let pending = pendingReviewActiveState else { break }
      desiredActiveState = pending
    } while true
    isReviewSyncing = false
  }
}
