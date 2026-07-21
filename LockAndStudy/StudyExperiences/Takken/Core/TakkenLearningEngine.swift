import Foundation

struct TakkenPendingPreview: Codable, Equatable, Sendable, Identifiable {
  static let displayDuration: TimeInterval = 120
  static let recallDuration: TimeInterval = 86_400

  let id: UUID
  let sourceUnlockBundleID: UUID
  let conceptID: String
  let sourceQuestionID: String
  let preferredVariantID: String?
  let contentVersion: String
  let createdAt: Date
  let recallExpiresAt: Date
  var confirmedAt: Date?
  var consumedAt: Date?
  var foregroundExposureSeconds: TimeInterval

  var displayExpiresAt: Date { createdAt.addingTimeInterval(Self.displayDuration) }

  func displayRemainingSeconds(at date: Date) -> TimeInterval {
    max(0, displayExpiresAt.timeIntervalSince(date))
  }

  func isDisplayable(at date: Date) -> Bool {
    consumedAt == nil && displayRemainingSeconds(at: date) > 0
  }

  func isUsableForRecall(contentVersion: String, now: Date) -> Bool {
    self.contentVersion == contentVersion && confirmedAt != nil && consumedAt == nil
      && recallExpiresAt > now
  }

  mutating func recordForegroundExposure(seconds: TimeInterval, at date: Date) {
    guard seconds > 0, confirmedAt == nil, isDisplayable(at: date) else { return }
    foregroundExposureSeconds += seconds
    if foregroundExposureSeconds >= 2 { confirmedAt = date }
  }

  mutating func resetUnconfirmedForegroundExposure() {
    guard confirmedAt == nil else { return }
    foregroundExposureSeconds = 0
  }
}

struct TakkenPresentedQuestion: Identifiable, Equatable, Sendable {
  let source: TakkenQuestion
  let presentedChoices: [StudyChoice]
  let correctChoiceID: Int
  let seed: UInt64
  let sourceChoiceIDsByPresentedID: [Int: String]

  var id: String { source.id }
  var correctChoiceText: String {
    presentedChoices.first { $0.id == correctChoiceID }?.text ?? "未設定"
  }

  func sourceChoiceID(for presentedID: Int) -> String? {
    sourceChoiceIDsByPresentedID[presentedID]
  }

  static func make(source: TakkenQuestion, sessionID: UUID) -> TakkenPresentedQuestion {
    let seed = TakkenStableRandom.seed("\(sessionID.uuidString)::\(source.id)")
    var stableChoices = source.choices
    if source.resolvedFormat != .trueFalse {
      stableChoices = TakkenStableRandom.shuffled(stableChoices, seed: seed)
    }
    let displayed = stableChoices.enumerated().map { StudyChoice(id: $0.offset, text: $0.element.text) }
    let mapping = Dictionary(uniqueKeysWithValues: stableChoices.enumerated().map { ($0.offset, $0.element.id) })
    let correct = stableChoices.firstIndex { $0.id == source.correctChoiceID } ?? 0
    return .init(
      source: source, presentedChoices: displayed, correctChoiceID: correct, seed: seed,
      sourceChoiceIDsByPresentedID: mapping)
  }
}

enum TakkenStableRandom {
  static func seed(_ value: String) -> UInt64 {
    value.utf8.reduce(14_695_981_039_346_656_037) { hash, byte in
      (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  static func shuffled<Element>(_ values: [Element], seed: UInt64) -> [Element] {
    var result = values
    var generator = Generator(state: seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed)
    guard result.count > 1 else { return result }
    for index in stride(from: result.count - 1, through: 1, by: -1) {
      let other = Int(generator.next() % UInt64(index + 1))
      if index != other { result.swapAt(index, other) }
    }
    return result
  }

  private struct Generator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }
  }
}

struct TakkenQuestionSelectionRequest: Sendable {
  let questions: [TakkenQuestion]
  let settings: TakkenSettings
  let progress: [String: ItemProgress]
  let recentAnswers: [StudyAnswerRecord]
  let packID: StudyPackID
  let mode: StudyMode
  let count: Int
  let sessionID: UUID
  let pendingPreview: TakkenPendingPreview?
  let now: Date
}

struct TakkenQuestionSelectionEngine: Sendable {
  private let difficultyRank = ["基礎": 0, "標準": 1, "応用": 2]
  private let importanceRank = ["高": 2, "中": 1, "低": 0]

