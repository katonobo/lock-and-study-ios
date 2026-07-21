import Foundation

struct VocabularyContentMetadata: Codable, Equatable, Sendable {
  let cefr: String
  let contentVersion: String
  let releaseStatus: String
  let releaseEligible: Bool
}

struct VocabularyPendingPreview: Codable, Sendable, Equatable, Identifiable {
  static let displayDuration: TimeInterval = 120
  static let recallDuration: TimeInterval = 86_400

  let id: UUID
  let sourceUnlockBundleID: UUID
  let itemID: String
  let contentVersion: String
  let createdAt: Date
  let recallExpiresAt: Date
  var confirmedAt: Date?
  var consumedAt: Date?
  var foregroundExposureSeconds: TimeInterval

  var displayExpiresAt: Date {
    createdAt.addingTimeInterval(Self.displayDuration)
  }

  func displayRemainingSeconds(at date: Date) -> TimeInterval {
    max(0, displayExpiresAt.timeIntervalSince(date))
  }

  func isDisplayable(at date: Date) -> Bool {
    consumedAt == nil && displayRemainingSeconds(at: date) > 0
  }

  func isUsableForRecall(contentVersion: String, now: Date) -> Bool {
    self.contentVersion == contentVersion
      && confirmedAt != nil
      && consumedAt == nil
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

struct VocabularyItem: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let levelCode: String
  let levelName: String
  let order: Int
  let levelOrder: Int
  let headword: String
  let displayWord: String
  let partOfSpeechJa: String
  let primaryPosJa: String
  let quizMeaningJa: String
  let fullMeaningJa: String
  let exampleEn: String
  let exampleJa: String
  let questionType: String
  let instructionJa: String
  let prompt: String
  let options: [String]
  let correctIndex: Int
  let correctAnswer: String
  let explanationJa: String
  let speechText: String
  let metadata: VocabularyContentMetadata

  var studyItemID: StudyItemID { .init(rawValue: id) }
}

enum VocabularyLevel: String, Codable, CaseIterable, Identifiable, Sendable {
  case level0 = "L0", level1 = "L1", level2 = "L2", level3 = "L3", level4 = "L4"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .level0: return "基礎・A1"
    case .level1: return "中学1年"
    case .level2: return "中学2年"
    case .level3: return "中学3年"
    case .level4: return "高校基礎"
    }
  }
}

struct VocabularySettings: Codable, Equatable, Sendable {
  var selectedLevelCodes: Set<String>
  var dailyGoal: Int
  var speechEnabled: Bool
  var examplesEnabled: Bool

  static let standard = VocabularySettings(
    selectedLevelCodes: [VocabularyLevel.level0.rawValue],
    dailyGoal: 10,
    speechEnabled: true,
    examplesEnabled: true
  )

  private static let key = "lockandstudy.experience.vocabulary.settings.v1"
  static func load(defaults: UserDefaults = LockAndStudySharedConstants.defaults) -> VocabularySettings {
    guard let data = defaults.data(forKey: key),
          let value = try? SharedJSON.decoder().decode(VocabularySettings.self, from: data) else { return .standard }
    return value
  }
  func save(defaults: UserDefaults = LockAndStudySharedConstants.defaults) throws {
    defaults.set(try SharedJSON.encoder().encode(self), forKey: Self.key)
  }
}

struct VocabularyQuestion: Equatable, Identifiable, Sendable {
  let id: UUID
  let item: VocabularyItem
  let choices: [StudyChoice]
  let correctChoiceID: Int
}

struct VocabularyPackage: Sendable {
  let items: [VocabularyItem]
  let freeSampleIDs: Set<String>
}

struct VocabularyRepository: Sendable {
  let loader: VerifiedContentLoader
  init(bundle: Bundle = .main) { loader = .init(bundle: bundle) }

  func load(manifest: StudyPackManifest) throws -> VocabularyPackage {
    guard !manifest.contentFiles.isEmpty else { throw ContentRepositoryError.missing(manifest.title) }
    guard let samplePath = manifest.sampleDefinition.catalogFile else {
      throw ContentRepositoryError.missing("固定無料サンプル")
    }
    var items: [VocabularyItem] = []
    var verifiedSampleData: Data?
    let decoder = JSONDecoder()
    for descriptor in manifest.contentFiles {
      let data = try loader.data(for: descriptor)
      if descriptor.path == samplePath {
        verifiedSampleData = data
        continue
      }
      let decoded = try decoder.decode([VocabularyItem].self, from: data)
      guard decoded.count == descriptor.itemCount else {
        throw ContentRepositoryError.invalid("\(descriptor.path) の件数がmanifestと一致しません")
      }
      items.append(contentsOf: decoded)
    }
    guard items.count == manifest.expectedItemCount else {
      throw ContentRepositoryError.invalid("英単語の合計件数が\(manifest.expectedItemCount)件ではありません")
    }
    guard Set(items.map(\.id)).count == items.count else {
      throw ContentRepositoryError.invalid("英単語IDが重複しています")
    }
    let sampleData = try verifiedSampleData ?? loader.data(resourcePath: samplePath)
    let catalog = try decoder.decode(VocabularyFreeSampleCatalog.self, from: sampleData)
    let sampleIDs = Set(catalog.levels.flatMap { $0.questions.map(\.id) })
    guard sampleIDs.count == manifest.sampleDefinition.count,
          sampleIDs.isSubset(of: Set(items.map(\.id))) else {
      throw ContentRepositoryError.invalid("固定無料250語を検証できません")
    }
    return .init(items: items.sorted { $0.order < $1.order }, freeSampleIDs: sampleIDs)
  }
}

