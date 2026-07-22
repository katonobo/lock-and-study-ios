import Foundation

enum ContentRepositoryError: LocalizedError {
  case missing(String)
  case invalid(String)
  case unsupported

  var errorDescription: String? {
    switch self {
    case .missing(let value): return "教材ファイルが見つかりません: \(value)"
    case .invalid(let value): return "教材を検証できません: \(value)"
    case .unsupported: return "対応していない教材形式です。"
    }
  }
}

actor ContentRepository {
  private let source: any ContentAssetSource
  private let registry: StudyModuleRegistry
  private var manifestsCache: [StudyPackManifest]?
  private var promptCache: [String: [StudyPrompt]] = [:]
  private var vocabularyCache: [String: VocabularyPackage] = [:]
  private var takkenCache: [String: [TakkenQuestion]] = [:]

  init(
    source: any ContentAssetSource = BundledContentSource(),
    registry: StudyModuleRegistry = .standard
  ) {
    self.source = source
    self.registry = registry
  }

  func releasedManifests() async throws -> [StudyPackManifest] {
    if let manifestsCache { return manifestsCache }
    let data = try await source.catalogData()
    let decoder = SharedJSON.decoder()
    guard let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
      throw ContentRepositoryError.invalid("教材カタログが配列ではありません")
    }
    let manifests = entries.compactMap { entry -> StudyPackManifest? in
      guard JSONSerialization.isValidJSONObject(entry),
        let entryData = try? JSONSerialization.data(withJSONObject: entry),
        let manifest = try? decoder.decode(StudyPackManifest.self, from: entryData)
      else { return nil }
      return manifest
    }
    let released = manifests.filter {
      ($0.releaseStatus == .release && $0.isEnabled) || $0.releaseStatus == .retired
    }
    .sorted { $0.sortOrder < $1.sortOrder }
    guard !released.isEmpty else { throw ContentRepositoryError.invalid("利用可能な教材がありません") }
    guard Set(released.map(\.id)).count == released.count else {
      throw ContentRepositoryError.invalid("pack IDが重複しています")
    }
    manifestsCache = released
    return released
  }

  func prompts(for packID: StudyPackID) async throws -> [StudyPrompt] {
    let manifest = try await manifest(for: packID)
    let key = cacheKey(manifest)
    if let cached = promptCache[key] { return cached }
    guard let module = registry.module(for: manifest.moduleType) else {
      throw ContentRepositoryError.unsupported
    }
    let location = try await requiredPackageLocation(manifest)
    let prompts = try module.loadPrompts(manifest: manifest, packageRoot: location.rootURL)
    let issues = module.validate(manifest: manifest, prompts: prompts)
    guard issues.isEmpty else {
      throw ContentRepositoryError.invalid(issues.joined(separator: ", "))
    }
    promptCache[key] = prompts
    return prompts
  }

  func vocabularyPackage(for packID: StudyPackID) async throws -> VocabularyPackage {
    let manifest = try await manifest(for: packID)
    guard manifest.moduleType == .vocabulary else { throw ContentRepositoryError.unsupported }
    let key = cacheKey(manifest)
    if let cached = vocabularyCache[key] { return cached }
    let location = try await requiredPackageLocation(manifest)
    let package = try VocabularyRepository(packageRoot: location.rootURL).load(manifest: manifest)
    vocabularyCache[key] = package
    return package
  }

  func takkenQuestions(for packID: StudyPackID) async throws -> [TakkenQuestion] {
    let manifest = try await manifest(for: packID)
    guard manifest.moduleType == .takken else { throw ContentRepositoryError.unsupported }
    let key = cacheKey(manifest)
    if let cached = takkenCache[key] { return cached }
    let location = try await requiredPackageLocation(manifest)
    let questions = try TakkenQuestionRepository(packageRoot: location.rootURL).load(
      manifest: manifest)
    takkenCache[key] = questions
    return questions
  }

  func sampleIDs(for packID: StudyPackID, itemIDs: Set<String>) async throws -> Set<String> {
    let manifest = try await manifest(for: packID)
    let location = try await requiredPackageLocation(manifest)
    return try ContentSampleResolver(packageRoot: location.rootURL).sampleIDs(
      manifest: manifest,
      allItemIDs: itemIDs)
  }

  func text(resourcePath: String, for packID: StudyPackID) async throws -> String {
    let manifest = try await manifest(for: packID)
    let location = try await requiredPackageLocation(manifest)
    return try VerifiedContentLoader(packageRoot: location.rootURL).text(
      resourcePath: resourcePath)
  }

  func packageLocation(for packID: StudyPackID) async throws -> ContentPackageLocation {
    try await requiredPackageLocation(manifest(for: packID))
  }

  func clearCache(for packID: StudyPackID? = nil) {
    guard let packID else {
      manifestsCache = nil
      promptCache.removeAll()
      vocabularyCache.removeAll()
      takkenCache.removeAll()
      return
    }
    let prefix = packID.rawValue + "::"
    promptCache = promptCache.filter { !$0.key.hasPrefix(prefix) }
    vocabularyCache = vocabularyCache.filter { !$0.key.hasPrefix(prefix) }
    takkenCache = takkenCache.filter { !$0.key.hasPrefix(prefix) }
  }

  private func manifest(for packID: StudyPackID) async throws -> StudyPackManifest {
    guard let manifest = try await releasedManifests().first(where: { $0.id == packID }) else {
      throw ContentRepositoryError.missing(packID.rawValue)
    }
    return manifest
  }

  private func requiredPackageLocation(
    _ manifest: StudyPackManifest
  ) async throws -> ContentPackageLocation {
    guard
      let location = try await source.packageLocation(
        for: manifest.id,
        contentVersion: manifest.contentVersion)
    else { throw ContentRepositoryError.missing(manifest.id.rawValue) }
    return location
  }

  private func cacheKey(_ manifest: StudyPackManifest) -> String {
    "\(manifest.id.rawValue)::\(manifest.contentVersion)"
  }
}
