import Foundation

struct StudyPackID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }
}

struct StudyCategoryID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }

  static let english: Self = "language.english"
  static let japanese: Self = "language.japanese"
  static let qualification: Self = "qualification"
}

struct StudySeriesID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }

  static let englishVocabulary: Self = "english.vocabulary"
  static let takken: Self = "qualification.takken"
}

struct ContentSchemaID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral value: String) { rawValue = value }

  static let flashcardItemsV1: Self = "flashcard.items.v1"
  static let certificationQuestionsV1: Self = "certification.questions.v1"
  static let sampleIndexV1: Self = "sample.index.v1"
  static let safeFallbackV1: Self = "safe-fallback.items.v1"
}

struct ContentComponentID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral, Sendable {
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

enum EditionPolicy: String, Codable, Sendable {
  case evergreen, annual, versioned
}

enum PackStoreState: String, Codable, Sendable {
  case upcoming, forSale, archivedOwnedOnly, withdrawn
}

enum ContentDeliveryMode: String, Codable, Sendable {
  case bundled, downloadable
}

enum PassAccessPolicy: String, Codable, Sendable {
  // activeAndArchived remains decode-compatible with early v9 catalogs, but archived access is
  // intentionally disabled. archivedOwnedOnly is always restricted to one-time owners.
  case included, excluded, latestEditionOnly, activeAndArchived

  func permitsAccess(storeState: PackStoreState) -> Bool {
    guard storeState == .forSale else { return false }
    switch self {
    case .included: return true
    case .excluded: return false
    case .latestEditionOnly: return true
    case .activeAndArchived: return true
    }
  }
}

struct StudyCategoryManifest: Codable, Identifiable, Equatable, Sendable {
  let schemaVersion: Int
  let id: StudyCategoryID
  let parentCategoryID: StudyCategoryID?
  let title: String
  let subtitle: String?
  let systemImage: String
  let sortOrder: Int
  let isVisible: Bool
  let availableFrom: Date?
  let themeToken: String?
}

struct StudySeriesManifest: Codable, Identifiable, Equatable, Sendable {
  let schemaVersion: Int
  let id: StudySeriesID
  let categoryID: StudyCategoryID
  let title: String
  let subtitle: String?
  let description: String
  let sortOrder: Int
  let editionPolicy: EditionPolicy
  let defaultExperienceID: StudyExperienceID?
  let isVisible: Bool
}
enum ReleaseStatus: String, Codable, CaseIterable, Sendable {
  case draft, reviewed, release, retired
}

struct ContentFileDescriptor: Codable, Equatable, Sendable {
  let path: String
  let sha256: String
  let itemCount: Int
  let byteCount: Int?

  init(path: String, sha256: String, itemCount: Int, byteCount: Int? = nil) {
    self.path = path
    self.sha256 = sha256
    self.itemCount = itemCount
    self.byteCount = byteCount
  }
}

struct ContentComponentManifest: Codable, Identifiable, Equatable, Sendable {
  let id: ContentComponentID
  let title: String
  let experienceID: StudyExperienceID
  let contentSchemaID: ContentSchemaID
  let sortOrder: Int
  let contentFiles: [ContentFileDescriptor]
  let metadataFile: String?
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

struct FlashcardCourseDefinition: Codable, Equatable, Identifiable, Sendable {
  let code: String
  let title: String
  let subtitle: String?
  let sampleLabel: String?
  var id: String { code }
}

struct FlashcardEmptyStateCopy: Codable, Equatable, Sendable {
  let noDueReview: String
  let noMistakes: String
  let noWeakItems: String
  let noNewItems: String
  let noAvailableItems: String

  static let generic = Self(
    noDueReview: "期限が来た復習はありません。",
    noMistakes: "復習する誤答はまだありません。",
    noWeakItems: "学び直し対象はまだありません。",
    noNewItems: "このコースの新しい項目は一巡しました。期限到来復習を続けられます。",
    noAvailableItems: "利用できる問題がありません。")
}

struct FlashcardPresentationProfile: Codable, Equatable, Sendable {
  let subjectName: String
  let itemSingularName: String
  let itemPluralName: String
  let itemCountUnit: String
  let homeTitle: String
  let firstRunTitle: String
  let firstRunDescription: String
  let startButtonTitle: String
  let searchPlaceholder: String
  let catalogTitle: String
  let frontLabel: String
  let backLabel: String
  let unlockTitle: String
  let supportsSpeech: Bool
  let supportsExamples: Bool
  let supportsReverseDirection: Bool
  var emptyStateCopy: FlashcardEmptyStateCopy? = nil
  let courseDefinitions: [FlashcardCourseDefinition]

