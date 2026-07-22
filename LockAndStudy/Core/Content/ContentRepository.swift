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
  private let validatedCatalogStore: ValidatedCatalogStore?
  private var catalogCache: StudyCatalogSnapshot?
  private var lastKnownGoodCatalog: StudyCatalogSnapshot?
  private var catalogIssueCache: [CatalogValidationIssue] = []
  private var promptCache: [String: [StudyPrompt]] = [:]
  private var vocabularyCache: [String: VocabularyPackage] = [:]
  private var takkenCache: [String: [TakkenQuestion]] = [:]

  init(
    source: any ContentAssetSource = BundledContentSource(),
    registry: StudyModuleRegistry = .standard,
    validatedCatalogStore: ValidatedCatalogStore? = nil
  ) {
    self.source = source
    self.registry = registry
    self.validatedCatalogStore = validatedCatalogStore
  }

  func releasedManifests() async throws -> [StudyPackManifest] {
    let snapshot = try await catalogSnapshot()
    return snapshot.packs
  }

  func catalogSnapshot() async throws -> StudyCatalogSnapshot {
    if let catalogCache { return catalogCache }
    let candidates = await source.catalogDataCandidates()
    var lastError: Error = ContentRepositoryError.missing("study_pack_catalog.json")

    if let primary = candidates.first ?? nil {
      do {
        let snapshot = try validatedSnapshot(from: primary, recordsDiagnostics: true)
        return try await accept(
          snapshot, persist: !isSafeFallbackOnly(snapshot))
      } catch {
        lastError = error
      }
    }

    if let lastKnownGoodCatalog {
      catalogCache = lastKnownGoodCatalog
      return lastKnownGoodCatalog
    }

    if let validatedCatalogStore {
      for persisted in await validatedCatalogStore.catalogDataCandidates() {
        do {
          let snapshot = try validatedSnapshot(from: persisted, recordsDiagnostics: false)
          catalogCache = snapshot
          lastKnownGoodCatalog = snapshot
          return snapshot
        } catch {
          lastError = error
        }
      }
    }

    for fallback in candidates.dropFirst().compactMap({ $0 }) {
      do {
        let snapshot = try validatedSnapshot(
          from: fallback, recordsDiagnostics: catalogIssueCache.isEmpty)
        return try await accept(
          snapshot, persist: !isSafeFallbackOnly(snapshot))
      } catch {
        lastError = error
      }
    }
    throw lastError
  }

  func catalogDiagnostics() -> [CatalogValidationIssue] { catalogIssueCache }

  func reloadCatalog() async throws -> StudyCatalogSnapshot {
    catalogCache = nil
    return try await catalogSnapshot()
  }

  private func accept(
    _ snapshot: StudyCatalogSnapshot,
    persist: Bool
  ) async throws -> StudyCatalogSnapshot {
    catalogCache = snapshot
    lastKnownGoodCatalog = snapshot
    if persist, let validatedCatalogStore {
      do {
        let bytes = try SharedJSON.encoder().encode(snapshot)
        try await validatedCatalogStore.save(catalogData: bytes, snapshot: snapshot)
      } catch {
        catalogIssueCache.append(.init(
          "catalog-lkg-write-failed",
          "validated Catalogを永続化できませんでした: \(error.localizedDescription)",
          scope: .global))
      }
    }
    return snapshot
  }

  private func validatedSnapshot(
    from data: Data,
    recordsDiagnostics: Bool
  ) throws -> StudyCatalogSnapshot {
    let decoded = try StudyCatalogDecoder().decode(data)
    let validation = StudyCatalogValidator().validate(decoded)
    if recordsDiagnostics { catalogIssueCache = validation }
    let fatal = validation.filter(\.isGlobalFatal)
    guard fatal.isEmpty else {
      throw ContentRepositoryError.invalid(
        "Catalog全体を拒否しました: \(fatal.map(\.code).joined(separator: ", "))")
    }

    let invalidPackIDs = Set(validation.compactMap { issue in
      issue.scope == .pack ? issue.packID : nil
    })
    let categoryIDs = Set(decoded.categories.map(\.id))
    let seriesIDs = Set(decoded.series.map(\.id))
    let released = decoded.packs.filter {
      ($0.releaseStatus == .release && $0.isEnabled) || $0.releaseStatus == .retired
    }.filter {
      !invalidPackIDs.contains($0.id)
        && categoryIDs.contains($0.categoryID)
        && seriesIDs.contains($0.seriesID)
    }.sorted { $0.sortOrder < $1.sortOrder }
    guard !released.isEmpty else {
      throw ContentRepositoryError.invalid("利用可能な教材がありません")
    }
    return StudyCatalogSnapshot(
      schemaVersion: decoded.schemaVersion,
      generatedAt: decoded.generatedAt,
      categories: decoded.categories,
      series: decoded.series,
      packs: released)
  }

  private func isSafeFallbackOnly(_ snapshot: StudyCatalogSnapshot) -> Bool {
    !snapshot.packs.isEmpty
      && snapshot.packs.allSatisfy { $0.experienceID.normalizedTemplateID == .safeFallbackV1 }
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
