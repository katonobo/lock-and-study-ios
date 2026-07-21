import Foundation

enum TakkenQuestionFormat: String, Codable, CaseIterable, Sendable {
  case trueFalse = "true_false"
  case numberChoice = "number_choice"
  case wordingContrast = "wording_contrast"
  case multipleChoice = "multiple_choice"
  case caseStudy = "case_study"

  var displayName: String {
    switch self {
    case .trueFalse: return "○×"
    case .numberChoice: return "数値選択"
    case .wordingContrast: return "文言比較"
    case .multipleChoice: return "4択"
    case .caseStudy: return "事例問題"
    }
  }
}

struct TakkenChoice: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let text: String
  let rationale: String?
  let misconceptionCode: String?
}

struct TakkenPreviewPayload: Codable, Equatable, Sendable {
  let title: String
  let rule: String
  let contrast: String?
  let mnemonic: String?
}

struct TakkenQuestion: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let conceptID: String?
  let variantID: String?
  let examYear: Int?
  let lawBasisDate: String?
  let category: String
  let subCategory: String?
  let difficulty: String
  let format: TakkenQuestionFormat?
  let prompt: String
  let choices: [TakkenChoice]
  let correctIndex: Int
  let correctChoiceID: String
  let explanation: String
  let shortExplanation: String?
  let longExplanation: String?
  let keyPoint: String?
  let preview: TakkenPreviewPayload?
  let minimumReviewSeconds: Int?
  let contrastNote: String?
  let wrongChoiceRationales: [String: String]?
  let distractorReviewStatus: String?
  let sourceNote: String?
  let reviewStatus: String?
  let version: Int?
  let packId: String?
  let tags: [String]
  let unlockEligible: Bool
  let last30DaysEligible: Bool
  let weaknessEligible: Bool
  let estimatedSeconds: Int?
  let importance: String?
  let retired: Bool
  let replacementId: String?
  let updatedAt: String?
  let contentVersion: Int?
  let requiresAnnualReview: Bool
  let requiresAnnualUpdate: Bool
  let volatileReason: String?
  let statisticsYear: Int?
  let dataSourceLabel: String?
  let isPlaceholder: Bool

  var resolvedConceptID: String { conceptID ?? id }
  var resolvedVariantID: String { variantID ?? "legacy" }
  var resolvedFormat: TakkenQuestionFormat {
    format ?? (choices.count == 2 ? .trueFalse : .multipleChoice)
  }
  var resolvedPreview: TakkenPreviewPayload {
    preview ?? .init(
      title: subCategory ?? category,
      rule: keyPoint ?? shortExplanation ?? explanation,
      contrast: contrastNote,
      mnemonic: nil)
  }
  var choiceTexts: [String] { choices.map(\.text) }

  enum CodingKeys: String, CodingKey {
    case id, conceptID, variantID, examYear, lawBasisDate, category, subCategory, difficulty
    case format, prompt, choices, correctIndex, correctChoiceID, explanation, shortExplanation
    case longExplanation, keyPoint, preview, minimumReviewSeconds, contrastNote
    case wrongChoiceRationales, distractorReviewStatus, sourceNote, reviewStatus, version, packId
    case tags, unlockEligible, last30DaysEligible, weaknessEligible, estimatedSeconds, importance
    case retired, replacementId, updatedAt, contentVersion, requiresAnnualReview
    case requiresAnnualUpdate, volatileReason, statisticsYear, dataSourceLabel, isPlaceholder
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    conceptID = try c.decodeIfPresent(String.self, forKey: .conceptID)
    variantID = try c.decodeIfPresent(String.self, forKey: .variantID)
    examYear = try c.decodeIfPresent(Int.self, forKey: .examYear)
    lawBasisDate = try c.decodeIfPresent(String.self, forKey: .lawBasisDate)
    category = try c.decode(String.self, forKey: .category)
    subCategory = try c.decodeIfPresent(String.self, forKey: .subCategory)
    difficulty = try c.decode(String.self, forKey: .difficulty)
    format = try c.decodeIfPresent(TakkenQuestionFormat.self, forKey: .format)
    prompt = try c.decode(String.self, forKey: .prompt)
    let rationaleMap = try c.decodeIfPresent([String: String].self, forKey: .wrongChoiceRationales)
    if let stable = try? c.decode([TakkenChoice].self, forKey: .choices) {
      choices = stable
    } else {
      let legacy = try c.decode([String].self, forKey: .choices)
      choices = legacy.enumerated().map { index, text in
        let choiceID = "choice-\(index)"
        return .init(
          id: choiceID, text: text,
          rationale: rationaleMap?[choiceID] ?? rationaleMap?[text], misconceptionCode: nil)
      }
    }
    correctIndex = try c.decodeIfPresent(Int.self, forKey: .correctIndex) ?? 0
    let decodedCorrectChoiceID = try c.decodeIfPresent(String.self, forKey: .correctChoiceID)
      ?? choices[safe: correctIndex]?.id ?? "choice-0"
    var hasCorrectChoice = false
    for choice in choices where choice.id == decodedCorrectChoiceID { hasCorrectChoice = true }
    guard hasCorrectChoice else {
      throw DecodingError.dataCorruptedError(
        forKey: .correctChoiceID, in: c, debugDescription: "正解choice IDが存在しません")
    }
    correctChoiceID = decodedCorrectChoiceID
    explanation = try c.decode(String.self, forKey: .explanation)
    shortExplanation = try c.decodeIfPresent(String.self, forKey: .shortExplanation)
    longExplanation = try c.decodeIfPresent(String.self, forKey: .longExplanation)
    keyPoint = try c.decodeIfPresent(String.self, forKey: .keyPoint)
    preview = try c.decodeIfPresent(TakkenPreviewPayload.self, forKey: .preview)
    minimumReviewSeconds = try c.decodeIfPresent(Int.self, forKey: .minimumReviewSeconds)
    contrastNote = try c.decodeIfPresent(String.self, forKey: .contrastNote)
    wrongChoiceRationales = rationaleMap
    distractorReviewStatus = try c.decodeIfPresent(String.self, forKey: .distractorReviewStatus)
    sourceNote = try c.decodeIfPresent(String.self, forKey: .sourceNote)
    reviewStatus = try c.decodeIfPresent(String.self, forKey: .reviewStatus)
    version = try c.decodeIfPresent(Int.self, forKey: .version)
    packId = try c.decodeIfPresent(String.self, forKey: .packId)
    tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    unlockEligible = try c.decodeIfPresent(Bool.self, forKey: .unlockEligible) ?? true
    last30DaysEligible = try c.decodeIfPresent(Bool.self, forKey: .last30DaysEligible) ?? false
    weaknessEligible = try c.decodeIfPresent(Bool.self, forKey: .weaknessEligible) ?? true
    estimatedSeconds = try c.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
    importance = try c.decodeIfPresent(String.self, forKey: .importance)
    retired = try c.decodeIfPresent(Bool.self, forKey: .retired) ?? false
    replacementId = try c.decodeIfPresent(String.self, forKey: .replacementId)
    updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    contentVersion = try c.decodeIfPresent(Int.self, forKey: .contentVersion)
    requiresAnnualReview = try c.decodeIfPresent(Bool.self, forKey: .requiresAnnualReview) ?? false
    requiresAnnualUpdate = try c.decodeIfPresent(Bool.self, forKey: .requiresAnnualUpdate) ?? false
    volatileReason = try c.decodeIfPresent(String.self, forKey: .volatileReason)
    statisticsYear = try c.decodeIfPresent(Int.self, forKey: .statisticsYear)
    dataSourceLabel = try c.decodeIfPresent(String.self, forKey: .dataSourceLabel)
    isPlaceholder = try c.decodeIfPresent(Bool.self, forKey: .isPlaceholder) ?? false
  }

  init(
    id: String, conceptID: String? = nil, variantID: String? = nil,
    format: TakkenQuestionFormat, prompt: String, choices: [TakkenChoice],
    correctChoiceID: String, category: String = "宅建業法", subCategory: String? = "テスト",
    difficulty: String = "標準", importance: String? = "中",
    explanation: String = "正しいルールを確認します。", preview: TakkenPreviewPayload? = nil,
    minimumReviewSeconds: Int? = nil, contrastNote: String? = nil
  ) {
    self.id = id
    self.conceptID = conceptID
    self.variantID = variantID
    examYear = 2026
    lawBasisDate = "2026-04-01"
    self.category = category
    self.subCategory = subCategory
    self.difficulty = difficulty
    self.format = format
    self.prompt = prompt
    self.choices = choices
    correctIndex = choices.firstIndex { $0.id == correctChoiceID } ?? 0
    self.correctChoiceID = correctChoiceID
    self.explanation = explanation
    shortExplanation = explanation
    longExplanation = explanation
    keyPoint = preview?.rule
    self.preview = preview
    self.minimumReviewSeconds = minimumReviewSeconds
    self.contrastNote = contrastNote
    wrongChoiceRationales = nil
    distractorReviewStatus = "checked"
    sourceNote = "test-fixture"
    reviewStatus = "checked"
    version = 2
    packId = "takken2026.v1"
    tags = []
    unlockEligible = true
    last30DaysEligible = false
    weaknessEligible = true
    estimatedSeconds = nil
    self.importance = importance
    retired = false
    replacementId = nil
    updatedAt = nil
    contentVersion = 2
    requiresAnnualReview = false
    requiresAnnualUpdate = false
    volatileReason = nil
    statisticsYear = nil
    dataSourceLabel = nil
    isPlaceholder = false
  }
}

