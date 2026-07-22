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
  private var catalogCache: StudyCatalogSnapshot?
  private var lastKnownGoodCatalog: StudyCatalogSnapshot?
  private var catalogIssueCache: [CatalogValidationIssue] = []
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
    let snapshot = try await catalogSnapshot()
    return snapshot.packs
  }

  func catalogSnapshot() async throws -> StudyCatalogSnapshot {
    if let catalogCache { return catalogCache }
    do {
      let data = try await source.catalogData()
      let decoded = try StudyCatalogDecoder().decode(data)
      let validation = StudyCatalogValidator().validate(decoded)
      catalogIssueCache = validation
      let invalidPackIDs = Set(validation.compactMap(\.packID))
      let validCategoryIDs = validCategories(in: decoded)
      let validSeriesIDs = Set(decoded.series.filter {
        validCategoryIDs.contains($0.categoryID)
      }.map(\.id))
      var seen: Set<StudyPackID> = []
      let released = decoded.packs.filter {
        ($0.releaseStatus == .release && $0.isEnabled) || $0.releaseStatus == .retired
      }
      .filter {
        !invalidPackIDs.contains($0.id)
          && validCategoryIDs.contains($0.categoryID)
          && validSeriesIDs.contains($0.seriesID)
          && seen.insert($0.id).inserted
      }
      .sorted { $0.sortOrder < $1.sortOrder }
      guard !released.isEmpty else {
        throw ContentRepositoryError.invalid("利用可能な教材がありません")
      }
      let snapshot = StudyCatalogSnapshot(
        schemaVersion: decoded.schemaVersion,
        generatedAt: decoded.generatedAt,
        categories: decoded.categories.filter { validCategoryIDs.contains($0.id) },
        series: decoded.series.filter { validSeriesIDs.contains($0.id) },
        packs: released)
      catalogCache = snapshot
      lastKnownGoodCatalog = snapshot
      return snapshot
    } catch {
      if let lastKnownGoodCatalog {
        catalogCache = lastKnownGoodCatalog
        return lastKnownGoodCatalog
      }
      throw error
    }
  }

  func catalogDiagnostics() -> [CatalogValidationIssue] { catalogIssueCache }

  func reloadCatalog() async throws -> StudyCatalogSnapshot {
    catalogCache = nil
    return try await catalogSnapshot()
  }

  func prompts(for packID: StudyPackID) async throws -> [StudyPrompt] {
    let manifest = try await manifest(for: packID)
    let key = cacheKey(manifest)
    if let cached = promptCache[key] { return cached }
    guard let module = registry.module(for: manifest.moduleType) else {
      throw ContentRepositoryError.unsupported
    }
    var lastError: Error?
    for location in try await candidatePackageLocations(manifest) {
      do {
        let prompts = try module.loadPrompts(manifest: manifest, packageRoot: location.rootURL)
        let issues = module.validate(manifest: manifest, prompts: prompts)
        guard issues.isEmpty else {
          throw ContentRepositoryError.invalid(issues.joined(separator: ", "))
        }
        promptCache[key] = prompts
        return prompts
      } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing(manifest.id.rawValue)
  }

  func vocabularyPackage(for packID: StudyPackID) async throws -> VocabularyPackage {
    let manifest = try await manifest(for: packID)
    guard manifest.moduleType == .vocabulary else { throw ContentRepositoryError.unsupported }
    let key = cacheKey(manifest)
    if let cached = vocabularyCache[key] { return cached }
    var lastError: Error?
    for location in try await candidatePackageLocations(manifest) {
      do {
        let package = try VocabularyRepository(packageRoot: location.rootURL).load(
          manifest: manifest)
        vocabularyCache[key] = package
        return package
      } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing(manifest.id.rawValue)
  }

  func takkenQuestions(for packID: StudyPackID) async throws -> [TakkenQuestion] {
    let manifest = try await manifest(for: packID)
    guard manifest.moduleType == .takken else { throw ContentRepositoryError.unsupported }
    let key = cacheKey(manifest)
    if let cached = takkenCache[key] { return cached }
    var lastError: Error?
    for location in try await candidatePackageLocations(manifest) {
      do {
        let questions = try TakkenQuestionRepository(packageRoot: location.rootURL).load(
          manifest: manifest)
        takkenCache[key] = questions
        return questions
      } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing(manifest.id.rawValue)
  }

  func sampleIDs(for packID: StudyPackID, itemIDs: Set<String>) async throws -> Set<String> {
    let manifest = try await manifest(for: packID)
    var lastError: Error?
    for location in try await candidatePackageLocations(manifest) {
      do {
        return try ContentSampleResolver(packageRoot: location.rootURL).sampleIDs(
          manifest: manifest, allItemIDs: itemIDs)
      } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing(manifest.id.rawValue)
  }

  func text(resourcePath: String, for packID: StudyPackID) async throws -> String {
    let manifest = try await manifest(for: packID)
    var lastError: Error?
    for location in try await candidatePackageLocations(manifest) {
      do {
        return try VerifiedContentLoader(packageRoot: location.rootURL).text(
          resourcePath: resourcePath)
      } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing(resourcePath)
  }

  func packageLocation(for packID: StudyPackID) async throws -> ContentPackageLocation {
    try await requiredPackageLocation(manifest(for: packID))
  }

  func clearCache(for packID: StudyPackID? = nil) {
    guard let packID else {
      catalogCache = nil
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
    guard let location = try await candidatePackageLocations(manifest).first else {
      throw ContentRepositoryError.missing(manifest.id.rawValue)
    }
    return location
  }

  private func candidatePackageLocations(
    _ manifest: StudyPackManifest
  ) async throws -> [ContentPackageLocation] {
    let locations = try await source.packageLocations(
      for: manifest.id, contentVersion: manifest.contentVersion)
    guard !locations.isEmpty else {
      throw ContentRepositoryError.missing(manifest.id.rawValue)
    }
    return locations
  }

  private func cacheKey(_ manifest: StudyPackManifest) -> String {
    let component = manifest.components.sorted { $0.sortOrder < $1.sortOrder }.first?.id.rawValue
      ?? "primary"
    return "\(manifest.id.rawValue)::\(manifest.contentVersion)::\(component)"
  }

  private func validCategories(in snapshot: StudyCatalogSnapshot) -> Set<StudyCategoryID> {
    let byID = snapshot.categoryByID
    return Set(snapshot.categories.compactMap { category in
      var visited: Set<StudyCategoryID> = []
      var current: StudyCategoryID? = category.id
      while let value = current {
        guard visited.insert(value).inserted, let node = byID[value] else { return nil }
        current = node.parentCategoryID
      }
      return category.id
    })
  }
}