  func select(_ request: TakkenQuestionSelectionRequest) -> [TakkenPresentedQuestion] {
    guard request.count > 0 else { return [] }
    var eligible = request.questions.filter { question in
      (request.mode != .unlock || question.unlockEligible)
        && (request.settings.selectedCategories.isEmpty
          || request.settings.selectedCategories.contains(question.category))
        && (request.settings.selectedDifficulties.isEmpty
          || request.settings.selectedDifficulties.contains(question.difficulty))
    }
    if request.settings.last30DaysFocus {
      let focused = eligible.filter(\.last30DaysEligible)
      if !focused.isEmpty { eligible = focused }
    }
    eligible = filterForMode(eligible, request: request)

    let recentItemIDs = Set(request.recentAnswers.suffix(10).map { $0.itemID.rawValue })
    let recentFormats = request.recentAnswers.suffix(20).compactMap {
      $0.questionFormat.flatMap(TakkenQuestionFormat.init(rawValue:))
    }
    let target = formatTargets(for: request.mode)
    var selected: [TakkenQuestion] = []
    var selectedConcepts: Set<String> = []

    if let preview = request.pendingPreview {
      let candidates = eligible.filter { $0.resolvedConceptID == preview.conceptID }
      let preferred = candidates.first { $0.resolvedVariantID != preview.preferredVariantID }
        ?? candidates.first
      if let preferred {
        selected.append(preferred)
        selectedConcepts.insert(preferred.resolvedConceptID)
      }
    }

    while selected.count < request.count {
      let pool = eligible.filter { candidate in
        !selected.contains(where: { $0.id == candidate.id })
          && !selectedConcepts.contains(candidate.resolvedConceptID)
      }
      guard let next = pool.min(by: { lhs, rhs in
        ranking(
          lhs, request: request, recentItemIDs: recentItemIDs,
          formatHistory: recentFormats + selected.map(\.resolvedFormat), target: target)
          < ranking(
            rhs, request: request, recentItemIDs: recentItemIDs,
            formatHistory: recentFormats + selected.map(\.resolvedFormat), target: target)
      }) else { break }
      selected.append(next)
      selectedConcepts.insert(next.resolvedConceptID)
    }

    if selected.count < request.count {
      let remaining = eligible.filter { candidate in !selected.contains { $0.id == candidate.id } }
        .sorted { stableTie($0, request: request) < stableTie($1, request: request) }
      selected.append(contentsOf: remaining.prefix(request.count - selected.count))
    }
    return selected.prefix(request.count).map {
      TakkenPresentedQuestion.make(source: $0, sessionID: request.sessionID)
    }
  }

  private func filterForMode(
    _ questions: [TakkenQuestion], request: TakkenQuestionSelectionRequest
  ) -> [TakkenQuestion] {
    let filtered = questions.filter { question in
      let value = progress(question, request: request)
      switch request.mode {
      case .mistakes: return value.incorrectCount > 0
      case .weakness:
        return question.weaknessEligible
          && value.incorrectCount >= max(1, value.correctCount)
      case .newItems: return value.answerCount == 0
      case .review: return value.dueAt.map { $0 <= request.now } ?? false
      default: return true
      }
    }
    return filtered.isEmpty && request.mode == .unlock ? questions : filtered
  }

  private func ranking(
    _ question: TakkenQuestion,
    request: TakkenQuestionSelectionRequest,
    recentItemIDs: Set<String>,
    formatHistory: [TakkenQuestionFormat],
    target: [TakkenQuestionFormat: Double]
  ) -> (Int, Int, Int, Int, UInt64) {
    let value = progress(question, request: request)
    let priority: Int
    if value.dueAt.map({ $0 <= request.now }) == true { priority = 0 }
    else if value.incorrectCount > value.correctCount { priority = 1 }
    else if value.answerCount == 0 { priority = 2 }
    else { priority = 3 }
    let recentPenalty = recentItemIDs.contains(question.id) ? 1 : 0
    let count = formatHistory.filter { $0 == question.resolvedFormat }.count
    let desired = target[question.resolvedFormat] ?? 0
    let formatPenalty = Int((Double(count + 1) / Double(max(1, formatHistory.count + 1)) - desired) * 1_000)
    let difficulty = difficultyRank[question.difficulty] ?? 99
    let importance = -(importanceRank[question.importance ?? ""] ?? 0)
    return (priority, recentPenalty, formatPenalty, importance + difficulty, stableTie(question, request: request))
  }