private struct VocabularyFreeSampleCatalog: Decodable {
  struct Level: Decodable {
    struct Question: Decodable { let id: String }
    let questions: [Question]
  }
  let levels: [Level]
}

struct VocabularyQuestionGenerator: Sendable {
  func makeQuestion(for item: VocabularyItem) throws -> VocabularyQuestion {
    guard item.options.count == 4, item.options.indices.contains(item.correctIndex),
          item.options[item.correctIndex] == item.correctAnswer else {
      throw ContentRepositoryError.invalid("\(item.id) の正式四択を生成できません")
    }
    return .init(
      id: UUID(),
      item: item,
      choices: item.options.enumerated().map { .init(id: $0.offset, text: $0.element) },
      correctChoiceID: item.correctIndex
    )
  }
}

struct VocabularyLearningQueuePlanner: Sendable {
  func makeQueue(
    items: [VocabularyItem],
    progress: [String: ItemProgress],
    packID: StudyPackID = "english3000.v1",
    mode: StudyMode,
    count: Int,
    now: Date
  ) -> [VocabularyItem] {
    let unique = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
    func value(_ item: VocabularyItem) -> ItemProgress {
      progress[CompositeStudyItemID(packID: packID, itemID: .init(rawValue: item.id)).storageKey]
        ?? .initial(.init(packID: packID, itemID: .init(rawValue: item.id)))
    }
    let sorted: [VocabularyItem]
    switch mode {
    case .mistakes:
      sorted = unique.filter { value($0).incorrectCount > 0 }.sorted {
        (value($0).lastAnsweredAt ?? .distantPast) > (value($1).lastAnsweredAt ?? .distantPast)
      }
    case .weakness:
      sorted = unique.filter { value($0).incorrectCount > 0 && value($0).incorrectCount >= value($0).correctCount }.sorted {
        if value($0).incorrectCount != value($1).incorrectCount { return value($0).incorrectCount > value($1).incorrectCount }
        return $0.order < $1.order
      }
    case .newItems:
      sorted = unique.filter { value($0).answerCount == 0 }.sorted { $0.order < $1.order }
    case .review:
      sorted = unique.filter { value($0).dueAt.map { $0 <= now } ?? false }.sorted {
        (value($0).dueAt ?? .distantFuture) < (value($1).dueAt ?? .distantFuture)
      }
    case .practice, .unlock:
      let due = unique.filter { value($0).dueAt.map { $0 <= now } ?? false }.sorted {
        (value($0).dueAt ?? .distantFuture) < (value($1).dueAt ?? .distantFuture)
      }
      let dueIDs = Set(due.map(\.id))
      let newItems = unique.filter { value($0).answerCount == 0 && !dueIDs.contains($0.id) }.sorted { $0.order < $1.order }
      let used = dueIDs.union(newItems.map(\.id))
      let retained = unique.filter { !used.contains($0.id) }.sorted {
        (value($0).lastAnsweredAt ?? .distantPast) < (value($1).lastAnsweredAt ?? .distantPast)
      }
      sorted = due + newItems + retained
    }
    return Array(sorted.prefix(max(0, count)))
  }
}

struct VocabularyFeedbackPlanner: Sendable {
  func plan(wrongAttemptCount: Int) -> StudyFeedbackPlan {
    switch wrongAttemptCount {
    case 0: return .immediate
    case 1: return .relearn6
    case 2: return .relearn12
    default: return .guided20
    }
  }
  func waitSeconds(for plan: StudyFeedbackPlan) -> Int {
    switch plan { case .immediate: return 0; case .relearn6: return 6; case .relearn12: return 12; case .guided20: return 20 }
  }
}

struct VocabularyWeeklyReport: Equatable, Sendable {
  let answers: Int
  let correct: Int
  let learned: Int
  let due: Int
  let streak: Int
  var accuracy: Int { answers == 0 ? 0 : Int((Double(correct) / Double(answers) * 100).rounded()) }
}

struct VocabularyWeeklyReportService: Sendable {
  func make(
    answers: [StudyAnswerRecord],
    progress: [String: ItemProgress],
    packID: StudyPackID,
    now: Date,
    calendar: Calendar = .current
  ) -> VocabularyWeeklyReport {
    let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? .distantPast
    let scoped = answers.filter { $0.experienceID == .vocabulary && $0.answeredAt >= start }
    let learned = progress.values.filter { $0.id.packID == packID && $0.answerCount > 0 }.count
    let due = progress.values.filter { $0.id.packID == packID && ($0.dueAt.map { $0 <= now } ?? false) }.count
    let days = Set(scoped.map { calendar.startOfDay(for: $0.answeredAt) })
    var streak = 0
    for offset in 0..<365 {
      guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)), days.contains(day) else { break }
      streak += 1
    }
    return .init(answers: scoped.count, correct: scoped.filter(\.isCorrect).count, learned: learned, due: due, streak: streak)
  }
}
