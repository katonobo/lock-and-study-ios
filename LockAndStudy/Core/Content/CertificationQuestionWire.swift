import Foundation

enum CertificationQuestionFormat: String, Codable, CaseIterable, Sendable {
  case trueFalse = "true_false"
  case numberChoice = "number_choice"
  case wordingContrast = "wording_contrast"
  case multipleChoice = "multiple_choice"
  case caseStudy = "case_study"
}

struct CertificationChoiceWire: Decodable, Equatable, Sendable {
  let id: String
  let text: String
  let rationale: String?
  let misconceptionCode: String?
}

struct CertificationPreviewWire: Decodable, Equatable, Sendable {
  let title: String
  let rule: String
  let contrast: String?
  let mnemonic: String?
}

/// Canonical qualification/case-question wire model shared by staging and runtime loading.
struct CertificationQuestionWire: Decodable, Equatable, Sendable {
  let id: String
  let conceptID: String?
  let variantID: String?
  let examYear: Int?
  let lawBasisDate: String?
  let category: String
  let subCategory: String?
  let difficulty: String
  let format: CertificationQuestionFormat?
  let prompt: String
  let choices: [CertificationChoiceWire]
  let correctIndex: Int
  let correctChoiceID: String
  let explanation: String
  let shortExplanation: String?
  let longExplanation: String?
  let keyPoint: String?
  let preview: CertificationPreviewWire?
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

  fileprivate enum CodingKeys: String, CodingKey {
    case id, conceptID, variantID, examYear, lawBasisDate, category, subCategory, difficulty
    case format, prompt, choices, correctIndex, correctChoiceID, explanation, shortExplanation
    case longExplanation, keyPoint, preview, minimumReviewSeconds, contrastNote
    case wrongChoiceRationales, distractorReviewStatus, sourceNote, reviewStatus, version, packId
    case tags, unlockEligible, last30DaysEligible, weaknessEligible, estimatedSeconds, importance
    case retired, replacementId, updatedAt, contentVersion, requiresAnnualReview
    case requiresAnnualUpdate, volatileReason, statisticsYear, dataSourceLabel, isPlaceholder
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeRequiredNonemptyString(.id)
    conceptID = try container.decodeIfPresent(String.self, forKey: .conceptID)
    variantID = try container.decodeIfPresent(String.self, forKey: .variantID)
    examYear = try container.decodeIfPresent(Int.self, forKey: .examYear)
    lawBasisDate = try container.decodeIfPresent(String.self, forKey: .lawBasisDate)
    category = try container.decodeRequiredNonemptyString(.category)
    subCategory = try container.decodeIfPresent(String.self, forKey: .subCategory)
    difficulty = try container.decodeRequiredNonemptyString(.difficulty)
    format = try container.decodeIfPresent(CertificationQuestionFormat.self, forKey: .format)
    prompt = try container.decodeRequiredNonemptyString(.prompt)

    let rationaleMap = try container.decodeIfPresent(
      [String: String].self, forKey: .wrongChoiceRationales)
    if let objectChoices = try? container.decode(
      [CertificationChoiceWire].self, forKey: .choices)
    {
      choices = objectChoices
    } else {
      let legacyChoices = try container.decode([String].self, forKey: .choices)
      choices = legacyChoices.enumerated().map { index, text in
        let choiceID = "choice-\(index)"
        return .init(
          id: choiceID,
          text: text,
          rationale: rationaleMap?[choiceID] ?? rationaleMap?[text],
          misconceptionCode: nil)
      }
    }
    guard choices.count >= 2 else {
      throw container.invalid(.choices, "choiceは2件以上必要です")
    }
    let choiceIDs = choices.map(\.id)
    guard
      choices.allSatisfy({
        !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }), Set(choiceIDs).count == choiceIDs.count
    else {
      throw container.invalid(.choices, "choice IDまたは本文が空、またはIDが重複しています")
    }

    let suppliedIndex = try container.decodeIfPresent(Int.self, forKey: .correctIndex)
    if let suppliedIndex, !choices.indices.contains(suppliedIndex) {
      throw container.invalid(.correctIndex, "正解indexが範囲外です")
    }
    let suppliedID = try container.decodeIfPresent(String.self, forKey: .correctChoiceID)
    if let suppliedID, !choiceIDs.contains(suppliedID) {
      throw container.invalid(.correctChoiceID, "正解choice IDが存在しません")
    }
    guard suppliedID != nil || suppliedIndex != nil else {
      throw container.invalid(.correctChoiceID, "正解choice IDまたはindexが必要です")
    }
    let indexedID = suppliedIndex.map { choiceIDs[$0] }
    if let suppliedID, let indexedID, suppliedID != indexedID {
      throw container.invalid(.correctChoiceID, "correctChoiceIDとcorrectIndexが一致しません")
    }
    correctChoiceID = suppliedID ?? indexedID!
    correctIndex = choiceIDs.firstIndex(of: correctChoiceID)!
    if rationaleMap?.keys.contains(correctChoiceID) == true
      || choices[correctIndex].rationale != nil
    {
      throw container.invalid(.wrongChoiceRationales, "正解choiceに誤答rationaleを設定できません")
    }

    let suppliedExplanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    shortExplanation = try container.decodeIfPresent(String.self, forKey: .shortExplanation)
    longExplanation = try container.decodeIfPresent(String.self, forKey: .longExplanation)
    guard
      let resolvedExplanation = [suppliedExplanation, shortExplanation, longExplanation]
        .compactMap({ $0 })
        .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else {
      throw container.invalid(.explanation, "説明が必要です")
    }
    explanation = resolvedExplanation

    keyPoint = try container.decodeIfPresent(String.self, forKey: .keyPoint)
    preview = try container.decodeIfPresent(CertificationPreviewWire.self, forKey: .preview)
    minimumReviewSeconds = try container.decodeIfPresent(Int.self, forKey: .minimumReviewSeconds)
    contrastNote = try container.decodeIfPresent(String.self, forKey: .contrastNote)
    wrongChoiceRationales = rationaleMap
    distractorReviewStatus = try container.decodeIfPresent(
      String.self, forKey: .distractorReviewStatus)
    sourceNote = try container.decodeIfPresent(String.self, forKey: .sourceNote)
    reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
    version = try container.decodeIfPresent(Int.self, forKey: .version)
    packId = try container.decodeIfPresent(String.self, forKey: .packId)
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    unlockEligible = try container.decodeIfPresent(Bool.self, forKey: .unlockEligible) ?? true
    last30DaysEligible =
      try container.decodeIfPresent(
        Bool.self, forKey: .last30DaysEligible) ?? false
    weaknessEligible = try container.decodeIfPresent(Bool.self, forKey: .weaknessEligible) ?? true
    estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
    importance = try container.decodeIfPresent(String.self, forKey: .importance)
    retired = try container.decodeIfPresent(Bool.self, forKey: .retired) ?? false
    replacementId = try container.decodeIfPresent(String.self, forKey: .replacementId)
    updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    contentVersion = try container.decodeIfPresent(Int.self, forKey: .contentVersion)
    requiresAnnualReview =
      try container.decodeIfPresent(
        Bool.self, forKey: .requiresAnnualReview) ?? false
    requiresAnnualUpdate =
      try container.decodeIfPresent(
        Bool.self, forKey: .requiresAnnualUpdate) ?? false
    volatileReason = try container.decodeIfPresent(String.self, forKey: .volatileReason)
    statisticsYear = try container.decodeIfPresent(Int.self, forKey: .statisticsYear)
    dataSourceLabel = try container.decodeIfPresent(String.self, forKey: .dataSourceLabel)
    isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder) ?? false
  }
}

