import Foundation

struct ContentPackageLocation: Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case bundled, installed }

  let kind: Kind
  let rootURL: URL

  func fileURL(for relativePath: String) throws -> URL {
    guard !relativePath.isEmpty else { throw ContentRepositoryError.invalid("教材pathが空です") }
    let relative = URL(fileURLWithPath: relativePath)
    guard !relativePath.hasPrefix("/"), !relative.pathComponents.contains("..") else {
      throw ContentRepositoryError.invalid("教材package外のpathは利用できません: \(relativePath)")
    }
    let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
      .resolvingSymlinksInPath()
    guard candidate.path.hasPrefix(root.path + "/") else {
      throw ContentRepositoryError.invalid("教材package外のpathは利用できません: \(relativePath)")
    }
    return candidate
  }
}

protocol ContentAssetSource: Sendable {
  func catalogData() async throws -> Data
  func catalogDataCandidates() async -> [Data?]
  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation?
  func packageLocations(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> [ContentPackageLocation]
}

extension ContentAssetSource {
  func catalogDataCandidates() async -> [Data?] {
    [try? await catalogData()]
  }

  func packageLocations(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> [ContentPackageLocation] {
    try await packageLocation(for: packID, contentVersion: contentVersion).map { [$0] } ?? []
  }
}

struct BundledContentSource: ContentAssetSource, @unchecked Sendable {
  let bundle: Bundle

  init(bundle: Bundle = .main) { self.bundle = bundle }

  func catalogData() async throws -> Data {
    guard let url = bundle.url(forResource: "study_pack_catalog", withExtension: "json") else {
      throw ContentRepositoryError.missing("study_pack_catalog.json")
    }
    return try Data(contentsOf: url)
  }

  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? {
    guard let root = bundle.resourceURL else { return nil }
    return .init(kind: .bundled, rootURL: root)
  }
}

struct InstalledContentPackage: Codable, Equatable, Sendable {
  let packID: StudyPackID
  let contentVersion: String
  let rootURL: URL
}

struct StagedContentPackage: Sendable {
  let manifest: StudyPackManifest
  let sourceRootURL: URL

  var packID: StudyPackID { manifest.id }
  var contentVersion: String { manifest.contentVersion }
}

protocol ContentPackageStoring: Sendable {
  func installedVersions(for packID: StudyPackID) async throws -> [String]
  func activePackage(for packID: StudyPackID) async throws -> InstalledContentPackage?
  func stage(_ package: StagedContentPackage) async throws -> InstalledContentPackage
  func activate(_ package: InstalledContentPackage) async throws
  func rollback(packID: StudyPackID) async throws
  func remove(packID: StudyPackID, version: String) async throws
}

actor ContentPackageStore: ContentPackageStoring {
  private let rootURL: URL
  private let fileManager: FileManager
  private let appVersion: String
  private let packageValidator: ContentPackageValidator
  private let progressMigrationService: ProgressMigrationService

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
    validatorRegistry: ContentFileValidatorRegistry = .standard,
    progressStore: (any ContentProgressMigrationStoring)? = nil
  ) {
    self.fileManager = fileManager
    self.appVersion = appVersion
    packageValidator = ContentPackageValidator(registry: validatorRegistry)
    progressMigrationService = ProgressMigrationService(progressStore: progressStore)
    self.rootURL =
      rootURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LockAndStudy/Content/Packs", isDirectory: true)
  }

  func installedVersions(for packID: StudyPackID) throws -> [String] {
    let directory = try packDirectory(packID)
    guard fileManager.fileExists(atPath: directory.path) else { return [] }
    return try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.lastPathComponent != "active.json" }.map(\.lastPathComponent).sorted()
  }

  func activePackage(for packID: StudyPackID) throws -> InstalledContentPackage? {
    let directory = try packDirectory(packID)
    let pointer = directory.appendingPathComponent("active.json")
    guard fileManager.fileExists(atPath: pointer.path) else { return nil }
    let document = try SharedJSON.decoder().decode(
      ActivePointer.self, from: Data(contentsOf: pointer))
    let packageRoot = try versionDirectory(packID: packID, version: document.contentVersion)
    guard fileManager.fileExists(atPath: packageRoot.path) else { return nil }
    return .init(packID: packID, contentVersion: document.contentVersion, rootURL: packageRoot)
  }

