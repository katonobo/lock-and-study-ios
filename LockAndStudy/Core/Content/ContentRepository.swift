import CryptoKit
import Foundation

enum ContentRepositoryError: LocalizedError {
  case missing(String), invalid(String), unsupported
  var errorDescription: String? {
    switch self { case .missing(let value): return "教材ファイルが見つかりません: \(value)"; case .invalid(let value): return "教材を検証できません: \(value)"; case .unsupported: return "対応していない教材形式です。" }
  }
}

actor ContentRepository {
  private let bundle: Bundle
  private let registry: StudyModuleRegistry
  private var manifestsCache: [StudyPackManifest]?
  private var promptCache: [StudyPackID: [StudyPrompt]] = [:]

  init(bundle: Bundle = .main, registry: StudyModuleRegistry = .standard) { self.bundle = bundle; self.registry = registry }

  func releasedManifests() throws -> [StudyPackManifest] {
    if let manifestsCache { return manifestsCache }
    guard let url = bundle.url(forResource: "study_pack_catalog", withExtension: "json") else { throw ContentRepositoryError.missing("study_pack_catalog.json") }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let all = try decoder.decode([StudyPackManifest].self, from: Data(contentsOf: url))
    let released = all.filter { $0.releaseStatus == .release && $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    guard Set(released.map(\.id)).count == released.count else { throw ContentRepositoryError.invalid("pack IDが重複しています") }
    manifestsCache = released
    return released
  }

  func prompts(for packID: StudyPackID) throws -> [StudyPrompt] {
    if let cached = promptCache[packID] { return cached }
    guard let manifest = try releasedManifests().first(where: { $0.id == packID }), let module = registry.module(for: manifest.moduleType) else { throw ContentRepositoryError.unsupported }
    try verifyFiles(manifest)
    let prompts = try module.loadPrompts(manifest: manifest, bundle: bundle)
    let issues = module.validate(manifest: manifest, prompts: prompts)
    guard issues.isEmpty else { throw ContentRepositoryError.invalid(issues.joined(separator: ", ")) }
    promptCache[packID] = prompts
    return prompts
  }

  private func verifyFiles(_ manifest: StudyPackManifest) throws {
    for descriptor in manifest.contentFiles {
      let name = URL(fileURLWithPath: descriptor.path).deletingPathExtension().lastPathComponent
      let ext = URL(fileURLWithPath: descriptor.path).pathExtension
      guard let url = bundle.url(forResource: name, withExtension: ext) else { throw ContentRepositoryError.missing(descriptor.path) }
      let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
      guard digest == descriptor.sha256 else { throw ContentRepositoryError.invalid("\(descriptor.path) のSHA-256不一致") }
    }
  }
}