  private func progress(
    _ question: TakkenQuestion, request: TakkenQuestionSelectionRequest
  ) -> ItemProgress {
    let id = CompositeStudyItemID(
      packID: request.packID, itemID: .init(rawValue: question.id))
    return request.progress[id.storageKey] ?? .initial(id)
  }

  private func stableTie(
    _ question: TakkenQuestion, request: TakkenQuestionSelectionRequest
  ) -> UInt64 {
    TakkenStableRandom.seed("\(request.sessionID.uuidString)::\(question.id)")
  }

  private func formatTargets(for mode: StudyMode) -> [TakkenQuestionFormat: Double] {
    switch mode {
    case .unlock:
      return [.trueFalse: 0.30, .numberChoice: 0.30, .wordingContrast: 0.25,
              .multipleChoice: 0.075, .caseStudy: 0.075]
    default:
      return [.trueFalse: 0.20, .numberChoice: 0.20, .wordingContrast: 0.20,
              .multipleChoice: 0.20, .caseStudy: 0.20]
    }
  }
}

struct TakkenExplanationPresentation: Equatable, Sendable {
  let selectedText: String
  let correctText: String
  let whyWrong: String
  let rule: String
  let contrast: String?
  let keyPoint: String?
  let sourceNote: String?
  let lawBasisDate: String?
}

struct TakkenWrongReviewState: Equatable, Sendable {
  let selectedChoiceID: Int
  let correctChoiceID: Int
  let wrongAttemptCount: Int
  let minimumReviewEndsAt: Date
  let explanation: TakkenExplanationPresentation
}

struct TakkenCorrectReviewState: Equatable, Sendable {
  let selectedChoiceID: Int
  let correctChoiceID: Int
  let wasRelearned: Bool
  let explanation: TakkenExplanationPresentation
}

enum TakkenAnswerPhase: Equatable, Sendable {
  case answering
  case reviewingWrong(TakkenWrongReviewState)
  case readyToRetry(TakkenWrongReviewState)
  case answeredCorrect(TakkenCorrectReviewState)
}

struct TakkenAnswerStateMachine: Equatable, Sendable {
  private(set) var phase: TakkenAnswerPhase = .answering
  private(set) var wrongAttemptCount = 0

  init() {}

  init(
    restoring question: TakkenUnlockQuestionSnapshot,
    selectedChoiceID: Int,
    wrongAttemptCount: Int,
    reviewRequiredUntil: Date?,
    now: Date
  ) {
    self.wrongAttemptCount = max(1, wrongAttemptCount)
    let selected = question.choices.first { $0.id == selectedChoiceID }?.text ?? "未選択"
    let correct = question.choices.first { $0.id == question.correctChoiceID }?.text ?? "未設定"
    let explanation = TakkenExplanationPresentation(
      selectedText: selected,
      correctText: correct,
      whyWrong: question.wrongChoiceRationales?[selectedChoiceID]
        ?? question.shortExplanation,
      rule: question.longExplanation,
      contrast: question.contrastNote,
      keyPoint: question.keyPoint,
      sourceNote: question.sourceNote,
      lawBasisDate: question.lawBasisDate)
    let state = TakkenWrongReviewState(
      selectedChoiceID: selectedChoiceID,
      correctChoiceID: question.correctChoiceID,
      wrongAttemptCount: self.wrongAttemptCount,
      minimumReviewEndsAt: reviewRequiredUntil ?? now,
      explanation: explanation)
    phase = state.minimumReviewEndsAt > now ? .reviewingWrong(state) : .readyToRetry(state)
  }

