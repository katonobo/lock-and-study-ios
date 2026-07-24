import Foundation

protocol ContentFileValidating: Sendable {
  var schemaID: ContentSchemaID { get }
  func validate(
    data: Data,
    descriptor: ContentFileDescriptor,
    packageRoot: URL
  ) throws
}

struct ValidatedContentFile: Sendable {
  let descriptor: ContentFileDescriptor
  let data: Data
}

/// Runs after every file has passed its schema validator so cross-file invariants fail at stage time.
protocol ContentSchemaPackageValidating: Sendable {
  var schemaID: ContentSchemaID { get }
  func validate(
    manifest: StudyPackManifest,
    files: [ValidatedContentFile],
    packageRoot: URL
  ) throws
}

struct ContentFileValidatorRegistry: Sendable {
  private let validators: [ContentSchemaID: any ContentFileValidating]
  private let packageValidators: [ContentSchemaID: any ContentSchemaPackageValidating]

  init(
    validators: [any ContentFileValidating],
    packageValidators: [any ContentSchemaPackageValidating] = []
  ) {
    self.validators = Dictionary(uniqueKeysWithValues: validators.map { ($0.schemaID, $0) })
    self.packageValidators = Dictionary(
      uniqueKeysWithValues: packageValidators.map { ($0.schemaID, $0) })
  }

  func validator(for schemaID: ContentSchemaID) -> (any ContentFileValidating)? {
    validators[schemaID]
  }

  func packageValidator(
    for schemaID: ContentSchemaID
  ) -> (any ContentSchemaPackageValidating)? {
    packageValidators[schemaID]
  }

  static let standard = ContentFileValidatorRegistry(
    trustMode: .production)

  static func configured(trustMode: ContentTrustMode) -> ContentFileValidatorRegistry {
    ContentFileValidatorRegistry(
      validators: [
        FlashcardItemsV1Validator(),
        CertificationQuestionsV1Validator(),
        SampleIndexV1Validator(),
      ],
      packageValidators: [CertificationQuestionsV1PackageValidator(trustMode: trustMode)])
  }

  private init(trustMode: ContentTrustMode) {
    self = Self.configured(trustMode: trustMode)
  }
}

struct ContentPackageValidator: Sendable {
  let registry: ContentFileValidatorRegistry

  init(registry: ContentFileValidatorRegistry = .standard) {
    self.registry = registry
  }

  func validate(manifest: StudyPackManifest, packageRoot: URL) throws {
    let loader = VerifiedContentLoader(packageRoot: packageRoot)
    var validatedFiles: [ContentSchemaID: [ValidatedContentFile]] = [:]
    for component in manifest.components {
      guard let validator = registry.validator(for: component.contentSchemaID) else {
        throw ContentRepositoryError.invalid(
          "未登録content schemaです: \(component.contentSchemaID.rawValue)")
      }
      validatedFiles[component.contentSchemaID, default: []] += []
      for descriptor in component.contentFiles {
        let data = try loader.data(for: descriptor)
        guard !data.isEmpty else {
          throw ContentRepositoryError.invalid("\(descriptor.path) が空です")
        }
        if let expectedByteCount = descriptor.byteCount, data.count != expectedByteCount {
          throw ContentRepositoryError.invalid("\(descriptor.path) のbyte数が一致しません")
        }
        try validator.validate(
          data: data,
          descriptor: descriptor,
          packageRoot: packageRoot)
        validatedFiles[component.contentSchemaID, default: []].append(
          .init(descriptor: descriptor, data: data))
      }
    }
    for (schemaID, files) in validatedFiles {
      try registry.packageValidator(for: schemaID)?.validate(
        manifest: manifest,
        files: files,
        packageRoot: packageRoot)
    }
  }
}

struct OpaqueBinaryContentValidator: ContentFileValidating {
  let schemaID: ContentSchemaID
  let minimumByteCount: Int
  let allowedPathExtensions: Set<String>

  init(
    schemaID: ContentSchemaID,
    minimumByteCount: Int = 1,
    allowedPathExtensions: Set<String> = []
  ) {
    self.schemaID = schemaID
    self.minimumByteCount = minimumByteCount
    self.allowedPathExtensions = Set(allowedPathExtensions.map { $0.lowercased() })
  }

  func validate(data: Data, descriptor: ContentFileDescriptor, packageRoot: URL) throws {
    guard data.count >= minimumByteCount else {
      throw ContentRepositoryError.invalid("\(descriptor.path) のbinary dataが不足しています")
    }
    if !allowedPathExtensions.isEmpty {
      let pathExtension = URL(fileURLWithPath: descriptor.path).pathExtension.lowercased()
      guard allowedPathExtensions.contains(pathExtension) else {
        throw ContentRepositoryError.invalid("\(descriptor.path) の拡張子は利用できません")
      }
    }
  }
}

