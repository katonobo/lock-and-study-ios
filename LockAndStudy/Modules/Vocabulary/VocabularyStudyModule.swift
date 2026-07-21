import Foundation

private struct VocabularyMetadataDTO: Decodable { let contentVersion: String }
private struct VocabularyDTO: Decodable {
  let id: String
  let levelCode: String
  let displayWord: String
  let quizMeaningJa: String
  let options: [String]
  let correctIndex: Int
  let explanationJa: String
  let exampleEn: String
  let exampleJa: String
  let speechText: String
  let metadata: VocabularyMetadataDTO
}
private struct FreeSampleCatalogDTO: Decodable {
  struct Level: Decodable { struct Question: Decodable { let id: String }; let questions: [Question] }
  let levels: [Level]
  var ids: Set<String> { Set(levels.flatMap { $0.questions.map(\.id) }) }
}

struct VocabularyStudyModule: StudyModule {
  let moduleType = StudyModuleType.vocabulary
  func loadPrompts(manifest: StudyPackManifest, bundle: Bundle) throws -> [StudyPrompt] {
    guard let file = manifest.contentFiles.first,
          let contentURL = resourceURL(file.path, bundle: bundle),
          let sampleFile = manifest.sampleDefinition.catalogFile,
          let sampleURL = resourceURL(sampleFile, bundle: bundle) else { throw ContentRepositoryError.missing(manifest.title) }
    let decoder = JSONDecoder()
    let items = try decoder.decode([VocabularyDTO].self, from: Data(contentsOf: contentURL))
    let sampleIDs = try decoder.decode(FreeSampleCatalogDTO.self, from: Data(contentsOf: sampleURL)).ids
    return items.map { item in
      StudyPrompt(packID: manifest.id, moduleType: .vocabulary, itemID: .init(rawValue: item.id), prompt: item.displayWord,
                  choices: item.options.enumerated().map { .init(id: $0.offset, text: $0.element) }, correctChoiceID: item.correctIndex,
                  shortExplanation: item.explanationJa, longExplanation: "\(item.explanationJa)\n\(item.exampleEn)\n\(item.exampleJa)",
                  sourceNote: nil, category: item.levelCode, subcategory: nil, contentVersion: item.metadata.contentVersion,
                  questionVersion: 1, examYear: nil, lawBasisDate: nil, isFreeSample: sampleIDs.contains(item.id),
                  speechText: item.speechText, exampleText: "\(item.exampleEn)\n\(item.exampleJa)")
    }
  }
  func validate(manifest: StudyPackManifest, prompts: [StudyPrompt]) -> [String] {
    var issues: [String] = []
    if prompts.count != manifest.expectedItemCount { issues.append("期待件数\(manifest.expectedItemCount)に対して\(prompts.count)件") }
    if prompts.filter(\.isFreeSample).count != 250 { issues.append("無料英単語が250件ではありません") }
    if Set(prompts.map(\.id)).count != prompts.count { issues.append("問題IDが重複しています") }
    if prompts.contains(where: { $0.choices.count != 4 || !$0.choices.indices.contains($0.correctChoiceID) }) { issues.append("選択肢が不正です") }
    return issues
  }
  func feedbackPlan(wrongAttemptCount: Int) -> StudyFeedbackPlan {
    switch wrongAttemptCount { case 0: return .immediate; case 1: return .relearn6; case 2: return .relearn12; default: return .guided20 }
  }
  private func resourceURL(_ path: String, bundle: Bundle) -> URL? {
    let url = URL(fileURLWithPath: path)
    return bundle.url(forResource: url.deletingPathExtension().lastPathComponent, withExtension: url.pathExtension)
  }
}