struct TakkenStudyModule: StudyModule {
  let moduleType = StudyModuleType.takken

  func loadPrompts(manifest: StudyPackManifest, bundle: Bundle) throws -> [StudyPrompt] {
    try TakkenQuestionRepository(bundle: bundle).load(manifest: manifest).map { item in
      StudyPrompt(
        packID: manifest.id, moduleType: .takken, itemID: .init(rawValue: item.id),
        prompt: item.prompt,
        choices: item.choices.enumerated().map { .init(id: $0.offset, text: $0.element.text) },
        correctChoiceID: item.correctIndex,
        shortExplanation: item.shortExplanation ?? item.explanation,
        longExplanation: item.longExplanation ?? item.explanation,
        sourceNote: item.sourceNote, category: item.category, subcategory: item.subCategory,
        contentVersion: manifest.contentVersion, questionVersion: item.version ?? 1,
        examYear: item.examYear, lawBasisDate: item.lawBasisDate, isFreeSample: true,
        speechText: nil, exampleText: item.keyPoint)
    }
  }

  func validate(manifest: StudyPackManifest, prompts: [StudyPrompt]) -> [String] {
    var issues: [String] = []
    if prompts.count != manifest.expectedItemCount { issues.append("期待件数と一致しません") }
    if Set(prompts.map(\.id)).count != prompts.count { issues.append("問題IDが重複しています") }
    if prompts.contains(where: {
      $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || $0.shortExplanation.isEmpty || !$0.choices.indices.contains($0.correctChoiceID)
    }) { issues.append("問題本文・解説・正解位置が不正です") }
    return issues
  }

