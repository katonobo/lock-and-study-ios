import Foundation

struct StudyPackID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }
}

struct StudyItemID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }
}

struct CompositeStudyItemID: Codable, Hashable, Sendable {
  let packID: StudyPackID
  let itemID: StudyItemID
  var storageKey: String { "\(packID.rawValue)::\(itemID.rawValue)" }
}

enum StudyModuleType: String, Codable, CaseIterable, Sendable { case vocabulary, takken }
enum ReleaseStatus: String, Codable, CaseIterable, Sendable { case draft, reviewed, release, retired }

struct ContentFileDescriptor: Codable, Equatable, Sendable {
  let path: String
  let sha256: String
  let itemCount: Int
}

struct SampleDefinition: Codable, Equatable, Sendable {
  let kind: String
  let count: Int
  let catalogFile: String?
}

struct QualificationMetadata: Codable, Equatable, Sendable {
  let examYear: Int?
  let lawBasisDate: String?
  let requiresAnnualReview: Bool
  let statisticsYear: Int?
}

struct StudyPackManifest: Codable, Identifiable, Equatable, Sendable {
  let schemaVersion: Int
  let id: StudyPackID
  let moduleType: StudyModuleType
  let title: String
  let subtitle: String
  let description: String
  let contentVersion: String
  let minimumAppVersion: String
  let releaseStatus: ReleaseStatus
  let isEnabled: Bool
  let sortOrder: Int
  let expectedItemCount: Int
  let conceptCount: Int?
  let variantCount: Int?
  let sampleDefinition: SampleDefinition
  let oneTimeProductID: String?
  let passEligible: Bool
  let saleReady: Bool
  let contentFiles: [ContentFileDescriptor]
  let metadataFile: String?
  let creditsFile: String?
  let availableFrom: Date?
  let retiredAt: Date?
  let supersedesPackID: StudyPackID?
  let locale: String
  let qualification: QualificationMetadata?
}

extension StudyPackManifest {
  var publishedCountLabel: String {
    switch moduleType {
    case .vocabulary: return "\(expectedItemCount)語"
    case .takken:
      guard let conceptCount else { return "\(expectedItemCount)問" }
      if let variantCount, variantCount != conceptCount {
        return "\(conceptCount)論点・\(variantCount)問"
      }
      return "\(conceptCount)論点"
    }
  }

  var publishedStructureDescription: String {
    guard moduleType == .takken, let conceptCount else { return publishedCountLabel }
    return "宅建業法\(conceptCount)論点・校閲済み\(variantCount ?? expectedItemCount)問"
  }
}

struct StudyChoice: Codable, Identifiable, Equatable, Sendable {
  let id: Int
  let text: String
}

struct StudyPrompt: Codable, Identifiable, Equatable, Sendable {
  var id: CompositeStudyItemID { .init(packID: packID, itemID: itemID) }
  let packID: StudyPackID
  let moduleType: StudyModuleType
  let itemID: StudyItemID
  let prompt: String
  let choices: [StudyChoice]
  let correctChoiceID: Int
  let shortExplanation: String
  let longExplanation: String
  let sourceNote: String?
  let category: String
  let subcategory: String?
  let contentVersion: String
  let questionVersion: Int
  let examYear: Int?
  let lawBasisDate: String?
  let isFreeSample: Bool
  let speechText: String?
  let exampleText: String?
}

enum StudyMode: String, Codable, CaseIterable, Sendable { case practice, unlock, review, mistakes, weakness, newItems }
enum StudyFeedbackPlan: String, Codable, Sendable { case immediate, relearn6, relearn12, guided20 }

struct StudyProgressSummary: Codable, Equatable, Sendable {
  let packID: StudyPackID
  let answeredCount: Int
  let correctCount: Int
  let uniqueItemCount: Int
  var accuracy: Double { answeredCount == 0 ? 0 : Double(correctCount) / Double(answeredCount) }
}

protocol StudyModule: Sendable {
  var moduleType: StudyModuleType { get }
  func loadPrompts(manifest: StudyPackManifest, bundle: Bundle) throws -> [StudyPrompt]
  func validate(manifest: StudyPackManifest, prompts: [StudyPrompt]) -> [String]
  func feedbackPlan(wrongAttemptCount: Int) -> StudyFeedbackPlan
}

struct StudyModuleRegistry: Sendable {
  private let modules: [StudyModuleType: any StudyModule]
  init(modules: [any StudyModule]) { self.modules = Dictionary(uniqueKeysWithValues: modules.map { ($0.moduleType, $0) }) }
  func module(for type: StudyModuleType) -> (any StudyModule)? { modules[type] }
  static let standard = StudyModuleRegistry(modules: [VocabularyStudyModule(), TakkenStudyModule()])
}
