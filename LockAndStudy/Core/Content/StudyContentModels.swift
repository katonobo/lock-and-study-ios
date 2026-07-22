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

struct StudyModuleType: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let vocabulary = Self(rawValue: "vocabulary")
  static let takken = Self(rawValue: "takken")
}

struct StudyExperienceType: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let vocabularyV1 = Self(rawValue: "vocabulary.v1")
  static let takkenV1 = Self(rawValue: "certification.takken.v1")
}
enum ReleaseStatus: String, Codable, CaseIterable, Sendable {
  case draft, reviewed, release, retired
}

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
  static let supportedSchemaVersion = 1
  let schemaVersion: Int
  let id: StudyPackID
  let moduleType: StudyModuleType
  let experienceType: StudyExperienceType
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
  let progressMigrationFile: String?
}

extension StudyPackManifest {
  var publishedCountLabel: String {
    if moduleType == .vocabulary { return "\(expectedItemCount)語" }
    if moduleType == .takken {
      guard let conceptCount else { return "\(expectedItemCount)問" }
      if let variantCount, variantCount != conceptCount {
        return "\(conceptCount)論点・\(variantCount)問"
      }
      return "\(conceptCount)論点"
    }
    return "\(expectedItemCount)項目"
  }

  var publishedStructureDescription: String {
    guard moduleType == .takken, let conceptCount else { return publishedCountLabel }
    return "宅建業法\(conceptCount)論点・校閲済み\(variantCount ?? expectedItemCount)問"
  }
}

enum PackAvailability: Equatable, Sendable {
  case available
  case comingSoon(Date)
  case updateAppRequired
  case retiredOwned
  case retiredUnavailable
  case notForSale
  case invalid(String)

  var canOpen: Bool {
    switch self {
    case .available, .retiredOwned, .notForSale: return true
    default: return false
    }
  }

  var message: String {
    switch self {
    case .available: return "利用できます"
    case .comingSoon: return "公開前です"
    case .updateAppRequired: return "この教材を使うにはアプリの更新が必要です"
    case .retiredOwned: return "販売終了・購入済み"
    case .retiredUnavailable: return "販売を終了しました"
    case .notForSale: return "無料範囲を利用できます・現在は販売していません"
    case .invalid(let reason): return reason
    }
  }
}

struct PackAvailabilityResolver: Sendable {
  func resolve(
    manifest: StudyPackManifest,
    appVersion: String,
    now: Date,
    isOwned: Bool,
    supportsExperience: Bool
  ) -> PackAvailability {
    guard manifest.schemaVersion <= StudyPackManifest.supportedSchemaVersion else {
      return .updateAppRequired
    }
    guard supportsExperience else { return .updateAppRequired }
    if compareVersions(appVersion, manifest.minimumAppVersion) == .orderedAscending {
      return .updateAppRequired
    }
    if let availableFrom = manifest.availableFrom, availableFrom > now {
      return .comingSoon(availableFrom)
    }
    if manifest.releaseStatus == .retired
      || manifest.retiredAt.map({ $0 <= now }) == true
    {
      return isOwned ? .retiredOwned : .retiredUnavailable
    }
    guard manifest.releaseStatus == .release, manifest.isEnabled else {
      return .invalid("この教材は現在利用できません")
    }
    return manifest.saleReady ? .available : .notForSale
  }

  private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: .numeric)
  }
}

enum ProgressCompatibility: String, Codable, Sendable {
  case preserve
  case resetItem
  case migrate
}

struct ItemProgressMigration: Codable, Equatable, Sendable {
  let oldItemID: StudyItemID
  let newItemID: StudyItemID
  let policy: ProgressCompatibility
}

struct ProgressMigrationDocument: Codable, Equatable, Sendable {
  let fromContentVersion: String
  let toContentVersion: String
  let itemMigrations: [ItemProgressMigration]
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

enum StudyMode: String, Codable, CaseIterable, Sendable {
  case practice, unlock, review, mistakes, weakness, newItems
}
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
  func loadPrompts(manifest: StudyPackManifest, packageRoot: URL) throws -> [StudyPrompt]
  func validate(manifest: StudyPackManifest, prompts: [StudyPrompt]) -> [String]
  func feedbackPlan(wrongAttemptCount: Int) -> StudyFeedbackPlan
}

struct StudyModuleRegistry: Sendable {
  private let modules: [StudyModuleType: any StudyModule]
  init(modules: [any StudyModule]) {
    self.modules = Dictionary(uniqueKeysWithValues: modules.map { ($0.moduleType, $0) })
  }
  func module(for type: StudyModuleType) -> (any StudyModule)? { modules[type] }
  static let standard = StudyModuleRegistry(modules: [VocabularyStudyModule(), TakkenStudyModule()])
}