  func feedbackPlan(wrongAttemptCount: Int) -> StudyFeedbackPlan {
    wrongAttemptCount == 0 ? .immediate : (wrongAttemptCount == 1 ? .relearn6 : .relearn12)
  }
}

struct TakkenQuestionRepository: Sendable {
  let loader: VerifiedContentLoader
  init(bundle: Bundle = .main) { loader = .init(bundle: bundle) }

  func load(manifest: StudyPackManifest) throws -> [TakkenQuestion] {
    guard !manifest.contentFiles.isEmpty else {
      throw ContentRepositoryError.missing(manifest.title)
    }
    let decoder = JSONDecoder()
    var all: [TakkenQuestion] = []
    for descriptor in manifest.contentFiles {
      let decoded = try decoder.decode([TakkenQuestion].self, from: loader.data(for: descriptor))
      guard decoded.count == descriptor.itemCount else {
        throw ContentRepositoryError.invalid("\(descriptor.path) の件数がmanifestと一致しません")
      }
      all.append(contentsOf: decoded)
    }
    guard Set(all.map(\.id)).count == all.count else {
      throw ContentRepositoryError.invalid("宅建問題IDが重複しています")
    }
    let active = all.filter { !$0.retired }.sorted {
      if $0.category != $1.category { return $0.category < $1.category }
      if ($0.subCategory ?? "") != ($1.subCategory ?? "") {
        return ($0.subCategory ?? "") < ($1.subCategory ?? "")
      }
      return $0.id < $1.id
    }
    guard active.count == manifest.expectedItemCount else {
      throw ContentRepositoryError.invalid("宅建の公開合計件数が\(manifest.expectedItemCount)問ではありません")
    }
    guard !active.contains(where: {
      $0.isPlaceholder
        || !(($0.reviewStatus == "checked") || ($0.reviewStatus == "reviewed")
          || ($0.reviewStatus == "release"))
    }) else {
      throw ContentRepositoryError.invalid("未校閲またはplaceholderの宅建問題が含まれています")
    }
    return active
  }
}
