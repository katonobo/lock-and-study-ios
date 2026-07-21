import CryptoKit
import Foundation
import Security

enum ManagementCodeError: LocalizedError, Equatable {
    case noCredential
    case invalidCode
    case invalidFormat
    case lockedOut(until: Date)
    case randomGenerationFailed
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .noCredential: return "管理コードが未設定です。"
        case .invalidCode: return "管理コードが違います。"
        case .invalidFormat: return "管理コードは6桁の数字にしてください。"
        case let .lockedOut(until): return "入力回数が多すぎます。\(until.formatted(date: .omitted, time: .shortened))以降に再試行してください。"
        case .randomGenerationFailed: return "安全なコードを生成できませんでした。"
        case .storageFailed: return "管理コードを保存できませんでした。"
        }
    }
}

protocol ManagementCodeBackingStore: Sendable {
    func loadCredentialData() throws -> Data?
    func saveCredentialData(_ data: Data) throws
    func deleteCredentialData() throws
}

final class InMemoryManagementCodeBackingStore: ManagementCodeBackingStore, @unchecked Sendable {
    private var data: Data?
    init(data: Data? = nil) { self.data = data }
    func loadCredentialData() throws -> Data? { data }
    func saveCredentialData(_ data: Data) throws { self.data = data }
    func deleteCredentialData() throws { data = nil }
}

final class KeychainManagementCodeBackingStore: ManagementCodeBackingStore, @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.ameneko.lockandstudy.management-code", account: String = "managementCode") {
        self.service = service
        self.account = account
    }

    func loadCredentialData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ManagementCodeError.storageFailed }
        return item as? Data
    }

    func saveCredentialData(_ data: Data) throws {
        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw ManagementCodeError.storageFailed }
        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ManagementCodeError.storageFailed }
    }

    func deleteCredentialData() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw ManagementCodeError.storageFailed
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct ManagementCodeSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = ManagementCodeSnapshot.currentSchemaVersion
    var codeSalt: Data
    var codeVerifier: Data
    var iterations: Int
    var failedAttempts: Int
    var lockoutUntil: Date?
    var lastFailureAt: Date?
    var updatedAt: Date
}

