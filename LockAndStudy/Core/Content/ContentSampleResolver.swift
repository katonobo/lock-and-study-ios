import Foundation

struct ContentSampleResolver: Sendable {
  let packageRoot: URL

  func sampleIDs(
    manifest: StudyPackManifest,
    allItemIDs: Set<String>
  ) throws -> Set<String> {
    switch manifest.sampleDefinition.kind {
    case "allReleased":
      guard manifest.sampleDefinition.count == allItemIDs.count else {
        throw ContentRepositoryError.invalid("無料サンプル件数がmanifestと一致しません")
      }
      return allItemIDs
    case "fixed":
      guard let path = manifest.sampleDefinition.catalogFile else {
        throw ContentRepositoryError.missing("固定無料サンプル")
      }
      let data = try VerifiedContentLoader(packageRoot: packageRoot).data(resourcePath: path)
      let ids = try extractIDs(from: data).intersection(allItemIDs)
      guard ids.count == manifest.sampleDefinition.count else {
        throw ContentRepositoryError.invalid("固定無料サンプル件数がmanifestと一致しません")
      }
      return ids
    default:
      throw ContentRepositoryError.invalid("未対応の無料サンプル定義です")
    }
  }

  private func extractIDs(from data: Data) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: data)
    var ids: Set<String> = []
    func visit(_ value: Any) {
      if let dictionary = value as? [String: Any] {
        if let id = dictionary["id"] as? String { ids.insert(id) }
        dictionary.values.forEach(visit)
      } else if let array = value as? [Any] {
        array.forEach(visit)
      }
    }
    visit(object)
    return ids
  }
}