struct FlashcardItemsV1Validator: ContentFileValidating {
  let schemaID: ContentSchemaID = .flashcardItemsV1

  func validate(data: Data, descriptor: ContentFileDescriptor, packageRoot: URL) throws {
    let items = try JSONContentValidation.items(in: data)
    guard items.count == descriptor.itemCount else {
      throw ContentRepositoryError.invalid("\(descriptor.path) の項目数が一致しません")
    }
    try JSONContentValidation.validateUniqueIDs(items, path: descriptor.path)
    for item in items {
      try JSONContentValidation.requireString("id", in: item, path: descriptor.path)
      try JSONContentValidation.requireString("prompt", in: item, path: descriptor.path)
      try JSONContentValidation.requireString("explanationJa", in: item, path: descriptor.path)
      try JSONContentValidation.validateChoices(
        key: "options", correctIndexKey: "correctIndex", in: item, path: descriptor.path)
    }
  }
}

struct CertificationQuestionsV1Validator: ContentFileValidating {
  let schemaID: ContentSchemaID = .certificationQuestionsV1

  func validate(data: Data, descriptor: ContentFileDescriptor, packageRoot: URL) throws {
    let items = try CertificationQuestionWireDecoder().decode(data)
    guard items.count == descriptor.itemCount else {
      throw ContentRepositoryError.invalid("\(descriptor.path) の項目数が一致しません")
    }
  }
}

struct CertificationQuestionsV1PackageValidator: ContentSchemaPackageValidating {
  let schemaID: ContentSchemaID = .certificationQuestionsV1
  let trustMode: ContentTrustMode

  init(trustMode: ContentTrustMode = .production) {
    self.trustMode = trustMode
  }

  func validate(
    manifest: StudyPackManifest,
    files: [ValidatedContentFile],
    packageRoot: URL
  ) throws {
    guard !files.isEmpty else {
      throw ContentRepositoryError.missing(manifest.title)
    }
    let decoder = CertificationQuestionWireDecoder()
    let questions = try files.flatMap { try decoder.decode($0.data) }
    _ = try CertificationQuestionPackagePolicy(trustMode: trustMode).validatedActiveQuestions(
      questions,
      manifest: manifest,
      packageRoot: packageRoot)
  }
}

struct SampleIndexV1Validator: ContentFileValidating {
  let schemaID: ContentSchemaID = .sampleIndexV1

  func validate(data: Data, descriptor: ContentFileDescriptor, packageRoot: URL) throws {
    let items = try JSONContentValidation.items(in: data)
    guard items.count == descriptor.itemCount else {
      throw ContentRepositoryError.invalid("\(descriptor.path) のsample件数が一致しません")
    }
    try JSONContentValidation.validateUniqueIDs(items, path: descriptor.path)
  }
}

private enum JSONContentValidation {
  static func items(in data: Data) throws -> [[String: Any]] {
    let object = try JSONSerialization.jsonObject(with: data)
    if let values = object as? [[String: Any]] { return values }
    if let dictionary = object as? [String: Any],
      let questions = dictionary["questions"] as? [[String: Any]]
    {
      return questions
    }
    if let dictionary = object as? [String: Any],
      let levels = dictionary["levels"] as? [[String: Any]]
    {
      return levels.flatMap { ($0["questions"] as? [[String: Any]]) ?? [] }
    }
    throw ContentRepositoryError.invalid("教材JSONの項目配列を確認できません")
  }

  static func validateUniqueIDs(_ items: [[String: Any]], path: String) throws {
    let ids = items.compactMap { $0["id"] as? String }
    guard ids.count == items.count, Set(ids).count == ids.count else {
      throw ContentRepositoryError.invalid("\(path) のIDが空または重複しています")
    }
  }

  static func requireString(
    _ key: String,
    in item: [String: Any],
    path: String
  ) throws {
    guard let value = item[key] as? String,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw ContentRepositoryError.invalid("\(path) の\(key)が空です") }
  }

  static func validateChoices(
    key: String,
    correctIndexKey: String,
    in item: [String: Any],
    path: String
  ) throws {
    let choiceCount: Int?
    if let choices = item[key] as? [String],
      choices.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    {
      choiceCount = choices.count
    } else if let choices = item[key] as? [[String: Any]],
      choices.allSatisfy({ choice in
        (choice["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          == false
      })
    {
      choiceCount = choices.count
    } else {
      choiceCount = nil
    }
    guard let choiceCount,
      choiceCount >= 2,
      let correctIndex = item[correctIndexKey] as? Int,
      (0..<choiceCount).contains(correctIndex)
    else {
      throw ContentRepositoryError.invalid("\(path) の選択肢または正解が不正です")
    }
  }
}
