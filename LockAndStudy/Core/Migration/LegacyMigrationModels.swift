import CryptoKit
import Foundation

struct LegacyEntitlementClaim: Codable, Equatable, Identifiable, Sendable {
  let schemaVersion: Int
  let sourceBundleID: String
  let sourceProductID: String
  let verifiedTransactionID: UInt64
  let originalTransactionID: UInt64
  let purchaseDate: Date
  let expirationDate: Date?
  let ownershipType: OwnershipType
  let destinationPackID: StudyPackID?
  let id: UUID
  let nonce: UUID
  let createdAt: Date
  var consumedAt: Date?
  let integrityDigest: String

  func expectedDigest() -> String {
    let fields = [String(schemaVersion), sourceBundleID, sourceProductID, String(verifiedTransactionID),
                  String(originalTransactionID), String(purchaseDate.timeIntervalSince1970),
                  expirationDate.map { String($0.timeIntervalSince1970) } ?? "none",
                  ownershipType.rawValue, destinationPackID?.rawValue ?? "pass", id.uuidString, nonce.uuidString]
    return SHA256.hash(data: Data(fields.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct LegacyProgressEvent: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let sourceBundleID: String
  let sourceContentVersion: String
  let packID: StudyPackID
  let itemID: StudyItemID
  let answeredAt: Date?
  let correctCount: Int
  let incorrectCount: Int
  let dueAt: Date?
}

struct LegacyProgressExport: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let exportID: UUID
  let sourceBundleID: String
  let createdAt: Date
  let events: [LegacyProgressEvent]
}

enum LegacyMigrationMapping {
  static let allowed: [String: [String: StudyPackID?]] = [
    "com.ameneko.eitangolock": [
      "com.ameneko.eitangolock.premium.lifetime": StudyPackID(rawValue: "english3000.v1"),
      "com.ameneko.eitangolock.premium.monthly": nil,
      "com.ameneko.eitangolock.premium.yearly": nil
    ],
    "com.ameneko.takkenlock": [
      "com.ameneko.takkenlock.premium_lifetime": StudyPackID(rawValue: "takken2026.v1")
    ]
  ]

  static func destination(sourceBundleID: String, productID: String) -> StudyPackID?? {
    allowed[sourceBundleID]?[productID]
  }

  static func permits(sourceBundleID: String, packID: StudyPackID) -> Bool {
    switch sourceBundleID {
    case "com.ameneko.eitangolock": return packID == "english3000.v1"
    case "com.ameneko.takkenlock": return packID == "takken2026.v1"
    default: return false
    }
  }
}

enum LegacyMigrationError: LocalizedError { case unavailable, invalidClaim, unsupportedSource
  var errorDescription: String? { switch self { case .unavailable: return "移行データを利用できません。"; case .invalidClaim: return "移行データの整合性を確認できません。"; case .unsupportedSource: return "この購入は移行対象ではありません。" } }
}

final class LegacyMigrationService {
  private let rootURL: URL
  private let fileManager: FileManager
  private let encoder = SharedJSON.encoder()
  private let decoder = SharedJSON.decoder()

  init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
    self.fileManager = fileManager
    if let rootURL { self.rootURL = rootURL }
    else if let value = fileManager.containerURL(forSecurityApplicationGroupIdentifier: LockAndStudySharedConstants.migrationAppGroupID) { self.rootURL = value }
    else { throw LegacyMigrationError.unavailable }
  }

  func importClaims(now: Date) throws -> [LegacyGrant] {
    let url = rootURL.appendingPathComponent("lockandstudy.legacy.claims.v1.json")
    guard let data = try? Data(contentsOf: url) else { return [] }
    var claims = try decoder.decode([LegacyEntitlementClaim].self, from: data)
    var grants: [LegacyGrant] = []
    var changed = false
    for index in claims.indices where claims[index].consumedAt == nil {
      let claim = claims[index]
      guard claim.schemaVersion == 1, claim.verifiedTransactionID > 0,
            claim.originalTransactionID > 0, claim.integrityDigest == claim.expectedDigest() else { throw LegacyMigrationError.invalidClaim }
      guard let mapping = LegacyMigrationMapping.destination(sourceBundleID: claim.sourceBundleID, productID: claim.sourceProductID) else { throw LegacyMigrationError.unsupportedSource }
      let destination = mapping
      if destination == nil, claim.expirationDate.map({ $0 <= now }) ?? true {
        claims[index].consumedAt = now; changed = true; continue
      }
      grants.append(.init(id: claim.id, sourceBundleID: claim.sourceBundleID, destinationPackID: destination,
                          passExpiration: destination == nil ? claim.expirationDate : nil, importedAt: now))
      claims[index].consumedAt = now; changed = true
    }
    if changed { try encoder.encode(claims).write(to: url, options: .atomic) }
    return grants
  }

  func loadProgressExport() throws -> LegacyProgressExport? {
    let url = rootURL.appendingPathComponent("lockandstudy.legacy.progress.v1.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    let export = try decoder.decode(LegacyProgressExport.self, from: data)
    guard export.schemaVersion == 1, LegacyMigrationMapping.allowed.keys.contains(export.sourceBundleID) else { throw LegacyMigrationError.unsupportedSource }
    return export
  }
}