  var resolvedEmptyStateCopy: FlashcardEmptyStateCopy {
    emptyStateCopy ?? .generic
  }

  static func generic(for manifest: StudyPackManifest) -> Self {
    .init(
      subjectName: manifest.title, itemSingularName: "項目", itemPluralName: "項目",
      itemCountUnit: "項目", homeTitle: "今日の学習", firstRunTitle: "学習コース",
      firstRunDescription: "最初に学ぶ範囲を選びます。あとから設定で変更できます。",
      startButtonTitle: "学習を始める", searchPlaceholder: "教材を検索",
      catalogTitle: "教材一覧", frontLabel: "問題", backLabel: "答え",
      unlockTitle: "学習して解除", supportsSpeech: false, supportsExamples: false,
      supportsReverseDirection: false, courseDefinitions: [])
  }
}

struct CertificationCategoryDefinition: Codable, Equatable, Identifiable, Sendable {
  let code: String
  let title: String
  var id: String { code }
}

struct CertificationFormatDefinition: Codable, Equatable, Identifiable, Sendable {
  let code: String
  let title: String
  var id: String { code }
}

struct CertificationPresentationProfile: Codable, Equatable, Sendable {
  let subjectName: String
  let homeTitle: String
  let firstRunTitle: String
  let firstRunDescription: String
  let startButtonTitle: String
  let unlockTitle: String
  let freeContentLabel: String
  let categoryDefinitions: [CertificationCategoryDefinition]
  let formatDefinitions: [CertificationFormatDefinition]
  let showsEditionYear: Bool
  let showsLawBasisDate: Bool
  let supportsFinalSprint: Bool

  static func generic(for manifest: StudyPackManifest) -> Self {
    .init(
      subjectName: manifest.title, homeTitle: "今日の学習", firstRunTitle: "学習設定",
      firstRunDescription: "学ぶ分野と問題数を選びます。あとから設定で変更できます。",
      startButtonTitle: "学習を始める", unlockTitle: "問題を解いて解除",
      freeContentLabel: "無料問題", categoryDefinitions: [], formatDefinitions: [],
      showsEditionYear: manifest.editionYear != nil,
      showsLawBasisDate: manifest.qualification?.lawBasisDate != nil,
      supportsFinalSprint: false)
  }
}

struct StudyPresentationProfile: Codable, Equatable, Sendable {
  let flashcard: FlashcardPresentationProfile?
  let certification: CertificationPresentationProfile?
}

struct StudyPackManifest: Codable, Identifiable, Equatable, Sendable {
  static let supportedSchemaVersion = 2
  let schemaVersion: Int
  let id: StudyPackID
  let categoryID: StudyCategoryID
  let seriesID: StudySeriesID
  let experienceID: StudyExperienceID
  let editionID: String
  let editionYear: Int?
  let editionPolicy: EditionPolicy
  let storeState: PackStoreState
  let deliveryMode: ContentDeliveryMode
  let passAccessPolicy: PassAccessPolicy
  let components: [ContentComponentManifest]

  // Transitional v1 fields remain readable while presentation adapters are migrated.
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
  let progressMigrationSHA256: String?
  let presentation: StudyPresentationProfile?

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, categoryID, seriesID, experienceID, editionID, editionYear
    case editionPolicy, storeState, deliveryMode, passAccessPolicy, components
    case moduleType, experienceType, title, subtitle, description, contentVersion
    case minimumAppVersion, releaseStatus, isEnabled, sortOrder, expectedItemCount
    case conceptCount, variantCount, sampleDefinition, oneTimeProductID, passEligible
    case saleReady, contentFiles, metadataFile, creditsFile, availableFrom, retiredAt
    case supersedesPackID, locale, qualification, progressMigrationFile, progressMigrationSHA256
    case presentation
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    id = try container.decode(StudyPackID.self, forKey: .id)