  func activate(_ package: InstalledContentPackage) async throws {
    let directory = try packDirectory(package.packID)
    let expected = try versionDirectory(packID: package.packID, version: package.contentVersion)
    guard package.rootURL.standardizedFileURL.resolvingSymlinksInPath() == expected,
      fileManager.fileExists(atPath: expected.path)
    else { throw ContentRepositoryError.invalid("インストール済み教材の配置が不正です") }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let previous = try activePointer(for: package.packID)?.contentVersion
    let manifest = try stagedManifest(at: expected)
    if let manifest {
      guard manifest.id == package.packID, manifest.contentVersion == package.contentVersion else {
        throw ContentRepositoryError.invalid("staged manifestがpackageと一致しません")
      }
      do {
        try await progressMigrationService.prepareActivation(
          manifest: manifest,
          packageRoot: expected,
          previousContentVersion: previous)
      } catch {
        if let previous {
          try? await progressMigrationService.rollback(
            packID: package.packID,
            fromContentVersion: previous,
            toContentVersion: package.contentVersion)
        }
        throw error
      }
    }
    let pointer = ActivePointer(
      contentVersion: package.contentVersion,
      previousContentVersion: previous == package.contentVersion ? nil : previous,
      activatedAt: Date())
    do {
      try SharedJSON.encoder().encode(pointer).write(
        to: directory.appendingPathComponent("active.json"),
        options: .atomic)
    } catch {
      if let previous {
        try? await progressMigrationService.rollback(
          packID: package.packID,
          fromContentVersion: previous,
          toContentVersion: package.contentVersion)
      }
      throw error
    }
  }

  func stage(_ package: StagedContentPackage) throws -> InstalledContentPackage {
    guard package.manifest.schemaVersion <= StudyPackManifest.supportedSchemaVersion else {
      throw ContentRepositoryError.unsupported
    }
    guard package.manifest.minimumAppVersion.compare(appVersion, options: .numeric)
      != .orderedDescending
    else { throw ContentRepositoryError.invalid("この教材には新しいアプリが必要です") }
    let source = package.sourceRootURL.standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw ContentRepositoryError.missing(source.lastPathComponent) }
    try validate(manifest: package.manifest, packageRoot: source)