  mutating func record(
    selectedChoiceID: Int, question: TakkenPresentedQuestion, at date: Date
  ) {
    let explanation = makeExplanation(selectedChoiceID: selectedChoiceID, question: question)
    if selectedChoiceID == question.correctChoiceID {
      phase = .answeredCorrect(.init(
        selectedChoiceID: selectedChoiceID, correctChoiceID: question.correctChoiceID,
        wasRelearned: wrongAttemptCount > 0, explanation: explanation))
      return
    }
    wrongAttemptCount += 1
    let base = question.source.minimumReviewSeconds ?? 10
    let staged = wrongAttemptCount == 1 ? 10 : (wrongAttemptCount == 2 ? 15 : 20)
    let state = TakkenWrongReviewState(
      selectedChoiceID: selectedChoiceID, correctChoiceID: question.correctChoiceID,
      wrongAttemptCount: wrongAttemptCount,
      minimumReviewEndsAt: date.addingTimeInterval(TimeInterval(max(base, staged))),
      explanation: explanation)
    phase = .reviewingWrong(state)
  }

  mutating func record(
    selectedChoiceID: Int, question: TakkenUnlockQuestionSnapshot, at date: Date
  ) {
    let selected = question.choices.first { $0.id == selectedChoiceID }?.text ?? "未選択"
    let correct = question.choices.first { $0.id == question.correctChoiceID }?.text ?? "未設定"
    let explanation = TakkenExplanationPresentation(
      selectedText: selected,
      correctText: correct,
      whyWrong: question.wrongChoiceRationales?[selectedChoiceID]
        ?? question.shortExplanation,
      rule: question.longExplanation,
      contrast: question.contrastNote,
      keyPoint: question.keyPoint,
      sourceNote: question.sourceNote,
      lawBasisDate: question.lawBasisDate)
    if selectedChoiceID == question.correctChoiceID {
      phase = .answeredCorrect(.init(
        selectedChoiceID: selectedChoiceID, correctChoiceID: question.correctChoiceID,
        wasRelearned: wrongAttemptCount > 0, explanation: explanation))
      return
    }
    wrongAttemptCount += 1
    let staged = wrongAttemptCount == 1 ? 10 : (wrongAttemptCount == 2 ? 15 : 20)
    let state = TakkenWrongReviewState(
      selectedChoiceID: selectedChoiceID, correctChoiceID: question.correctChoiceID,
      wrongAttemptCount: wrongAttemptCount,
      minimumReviewEndsAt: date.addingTimeInterval(
        TimeInterval(max(question.minimumReviewSeconds ?? 10, staged))),
      explanation: explanation)
    phase = .reviewingWrong(state)
  }

  mutating func update(at date: Date) {
    guard case .reviewingWrong(let state) = phase, date >= state.minimumReviewEndsAt else { return }
    phase = .readyToRetry(state)
  }

  mutating func delayReview(by interval: TimeInterval) {
    guard interval > 0, case .reviewingWrong(let state) = phase else { return }
    phase = .reviewingWrong(.init(
      selectedChoiceID: state.selectedChoiceID,
      correctChoiceID: state.correctChoiceID,
      wrongAttemptCount: state.wrongAttemptCount,
      minimumReviewEndsAt: state.minimumReviewEndsAt.addingTimeInterval(interval),
      explanation: state.explanation))
  }

  @discardableResult mutating func retry() -> Bool {
    guard case .readyToRetry = phase else { return false }
    phase = .answering
    return true
  }

  func remainingSeconds(at date: Date) -> Int {
    guard case .reviewingWrong(let state) = phase else { return 0 }
    return max(0, Int(ceil(state.minimumReviewEndsAt.timeIntervalSince(date))))
  }

  private func makeExplanation(
    selectedChoiceID: Int, question: TakkenPresentedQuestion
  ) -> TakkenExplanationPresentation {
    let selected = question.presentedChoices.first { $0.id == selectedChoiceID }?.text ?? "未選択"
    let sourceChoiceID = question.sourceChoiceID(for: selectedChoiceID)
    let sourceChoice = question.source.choices.first { $0.id == sourceChoiceID }
    return .init(
      selectedText: selected,
      correctText: question.correctChoiceText,
      whyWrong: sourceChoice?.rationale
        ?? sourceChoiceID.flatMap { question.source.wrongChoiceRationales?[$0] }
        ?? question.source.shortExplanation ?? question.source.explanation,
      rule: question.source.longExplanation ?? question.source.explanation,
      contrast: question.source.contrastNote,
      keyPoint: question.source.keyPoint,
      sourceNote: question.source.sourceNote,
      lawBasisDate: question.source.lawBasisDate)
  }
}
