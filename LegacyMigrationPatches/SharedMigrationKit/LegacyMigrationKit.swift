import CryptoKit
import Foundation
import StoreKit
import SwiftUI

public struct LegacyMigrationClaim: Codable, Identifiable {
  public let schemaVersion: Int
  public let sourceBundleID: String
  public let sourceProductID: String
  public let verifiedTransactionID: UInt64
  public let originalTransactionID: UInt64
  public let purchaseDate: Date
  public let expirationDate: Date?
  public let ownershipType: String
  public let destinationPackID: String?
  public let id: UUID
  public let nonce: UUID
  public let createdAt: Date
  public var consumedAt: Date?
  public let integrityDigest: String

  public static func make(transaction: StoreKit.Transaction, sourceBundleID: String, destinationPackID: String?) -> LegacyMigrationClaim {
    let id = UUID(), nonce = UUID(), schemaVersion = 1
    let ownership = transaction.ownershipType == .familyShared ? "familyShared" : "purchased"
    let fields = [String(schemaVersion), sourceBundleID, transaction.productID, String(transaction.id),
                  String(transaction.originalID), String(transaction.purchaseDate.timeIntervalSince1970),
                  transaction.expirationDate.map { String($0.timeIntervalSince1970) } ?? "none",
                  ownership, destinationPackID ?? "pass", id.uuidString, nonce.uuidString]
    let digest = SHA256.hash(data: Data(fields.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    return .init(schemaVersion: schemaVersion, sourceBundleID: sourceBundleID, sourceProductID: transaction.productID,
                 verifiedTransactionID: transaction.id, originalTransactionID: transaction.originalID,
                 purchaseDate: transaction.purchaseDate, expirationDate: transaction.expirationDate,
                 ownershipType: ownership, destinationPackID: destinationPackID, id: id, nonce: nonce,
                 createdAt: Date(), consumedAt: nil, integrityDigest: digest)
  }
}

public struct LegacyProgressEvent: Codable, Identifiable {
  public let id: UUID
  public let sourceBundleID: String
  public let sourceContentVersion: String
  public let packID: String
  public let itemID: String
  public let answeredAt: Date?
  public let correctCount: Int
  public let incorrectCount: Int
  public let dueAt: Date?

  public init(id: UUID = UUID(), sourceBundleID: String, sourceContentVersion: String, packID: String,
              itemID: String, answeredAt: Date?, correctCount: Int, incorrectCount: Int, dueAt: Date?) {
    self.id = id; self.sourceBundleID = sourceBundleID; self.sourceContentVersion = sourceContentVersion
    self.packID = packID; self.itemID = itemID; self.answeredAt = answeredAt
    self.correctCount = correctCount; self.incorrectCount = incorrectCount; self.dueAt = dueAt
  }
}

public struct LegacyProgressPayload: Codable {
  public let schemaVersion: Int
  public let exportID: UUID
  public let sourceBundleID: String
  public let createdAt: Date
  public let events: [LegacyProgressEvent]
}

public actor LegacyMigrationWriter {
  public static let migrationAppGroupID = "group.com.ameneko.lockandstudy.migration"
  private let root: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(fileManager: FileManager = .default) throws {
    guard let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.migrationAppGroupID) else {
      throw CocoaError(.fileNoSuchFile)
    }
    self.root = root
    encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
  }

  public func appendVerifiedTransaction(_ transaction: StoreKit.Transaction, sourceBundleID: String, destinationPackID: String?) throws {
    let url = root.appendingPathComponent("lockandstudy.legacy.claims.v1.json")
    var claims = ((try? Data(contentsOf: url)).flatMap { try? decoder.decode([LegacyMigrationClaim].self, from: $0) }) ?? []
    guard !claims.contains(where: { $0.originalTransactionID == transaction.originalID && $0.sourceProductID == transaction.productID }) else { return }
    claims.append(.make(transaction: transaction, sourceBundleID: sourceBundleID, destinationPackID: destinationPackID))
    try encoder.encode(claims).write(to: url, options: .atomic)
  }

  public func writeProgress(sourceBundleID: String, events: [LegacyProgressEvent]) throws {
    let payload = LegacyProgressPayload(schemaVersion: 1, exportID: UUID(), sourceBundleID: sourceBundleID, createdAt: Date(), events: events)
    try encoder.encode(payload).write(to: root.appendingPathComponent("lockandstudy.legacy.progress.v1.json"), options: .atomic)
  }
}

public struct LegacyMigrationView: View {
  let export: () async throws -> Int
  @State private var state = "購入情報を検証して移行データを作成します。"
  public init(export: @escaping () async throws -> Int) { self.export = export }
  public var body: some View {
    Form {
      Section { Text("Screen Timeの対象、管理コード、ロック設定、緊急解除履歴は移行しません。") }
      Section { Button("購入と学習進捗の移行データを作成") { Task { do { state = "\(try await export())件を書き出しました。ロックンスタディを開いて読み込んでください。" } catch { state = "検証済みの移行データを作成できませんでした。" } } }; Text(state).font(.footnote) }
    }.navigationTitle("ロックンスタディへ移行")
  }
}
