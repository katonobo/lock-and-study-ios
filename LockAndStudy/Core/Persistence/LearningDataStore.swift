import Foundation

enum LearningDataStoreError: LocalizedError, Equatable {
  case unavailable, corrupted(String), unsupportedSchema(Int)
  var errorDescription: String? {
    switch self { case .unavailable: return "学習データの保存場所を利用できません。"; case .corrupted: return "破損した学習データをバックアップしました。"; case .unsupportedSchema(let value): return "未対応のデータ形式です (schema \(value))。" }
  }
}

private struct ProgressDocument: Codable { let schemaVersion: Int; var items: [String: ItemProgress] }
private struct EventDocument: Codable { let schemaVersion: Int; var events: [LearningEvent] }
private struct BundleDocument: Codable { let schemaVersion: Int; var bundle: UnlockLearningBundleSnapshot? }
private struct LegacyImportDocument: Codable { let schemaVersion: Int; var importedEventIDs: Set<UUID> }
private struct ExportDocument: Codable { let schemaVersion: Int; let exportedAt: Date; let progress: [String: ItemProgress]; let events: [LearningEvent]; let answersByMonth: [String: [StudyAnswerRecord]] }

actor LearningDataStore {
  static let schemaVersion = 1
  private let rootURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var progressCache: [String: ItemProgress]?

  init(rootURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LockAndStudy", isDirectory: true)
    encoder = SharedJSON.encoder(); encoder.outputFormatting = [.sortedKeys]
    decoder = SharedJSON.decoder()
    try? fileManager.createDirectory(at: self.rootURL.appendingPathComponent("answers", isDirectory: true), withIntermediateDirectories: true)
    try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: self.rootURL.path)
  }

  func progress(for id: CompositeStudyItemID) throws -> ItemProgress {
    try allProgress()[id.storageKey] ?? .initial(id)
  }

  func allProgress() throws -> [String: ItemProgress] {
    if let progressCache { return progressCache }
    let doc: ProgressDocument = try load(progressURL, fallback: .init(schemaVersion: Self.schemaVersion, items: [:]))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    progressCache = doc.items; return doc.items
  }

  func record(_ answer: StudyAnswerRecord) throws {
    var progress = try progress(for: .init(packID: answer.packID, itemID: answer.itemID))
    progress = SRSScheduler().applying(isCorrect: answer.isCorrect, to: progress, at: answer.answeredAt)
    var all = try allProgress(); all[progress.id.storageKey] = progress
    try write(ProgressDocument(schemaVersion: Self.schemaVersion, items: all), to: progressURL); progressCache = all
    let data = try encoder.encode(answer) + Data([0x0A])
    let url = answersURL.appendingPathComponent("\(month(answer.answeredAt)).ndjson")
    if fileManager.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: data)
    } else { try data.write(to: url, options: .atomic); protect(url) }
    try record(.init(kind: .answerSubmitted, occurredAt: answer.answeredAt, packID: answer.packID, sessionID: answer.sessionID, detailCode: answer.isCorrect ? "correct" : "incorrect"))
  }

  func record(_ event: LearningEvent) throws {
    var doc: EventDocument = try load(eventsURL, fallback: .init(schemaVersion: Self.schemaVersion, events: []))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    doc.events.append(event); if doc.events.count > 10_000 { doc.events.removeFirst(doc.events.count - 10_000) }
    try write(doc, to: eventsURL)
  }

  func answers(monthKey: String) throws -> [StudyAnswerRecord] {
    let url = answersURL.appendingPathComponent("\(monthKey).ndjson")
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
    do { return try text.split(separator: "\n").map { try decoder.decode(StudyAnswerRecord.self, from: Data($0.utf8)) } }
    catch { let backup = backupCorrupt(url); throw LearningDataStoreError.corrupted(backup.lastPathComponent) }
  }

  func events() throws -> [LearningEvent] {
    let doc: EventDocument = try load(eventsURL, fallback: .init(schemaVersion: Self.schemaVersion, events: []))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    return doc.events
  }

  @discardableResult
  func importLegacyProgress(_ export: LegacyProgressExport) throws -> Int {
    guard export.schemaVersion == 1,
          LegacyMigrationMapping.allowed.keys.contains(export.sourceBundleID) else {
      throw LegacyMigrationError.unsupportedSource
    }
    var imports: LegacyImportDocument = try load(
      legacyImportsURL,
      fallback: .init(schemaVersion: Self.schemaVersion, importedEventIDs: [])
    )
    guard imports.schemaVersion == Self.schemaVersion else {
      throw LearningDataStoreError.unsupportedSchema(imports.schemaVersion)
    }
    var progress = try allProgress()
    var imported = 0
    for event in export.events where !imports.importedEventIDs.contains(event.id) {
      guard event.sourceBundleID == export.sourceBundleID,
            event.correctCount >= 0, event.incorrectCount >= 0,
            LegacyMigrationMapping.permits(sourceBundleID: export.sourceBundleID, packID: event.packID) else {
        throw LegacyMigrationError.invalidClaim
      }
      let id = CompositeStudyItemID(packID: event.packID, itemID: event.itemID)
      var value = progress[id.storageKey] ?? .initial(id)
      value.correctCount = max(value.correctCount, event.correctCount)
      value.incorrectCount = max(value.incorrectCount, event.incorrectCount)
      value.answerCount = max(value.answerCount, event.correctCount + event.incorrectCount)
      if let answeredAt = event.answeredAt, value.lastAnsweredAt.map({ answeredAt > $0 }) ?? true {
        value.lastAnsweredAt = answeredAt
        value.dueAt = event.dueAt
      }
      value.consecutiveCorrect = 0
      progress[id.storageKey] = value
      imports.importedEventIDs.insert(event.id)
      imported += 1
    }
    guard imported > 0 else { return 0 }
    // The merge operation only takes maxima, so retrying after an interrupted pair of writes is idempotent.
    try write(ProgressDocument(schemaVersion: Self.schemaVersion, items: progress), to: progressURL)
    progressCache = progress
    try write(imports, to: legacyImportsURL)
    try record(.init(kind: .contentMigrated, detailCode: "legacy-progress:\(export.exportID.uuidString)"))
    return imported
  }

  func saveUnlockBundle(_ bundle: UnlockLearningBundleSnapshot?) throws { try write(BundleDocument(schemaVersion: Self.schemaVersion, bundle: bundle), to: bundleURL) }
  func loadUnlockBundle(now: Date) throws -> UnlockLearningBundleSnapshot? {
    let doc: BundleDocument = try load(bundleURL, fallback: .init(schemaVersion: Self.schemaVersion, bundle: nil))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    guard let bundle = doc.bundle, bundle.isRestorable(at: now) else { return nil }
    return bundle
  }

  func exportJSON() throws -> URL {
    var byMonth: [String: [StudyAnswerRecord]] = [:]
    let files = (try? fileManager.contentsOfDirectory(at: answersURL, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.pathExtension == "ndjson" { byMonth[file.deletingPathExtension().lastPathComponent] = try answers(monthKey: file.deletingPathExtension().lastPathComponent) }
    let url = rootURL.appendingPathComponent("lockandstudy-learning-export.json")
    try write(ExportDocument(schemaVersion: Self.schemaVersion, exportedAt: Date(), progress: try allProgress(), events: try events(), answersByMonth: byMonth), to: url)
    return url
  }

  func deleteLearningHistory() throws {
    for url in [progressURL, eventsURL, bundleURL] { try? fileManager.removeItem(at: url) }
    let files = (try? fileManager.contentsOfDirectory(at: answersURL, includingPropertiesForKeys: nil)) ?? []
    for file in files { try? fileManager.removeItem(at: file) }
    progressCache = nil
  }

  private var progressURL: URL { rootURL.appendingPathComponent("progress.v1.json") }
  private var eventsURL: URL { rootURL.appendingPathComponent("events.v1.json") }
  private var bundleURL: URL { rootURL.appendingPathComponent("unlock-bundle.v1.json") }
  private var legacyImportsURL: URL { rootURL.appendingPathComponent("legacy-imports.v1.json") }
  private var answersURL: URL { rootURL.appendingPathComponent("answers", isDirectory: true) }
  private func month(_ date: Date) -> String { let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date); return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0) }
  private func load<T: Codable>(_ url: URL, fallback: T) throws -> T {
    guard fileManager.fileExists(atPath: url.path) else { return fallback }
    do { return try decoder.decode(T.self, from: Data(contentsOf: url)) }
    catch { let backup = backupCorrupt(url); throw LearningDataStoreError.corrupted(backup.lastPathComponent) }
  }
  private func write<T: Encodable>(_ value: T, to url: URL) throws { try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(value).write(to: url, options: .atomic); protect(url) }
  private func protect(_ url: URL) { try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path) }
  private func backupCorrupt(_ url: URL) -> URL { let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).bak"); try? fileManager.moveItem(at: url, to: backup); return backup }
}