    let target = try versionDirectory(
      packID: package.packID, version: package.contentVersion)
    guard !fileManager.fileExists(atPath: target.path) else {
      try validate(manifest: package.manifest, packageRoot: target)
      try writeStagedManifest(package.manifest, at: target)
      return .init(
        packID: package.packID, contentVersion: package.contentVersion, rootURL: target)
    }
    let parent = target.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let temporary = parent.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.copyItem(at: source, to: temporary)
      try validate(manifest: package.manifest, packageRoot: temporary)
      try writeStagedManifest(package.manifest, at: temporary)
      try fileManager.moveItem(at: temporary, to: target)
    } catch {
      if fileManager.fileExists(atPath: temporary.path) {
        try? fileManager.removeItem(at: temporary)
      }
      throw error
    }
    return .init(
      packID: package.packID, contentVersion: package.contentVersion, rootURL: target)
  }

  func rollback(packID: StudyPackID) async throws {
    guard let current = try activePointer(for: packID),
      let previous = current.previousContentVersion
    else { throw ContentRepositoryError.invalid("rollbackできる旧版がありません") }
    let previousRoot = try versionDirectory(packID: packID, version: previous)
    guard fileManager.fileExists(atPath: previousRoot.path) else {
      throw ContentRepositoryError.missing(previous)
    }
    try await progressMigrationService.rollback(
      packID: packID,
      fromContentVersion: previous,
      toContentVersion: current.contentVersion)
    let pointer = ActivePointer(
      contentVersion: previous,
      previousContentVersion: current.contentVersion,
      activatedAt: Date())
    do {
      try SharedJSON.encoder().encode(pointer).write(
        to: try packDirectory(packID).appendingPathComponent("active.json"),
        options: .atomic)
    } catch {
      if let currentManifest = try stagedManifest(
        at: try versionDirectory(packID: packID, version: current.contentVersion))
      {
        try? await progressMigrationService.prepareActivation(
          manifest: currentManifest,
          packageRoot: try versionDirectory(packID: packID, version: current.contentVersion),
          previousContentVersion: previous)
      }
      throw error
    }
  }

  func remove(packID: StudyPackID, version: String) throws {
    if try activePackage(for: packID)?.contentVersion == version {
      throw ContentRepositoryError.invalid("利用中の教材versionは削除できません")
    }
    let target = try versionDirectory(packID: packID, version: version)
    if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
  }

  private func packDirectory(_ packID: StudyPackID) throws -> URL {
    try componentURL(root: rootURL, component: packID.rawValue, label: "pack ID")
  }

  private func versionDirectory(packID: StudyPackID, version: String) throws -> URL {
    try componentURL(root: packDirectory(packID), component: version, label: "content version")
  }

  private func componentURL(root: URL, component: String, label: String) throws -> URL {
    guard !component.isEmpty, component != ".", component != "..",
      !component.contains("/"), !component.contains("\\")
    else { throw ContentRepositoryError.invalid("\(label)が不正です") }
    return try ContentPackageLocation(kind: .installed, rootURL: root).fileURL(for: component)
  }

  private func activePointer(for packID: StudyPackID) throws -> ActivePointer? {
    let pointerURL = try packDirectory(packID).appendingPathComponent("active.json")
    guard fileManager.fileExists(atPath: pointerURL.path) else { return nil }
    return try SharedJSON.decoder().decode(
      ActivePointer.self, from: Data(contentsOf: pointerURL))
  }

  private func validate(manifest: StudyPackManifest, packageRoot: URL) throws {
    try packageValidator.validate(manifest: manifest, packageRoot: packageRoot)
  }

  private func writeStagedManifest(_ manifest: StudyPackManifest, at root: URL) throws {
    try SharedJSON.encoder().encode(manifest).write(
      to: root.appendingPathComponent(Self.stagedManifestFilename),
      options: .atomic)
  }

  private func stagedManifest(at root: URL) throws -> StudyPackManifest? {
    let url = root.appendingPathComponent(Self.stagedManifestFilename)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try SharedJSON.decoder().decode(StudyPackManifest.self, from: Data(contentsOf: url))
  }

  private static let stagedManifestFilename = ".lockandstudy-manifest.json"

  private struct ActivePointer: Codable {
    let contentVersion: String
    let previousContentVersion: String?
    let activatedAt: Date

    init(contentVersion: String, previousContentVersion: String?, activatedAt: Date) {
      self.contentVersion = contentVersion
      self.previousContentVersion = previousContentVersion
      self.activatedAt = activatedAt
    }
  }
}

struct InstalledContentSource: ContentAssetSource {
  private let fallbackCatalogData: Data?
  private let catalogSource: (any ContentAssetSource)?
  let store: any ContentPackageStoring

  init(fallbackCatalogData: Data, store: any ContentPackageStoring) {
    self.fallbackCatalogData = fallbackCatalogData
    catalogSource = nil
    self.store = store
  }

  init(catalogSource: any ContentAssetSource, store: any ContentPackageStoring) {
    fallbackCatalogData = nil
    self.catalogSource = catalogSource
    self.store = store
  }

  func catalogData() async throws -> Data {
    if let fallbackCatalogData { return fallbackCatalogData }
    guard let catalogSource else {
      throw ContentRepositoryError.missing("study_pack_catalog.json")
    }
    return try await catalogSource.catalogData()
  }

  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? {
    guard let package = try await store.activePackage(for: packID),
      package.contentVersion == contentVersion
    else { return nil }
    return .init(kind: .installed, rootURL: package.rootURL)
  }
}

