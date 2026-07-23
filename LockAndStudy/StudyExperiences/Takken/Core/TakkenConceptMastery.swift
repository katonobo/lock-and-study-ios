import Foundation

enum TakkenConceptMasteryState: String, Equatable, Sendable {
  case unlearned
  case learning
  case relearning
  case stabilizing
  case mastered
  case due
}

enum TakkenMisconceptionTagger {
  static func tags(correct: Bool, misconceptionCode: String?) -> [String] {
    guard !correct, let misconceptionCode, !misconceptionCode.isEmpty else {
      return []
    }
    return ["misconception:\(misconceptionCode)"]
  }
}

struct TakkenConceptMasterySnapshot: Equatable, Sendable {
  let conceptID: String
  let state: TakkenConceptMasteryState
  let answerCount: Int
  let firstAttemptCorrectCount: Int
  let incorrectCount: Int
  let distinctVariantCount: Int
  let distinctSessionCount: Int
  let consecutiveFirstAttemptCorrect: Int
  let lastAnsweredAt: Date?
  let dueAt: Date?
  let weakMisconceptionCodes: Set<String>
}

struct TakkenConceptMasteryPolicy: Sendable {
  func snapshot(
    conceptID: String,
    answers: [StudyAnswerRecord],
    now: Date,
    calendar: Calendar = .current
  ) -> TakkenConceptMasterySnapshot {
    let relevant = answers
      .filter { ($0.conceptID ?? $0.itemID.rawValue) == conceptID }
      .sorted(by: answerOrder)
    guard !relevant.isEmpty else {
      return .init(
        conceptID: conceptID, state: .unlearned, answerCount: 0,
        firstAttemptCorrectCount: 0, incorrectCount: 0, distinctVariantCount: 0,
        distinctSessionCount: 0, consecutiveFirstAttemptCorrect: 0,
        lastAnsweredAt: nil, dueAt: nil, weakMisconceptionCodes: [])
    }

    let initial = firstAttempts(relevant)
    let correctInitial = initial.filter(\.isCorrect)
    let streak = correctStreak(initial)
    let lastInitial = initial.last
    let dueAt = dueDate(
      after: lastInitial?.answeredAt ?? relevant.last?.answeredAt,
      streak: streak,
      lastWasCorrect: lastInitial?.isCorrect == true,
      calendar: calendar)
    let correctSessions = Set(correctInitial.map(\.sessionID))
    let correctVariants = Set(correctInitial.map {
      $0.variantID ?? $0.itemID.rawValue
    })
    let state: TakkenConceptMasteryState
    if let dueAt, dueAt <= now {
      state = .due
    } else if lastInitial?.isCorrect != true {
      state = .relearning
    } else if correctVariants.count >= 2 && correctSessions.count >= 2 && streak >= 2 {
      state = .mastered
    } else if correctSessions.count >= 2 {
      state = .stabilizing
    } else {
      state = .learning
    }
    let weakCodes = activeMisconceptionCodes(
      answers: relevant, firstAttempts: initial)
    return .init(
      conceptID: conceptID,
      state: state,
      answerCount: relevant.count,
      firstAttemptCorrectCount: correctInitial.count,
      incorrectCount: relevant.filter { !$0.isCorrect }.count,
      distinctVariantCount: correctVariants.count,
      distinctSessionCount: Set(relevant.map(\.sessionID)).count,
      consecutiveFirstAttemptCorrect: streak,
      lastAnsweredAt: relevant.last?.answeredAt,
      dueAt: dueAt,
      weakMisconceptionCodes: weakCodes)
  }

  func reviewIntervalDays(forFirstAttemptCorrectStreak streak: Int) -> Int {
    switch streak {
    case ..<1: return 0
    case 1: return 1
    case 2: return 3
    case 3: return 7
    case 4: return 14
    default: return 30
    }
  }