struct CertificationQuestionWireDecoder: Sendable {
  func decode(_ data: Data) throws -> [CertificationQuestionWire] {
    let decoder = JSONDecoder()
    let questions: [CertificationQuestionWire]
    if let direct = try? decoder.decode([CertificationQuestionWire].self, from: data) {
      questions = direct
    } else {
      questions = try decoder.decode(LevelDocument.self, from: data).levels.flatMap(\.questions)
    }
    guard Set(questions.map(\.id)).count == questions.count else {
      throw ContentRepositoryError.invalid("資格問題IDが重複しています")
    }
    return questions
  }

  private struct LevelDocument: Decodable {
    let levels: [Level]
  }

  private struct Level: Decodable {
    let questions: [CertificationQuestionWire]
  }
}

/// One source of truth for invariants that only become visible after all question files are joined.
struct CertificationQuestionPackagePolicy: Sendable {
  private let approvedReviewStatuses: Set<String> = ["checked", "reviewed", "release"]

  func descriptors(in manifest: StudyPackManifest) -> [ContentFileDescriptor] {
    let components = manifest.components.filter {
      $0.contentSchemaID == .certificationQuestionsV1
    }
    return components.isEmpty ? manifest.contentFiles : components.flatMap(\.contentFiles)
  }

  func validatedActiveQuestions(
    _ questions: [CertificationQuestionWire],
    manifest: StudyPackManifest,
    packageRoot: URL
  ) throws -> [CertificationQuestionWire] {
    guard Set(questions.map(\.id)).count == questions.count else {
      throw ContentRepositoryError.invalid("資格問題IDが複数ファイル間で重複しています")
    }
    let active = questions.filter { !$0.retired }
    guard active.count == manifest.expectedItemCount else {
      throw ContentRepositoryError.invalid(
        "資格問題の公開合計件数が\(manifest.expectedItemCount)問ではありません")
    }
    guard
      !active.contains(where: {
        $0.isPlaceholder || !approvedReviewStatuses.contains($0.reviewStatus ?? "")
      })
    else {
      throw ContentRepositoryError.invalid("未校閲またはplaceholderの資格問題が含まれています")
    }
    _ = try ContentSampleResolver(packageRoot: packageRoot).sampleIDs(
      manifest: manifest,
      allItemIDs: Set(active.map(\.id)))
    return active
  }
}

extension KeyedDecodingContainer where Key == CertificationQuestionWire.CodingKeys {
  fileprivate func decodeRequiredNonemptyString(_ key: Key) throws -> String {
    let value = try decode(String.self, forKey: key)
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw invalid(key, "\(key.stringValue)が空です")
    }
    return value
  }

  fileprivate func invalid(_ key: Key, _ description: String) -> DecodingError {
    DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: description)
  }
}
