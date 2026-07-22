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

protocol ContentPackageStoring: Sendable {
  func installedVersions(for packID: StudyPackID) async throws -> [String]
  func activePackage(for packID: StudyPackID) async throws -> InstalledContentPackage?
  func activate(_ package: InstalledContentPackage) async throws
  func remove(packID: StudyPackID, version: String) async throws
}

actor ContentPackageStore: ContentPackageStoring {
  private let rootURL: URL
  private let fileManager: FileManager

  init(rootURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
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
    let pointer = ActivePointer(contentVersion: package.contentVersion, activatedAt: Date())
    try SharedJSON.encoder().encode(pointer).write(
      to: directory.appendingPathComponent("active.json"),
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

  private struct ActivePointer: Codable {
    let contentVersion: String
    let activatedAt: Date
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