  private func dueDate(
    after date: Date?,
    streak: Int,
    lastWasCorrect: Bool,
    calendar: Calendar
  ) -> Date? {
    guard let date else { return nil }
    if !lastWasCorrect {
      return date.addingTimeInterval(6 * 60 * 60)
    }
    return calendar.date(
      byAdding: .day, value: reviewIntervalDays(forFirstAttemptCorrectStreak: streak),
      to: date)
  }

  private func firstAttempts(_ answers: [StudyAnswerRecord]) -> [StudyAnswerRecord] {
    let explicit = answers.filter { $0.wasFirstAttempt == true || $0.attemptNumber == 1 }
    let explicitKeys = Set(explicit.map {
      "\($0.sessionID.uuidString)::\($0.itemID.rawValue)"
    })
    let legacy = Dictionary(
      grouping: answers.filter {
        $0.attemptNumber == nil
          && !explicitKeys.contains("\($0.sessionID.uuidString)::\($0.itemID.rawValue)")
      },
      by: { "\($0.sessionID.uuidString)::\($0.itemID.rawValue)" }
    ).values.compactMap { $0.sorted(by: answerOrder).first }
    return (explicit + legacy).sorted(by: answerOrder)
  }

  private func correctStreak(_ answers: [StudyAnswerRecord]) -> Int {
    var result = 0
    for answer in answers.reversed() {
      guard answer.isCorrect else { break }
      result += 1
    }
    return result
  }

  private func activeMisconceptionCodes(
    answers: [StudyAnswerRecord],
    firstAttempts: [StudyAnswerRecord]
  ) -> Set<String> {
    var latestWrongByCode: [String: StudyAnswerRecord] = [:]
    for answer in answers where !answer.isCorrect {
      for code in misconceptionCodes(answer) {
        if let existing = latestWrongByCode[code],
          !answerOrder(existing, answer)
        {
          continue
        }
        latestWrongByCode[code] = answer
      }
    }
    return Set(latestWrongByCode.compactMap { code, wrong -> String? in
      let correctAfterWrong = firstAttempts.filter {
        $0.isCorrect && $0.answeredAt > wrong.answeredAt
      }
      let suitable = correctAfterWrong.filter {
        isSuitable(questionFormat: $0.questionFormat, for: code)
      }
      let resolvedByTargetedRecall =
        Set(suitable.map(\.sessionID)).count >= 2
        && Set(suitable.map { $0.variantID ?? $0.itemID.rawValue }).count >= 2
      let resolvedByMasteryAfterWrong =
        correctStreak(correctAfterWrong) >= 2
        && Set(correctAfterWrong.map(\.sessionID)).count >= 2
        && Set(
          correctAfterWrong.map { $0.variantID ?? $0.itemID.rawValue }
        ).count >= 2
      return resolvedByTargetedRecall || resolvedByMasteryAfterWrong ? nil : code
    })
  }

  private func misconceptionCodes(_ answer: StudyAnswerRecord) -> Set<String> {
    Set((answer.tags ?? []).compactMap { tag -> String? in
      let prefix = "misconception:"
      guard tag.hasPrefix(prefix) else { return nil }
      return String(tag.dropFirst(prefix.count))
    })
  }

  private func isSuitable(questionFormat: String?, for code: String) -> Bool {
    guard let format = questionFormat.flatMap(TakkenQuestionFormat.init(rawValue:))
    else { return false }
    switch code {
    case "number":
      return format == .numberChoice
    case "actor", "timing", "obligation", "procedure":
      return format == .wordingContrast || format == .caseStudy
    case "exception", "scope", "condition":
      return format == .multipleChoice || format == .caseStudy
    case "document", "terminology":
      return format == .trueFalse || format == .wordingContrast
    default:
      return false
    }
  }

  private func answerOrder(_ lhs: StudyAnswerRecord, _ rhs: StudyAnswerRecord) -> Bool {
    if lhs.answeredAt == rhs.answeredAt {
      return (lhs.attemptNumber ?? 1) < (rhs.attemptNumber ?? 1)
    }
    return lhs.answeredAt < rhs.answeredAt
  }
}
