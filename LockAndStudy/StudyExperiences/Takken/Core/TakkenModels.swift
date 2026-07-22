import Foundation

enum TakkenQuestionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case all, unanswered, correct, incorrect
  var id: String { rawValue }
  var title: String {
    switch self { case .all: return "すべて"; case .unanswered: return "未回答"; case .correct: return "正解"; case .incorrect: return "不正解" }
  }
}

struct TakkenSettings: Codable, Equatable, Sendable {
  var examYear: Int
  var selectedCategories: Set<String>
  var selectedDifficulties: Set<String>
  var last30DaysFocus: Bool
  var questionCount: Int

  static let standard = TakkenSettings(
    examYear: 2026,
    selectedCategories: [],
    selectedDifficulties: [],
    last30DaysFocus: false,
    questionCount: 10
  )
  private static let legacyKey = "lockandstudy.experience.takken.settings.v1"
  private static let legacyPackID: StudyPackID = "takken2026.v1"
  private static func key(_ packID: StudyPackID) -> String {
    "lockandstudy.pack.\(packID.rawValue).takken.settings.v2"
  }

  static func load(
    packID: StudyPackID,
    defaults: UserDefaults = LockAndStudySharedConstants.defaults
  ) -> TakkenSettings {
    if let data = defaults.data(forKey: key(packID)),
      let value = try? SharedJSON.decoder().decode(TakkenSettings.self, from: data)
    {
      return value
    }
    if packID == legacyPackID,
      let legacy = defaults.data(forKey: legacyKey),
      let value = try? SharedJSON.decoder().decode(TakkenSettings.self, from: legacy)
    {
      defaults.set(legacy, forKey: key(packID))
      return value
    }
    return .standard
  }

  static func load(defaults: UserDefaults = LockAndStudySharedConstants.defaults) -> TakkenSettings {
    load(packID: legacyPackID, defaults: defaults)
  }
  func save(
    packID: StudyPackID,
    defaults: UserDefaults = LockAndStudySharedConstants.defaults
  ) throws {
    defaults.set(try SharedJSON.encoder().encode(self), forKey: Self.key(packID))
  }
  func save(defaults: UserDefaults = LockAndStudySharedConstants.defaults) throws {
    try save(packID: Self.legacyPackID, defaults: defaults)
  }
}

struct TakkenQuestionService: Sendable {
  func filter(
    questions: [TakkenQuestion],
    progress: [String: ItemProgress],
    packID: StudyPackID,
    status: TakkenQuestionStatus = .all,
    category: String? = nil,
    subCategory: String? = nil,
    difficulties: Set<String> = [],
    search: String = ""
  ) -> [TakkenQuestion] {
    questions.filter { question in
      let itemProgress = progress[CompositeStudyItemID(packID: packID, itemID: .init(rawValue: question.id)).storageKey]
        ?? .initial(.init(packID: packID, itemID: .init(rawValue: question.id)))
      let statusMatches: Bool
      switch status {
      case .all: statusMatches = true
      case .unanswered: statusMatches = itemProgress.answerCount == 0
      case .correct: statusMatches = itemProgress.lastAnsweredAt != nil && itemProgress.consecutiveCorrect > 0
      case .incorrect: statusMatches = itemProgress.incorrectCount > 0 && itemProgress.consecutiveCorrect == 0
      }
      let searchMatches = search.isEmpty
        || question.prompt.localizedCaseInsensitiveContains(search)
        || question.explanation.localizedCaseInsensitiveContains(search)
        || (question.subCategory?.localizedCaseInsensitiveContains(search) ?? false)
        || (question.keyPoint?.localizedCaseInsensitiveContains(search) ?? false)
        || (question.contrastNote?.localizedCaseInsensitiveContains(search) ?? false)
        || (question.preview?.rule.localizedCaseInsensitiveContains(search) ?? false)
        || question.choices.contains { $0.text.localizedCaseInsensitiveContains(search) }
      return statusMatches
        && (category == nil || question.category == category)
        && (subCategory == nil || question.subCategory == subCategory)
        && (difficulties.isEmpty || difficulties.contains(question.difficulty))
        && searchMatches
    }
  }

  func practiceQuestions(
    questions: [TakkenQuestion],
    progress: [String: ItemProgress],
    packID: StudyPackID,
    settings: TakkenSettings,
    mode: StudyMode,
    count: Int,
    now: Date
  ) -> [TakkenQuestion] {
    TakkenQuestionSelectionEngine().select(.init(
      questions: questions, settings: settings, progress: progress, recentAnswers: [],
      packID: packID, mode: mode, count: count, sessionID: UUID(), pendingPreview: nil,
      now: now)).map(\.source)
  }
}

