import Foundation

enum LearningDataStoreError: LocalizedError, Equatable {
  case unavailable, corrupted(String), unsupportedSchema(Int), deletionFailed([String])
  var errorDescription: String? {
    switch self {
    case .unavailable: return "学習データの保存場所を利用できません。"
    case .corrupted: return "破損した学習データをバックアップしました。"
    case .unsupportedSchema(let value): return "未対応のデータ形式です (schema \(value))。"
    case .deletionFailed(let files): return "学習履歴を完全に削除できませんでした: \(files.joined(separator: ", "))"
    }
  }
}

private struct ProgressDocument: Codable {
  let schemaVersion: Int
  var items: [String: ItemProgress]
  var appliedSubmissionIDs: Set<String>?
}
private struct EventDocument: Codable { let schemaVersion: Int; var events: [LearningEvent] }
private struct BundleDocument: Codable { let schemaVersion: Int; var bundle: UnlockLearningBundleSnapshot? }
private struct ExperienceBundleDocument: Codable { let schemaVersion: Int; var bundle: ExperienceUnlockBundleSnapshot? }
private struct VocabularyPendingPreviewDocument: Codable {
  let schemaVersion: Int
  var preview: VocabularyPendingPreview?
  var previewsByPackID: [String: VocabularyPendingPreview]?
}
private struct TakkenPendingPreviewDocument: Codable {
  let schemaVersion: Int
  var preview: TakkenPendingPreview?
  var previewsByPackID: [String: TakkenPendingPreview]?
}
private struct LegacyImportDocument: Codable { let schemaVersion: Int; var importedEventIDs: Set<UUID> }
private struct ExportDocument: Codable { let schemaVersion: Int; let exportedAt: Date; let progress: [String: ItemProgress]; let events: [LearningEvent]; let answersByMonth: [String: [StudyAnswerRecord]] }
private enum AnswerWriteStage: String, Codable { case prepared, answerWritten, progressWritten, completed }
private struct AnswerTransaction: Codable {
  var stage: AnswerWriteStage
  let eventID: UUID
  var updatedAt: Date? = nil
  var completedAt: Date? = nil
}
private struct AnswerTransactionDocument: Codable { let schemaVersion: Int; var transactions: [String: AnswerTransaction] }

