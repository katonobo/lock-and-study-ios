import CryptoKit
import Foundation

protocol ContentProgressMigrationStoring: Sendable {
  func applyProgressMigration(
    _ document: ProgressMigrationDocument,
    documentDigest: String
  ) async throws
  func rollbackProgressMigration(
    packID: StudyPackID,
    fromContentVersion: String,
    toContentVersion: String
  ) async throws
  func isProgressMigrationApplied(
    packID: StudyPackID,
    fromContentVersion: String,
    toContentVersion: String,
    documentDigest: String
  ) async throws -> Bool
}

struct PreparedProgressMigration: Sendable {
  let document: ProgressMigrationDocument
  let documentDigest: String
}

struct ProgressMigrationService: Sendable {
  let progressStore: (any ContentProgressMigrationStoring)?

  func prepareActivation(
    manifest: StudyPackManifest,
    packageRoot: URL,
    previousContentVersion: String?
  ) throws -> PreparedProgressMigration? {
    guard let previousContentVersion, previousContentVersion != manifest.contentVersion else {
      return nil
    }
    guard let migrationPath = manifest.progressMigrationFile else {
      return nil  // Stable item IDs preserve progress without a migration document.
    }
    guard let expectedDigest = manifest.progressMigrationSHA256,
      expectedDigest.count == 64
    else {
      throw ContentRepositoryError.invalid("進捗移行fileのSHA-256がありません")
    }
    guard progressStore != nil else {
      throw ContentRepositoryError.invalid("進捗移行storeを利用できません")
    }

    let location = ContentPackageLocation(kind: .installed, rootURL: packageRoot)
    let fileURL = try location.fileURL(for: migrationPath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw ContentRepositoryError.missing(migrationPath)
    }
    let data = try Data(contentsOf: fileURL)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == expectedDigest else {
      throw ContentRepositoryError.invalid("進捗移行fileのSHA-256不一致")
    }
    let document = try SharedJSON.decoder().decode(ProgressMigrationDocument.self, from: data)
    guard document.schemaVersion == ProgressMigrationDocument.supportedSchemaVersion else {
      throw ContentRepositoryError.invalid("未対応の進捗移行schemaです")
    }
    guard document.packID == manifest.id else {
      throw ContentRepositoryError.invalid("進捗移行のpack IDが一致しません")
    }
    guard document.fromContentVersion == previousContentVersion,
      document.toContentVersion == manifest.contentVersion
    else {
      throw ContentRepositoryError.invalid("進捗移行のcontent versionが一致しません")
    }
    try validateMappings(document.itemMigrations)
    return .init(document: document, documentDigest: digest)
  }

  func apply(_ migration: PreparedProgressMigration?) async throws {
    guard let migration else { return }
    guard let progressStore else {
      throw ContentRepositoryError.invalid("進捗移行storeを利用できません")
    }
    try await progressStore.applyProgressMigration(
      migration.document,
      documentDigest: migration.documentDigest)
  }

  func rollback(
    packID: StudyPackID,
    fromContentVersion: String,
    toContentVersion: String
  ) async throws {
    try await progressStore?.rollbackProgressMigration(
      packID: packID,
      fromContentVersion: fromContentVersion,
      toContentVersion: toContentVersion)
  }

  func isApplied(_ migration: PreparedProgressMigration?) async throws -> Bool {
    guard let migration else { return true }
    guard let progressStore, let packID = migration.document.packID else { return false }
    return try await progressStore.isProgressMigrationApplied(
      packID: packID,
      fromContentVersion: migration.document.fromContentVersion,
      toContentVersion: migration.document.toContentVersion,
      documentDigest: migration.documentDigest)
  }

  private func validateMappings(_ mappings: [ItemProgressMigration]) throws {
    let oldIDs = mappings.map(\.oldItemID)
    guard Set(oldIDs).count == oldIDs.count else {
      throw ContentRepositoryError.invalid("進捗移行元IDが重複しています")
    }
    let migratedNewIDs = mappings.filter { $0.policy == .migrate }.map(\.newItemID)
    guard Set(migratedNewIDs).count == migratedNewIDs.count else {
      throw ContentRepositoryError.invalid("進捗移行先IDが重複しています")
    }
    for mapping in mappings where mapping.policy == .preserve {
      guard mapping.oldItemID == mapping.newItemID else {
        throw ContentRepositoryError.invalid("ID変更にはmigrate policyが必要です")
      }
    }
  }
}