struct CompositeContentSource: ContentAssetSource {
  let sources: [any ContentAssetSource]

  init(_ sources: [any ContentAssetSource]) { self.sources = sources }

  func catalogData() async throws -> Data {
    var lastError: Error?
    for source in sources {
      do { return try await source.catalogData() } catch { lastError = error }
    }
    throw lastError ?? ContentRepositoryError.missing("study_pack_catalog.json")
  }

  func catalogDataCandidates() async -> [Data?] {
    var candidates: [Data?] = []
    for source in sources {
      candidates.append(contentsOf: await source.catalogDataCandidates())
    }
    return candidates
  }

  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? {
    try await packageLocations(for: packID, contentVersion: contentVersion).first
  }

  func packageLocations(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> [ContentPackageLocation] {
    var locations: [ContentPackageLocation] = []
    for source in sources {
      do {
        locations.append(contentsOf: try await source.packageLocations(
          for: packID, contentVersion: contentVersion))
      } catch {
        continue
      }
    }
    var seen: Set<String> = []
    return locations.filter { seen.insert($0.rootURL.standardizedFileURL.path).inserted }
  }
}

protocol RemoteContentSource: ContentAssetSource {}

struct CatalogDataOverrideSource: ContentAssetSource {
  let data: Data
  let packageSource: any ContentAssetSource

  func catalogData() async throws -> Data { data }
  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? {
    try await packageSource.packageLocation(for: packID, contentVersion: contentVersion)
  }
  func packageLocations(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> [ContentPackageLocation] {
    try await packageSource.packageLocations(for: packID, contentVersion: contentVersion)
  }
}

struct SafeFallbackContentSource: ContentAssetSource {
  func catalogData() async throws -> Data {
    Data(Self.catalog.utf8)
  }

  func packageLocation(
    for packID: StudyPackID,
    contentVersion: String
  ) async throws -> ContentPackageLocation? { nil }

  static func builtInManifest() throws -> StudyPackManifest {
    guard let manifest = try StudyCatalogDecoder().decode(Data(catalog.utf8)).packs.first else {
      throw ContentRepositoryError.missing("safe-fallback.v1")
    }
    return manifest
  }

  private static let catalog = #"""
  {
    "schemaVersion": 2,
    "categories": [{
      "schemaVersion": 1, "id": "safe", "title": "安全な学習", "systemImage": "lifepreserver.fill",
      "sortOrder": 999, "isVisible": true, "themeToken": "teal"
    }],
    "series": [{
      "schemaVersion": 1, "id": "safe.fallback", "categoryID": "safe", "title": "安全な無料問題",
      "description": "教材を復旧できない場合の組み込み問題です。", "sortOrder": 999,
      "editionPolicy": "evergreen", "defaultExperienceID": "safe-fallback.v1", "isVisible": true
    }],
    "packs": [{
      "schemaVersion": 2, "id": "safe-fallback.v1", "categoryID": "safe", "seriesID": "safe.fallback",
      "experienceID": "safe-fallback.v1", "editionID": "v1", "editionPolicy": "evergreen",
      "storeState": "forSale", "deliveryMode": "bundled", "passAccessPolicy": "excluded",
      "moduleType": "safe-fallback", "experienceType": "safe-fallback.v1", "title": "安全な無料問題",
      "subtitle": "オフライン対応", "description": "組み込みの学習問題です。", "contentVersion": "built-in-v1",
      "minimumAppVersion": "1.0", "releaseStatus": "release", "isEnabled": true, "sortOrder": 999,
      "expectedItemCount": 3, "sampleDefinition": {"kind":"allReleased","count":3},
      "passEligible": false, "saleReady": false, "contentFiles": [],
      "components": [{"id":"safe","title":"安全な問題","experienceID":"safe-fallback.v1",
        "contentSchemaID":"safe-fallback.items.v1","sortOrder":0,"contentFiles":[]}], "locale":"ja-JP"
    }]
  }
  """#
}