    let decodedModule = try container.decodeIfPresent(StudyModuleType.self, forKey: .moduleType)
    let legacyExperience = try container.decodeIfPresent(
      StudyExperienceType.self, forKey: .experienceType)
    let explicitExperience = try container.decodeIfPresent(
      StudyExperienceID.self, forKey: .experienceID)
    experienceID = Self.normalizedExperienceID(
      explicitExperience?.rawValue ?? legacyExperience?.rawValue ?? decodedModule?.rawValue ?? "")
    moduleType = decodedModule ?? Self.moduleType(for: experienceID)
    experienceType = legacyExperience ?? Self.legacyExperienceType(for: experienceID)

    categoryID = try container.decodeIfPresent(StudyCategoryID.self, forKey: .categoryID)
      ?? Self.defaultCategoryID(for: moduleType)
    seriesID = try container.decodeIfPresent(StudySeriesID.self, forKey: .seriesID)
      ?? Self.defaultSeriesID(for: moduleType, packID: id)
    editionID = try container.decodeIfPresent(String.self, forKey: .editionID)
      ?? id.rawValue
    editionYear = try container.decodeIfPresent(Int.self, forKey: .editionYear)
      ?? (try container.decodeIfPresent(QualificationMetadata.self, forKey: .qualification))?.examYear
    editionPolicy = try container.decodeIfPresent(EditionPolicy.self, forKey: .editionPolicy)
      ?? (editionYear == nil ? .evergreen : .annual)

    title = try container.decode(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    contentVersion = try container.decode(String.self, forKey: .contentVersion)
    minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
      ?? "1.0"
    releaseStatus = try container.decodeIfPresent(ReleaseStatus.self, forKey: .releaseStatus)
      ?? .release
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    expectedItemCount = try container.decodeIfPresent(Int.self, forKey: .expectedItemCount) ?? 0
    conceptCount = try container.decodeIfPresent(Int.self, forKey: .conceptCount)
    variantCount = try container.decodeIfPresent(Int.self, forKey: .variantCount)
    sampleDefinition = try container.decodeIfPresent(SampleDefinition.self, forKey: .sampleDefinition)
      ?? .init(kind: "none", count: 0, catalogFile: nil)
    oneTimeProductID = try container.decodeIfPresent(String.self, forKey: .oneTimeProductID)
    passEligible = try container.decodeIfPresent(Bool.self, forKey: .passEligible)
      ?? ((try container.decodeIfPresent(PassAccessPolicy.self, forKey: .passAccessPolicy)) != .excluded)
    saleReady = try container.decodeIfPresent(Bool.self, forKey: .saleReady) ?? false
    let legacyFiles = try container.decodeIfPresent(
      [ContentFileDescriptor].self, forKey: .contentFiles) ?? []
    metadataFile = try container.decodeIfPresent(String.self, forKey: .metadataFile)
    creditsFile = try container.decodeIfPresent(String.self, forKey: .creditsFile)
    availableFrom = try container.decodeIfPresent(Date.self, forKey: .availableFrom)
    retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
    supersedesPackID = try container.decodeIfPresent(StudyPackID.self, forKey: .supersedesPackID)
    locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? "ja-JP"
    qualification = try container.decodeIfPresent(QualificationMetadata.self, forKey: .qualification)
    progressMigrationFile = try container.decodeIfPresent(String.self, forKey: .progressMigrationFile)
    progressMigrationSHA256 = try container.decodeIfPresent(
      String.self, forKey: .progressMigrationSHA256)
    presentation = try container.decodeIfPresent(
      StudyPresentationProfile.self, forKey: .presentation)

    storeState = try container.decodeIfPresent(PackStoreState.self, forKey: .storeState)
      ?? Self.legacyStoreState(releaseStatus: releaseStatus, retiredAt: retiredAt)
    deliveryMode = try container.decodeIfPresent(ContentDeliveryMode.self, forKey: .deliveryMode)
      ?? .bundled
    passAccessPolicy = try container.decodeIfPresent(PassAccessPolicy.self, forKey: .passAccessPolicy)
      ?? (passEligible ? .included : .excluded)

    let decodedComponents = try container.decodeIfPresent(
      [ContentComponentManifest].self, forKey: .components) ?? []
    if decodedComponents.isEmpty {
      components = [
        .init(
          id: "primary",
          title: title,
          experienceID: experienceID,
          contentSchemaID: Self.contentSchemaID(for: moduleType),
          sortOrder: 0,
          contentFiles: legacyFiles,
          metadataFile: metadataFile)
      ]
    } else {
      components = decodedComponents
    }
    contentFiles = legacyFiles.isEmpty ? components.flatMap(\.contentFiles) : legacyFiles
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(id, forKey: .id)
    try container.encode(categoryID, forKey: .categoryID)
    try container.encode(seriesID, forKey: .seriesID)
    try container.encode(experienceID, forKey: .experienceID)
    try container.encode(editionID, forKey: .editionID)
    try container.encodeIfPresent(editionYear, forKey: .editionYear)
    try container.encode(editionPolicy, forKey: .editionPolicy)
    try container.encode(storeState, forKey: .storeState)
    try container.encode(deliveryMode, forKey: .deliveryMode)
    try container.encode(passAccessPolicy, forKey: .passAccessPolicy)
    try container.encode(components, forKey: .components)
    try container.encode(moduleType, forKey: .moduleType)
    try container.encode(experienceType, forKey: .experienceType)
    try container.encode(title, forKey: .title)
    try container.encode(subtitle, forKey: .subtitle)
    try container.encode(description, forKey: .description)
    try container.encode(contentVersion, forKey: .contentVersion)
    try container.encode(minimumAppVersion, forKey: .minimumAppVersion)
    try container.encode(releaseStatus, forKey: .releaseStatus)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(sortOrder, forKey: .sortOrder)
    try container.encode(expectedItemCount, forKey: .expectedItemCount)
    try container.encodeIfPresent(conceptCount, forKey: .conceptCount)
    try container.encodeIfPresent(variantCount, forKey: .variantCount)
    try container.encode(sampleDefinition, forKey: .sampleDefinition)
    try container.encodeIfPresent(oneTimeProductID, forKey: .oneTimeProductID)
    try container.encode(passEligible, forKey: .passEligible)
    try container.encode(saleReady, forKey: .saleReady)
    try container.encode(contentFiles, forKey: .contentFiles)
    try container.encodeIfPresent(metadataFile, forKey: .metadataFile)
    try container.encodeIfPresent(creditsFile, forKey: .creditsFile)
    try container.encodeIfPresent(availableFrom, forKey: .availableFrom)
    try container.encodeIfPresent(retiredAt, forKey: .retiredAt)
    try container.encodeIfPresent(supersedesPackID, forKey: .supersedesPackID)
    try container.encode(locale, forKey: .locale)
    try container.encodeIfPresent(qualification, forKey: .qualification)
    try container.encodeIfPresent(progressMigrationFile, forKey: .progressMigrationFile)
    try container.encodeIfPresent(progressMigrationSHA256, forKey: .progressMigrationSHA256)
    try container.encodeIfPresent(presentation, forKey: .presentation)
  }