final class ManagementCodeStore: @unchecked Sendable {
    private let backing: ManagementCodeBackingStore
    private let dateProvider: any DateProviding
    private let iterations: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        backing: ManagementCodeBackingStore = KeychainManagementCodeBackingStore(),
        dateProvider: any DateProviding = SystemDateProvider(),
        iterations: Int = 120_000
    ) {
        self.backing = backing
        self.dateProvider = dateProvider
        self.iterations = iterations
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var hasManagementCode: Bool {
        (try? loadSnapshot()) != nil
    }

    func setCode(_ code: String) throws {
        try validateCodeFormat(code)
        let snapshot = try makeSnapshot(code: code, now: dateProvider.now())
        try saveSnapshot(snapshot)
    }

    func changeCode(currentCode: String, newCode: String) throws {
        _ = try verify(currentCode)
        try setCode(newCode)
    }

    func verify(_ code: String) throws -> Bool {
        var snapshot = try requireSnapshot()
        try validateCodeFormat(code)
        let now = effectiveNow(for: snapshot)
        if let lockoutUntil = snapshot.lockoutUntil, lockoutUntil > now {
            throw ManagementCodeError.lockedOut(until: lockoutUntil)
        }
        if let lockoutUntil = snapshot.lockoutUntil, lockoutUntil <= now {
            snapshot.lockoutUntil = nil
        }
        let verifier = Self.pbkdf2(password: Data(code.utf8), salt: snapshot.codeSalt, iterations: snapshot.iterations)
        if Self.constantTimeEqual(verifier, snapshot.codeVerifier) {
            snapshot.failedAttempts = 0
            snapshot.lockoutUntil = nil
            snapshot.lastFailureAt = nil
            snapshot.updatedAt = now
            try saveSnapshot(snapshot)
            return true
        }

        snapshot.failedAttempts += 1
        snapshot.lastFailureAt = now
        if snapshot.failedAttempts >= 10 {
            snapshot.lockoutUntil = now.addingTimeInterval(30 * 60)
        } else if snapshot.failedAttempts == 5 {
            snapshot.lockoutUntil = now.addingTimeInterval(5 * 60)
        }
        snapshot.updatedAt = now
        try saveSnapshot(snapshot)
        if let lockoutUntil = snapshot.lockoutUntil {
            throw ManagementCodeError.lockedOut(until: lockoutUntil)
        }
        throw ManagementCodeError.invalidCode
    }

    func removeCode() throws {
        try backing.deleteCredentialData()
    }

    func credentialSnapshotForTests() throws -> ManagementCodeSnapshot? {
        try loadSnapshot()
    }

    static func codeWarning(_ code: String) -> String? {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            return "管理コードは6桁の数字にしてください。"
        }
        if Set(code).count == 1 {
            return "同じ数字の繰り返しは推測されやすいため避けてください。"
        }
        let digits = code.compactMap(\.wholeNumberValue)
        if zip(digits, digits.dropFirst()).allSatisfy({ $0.1 == $0.0 + 1 }) ||
            zip(digits, digits.dropFirst()).allSatisfy({ $0.1 == $0.0 - 1 }) {
            return "連続した数字は推測されやすいため避けてください。"
        }
        return nil
    }

    private func validateCodeFormat(_ code: String) throws {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw ManagementCodeError.invalidFormat
        }
    }

    private func makeSnapshot(code: String, now: Date) throws -> ManagementCodeSnapshot {
        let salt = try Self.randomData(count: 16)
        return ManagementCodeSnapshot(
            schemaVersion: ManagementCodeSnapshot.currentSchemaVersion,
            codeSalt: salt,
            codeVerifier: Self.pbkdf2(password: Data(code.utf8), salt: salt, iterations: iterations),
            iterations: iterations,
            failedAttempts: 0,
            lockoutUntil: nil,
            lastFailureAt: nil,
            updatedAt: now
        )
    }

    private func requireSnapshot() throws -> ManagementCodeSnapshot {
        guard let snapshot = try loadSnapshot() else { throw ManagementCodeError.noCredential }
        return snapshot
    }

    private func loadSnapshot() throws -> ManagementCodeSnapshot? {
        guard let data = try backing.loadCredentialData() else { return nil }
        let snapshot = try decoder.decode(ManagementCodeSnapshot.self, from: data)
        guard snapshot.schemaVersion == ManagementCodeSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    private func saveSnapshot(_ snapshot: ManagementCodeSnapshot) throws {
        try backing.saveCredentialData(try encoder.encode(snapshot))
    }

    private func effectiveNow(for snapshot: ManagementCodeSnapshot) -> Date {
        let now = dateProvider.now()
        guard let lastFailureAt = snapshot.lastFailureAt, now < lastFailureAt else { return now }
        return lastFailureAt
    }

    private static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw ManagementCodeError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, keyByteCount: Int = 32) -> Data {
        let hLen = 32
        let blockCount = Int(ceil(Double(keyByteCount) / Double(hLen)))
        let key = SymmetricKey(data: password)
        var derived = Data()
        for blockIndex in 1...blockCount {
            var blockSalt = salt
            blockSalt.append(UInt8((blockIndex >> 24) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 16) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 8) & 0xff))
            blockSalt.append(UInt8(blockIndex & 0xff))
            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
            var t = u
            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for index in 0..<t.count {
                        t[index] ^= u[index]
                    }
                }
            }
            derived.append(t)
        }
        return derived.prefix(keyByteCount)
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        let lhsBytes = [UInt8](lhs)
        let rhsBytes = [UInt8](rhs)
        let maxCount = max(lhsBytes.count, rhsBytes.count)
        var diff = UInt8(lhsBytes.count ^ rhsBytes.count)
        for index in 0..<maxCount {
            let l = index < lhsBytes.count ? lhsBytes[index] : 0
            let r = index < rhsBytes.count ? rhsBytes[index] : 0
            diff |= l ^ r
        }
        return diff == 0
    }
}

enum ManagementCodeResetResult: Equatable {
    case scheduled(Date)
    case tooEarly(Date)
    case secondConfirmationRequired
    case removed
}

struct ManagementCodeResetService {
    let codeStore: ManagementCodeStore
    let policyStore: LockPolicyStore
    var cooldown: TimeInterval = 86_400

    @discardableResult
    func schedule(now: Date) -> ManagementCodeResetResult {
        if let pending = policyStore.loadPendingManagementReset() {
            return .scheduled(pending.availableAt)
        }
        let pending = PendingManagementCodeReset(id: UUID(), requestedAt: now, availableAt: now.addingTimeInterval(cooldown))
        policyStore.savePendingManagementReset(pending)
        return .scheduled(pending.availableAt)
    }

    func confirm(now: Date, secondConfirmation: Bool) throws -> ManagementCodeResetResult {
        guard let pending = policyStore.loadPendingManagementReset() else {
            return .secondConfirmationRequired
        }
        guard now >= pending.availableAt else { return .tooEarly(pending.availableAt) }
        guard secondConfirmation else { return .secondConfirmationRequired }
        try codeStore.removeCode()
        policyStore.savePendingManagementReset(nil)
        return .removed
    }

    func removeImmediately(currentCode: String) throws -> ManagementCodeResetResult {
        guard try codeStore.verify(currentCode) else { throw ManagementCodeError.invalidCode }
        try codeStore.removeCode()
        policyStore.savePendingManagementReset(nil)
        return .removed
    }
}