actor LearningDataStore {
  static let schemaVersion = 1
  private let rootURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var progressCache: [String: ItemProgress]?
  private var answerSubmissionIDCache: [String: Set<String>] = [:]

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
    let doc: ProgressDocument = try load(progressURL, fallback: .init(schemaVersion: Self.schemaVersion, items: [:], appliedSubmissionIDs: []))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    progressCache = doc.items; return doc.items
  }

  func record(_ answer: StudyAnswerRecord) throws {
    _ = try recordUnique(answer)
  }

  @discardableResult
  func recordUnique(_ answer: StudyAnswerRecord) throws -> Bool {
    let submissionID = answer.submissionID ?? answer.id.uuidString
    var transactions: AnswerTransactionDocument = try load(
      answerTransactionsURL,
      fallback: .init(schemaVersion: Self.schemaVersion, transactions: [:])
    )
    guard transactions.schemaVersion == Self.schemaVersion else {
      throw LearningDataStoreError.unsupportedSchema(transactions.schemaVersion)
    }
    if transactions.transactions[submissionID]?.stage == .completed { return false }
    if transactions.transactions[submissionID] == nil {
      transactions.transactions[submissionID] = .init(
        stage: .prepared,
        eventID: UUID(),
        updatedAt: Date())
      try write(transactions, to: answerTransactionsURL)
    }
    guard var transaction = transactions.transactions[submissionID] else { return false }

    if transaction.stage == .prepared {
      if try !answerExists(submissionID: submissionID, monthKey: month(answer.answeredAt)) {
        try append(answer)
      }
      transaction.stage = .answerWritten
      transaction.updatedAt = Date()
      transactions.transactions[submissionID] = transaction
      try write(transactions, to: answerTransactionsURL)
    }

    if transaction.stage == .answerWritten {
      var document: ProgressDocument = try load(
        progressURL,
        fallback: .init(schemaVersion: Self.schemaVersion, items: [:], appliedSubmissionIDs: [])
      )
      var applied = document.appliedSubmissionIDs ?? []
      if !applied.contains(submissionID) {
        let composite = CompositeStudyItemID(packID: answer.packID, itemID: answer.itemID)
        let old = document.items[composite.storageKey] ?? .initial(composite)
        document.items[composite.storageKey] = SRSScheduler().applying(isCorrect: answer.isCorrect, to: old, at: answer.answeredAt)
        applied.insert(submissionID)
        document.appliedSubmissionIDs = applied
        try write(document, to: progressURL)
        progressCache = document.items
      }
      transaction.stage = .progressWritten
      transaction.updatedAt = Date()
      transactions.transactions[submissionID] = transaction
      try write(transactions, to: answerTransactionsURL)
    }

    if transaction.stage == .progressWritten {
      try record(.init(
        id: transaction.eventID,
        kind: .answerSubmitted,
        occurredAt: answer.answeredAt,
        packID: answer.packID,
        sessionID: answer.sessionID,
        detailCode: answer.isCorrect ? "correct" : "incorrect"
      ))
      transaction.stage = .completed
      transaction.updatedAt = Date()
      transaction.completedAt = transaction.updatedAt
      transactions.transactions[submissionID] = transaction
      if transactions.transactions.count > 20_000 {
        let unfinished = transactions.transactions.filter { $0.value.stage != .completed }
        let completed = transactions.transactions.filter { $0.value.stage == .completed }
          .sorted {
            ($0.value.completedAt ?? $0.value.updatedAt ?? .distantPast)
              > ($1.value.completedAt ?? $1.value.updatedAt ?? .distantPast)
          }
          .prefix(10_000)
        transactions.transactions = unfinished.merging(
          Dictionary(uniqueKeysWithValues: completed.map { ($0.key, $0.value) })
        ) { current, _ in current }
      }
      try write(transactions, to: answerTransactionsURL)
    }
    return true
  }

  func record(_ event: LearningEvent) throws {
    var doc: EventDocument = try load(eventsURL, fallback: .init(schemaVersion: Self.schemaVersion, events: []))
    guard doc.schemaVersion == Self.schemaVersion else { throw LearningDataStoreError.unsupportedSchema(doc.schemaVersion) }
    guard !doc.events.contains(where: { $0.id == event.id }) else { return }
    doc.events.append(event); if doc.events.count > 10_000 { doc.events.removeFirst(doc.events.count - 10_000) }
    try write(doc, to: eventsURL)
  }

  func answers(monthKey: String) throws -> [StudyAnswerRecord] {
    let url = answersURL.appendingPathComponent("\(monthKey).ndjson")
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
    do { return try text.split(separator: "\n").map { try decoder.decode(StudyAnswerRecord.self, from: Data($0.utf8)) } }
    catch { let backup = backupCorrupt(url); throw LearningDataStoreError.corrupted(backup.lastPathComponent) }
  }

  func availableAnswerMonthKeys() throws -> [String] {
    let files = try fileManager.contentsOfDirectory(at: answersURL, includingPropertiesForKeys: nil)
    return files.filter { $0.pathExtension == "ndjson" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
  }

  func answers(from start: Date? = nil, through end: Date? = nil) throws -> [StudyAnswerRecord] {
    let values = try availableAnswerMonthKeys().flatMap { try answers(monthKey: $0) }
    return values.filter { answer in
      if let start, answer.answeredAt < start { return false }
      if let end, answer.answeredAt > end { return false }
      return true
    }.sorted { $0.answeredAt < $1.answeredAt }
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
    try write(ProgressDocument(schemaVersion: Self.schemaVersion, items: progress, appliedSubmissionIDs: nil), to: progressURL)
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

  func saveExperienceUnlockBundle(_ bundle: ExperienceUnlockBundleSnapshot?) throws {
    try write(ExperienceBundleDocument(schemaVersion: Self.schemaVersion, bundle: bundle), to: experienceBundleURL)
  }

  func loadExperienceUnlockBundle() throws -> ExperienceUnlockBundleSnapshot? {
    let document: ExperienceBundleDocument = try load(
      experienceBundleURL,
      fallback: .init(schemaVersion: Self.schemaVersion, bundle: nil)
    )
    guard document.schemaVersion == Self.schemaVersion else {
      throw LearningDataStoreError.unsupportedSchema(document.schemaVersion)
    }
    return document.bundle
  }

  func saveVocabularyPendingPreview(
    _ preview: VocabularyPendingPreview?,
    for packID: StudyPackID = "english3000.v1"
  ) throws {
    var document: VocabularyPendingPreviewDocument = try load(
      vocabularyPendingPreviewURL,
      fallback: .init(schemaVersion: Self.schemaVersion, preview: nil, previewsByPackID: [:]))
    var values = migratedVocabularyPreviews(document)
    if let preview {
      guard preview.packID == packID else {
        throw LearningDataStoreError.corrupted("予習のpack IDが一致しません")
      }
      values[packID.rawValue] = preview
    } else {
      values.removeValue(forKey: packID.rawValue)
    }
    document = .init(
      schemaVersion: Self.schemaVersion,
      preview: nil,
      previewsByPackID: values)
    try write(document, to: vocabularyPendingPreviewURL)
  }

  func loadVocabularyPendingPreview(
    for packID: StudyPackID = "english3000.v1",
    now: Date
  ) throws -> VocabularyPendingPreview? {
    var document: VocabularyPendingPreviewDocument = try load(
      vocabularyPendingPreviewURL,
      fallback: .init(schemaVersion: Self.schemaVersion, preview: nil, previewsByPackID: [:])
    )
    guard document.schemaVersion == Self.schemaVersion else {
      throw LearningDataStoreError.unsupportedSchema(document.schemaVersion)
    }
    let migrated = document.preview != nil
    var values = migratedVocabularyPreviews(document)
    if migrated {
      document = .init(
        schemaVersion: Self.schemaVersion,
        preview: nil,
        previewsByPackID: values)
      try write(document, to: vocabularyPendingPreviewURL)
    }
    guard let preview = values[packID.rawValue], preview.packID == packID else { return nil }
    guard preview.recallExpiresAt > now else {
      values.removeValue(forKey: packID.rawValue)
      try write(
        VocabularyPendingPreviewDocument(
          schemaVersion: Self.schemaVersion,
          preview: nil,
          previewsByPackID: values),
        to: vocabularyPendingPreviewURL)
      return nil
    }
    return preview
  }

  @discardableResult
  func consumeVocabularyPendingPreview(
    for packID: StudyPackID = "english3000.v1",
    id: UUID,
    at date: Date
  ) throws -> Bool {
    guard var preview = try loadVocabularyPendingPreview(for: packID, now: date),
      preview.id == id,
      preview.confirmedAt != nil,
      preview.consumedAt == nil
    else { return false }
    preview.consumedAt = date
    try saveVocabularyPendingPreview(preview, for: packID)
    return true
  }

  func saveTakkenPendingPreview(
    _ preview: TakkenPendingPreview?,
    for packID: StudyPackID = "takken2026.v1"
  ) throws {
    var document: TakkenPendingPreviewDocument = try load(
      takkenPendingPreviewURL,
      fallback: .init(schemaVersion: Self.schemaVersion, preview: nil, previewsByPackID: [:]))
    var values = migratedTakkenPreviews(document)
    if let preview {
      guard preview.packID == packID else {
        throw LearningDataStoreError.corrupted("予習のpack IDが一致しません")
      }
      values[packID.rawValue] = preview
    } else {
      values.removeValue(forKey: packID.rawValue)
    }
    document = .init(
      schemaVersion: Self.schemaVersion,
      preview: nil,
      previewsByPackID: values)
    try write(document, to: takkenPendingPreviewURL)
  }

  func loadTakkenPendingPreview(
    for packID: StudyPackID = "takken2026.v1",
    now: Date
  ) throws -> TakkenPendingPreview? {
    var document: TakkenPendingPreviewDocument
    do {
      document = try load(
        takkenPendingPreviewURL,
        fallback: .init(
          schemaVersion: Self.schemaVersion,
          preview: nil,
          previewsByPackID: [:]))
    } catch LearningDataStoreError.corrupted {
      return nil
    }
    guard document.schemaVersion == Self.schemaVersion else {
      throw LearningDataStoreError.unsupportedSchema(document.schemaVersion)
    }
    let migrated = document.preview != nil
    var values = migratedTakkenPreviews(document)
    if migrated {
      document = .init(
        schemaVersion: Self.schemaVersion,
        preview: nil,
        previewsByPackID: values)
      try write(document, to: takkenPendingPreviewURL)
    }
    guard let preview = values[packID.rawValue], preview.packID == packID else { return nil }
    guard preview.recallExpiresAt > now else {
      values.removeValue(forKey: packID.rawValue)
      try write(
        TakkenPendingPreviewDocument(
          schemaVersion: Self.schemaVersion,
          preview: nil,
          previewsByPackID: values),
        to: takkenPendingPreviewURL)
      return nil
    }
    return preview
  }

  @discardableResult
  func consumeTakkenPendingPreview(
    for packID: StudyPackID = "takken2026.v1",
    id: UUID,
    at date: Date
  ) throws -> Bool {
    guard var preview = try loadTakkenPendingPreview(for: packID, now: date),
      preview.id == id, preview.confirmedAt != nil, preview.consumedAt == nil
    else { return false }
    preview.consumedAt = date
    try saveTakkenPendingPreview(preview, for: packID)
    return true
  }

  func exportJSON() throws -> URL {
    var byMonth: [String: [StudyAnswerRecord]] = [:]
    let files = try fileManager.contentsOfDirectory(at: answersURL, includingPropertiesForKeys: nil)
    for file in files where file.pathExtension == "ndjson" { byMonth[file.deletingPathExtension().lastPathComponent] = try answers(monthKey: file.deletingPathExtension().lastPathComponent) }
    let url = rootURL.appendingPathComponent("lockandstudy-learning-export.json")
    try write(ExportDocument(schemaVersion: Self.schemaVersion, exportedAt: Date(), progress: try allProgress(), events: try events(), answersByMonth: byMonth), to: url)
    return url
  }

  func deleteLearningHistory() throws {
    var failures: [String] = []
    let candidates: [URL]
    do {
      candidates = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
    } catch {
      throw LearningDataStoreError.deletionFailed(["学習データ一覧を取得できません"])
    }
    for url in candidates {
      do { try fileManager.removeItem(at: url) }
      catch { failures.append(url.path.replacingOccurrences(of: rootURL.path + "/", with: "")) }
    }
    do {
      try fileManager.createDirectory(at: answersURL, withIntermediateDirectories: true)
    } catch {
      failures.append("answers（再作成失敗）")
    }
    let remaining: [String]
    do {
      remaining = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        .filter { $0 != answersURL }
        .map(\.lastPathComponent)
      let answerRemainders = try fileManager.contentsOfDirectory(at: answersURL, includingPropertiesForKeys: nil)
        .map { "answers/\($0.lastPathComponent)" }
      if !answerRemainders.isEmpty { failures.append(contentsOf: answerRemainders) }
    } catch {
      throw LearningDataStoreError.deletionFailed(Array(Set(failures + ["削除後の存在確認に失敗しました"])).sorted())
    }
    progressCache = nil
    answerSubmissionIDCache.removeAll()
    let unresolved = Array(Set(failures + remaining)).sorted()
    if !unresolved.isEmpty { throw LearningDataStoreError.deletionFailed(unresolved) }
  }

  private func migratedVocabularyPreviews(
    _ document: VocabularyPendingPreviewDocument
  ) -> [String: VocabularyPendingPreview] {
    var values = document.previewsByPackID ?? [:]
    if let legacy = document.preview {
      values[legacy.packID.rawValue] = legacy
    }
    return values
  }

  private func migratedTakkenPreviews(
    _ document: TakkenPendingPreviewDocument
  ) -> [String: TakkenPendingPreview] {
    var values = document.previewsByPackID ?? [:]
    if let legacy = document.preview {
      values[legacy.packID.rawValue] = legacy
    }
    return values
  }

  private var progressURL: URL { rootURL.appendingPathComponent("progress.v1.json") }
  private var eventsURL: URL { rootURL.appendingPathComponent("events.v1.json") }
  private var bundleURL: URL { rootURL.appendingPathComponent("unlock-bundle.v1.json") }
  private var experienceBundleURL: URL { rootURL.appendingPathComponent("experience-unlock-bundle.v2.json") }
  private var vocabularyPendingPreviewURL: URL {
    rootURL.appendingPathComponent("vocabulary-pending-preview.v1.json")
  }
  private var takkenPendingPreviewURL: URL {
    rootURL.appendingPathComponent("takken-pending-preview.v1.json")
  }
  private var answerTransactionsURL: URL { rootURL.appendingPathComponent("answer-transactions.v1.json") }
  private var legacyImportsURL: URL { rootURL.appendingPathComponent("legacy-imports.v1.json") }
  private var exportURL: URL { rootURL.appendingPathComponent("lockandstudy-learning-export.json") }
  private var answersURL: URL { rootURL.appendingPathComponent("answers", isDirectory: true) }
  private func month(_ date: Date) -> String { let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date); return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0) }
  private func append(_ answer: StudyAnswerRecord) throws {
    let data = try encoder.encode(answer) + Data([0x0A])
    let url = answersURL.appendingPathComponent("\(month(answer.answeredAt)).ndjson")
    if fileManager.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } else {
      try data.write(to: url, options: .atomic)
      protect(url)
    }
    answerSubmissionIDCache[month(answer.answeredAt), default: []]
      .insert(answer.submissionID ?? answer.id.uuidString)
  }
  private func answerExists(submissionID: String, monthKey: String) throws -> Bool {
    if let cached = answerSubmissionIDCache[monthKey] {
      return cached.contains(submissionID)
    }
    let identifiers = Set(
      try answers(monthKey: monthKey).map { $0.submissionID ?? $0.id.uuidString })
    answerSubmissionIDCache[monthKey] = identifiers
    return identifiers.contains(submissionID)
  }
  private func load<T: Codable>(_ url: URL, fallback: T) throws -> T {
    guard fileManager.fileExists(atPath: url.path) else { return fallback }
    do { return try decoder.decode(T.self, from: Data(contentsOf: url)) }
    catch { let backup = backupCorrupt(url); throw LearningDataStoreError.corrupted(backup.lastPathComponent) }
  }
  private func write<T: Encodable>(_ value: T, to url: URL) throws { try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(value).write(to: url, options: .atomic); protect(url) }
  private func protect(_ url: URL) { try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path) }
  private func backupCorrupt(_ url: URL) -> URL { let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).bak"); try? fileManager.moveItem(at: url, to: backup); return backup }
}
