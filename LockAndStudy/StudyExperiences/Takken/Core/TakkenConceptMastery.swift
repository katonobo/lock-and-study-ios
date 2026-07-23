import Foundation

enum TakkenConceptMasteryState: String, Equatable, Sendable {
  case unlearned
  case learning
  case relearning
  case stabilizing
  case mastered
  case due
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
    let weakCodes = Set(
      relevant
        .filter { !$0.isCorrect }
        .flatMap { $0.tags ?? [] }
        .compactMap { tag -> String? in
          let prefix = "misconception:"
          guard tag.hasPrefix(prefix) else { return nil }
          return String(tag.dropFirst(prefix.count))
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

  private func answerOrder(_ lhs: StudyAnswerRecord, _ rhs: StudyAnswerRecord) -> Bool {
    if lhs.answeredAt == rhs.answeredAt {
      return (lhs.attemptNumber ?? 1) < (rhs.attemptNumber ?? 1)
    }
    return lhs.answeredAt < rhs.answeredAt
  }
}
