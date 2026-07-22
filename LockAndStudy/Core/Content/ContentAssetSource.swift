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

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  ) {
    self.fileManager = fileManager
    self.appVersion = appVersion
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

  func activate(_ package: InstalledContentPackage) throws {
    let directory = try packDirectory(package.packID)
    let expected = try versionDirectory(packID: package.packID, version: package.contentVersion)
    guard package.rootURL.standardizedFileURL.resolvingSymlinksInPath() == expected,
      fileManager.fileExists(atPath: expected.path)
    else { throw ContentRepositoryError.invalid("インストール済み教材の配置が不正です") }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let previous = try activePointer(for: package.packID)?.contentVersion
    let pointer = ActivePointer(
      contentVersion: package.contentVersion,
      previousContentVersion: previous == package.contentVersion ? nil : previous,
      activatedAt: Date())
    try SharedJSON.encoder().encode(pointer).write(
      to: directory.appendingPathComponent("active.json"),
      options: .atomic)
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
      return .init(
        packID: package.packID, contentVersion: package.contentVersion, rootURL: target)
    }
    let parent = target.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let temporary = parent.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.copyItem(at: source, to: temporary)
      try validate(manifest: package.manifest, packageRoot: temporary)
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

  func rollback(packID: StudyPackID) throws {
    guard let current = try activePointer(for: packID),
      let previous = current.previousContentVersion
    else { throw ContentRepositoryError.invalid("rollbackできる旧版がありません") }
    let previousRoot = try versionDirectory(packID: packID, version: previous)
    guard fileManager.fileExists(atPath: previousRoot.path) else {
      throw ContentRepositoryError.missing(previous)
    }
    let pointer = ActivePointer(
      contentVersion: previous,
      previousContentVersion: current.contentVersion,
      activatedAt: Date())
    try SharedJSON.encoder().encode(pointer).write(
      to: try packDirectory(packID).appendingPathComponent("active.json"),
      options: .atomic)
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
    let loader = VerifiedContentLoader(packageRoot: packageRoot)
    for descriptor in manifest.contentFiles {
      let data = try loader.data(for: descriptor)
      guard try itemCount(in: data) == descriptor.itemCount else {
        throw ContentRepositoryError.invalid("\(descriptor.path) の項目数が一致しません")
      }
    }
  }

  private func itemCount(in data: Data) throws -> Int {
    let object = try JSONSerialization.jsonObject(with: data)
    if let items = object as? [Any] { return items.count }
    if let dictionary = object as? [String: Any],
      let levels = dictionary["levels"] as? [[String: Any]]
    {
      return levels.reduce(0) { count, level in
        count + ((level["questions"] as? [Any])?.count ?? 0)
      }
    }
    throw ContentRepositoryError.invalid("教材項目数を確認できません")
  }

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
  let fallbackCatalogData: Data
  let store: any ContentPackageStoring

  func catalogData() async throws -> Data { fallbackCatalogData }

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
