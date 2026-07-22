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

struct SafeFallbackUnlockChallengeProvider: UnlockChallengeProviding {
  func makeUnlockChallenge(packID: StudyPackID, request: UnlockChallengeRequest) async throws -> UnlockChallengeSnapshot {
    let count = request.policy.accessPacePreset.requiredLearningUnits
    let templates: [(String, [String], Int, String)] = [
      ("study の意味を選んでください。", ["学ぶ", "眠る", "走る", "忘れる"], 0, "study は『学ぶ・勉強する』という意味です。"),
      ("毎日の学習で大切な行動を選んでください。", ["短くても続ける", "答えだけ覚える", "記録を消す", "復習を避ける"], 0, "短時間でも継続し、間違いを復習することが定着につながります。"),
      ("復習に適したタイミングはどれですか。", ["忘れかけた頃", "一度も学ぶ前", "正解直後だけ", "一年後だけ"], 0, "忘れかけた頃の復習は記憶の定着に役立ちます。")
    ]
    let questions = (0..<count).map { index -> UnlockQuestionSnapshot in
      let template = templates[index % templates.count]
      return .safeFallback(.init(
        id: .init(rawValue: "safe-fallback-\(index + 1)"),
        prompt: template.0,
        choices: template.1.enumerated().map { .init(id: $0.offset, text: $0.element) },
        correctChoiceID: template.2,
        explanation: template.3
      ))
    }
    return .init(
      schemaVersion: 2,
      id: UUID(),
      requestID: request.requestID,
      origin: request.origin,
      experienceID: .safeFallback,
      packID: packID,
      policyVersion: request.policy.policyVersion,
      pace: request.policy.accessPacePreset,
      reviewLoad: request.policy.reviewLoadPreset,
      questions: questions,
      access: .init(packID: packID, reason: .freeSample, verifiedAt: request.entitlement.lastVerifiedAt),
      createdAt: request.now,
      expiresAt: request.now.addingTimeInterval(ExperienceUnlockBundleSnapshot.expirationInterval)
    )
  }
}

@MainActor
struct SafeFallbackExperience: StudyExperienceFactory {
  let descriptor = StudyExperienceDescriptor(
    id: .safeFallback,
    title: "安全な無料問題",
    subtitle: "教材を読み込めない場合の解除用",
    systemImage: "lifepreserver.fill",
    tintName: "teal",
    supportedExperienceTypes: []
  )
  let unlockChallengeProvider: any UnlockChallengeProviding = SafeFallbackUnlockChallengeProvider()
  func makeRootView(context: StudyExperienceContext) -> AnyView { AnyView(EmptyView()) }
  func makeFirstRunView(context: StudyExperienceContext) -> AnyView? { nil }
  func makeProgressSummary(context: StudyExperienceContext) async throws -> StudyExperienceSummary {
    .init(experienceID: .safeFallback, packID: context.manifest.id, answeredCount: 0, correctCount: 0, learnedItemCount: 0, dueCount: 0)
  }
  func makeUnlockChallengeView(snapshot: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) -> AnyView {
    AnyView(SafeFallbackUnlockChallengeView(bundle: snapshot, context: context))
  }
}

private struct SafeFallbackUnlockChallengeView: View {
  let bundle: ExperienceUnlockBundleSnapshot
  let context: UnlockChallengeViewContext
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

  init(bundle: ExperienceUnlockBundleSnapshot, context: UnlockChallengeViewContext) {
    self.bundle = bundle
    self.context = context
    let first = bundle.challenge.questions.firstIndex {
      !bundle.completedQuestionIDs.contains($0.id)
    } ?? 0
    _index = State(initialValue: first)
    _completedQuestionIDs = State(initialValue: bundle.completedQuestionIDs)
    if let question = bundle.challenge.questions[safe: first] {
      _selected = State(
        initialValue: bundle.lastSelectedChoiceIDByQuestionID?[question.id.rawValue])
      _waitRemaining = State(initialValue: max(
        0,
        Int(ceil(
          bundle.reviewRemainingActiveSecondsByQuestionID?[question.id.rawValue] ?? 0))))
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        ProgressView(
          value: Double(completedQuestionIDs.count),
          total: Double(max(1, bundle.challenge.questions.count)))
          .accessibilityIdentifier("safeFallback.unlock.progress")
        if let snapshot = bundle.challenge.questions[safe: index],
           case .safeFallback(let question) = snapshot {
          Text(question.prompt).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).studyCard()
          ForEach(question.choices) { choice in
            Button(choice.text) { submit(question: .safeFallback(question), choiceID: choice.id) }
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
    guard let snapshot = bundle.challenge.questions[safe: index], let selected else { return false }
    return selected != snapshot.correctChoiceID
  }

  private var isLast: Bool {
    !bundle.hasLaterUncompletedQuestion(
      after: index,
      completedQuestionIDs: completedQuestionIDs)
  }

  private func submit(question: UnlockQuestionSnapshot, choiceID: Int) {
    isSubmitting = true
    Task {
      switch await context.submit(
        question,
        choiceID,
        choiceID == question.correctChoiceID ? .immediate : .relearn6
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
    if let next = bundle.nextUncompletedQuestionIndex(
      after: index,
      completedQuestionIDs: completedQuestionIDs)
    {
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
    guard let question = bundle.challenge.questions[safe: index] else { return }
    isReviewSyncing = true
    var desiredActiveState = isActive
    repeat {
      pendingReviewActiveState = nil
      switch await context.updateReviewExposure(question.id, desiredActiveState) {
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