  private static func normalizedExperienceID(_ value: String) -> StudyExperienceID {
    switch value {
    case "vocabulary", "vocabulary.v1": return .init(rawValue: "flashcard.v1")
    case "takken", "certification.takken.v1": return .init(rawValue: "certification.v1")
    case "safe-fallback": return .init(rawValue: "safe-fallback.v1")
    default: return .init(rawValue: value)
    }
  }

  private static func legacyExperienceType(for id: StudyExperienceID) -> StudyExperienceType {
    switch id.rawValue {
    case "flashcard.v1": return .vocabularyV1
    case "certification.v1": return .takkenV1
    default: return .init(rawValue: id.rawValue)
    }
  }

  private static func moduleType(for id: StudyExperienceID) -> StudyModuleType {
    switch id.rawValue {
    case "flashcard.v1": return .vocabulary
    case "certification.v1": return .takken
    default: return .init(rawValue: id.rawValue)
    }
  }

  private static func defaultCategoryID(for module: StudyModuleType) -> StudyCategoryID {
    switch module {
    case .vocabulary: return .english
    case .takken: return .qualification
    default: return .init(rawValue: "uncategorized")
    }
  }

  private static func defaultSeriesID(
    for module: StudyModuleType, packID: StudyPackID
  ) -> StudySeriesID {
    switch module {
    case .vocabulary: return .englishVocabulary
    case .takken: return .takken
    default: return .init(rawValue: "uncategorized.\(packID.rawValue)")
    }
  }

