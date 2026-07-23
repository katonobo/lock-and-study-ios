import Foundation

struct TakkenPendingPreview: Codable, Equatable, Sendable, Identifiable {
  static let displayDuration: TimeInterval = 120
  static let recallDuration: TimeInterval = 86_400

  let id: UUID
  let packID: StudyPackID
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

  init(
    id: UUID,
    packID: StudyPackID = "takken2026.v1",
    sourceUnlockBundleID: UUID,
    conceptID: String,
    sourceQuestionID: String,
    preferredVariantID: String?,
    contentVersion: String,
    createdAt: Date,
    recallExpiresAt: Date,
    confirmedAt: Date?,
    consumedAt: Date?,
    foregroundExposureSeconds: TimeInterval
  ) {
    self.id = id
    self.packID = packID
    self.sourceUnlockBundleID = sourceUnlockBundleID
    self.conceptID = conceptID
    self.sourceQuestionID = sourceQuestionID
    self.preferredVariantID = preferredVariantID
    self.contentVersion = contentVersion
    self.createdAt = createdAt
    self.recallExpiresAt = recallExpiresAt
    self.confirmedAt = confirmedAt
    self.consumedAt = consumedAt
    self.foregroundExposureSeconds = foregroundExposureSeconds
  }

  enum CodingKeys: String, CodingKey {
    case id, packID, sourceUnlockBundleID, conceptID, sourceQuestionID, preferredVariantID
    case contentVersion, createdAt, recallExpiresAt, confirmedAt, consumedAt
    case foregroundExposureSeconds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    packID = try container.decodeIfPresent(StudyPackID.self, forKey: .packID) ?? "takken2026.v1"
    sourceUnlockBundleID = try container.decode(UUID.self, forKey: .sourceUnlockBundleID)
    conceptID = try container.decode(String.self, forKey: .conceptID)
    sourceQuestionID = try container.decode(String.self, forKey: .sourceQuestionID)
    preferredVariantID = try container.decodeIfPresent(String.self, forKey: .preferredVariantID)
    contentVersion = try container.decode(String.self, forKey: .contentVersion)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    recallExpiresAt = try container.decode(Date.self, forKey: .recallExpiresAt)
    confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
    consumedAt = try container.decodeIfPresent(Date.self, forKey: .consumedAt)
    foregroundExposureSeconds =
      try container.decodeIfPresent(TimeInterval.self, forKey: .foregroundExposureSeconds) ?? 0
  }

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

struct TakkenPendingPreviewResolver: Sendable {
  func visibleQuestion(
    for preview: TakkenPendingPreview?,
    in questions: [TakkenQuestion],
    contentVersion: String,
    at date: Date
  ) -> TakkenQuestion? {
    guard let preview, preview.isDisplayable(at: date),
      preview.contentVersion == contentVersion
    else { return nil }
    return questions.first { $0.id == preview.sourceQuestionID }
      ?? questions.first { $0.resolvedConceptID == preview.conceptID }
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
  private let masteryPolicy = TakkenConceptMasteryPolicy()

  func select(_ request: TakkenQuestionSelectionRequest) -> [TakkenPresentedQuestion] {
    guard request.count > 0 else { return [] }
    var eligible = request.questions.filter { question in
      (request.mode != .unlock || question.unlockEligible)
        && (request.mode != .unlock || (question.estimatedSeconds ?? 30) <= 30)
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

    let presentationHistory = uniquePresentationHistory(request.recentAnswers)
    let recentItemIDs = Set(presentationHistory.suffix(10).map { $0.itemID.rawValue })
    let recentVariantKeys = Set(presentationHistory.suffix(20).map {
      "\($0.conceptID ?? $0.itemID.rawValue)::\($0.variantID ?? $0.itemID.rawValue)"
    })
    let recentFormat = presentationHistory.last?.questionFormat.flatMap {
      TakkenQuestionFormat(rawValue: $0)
    }
    let grouped = Dictionary(grouping: eligible, by: \.resolvedConceptID)
    var selected: [TakkenQuestion] = []
    var selectedConcepts: Set<String> = []

    if let preview = request.pendingPreview {
      let candidates = grouped[preview.conceptID] ?? []
      let mastery = mastery(
        conceptID: preview.conceptID, request: request)
      let preferred = bestVariant(
        from: candidates, mastery: mastery, request: request,
        recentItemIDs: recentItemIDs, recentVariantKeys: recentVariantKeys,
        recentFormat: recentFormat, avoiding: preview.preferredVariantID)
      if let preferred {
        selected.append(preferred)
        selectedConcepts.insert(preferred.resolvedConceptID)
      }
    }

    while selected.count < request.count {
      let conceptPool = grouped.keys.filter { !selectedConcepts.contains($0) }
      guard let conceptID = conceptPool.min(by: { lhs, rhs in
        conceptRank(
          conceptID: lhs, questions: grouped[lhs] ?? [], request: request,
          recentFormat: recentFormat)
          < conceptRank(
            conceptID: rhs, questions: grouped[rhs] ?? [], request: request,
            recentFormat: recentFormat)
      }) else { break }
      let mastery = mastery(conceptID: conceptID, request: request)
      guard let next = bestVariant(
        from: grouped[conceptID] ?? [], mastery: mastery, request: request,
        recentItemIDs: recentItemIDs, recentVariantKeys: recentVariantKeys,
        recentFormat: recentFormat, avoiding: nil)
      else {
        selectedConcepts.insert(conceptID)
        continue
      }
      selected.append(next)
      selectedConcepts.insert(conceptID)
    }

    return selected.prefix(request.count).map {
      TakkenPresentedQuestion.make(source: $0, sessionID: request.sessionID)
    }
  }

  private func filterForMode(
    _ questions: [TakkenQuestion], request: TakkenQuestionSelectionRequest
  ) -> [TakkenQuestion] {
    let filtered = questions.filter { question in
      let snapshot = mastery(conceptID: question.resolvedConceptID, request: request)
      switch request.mode {
      case .mistakes: return snapshot.incorrectCount > 0
      case .weakness:
        return question.weaknessEligible
          && (snapshot.state == .relearning || !snapshot.weakMisconceptionCodes.isEmpty)
      case .newItems: return snapshot.state == .unlearned
      case .review:
        return snapshot.state == .due
          || progress(question, request: request).dueAt.map { $0 <= request.now } == true
      default: return true
      }
    }
    return filtered.isEmpty && request.mode == .unlock ? questions : filtered
  }

  private func conceptRank(
    conceptID: String,
    questions: [TakkenQuestion],
    request: TakkenQuestionSelectionRequest,
    recentFormat: TakkenQuestionFormat?
  ) -> (Int, Int, Int, Int, UInt64) {
    let snapshot = mastery(conceptID: conceptID, request: request)
    let itemDue = questions.contains {
      progress($0, request: request).dueAt.map { $0 <= request.now } == true
    }
    let priority: Int
    if snapshot.state == .due || itemDue {
      priority = 0
    } else if snapshot.state == .relearning {
      priority = 1
    } else if snapshot.state == .unlearned {
      switch importancePriority(questions) {
      case 0: priority = 2
      case 1: priority = 3
      default: priority = 6
      }
    } else if snapshot.state == .learning || snapshot.state == .stabilizing {
      priority = 4
    } else {
      priority = 5
    }
    let formatPenalty =
      recentFormat.map { recent in
        questions.contains { $0.resolvedFormat != recent } ? 0 : 1
      } ?? 0
    let answeredPenalty = snapshot.answerCount > 0 ? 1 : 0
    let importance = importancePriority(questions)
    return (
      priority, formatPenalty, answeredPenalty, importance,
      TakkenStableRandom.seed("\(request.sessionID.uuidString)::\(conceptID)"))
  }

  private func bestVariant(
    from questions: [TakkenQuestion],
    mastery: TakkenConceptMasterySnapshot,
    request: TakkenQuestionSelectionRequest,
    recentItemIDs: Set<String>,
    recentVariantKeys: Set<String>,
    recentFormat: TakkenQuestionFormat?,
    avoiding variantID: String?
  ) -> TakkenQuestion? {
    questions.min { lhs, rhs in
      variantRank(
        lhs, mastery: mastery, request: request, recentItemIDs: recentItemIDs,
        recentVariantKeys: recentVariantKeys, recentFormat: recentFormat,
        avoiding: variantID
      ).lexicographicallyPrecedes(
        variantRank(
          rhs, mastery: mastery, request: request, recentItemIDs: recentItemIDs,
          recentVariantKeys: recentVariantKeys, recentFormat: recentFormat,
          avoiding: variantID))
    }
  }

  private func variantRank(
    _ question: TakkenQuestion,
    mastery: TakkenConceptMasterySnapshot,
    request: TakkenQuestionSelectionRequest,
    recentItemIDs: Set<String>,
    recentVariantKeys: Set<String>,
    recentFormat: TakkenQuestionFormat?,
    avoiding variantID: String?
  ) -> [UInt64] {
    let variantKey = "\(question.resolvedConceptID)::\(question.resolvedVariantID)"
    return [
      UInt64(variantID == question.resolvedVariantID ? 1 : 0),
      UInt64(recentVariantKeys.contains(variantKey) ? 1 : 0),
      UInt64(recentItemIDs.contains(question.id) ? 1 : 0),
      UInt64(recentFormat == question.resolvedFormat ? 1 : 0),
      UInt64(weaknessPenalty(question.resolvedFormat, codes: mastery.weakMisconceptionCodes)),
      UInt64(request.mode == .unlock ? max(0, question.estimatedSeconds ?? 30) : 0),
      stableTie(question, request: request),
    ]
  }

  private func weaknessPenalty(
    _ format: TakkenQuestionFormat,
    codes: Set<String>
  ) -> Int {
    guard !codes.isEmpty else { return 0 }
    var preferred: Set<TakkenQuestionFormat> = []
    if codes.contains("number") { preferred.insert(.numberChoice) }
    if !codes.isDisjoint(with: ["actor", "timing", "obligation", "procedure"]) {
      preferred.formUnion([.wordingContrast, .caseStudy])
    }
    if !codes.isDisjoint(with: ["exception", "scope", "condition"]) {
      preferred.formUnion([.multipleChoice, .caseStudy])
    }
    if !codes.isDisjoint(with: ["document", "terminology"]) {
      preferred.formUnion([.trueFalse, .wordingContrast])
    }
    return preferred.contains(format) ? 0 : 1
  }

  private func importancePriority(_ questions: [TakkenQuestion]) -> Int {
    questions.map {
      switch $0.importance {
      case "高": return 0
      case "中": return 1
      case "低": return 2
      default: return 3
      }
    }.min() ?? 3
  }

  private func mastery(
    conceptID: String, request: TakkenQuestionSelectionRequest
  ) -> TakkenConceptMasterySnapshot {
    masteryPolicy.snapshot(
      conceptID: conceptID, answers: request.recentAnswers, now: request.now)
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

  private func uniquePresentationHistory(
    _ answers: [StudyAnswerRecord]
  ) -> [StudyAnswerRecord] {
    var seen: Set<String> = []
    return answers.sorted { lhs, rhs in
      if lhs.answeredAt == rhs.answeredAt {
        return (lhs.attemptNumber ?? 1) < (rhs.attemptNumber ?? 1)
      }
      return lhs.answeredAt < rhs.answeredAt
    }.filter { answer in
      seen.insert("\(answer.sessionID.uuidString)::\(answer.itemID.rawValue)").inserted
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
    restoring question: CertificationChallengeQuestion,
    selectedChoiceID: Int,
    wrongAttemptCount: Int,
    reviewRequiredUntil: Date?,
    now: Date
  ) {
    self.init(
      restoring: question,
      selectedChoiceID: selectedChoiceID,
      wrongAttemptCount: wrongAttemptCount,
      reviewRemainingActiveSeconds: max(
        0, reviewRequiredUntil?.timeIntervalSince(now) ?? 0),
      now: now)
  }

  init(
    restoring question: CertificationChallengeQuestion,
    selectedChoiceID: Int,
    wrongAttemptCount: Int,
    reviewRemainingActiveSeconds: TimeInterval,
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
      minimumReviewEndsAt: now.addingTimeInterval(max(0, reviewRemainingActiveSeconds)),
      explanation: explanation)
    phase = reviewRemainingActiveSeconds > 0 ? .reviewingWrong(state) : .readyToRetry(state)
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
    selectedChoiceID: Int, question: CertificationChallengeQuestion, at date: Date
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

  mutating func record(
    selectedChoiceID: Int,
    question: CertificationChallengeQuestion,
    authoritativeRemainingActiveSeconds: Int,
    attemptNumber: Int,
    at date: Date
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
    wrongAttemptCount = max(1, attemptNumber)
    let remaining = max(0, authoritativeRemainingActiveSeconds)
    let state = TakkenWrongReviewState(
      selectedChoiceID: selectedChoiceID, correctChoiceID: question.correctChoiceID,
      wrongAttemptCount: wrongAttemptCount,
      minimumReviewEndsAt: date.addingTimeInterval(TimeInterval(remaining)),
      explanation: explanation)
    phase = remaining > 0 ? .reviewingWrong(state) : .readyToRetry(state)
  }

  mutating func updateReviewRemaining(activeSeconds: Int, at date: Date) {
    let existing: TakkenWrongReviewState
    switch phase {
    case .reviewingWrong(let state), .readyToRetry(let state): existing = state
    case .answering, .answeredCorrect: return
    }
    let remaining = max(0, activeSeconds)
    let updated = TakkenWrongReviewState(
      selectedChoiceID: existing.selectedChoiceID,
      correctChoiceID: existing.correctChoiceID,
      wrongAttemptCount: existing.wrongAttemptCount,
      minimumReviewEndsAt: date.addingTimeInterval(TimeInterval(remaining)),
      explanation: existing.explanation)
    phase = remaining > 0 ? .reviewingWrong(updated) : .readyToRetry(updated)
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
