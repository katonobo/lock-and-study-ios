import Foundation

struct CatalogSignatureMetadata: Codable, Equatable, Sendable {
  let algorithm: String
  let keyID: String
  let signature: String
}

struct ValidatedCatalogMetadata: Codable, Equatable, Sendable {
  let catalogSchemaVersion: Int
  let generatedAt: Date?
  let validatedAt: Date
  let signature: CatalogSignatureMetadata?
}

private struct ValidatedCatalogDocument: Codable, Sendable {
  static let schemaVersion = 1

  let schemaVersion: Int
  let catalogData: Data
  let metadata: ValidatedCatalogMetadata
}

actor ValidatedCatalogStore {
  nonisolated let primaryURL: URL
  nonisolated let backupURL: URL

  private let fileManager: FileManager

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    let root = rootURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LockAndStudy/Content/Catalog", isDirectory: true)
    primaryURL = root.appendingPathComponent("validated-catalog-v1.json")
    backupURL = root.appendingPathComponent("validated-catalog-v1.backup.json")
  }

  func save(
    catalogData: Data,
    snapshot: StudyCatalogSnapshot,
    validatedAt: Date = Date(),
    signature: CatalogSignatureMetadata? = nil
  ) throws {
    let document = ValidatedCatalogDocument(
      schemaVersion: ValidatedCatalogDocument.schemaVersion,
      catalogData: catalogData,
      metadata: .init(
        catalogSchemaVersion: snapshot.schemaVersion,
        generatedAt: snapshot.generatedAt,
        validatedAt: validatedAt,
        signature: signature))
    let encoded = try SharedJSON.encoder().encode(document)
    try fileManager.createDirectory(
      at: primaryURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    if fileManager.fileExists(atPath: primaryURL.path) {
      let previous = try Data(contentsOf: primaryURL)
      try durableAtomicWrite(previous, to: backupURL)
    }
    try durableAtomicWrite(encoded, to: primaryURL)
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: primaryURL.path)
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: backupURL.path)
  }

  func catalogDataCandidates() -> [Data] {
    [primaryURL, backupURL].compactMap { url in
      guard let data = try? Data(contentsOf: url),
        let document = try? SharedJSON.decoder().decode(
          ValidatedCatalogDocument.self, from: data),
        document.schemaVersion == ValidatedCatalogDocument.schemaVersion
      else { return nil }
      return document.catalogData
    }
  }

  func metadata() -> ValidatedCatalogMetadata? {
    guard let data = try? Data(contentsOf: primaryURL),
      let document = try? SharedJSON.decoder().decode(
        ValidatedCatalogDocument.self, from: data),
      document.schemaVersion == ValidatedCatalogDocument.schemaVersion
    else { return nil }
    return document.metadata
  }

  private func durableAtomicWrite(_ data: Data, to destination: URL) throws {
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
    guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
      throw ContentRepositoryError.invalid("Catalogの一時ファイルを作成できません")
    }
    do {
      let handle = try FileHandle(forWritingTo: temporary)
      do {
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: destination)
      }
    } catch {
      if fileManager.fileExists(atPath: temporary.path) {
        try? fileManager.removeItem(at: temporary)
      }
      throw error
    }
  }
}
