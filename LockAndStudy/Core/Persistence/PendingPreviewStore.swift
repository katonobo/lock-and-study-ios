import Foundation

protocol PendingPreviewStoring: Sendable {
  func load<Preview: Codable & Sendable>(
    packID: StudyPackID,
    schemaID: String,
    as type: Preview.Type
  ) async throws -> Preview?
  func save<Preview: Codable & Sendable>(
    _ preview: Preview?,
    packID: StudyPackID,
    schemaID: String
  ) async throws
  func remove(packID: StudyPackID, schemaID: String) async throws
}

actor PendingPreviewStore: PendingPreviewStoring {
  private struct Document<Preview: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let packID: StudyPackID
    let schemaID: String
    let preview: Preview
  }

  private let rootURL: URL
  private let fileManager: FileManager

  init(rootURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.rootURL = rootURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LockAndStudy/PendingPreviews", isDirectory: true)
  }

  func load<Preview: Codable & Sendable>(
    packID: StudyPackID,
    schemaID: String,
    as type: Preview.Type
  ) throws -> Preview? {
    let url = try fileURL(packID: packID, schemaID: schemaID)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let document = try SharedJSON.decoder().decode(
      Document<Preview>.self, from: Data(contentsOf: url))
    guard document.schemaVersion == 1,
      document.packID == packID,
      document.schemaID == schemaID
    else { throw LearningDataStoreError.corrupted("予習データのscopeが一致しません") }
    return document.preview
  }

  func save<Preview: Codable & Sendable>(
    _ preview: Preview?,
    packID: StudyPackID,
    schemaID: String
  ) throws {
    guard let preview else {
      try remove(packID: packID, schemaID: schemaID)
      return
    }
    let url = try fileURL(packID: packID, schemaID: schemaID)
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try SharedJSON.encoder().encode(
      Document(schemaVersion: 1, packID: packID, schemaID: schemaID, preview: preview)
    ).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  func remove(packID: StudyPackID, schemaID: String) throws {
    let url = try fileURL(packID: packID, schemaID: schemaID)
    if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
  }

  private func fileURL(packID: StudyPackID, schemaID: String) throws -> URL {
    let pack = try safeComponent(packID.rawValue, label: "pack ID")
    let schema = try safeComponent(schemaID, label: "preview schema ID")
    return rootURL.appendingPathComponent(pack, isDirectory: true)
      .appendingPathComponent("\(schema).json")
  }

  private func safeComponent(_ value: String, label: String) throws -> String {
    guard !value.isEmpty, value != ".", value != "..",
      !value.contains("/"), !value.contains("\\")
    else { throw LearningDataStoreError.corrupted("\(label)が不正です") }
    return value
  }
}