struct TakkenFeedbackPlanner: Sendable {
  func plan(wrongAttemptCount: Int) -> StudyFeedbackPlan {
    switch wrongAttemptCount {
    case 0: return .immediate
    case 1: return .relearn6
    default: return .relearn12
    }
  }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int {
    switch plan { case .immediate: return 0; case .relearn6: return 10; case .relearn12: return 15; case .guided20: return 20 }
  }
}

struct TakkenQuestionListViewModel: Sendable {
  let questions: [TakkenQuestion]
  let progress: [String: ItemProgress]
  let packID: StudyPackID
  func rows(status: TakkenQuestionStatus, category: String?, subCategory: String?, difficulty: Set<String>, search: String) -> [TakkenQuestion] {
    TakkenQuestionService().filter(
      questions: questions, progress: progress, packID: packID, status: status,
      category: category, subCategory: subCategory, difficulties: difficulty, search: search
    )
  }
  var categories: [String] { Array(Set(questions.map(\.category))).sorted() }
  func subCategories(in category: String?) -> [String] {
    Array(Set(questions.filter { category == nil || $0.category == category }.compactMap(\.subCategory))).sorted()
  }
}

struct TakkenQuestionDetailViewModel: Sendable {
  let question: TakkenQuestion
  let answers: [StudyAnswerRecord]
  let packID: StudyPackID
  var answerHistory: [StudyAnswerRecord] {
    answers.filter { $0.packID == packID && $0.itemID.rawValue == question.id }
      .sorted { $0.answeredAt > $1.answeredAt }
  }
  var correctChoiceText: String { question.choices[safe: question.correctIndex]?.text ?? "未設定" }
  var explanation: String { question.longExplanation ?? question.explanation }
}

struct TakkenRecordsSummary: Equatable, Sendable {
  let answerCount: Int
  let correctCount: Int
  let wrongCount: Int
  let streak: Int
  let byCategory: [String: (answered: Int, correct: Int)]
  let bySubCategory: [String: (answered: Int, correct: Int)]
  var accuracy: Int { answerCount == 0 ? 0 : Int((Double(correctCount) / Double(answerCount) * 100).rounded()) }

  static func == (lhs: TakkenRecordsSummary, rhs: TakkenRecordsSummary) -> Bool {
    lhs.answerCount == rhs.answerCount && lhs.correctCount == rhs.correctCount && lhs.wrongCount == rhs.wrongCount && lhs.streak == rhs.streak
      && Set(lhs.byCategory.keys) == Set(rhs.byCategory.keys)
      && lhs.byCategory.allSatisfy { lhs.byCategory[$0.key]?.answered == rhs.byCategory[$0.key]?.answered && lhs.byCategory[$0.key]?.correct == rhs.byCategory[$0.key]?.correct }
      && Set(lhs.bySubCategory.keys) == Set(rhs.bySubCategory.keys)
      && lhs.bySubCategory.allSatisfy { lhs.bySubCategory[$0.key]?.answered == rhs.bySubCategory[$0.key]?.answered && lhs.bySubCategory[$0.key]?.correct == rhs.bySubCategory[$0.key]?.correct }
  }
}

struct TakkenRecordsAnalyzer: Sendable {
  func summary(
    answers: [StudyAnswerRecord],
    packID: StudyPackID,
    now: Date,
    calendar: Calendar = .current
  ) -> TakkenRecordsSummary {
    let scoped = answers.filter { $0.experienceID == .takken && $0.packID == packID }
    let grouped = Dictionary(grouping: scoped, by: \.category).mapValues { values in
      (answered: values.count, correct: values.filter(\.isCorrect).count)
    }
    let subCategories = Dictionary(grouping: scoped.filter { $0.subcategory != nil }, by: { $0.subcategory ?? "未分類" }).mapValues { values in
      (answered: values.count, correct: values.filter(\.isCorrect).count)
    }
    let days = Set(scoped.map { calendar.startOfDay(for: $0.answeredAt) })
    var streak = 0
    for offset in 0..<365 {
      guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)), days.contains(day) else { break }
      streak += 1
    }
    return .init(answerCount: scoped.count, correctCount: scoped.filter(\.isCorrect).count, wrongCount: scoped.filter { !$0.isCorrect }.count, streak: streak, byCategory: grouped, bySubCategory: subCategories)
  }
}
