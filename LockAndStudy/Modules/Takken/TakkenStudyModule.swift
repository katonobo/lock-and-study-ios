import Foundation

typealias TakkenQuestionFormat = CertificationQuestionFormat

extension CertificationQuestionFormat {
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

  init(id: String, text: String, rationale: String?, misconceptionCode: String?) {
    self.id = id
    self.text = text
    self.rationale = rationale
    self.misconceptionCode = misconceptionCode
  }

  init(wire: CertificationChoiceWire) {
    id = wire.id
    text = wire.text
    rationale = wire.rationale
    misconceptionCode = wire.misconceptionCode
  }
}

struct TakkenPreviewPayload: Codable, Equatable, Sendable {
  let title: String
  let rule: String
  let contrast: String?
  let mnemonic: String?

  init(title: String, rule: String, contrast: String?, mnemonic: String?) {
    self.title = title
    self.rule = rule
    self.contrast = contrast
    self.mnemonic = mnemonic
  }

  init(wire: CertificationPreviewWire) {
    title = wire.title
    rule = wire.rule
    contrast = wire.contrast
    mnemonic = wire.mnemonic
  }
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
    preview
      ?? .init(
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
    self.init(wire: try CertificationQuestionWire(from: decoder))
  }

  init(wire: CertificationQuestionWire) {
    id = wire.id
    conceptID = wire.conceptID
    variantID = wire.variantID
    examYear = wire.examYear
    lawBasisDate = wire.lawBasisDate
    category = wire.category
    subCategory = wire.subCategory
    difficulty = wire.difficulty
    format = wire.format
    prompt = wire.prompt
    choices = wire.choices.map(TakkenChoice.init(wire:))
    correctIndex = wire.correctIndex
    correctChoiceID = wire.correctChoiceID
    explanation = wire.explanation
    shortExplanation = wire.shortExplanation
    longExplanation = wire.longExplanation
    keyPoint = wire.keyPoint
    preview = wire.preview.map(TakkenPreviewPayload.init(wire:))
    minimumReviewSeconds = wire.minimumReviewSeconds
    contrastNote = wire.contrastNote
    wrongChoiceRationales = wire.wrongChoiceRationales
    distractorReviewStatus = wire.distractorReviewStatus
    sourceNote = wire.sourceNote
    reviewStatus = wire.reviewStatus
    version = wire.version
    packId = wire.packId
    tags = wire.tags
    unlockEligible = wire.unlockEligible
    last30DaysEligible = wire.last30DaysEligible
    weaknessEligible = wire.weaknessEligible
    estimatedSeconds = wire.estimatedSeconds
    importance = wire.importance
    retired = wire.retired
    replacementId = wire.replacementId
    updatedAt = wire.updatedAt
    contentVersion = wire.contentVersion
    requiresAnnualReview = wire.requiresAnnualReview
    requiresAnnualUpdate = wire.requiresAnnualUpdate
    volatileReason = wire.volatileReason
    statisticsYear = wire.statisticsYear
    dataSourceLabel = wire.dataSourceLabel
    isPlaceholder = wire.isPlaceholder
  }

  init(
    id: String, conceptID: String? = nil, variantID: String? = nil,
    format: TakkenQuestionFormat, prompt: String, choices: [TakkenChoice],
    correctChoiceID: String, category: String = "宅建業法", subCategory: String? = "テスト",
    difficulty: String = "標準", importance: String? = "中",
    explanation: String = "正しいルールを確認します。", preview: TakkenPreviewPayload? = nil,
    minimumReviewSeconds: Int? = nil, contrastNote: String? = nil,
    unlockEligible: Bool = true, estimatedSeconds: Int? = nil
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
    let resolvedCorrectIndex = choices.firstIndex { $0.id == correctChoiceID }
    precondition(resolvedCorrectIndex != nil, "correctChoiceID must exist")
    correctIndex = resolvedCorrectIndex!
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
    self.unlockEligible = unlockEligible
    last30DaysEligible = false
    weaknessEligible = true
    self.estimatedSeconds = estimatedSeconds
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

  func loadPrompts(manifest: StudyPackManifest, packageRoot: URL) throws -> [StudyPrompt] {
    let questions = try TakkenQuestionRepository(packageRoot: packageRoot).load(manifest: manifest)
    let sampleIDs = try ContentSampleResolver(packageRoot: packageRoot).sampleIDs(
      manifest: manifest,
      allItemIDs: Set(questions.map(\.id)))
    return questions.map { item in
      StudyPrompt(
        packID: manifest.id, moduleType: .takken, itemID: .init(rawValue: item.id),
        prompt: item.prompt,
        choices: item.choices.enumerated().map { .init(id: $0.offset, text: $0.element.text) },
        correctChoiceID: item.correctIndex,
        shortExplanation: item.shortExplanation ?? item.explanation,
        longExplanation: item.longExplanation ?? item.explanation,
        sourceNote: item.sourceNote, category: item.category, subcategory: item.subCategory,
        contentVersion: manifest.contentVersion, questionVersion: item.version ?? 1,
        examYear: item.examYear, lawBasisDate: item.lawBasisDate,
        isFreeSample: sampleIDs.contains(item.id),
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
    }) {
      issues.append("問題本文・解説・正解位置が不正です")
    }
    return issues
  }

  func feedbackPlan(wrongAttemptCount: Int) -> StudyFeedbackPlan {
    wrongAttemptCount == 0 ? .immediate : (wrongAttemptCount == 1 ? .relearn6 : .relearn12)
  }
}

struct TakkenQuestionRepository: Sendable {
  let loader: VerifiedContentLoader
  init(packageRoot: URL) { loader = .init(packageRoot: packageRoot) }

  func load(manifest: StudyPackManifest) throws -> [TakkenQuestion] {
    let policy = CertificationQuestionPackagePolicy()
    let descriptors = policy.descriptors(in: manifest)
    guard !descriptors.isEmpty else {
      throw ContentRepositoryError.missing(manifest.title)
    }
    let decoder = CertificationQuestionWireDecoder()
    var all: [CertificationQuestionWire] = []
    for descriptor in descriptors {
      let decoded = try decoder.decode(loader.data(for: descriptor))
      guard decoded.count == descriptor.itemCount else {
        throw ContentRepositoryError.invalid("\(descriptor.path) の件数がmanifestと一致しません")
      }
      all.append(contentsOf: decoded)
    }
    let active = try policy.validatedActiveQuestions(
      all,
      manifest: manifest,
      packageRoot: loader.packageRoot
    )
    .map(TakkenQuestion.init(wire:))
    .sorted {
      if $0.category != $1.category { return $0.category < $1.category }
      if ($0.subCategory ?? "") != ($1.subCategory ?? "") {
        return ($0.subCategory ?? "") < ($1.subCategory ?? "")
      }
      return $0.id < $1.id
    }
    return active
  }
}