  private static func contentSchemaID(for module: StudyModuleType) -> ContentSchemaID {
    switch module {
    case .vocabulary: return .flashcardItemsV1
    case .takken: return .certificationQuestionsV1
    default: return .init(rawValue: module.rawValue)
    }
  }

  private static func legacyStoreState(
    releaseStatus: ReleaseStatus, retiredAt: Date?
  ) -> PackStoreState {
    if releaseStatus == .retired || retiredAt != nil { return .archivedOwnedOnly }
    if releaseStatus == .release { return .forSale }
    return .upcoming
  }
}

extension StudyPackManifest {
  var flashcardPresentation: FlashcardPresentationProfile {
    presentation?.flashcard ?? .generic(for: self)
  }

  var certificationPresentation: CertificationPresentationProfile {
    presentation?.certification ?? .generic(for: self)
  }

  var publishedCountLabel: String {
    if experienceID.normalizedTemplateID == .flashcardV1 {
      return "\(expectedItemCount)\(flashcardPresentation.itemCountUnit)"
    }
    if experienceID.normalizedTemplateID == .certificationV1 {
      guard let conceptCount else { return "\(expectedItemCount)問" }
      if let variantCount, variantCount != conceptCount {
        return "\(conceptCount)論点・\(variantCount)問"
      }
      return "\(conceptCount)論点"
    }
    return "\(expectedItemCount)項目"
  }

  var publishedStructureDescription: String {
    guard experienceID.normalizedTemplateID == .certificationV1, let conceptCount else {
      return publishedCountLabel
    }
    return "\(certificationPresentation.subjectName) \(conceptCount)論点・校閲済み\(variantCount ?? expectedItemCount)問"
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
    if manifest.storeState == .archivedOwnedOnly
      || manifest.releaseStatus == .retired
      || manifest.retiredAt.map({ $0 <= now }) == true
    {
      return isOwned ? .retiredOwned : .retiredUnavailable
    }
    if manifest.storeState == .withdrawn {
      return .invalid("この教材は現在利用できません")
    }
    if manifest.storeState == .upcoming {
      return manifest.availableFrom.map(PackAvailability.comingSoon)
        ?? .invalid("この教材は公開準備中です")
    }
    guard manifest.releaseStatus == .release, manifest.isEnabled else {
      return .invalid("この教材は現在利用できません")
    }
    return manifest.storeState == .forSale && manifest.saleReady ? .available : .notForSale
  }

  private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: .numeric)
  }
}

enum ProgressCompatibilityPolicy: String, Codable, Sendable {
  case preserve
  case resetChangedItems
  case migrate
}

typealias ProgressCompatibility = ProgressCompatibilityPolicy

struct ItemProgressMigration: Codable, Equatable, Sendable {
  let oldItemID: StudyItemID
  let newItemID: StudyItemID
  let policy: ProgressCompatibilityPolicy
}

struct ProgressMigrationDocument: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1
  let schemaVersion: Int
  let packID: StudyPackID?
  let fromContentVersion: String
  let toContentVersion: String
  let defaultPolicy: ProgressCompatibilityPolicy
  let itemMigrations: [ItemProgressMigration]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, packID, fromContentVersion, toContentVersion, defaultPolicy, itemMigrations
  }

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    packID: StudyPackID? = nil,
    fromContentVersion: String,
    toContentVersion: String,
    defaultPolicy: ProgressCompatibilityPolicy = .preserve,
    itemMigrations: [ItemProgressMigration]
  ) {
    self.schemaVersion = schemaVersion
    self.packID = packID
    self.fromContentVersion = fromContentVersion
    self.toContentVersion = toContentVersion
    self.defaultPolicy = defaultPolicy
    self.itemMigrations = itemMigrations
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    packID = try container.decodeIfPresent(StudyPackID.self, forKey: .packID)
    fromContentVersion = try container.decode(String.self, forKey: .fromContentVersion)
    toContentVersion = try container.decode(String.self, forKey: .toContentVersion)
    defaultPolicy = try container.decodeIfPresent(
      ProgressCompatibilityPolicy.self, forKey: .defaultPolicy) ?? .preserve
    itemMigrations = try container.decodeIfPresent(
      [ItemProgressMigration].self, forKey: .itemMigrations) ?? []
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
