import Foundation

struct StudyCatalogSnapshot: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let generatedAt: Date?
  let categories: [StudyCategoryManifest]
  let series: [StudySeriesManifest]
  let packs: [StudyPackManifest]

  var categoryByID: [StudyCategoryID: StudyCategoryManifest] {
    categories.reduce(into: [:]) { result, value in result[value.id] = value }
  }

  var seriesByID: [StudySeriesID: StudySeriesManifest] {
    series.reduce(into: [:]) { result, value in result[value.id] = value }
  }
}

struct CatalogValidationIssue: Equatable, Sendable {
  let code: String
  let message: String
  let packID: StudyPackID?

  init(_ code: String, _ message: String, packID: StudyPackID? = nil) {
    self.code = code
    self.message = message
    self.packID = packID
  }
}

struct StudyCatalogDecoder: Sendable {
  func decode(_ data: Data) throws -> StudyCatalogSnapshot {
    let object = try JSONSerialization.jsonObject(with: data)
    if let legacyPacks = object as? [Any] {
      let packs: [StudyPackManifest] = try decodeEntries(legacyPacks, kind: "pack")
      guard !packs.isEmpty else {
        throw ContentRepositoryError.invalid("v1教材カタログに有効なpackがありません")
      }
      return .init(
        schemaVersion: 1,
        generatedAt: nil,
        categories: Self.legacyCategories,
        series: Self.legacySeries,
        packs: packs)
    }

    guard let dictionary = object as? [String: Any] else {
      throw ContentRepositoryError.invalid("教材カタログのroot形式が不正です")
    }
    let schemaVersion = dictionary["schemaVersion"] as? Int ?? 1
    guard schemaVersion <= 2 else {
      throw ContentRepositoryError.invalid("未対応の教材カタログschemaです")
    }
    let categories: [StudyCategoryManifest] = try decodeEntries(
      dictionary["categories"] as? [Any] ?? [], kind: "category")
    let series: [StudySeriesManifest] = try decodeEntries(
      dictionary["series"] as? [Any] ?? [], kind: "series")
    let packs: [StudyPackManifest] = try decodeEntries(
      dictionary["packs"] as? [Any] ?? [], kind: "pack")
    guard !packs.isEmpty else {
      throw ContentRepositoryError.invalid("v2教材カタログに有効なpackがありません")
    }
    return .init(
      schemaVersion: schemaVersion,
      generatedAt: decodeGeneratedAt(dictionary["generatedAt"]),
      categories: categories,
      series: series,
      packs: packs)
  }

  private func decodeEntries<Value: Decodable>(
    _ values: [Any],
    kind: String
  ) throws -> [Value] {
    let decoder = SharedJSON.decoder()
    return try values.enumerated().map { index, value in
      guard JSONSerialization.isValidJSONObject(value) else {
        throw ContentRepositoryError.invalid("catalog \(kind)[\(index)]がJSON objectではありません")
      }
      do {
        let data = try JSONSerialization.data(withJSONObject: value)
        return try decoder.decode(Value.self, from: data)
      } catch {
        throw ContentRepositoryError.invalid(
          "catalog \(kind)[\(index)]をdecodeできません: \(error.localizedDescription)")
      }
    }
  }

  private func decodeGeneratedAt(_ value: Any?) -> Date? {
    guard let value = value as? String else { return nil }
    return ISO8601DateFormatter().date(from: value)
  }

  private static let legacyCategories: [StudyCategoryManifest] = [
    .init(
      schemaVersion: 1, id: .english, parentCategoryID: nil, title: "英語",
      subtitle: nil, systemImage: "character.book.closed.fill", sortOrder: 10,
      isVisible: true, availableFrom: nil, themeToken: "indigo"),
    .init(
      schemaVersion: 1, id: .qualification, parentCategoryID: nil, title: "資格",
      subtitle: nil, systemImage: "building.columns.fill", sortOrder: 20,
      isVisible: true, availableFrom: nil, themeToken: "orange"),
  ]

  private static let legacySeries: [StudySeriesManifest] = [
    .init(
      schemaVersion: 1, id: .englishVocabulary, categoryID: .english,
      title: "英単語", subtitle: nil, description: "英単語を継続的に学ぶシリーズです。",
      sortOrder: 10, editionPolicy: .evergreen,
      defaultExperienceID: .init(rawValue: "flashcard.v1"), isVisible: true),
    .init(
      schemaVersion: 1, id: .takken, categoryID: .qualification,
      title: "宅地建物取引士", subtitle: nil, description: "年度別の宅建試験対策シリーズです。",
      sortOrder: 20, editionPolicy: .annual,
      defaultExperienceID: .init(rawValue: "certification.v1"), isVisible: true),
  ]
}

struct StudyCatalogValidator: Sendable {
  func validate(_ snapshot: StudyCatalogSnapshot) -> [CatalogValidationIssue] {
    var issues: [CatalogValidationIssue] = []
    appendDuplicates(snapshot.categories.map(\.id.rawValue), kind: "category", to: &issues)
    appendDuplicates(snapshot.series.map(\.id.rawValue), kind: "series", to: &issues)
    appendDuplicates(snapshot.packs.map(\.id.rawValue), kind: "pack", to: &issues)

    let categoryIDs = Set(snapshot.categories.map(\.id))
    let seriesByID = snapshot.seriesByID
    for category in snapshot.categories {
      if let parent = category.parentCategoryID, !categoryIDs.contains(parent) {
        issues.append(.init(
          "missing-parent-category",
          "category \(category.id.rawValue) references missing parent \(parent.rawValue)"))
      }
      if hasCategoryCycle(start: category.id, categories: snapshot.categoryByID) {
        issues.append(.init(
          "category-cycle", "category parent cycle contains \(category.id.rawValue)"))
      }
    }

    for series in snapshot.series where !categoryIDs.contains(series.categoryID) {
      issues.append(.init(
        "missing-series-category",
        "series \(series.id.rawValue) references missing category \(series.categoryID.rawValue)"))
    }

    var productOwners: [String: StudyPackID] = [:]
    for pack in snapshot.packs {
      guard let series = seriesByID[pack.seriesID] else {
        issues.append(.init(
          "missing-pack-series",
          "pack \(pack.id.rawValue) references missing series \(pack.seriesID.rawValue)",
          packID: pack.id))
        continue
      }
      if !categoryIDs.contains(pack.categoryID) {
        issues.append(.init(
          "missing-pack-category",
          "pack \(pack.id.rawValue) references missing category \(pack.categoryID.rawValue)",
          packID: pack.id))
      }
      if series.categoryID != pack.categoryID {
        issues.append(.init(
          "pack-series-category-mismatch",
          "pack and series categories differ for \(pack.id.rawValue)", packID: pack.id))
      }
      if pack.editionPolicy == .annual && pack.editionYear == nil {
        issues.append(.init(
          "annual-edition-year-missing", "annual pack requires editionYear", packID: pack.id))
      }
      if pack.storeState == .archivedOwnedOnly && pack.saleReady {
        issues.append(.init(
          "archived-pack-for-sale", "archivedOwnedOnly pack cannot be saleReady", packID: pack.id))
      }
      if pack.storeState == .withdrawn && pack.passAccessPolicy != .excluded {
        issues.append(.init(
          "withdrawn-pass-access", "withdrawn pack cannot be included in Study Pass", packID: pack.id))
      }
      let componentIDs = pack.components.map(\.id.rawValue)
      if Set(componentIDs).count != componentIDs.count {
        issues.append(.init(
          "duplicate-component-id", "component ID is duplicated", packID: pack.id))
      }
      if let productID = pack.oneTimeProductID {
        if let owner = productOwners[productID], owner != pack.id {
          issues.append(.init(
            "duplicate-product-id", "product ID \(productID) is reused", packID: pack.id))
        } else {
          productOwners[productID] = pack.id
        }
      }
    }

    for pack in snapshot.packs where hasSupersedesCycle(start: pack.id, packs: snapshot.packs) {
      issues.append(.init(
        "supersedes-cycle", "supersedes cycle contains \(pack.id.rawValue)", packID: pack.id))
    }
    let packIDs = Set(snapshot.packs.map(\.id))
    for pack in snapshot.packs {
      if let predecessor = pack.supersedesPackID, !packIDs.contains(predecessor) {
        issues.append(.init(
          "missing-superseded-pack",
          "pack \(pack.id.rawValue) references missing predecessor \(predecessor.rawValue)",
          packID: pack.id))
      }
    }
    return issues
  }

  private func appendDuplicates(
    _ values: [String], kind: String, to issues: inout [CatalogValidationIssue]
  ) {
    var seen: Set<String> = []
    for value in values where !seen.insert(value).inserted {
      issues.append(.init("duplicate-\(kind)-id", "\(kind) ID is duplicated: \(value)"))
    }
  }

  private func hasCategoryCycle(
    start: StudyCategoryID, categories: [StudyCategoryID: StudyCategoryManifest]
  ) -> Bool {
    var visited: Set<StudyCategoryID> = []
    var current: StudyCategoryID? = start
    while let value = current {
      guard visited.insert(value).inserted else { return true }
      current = categories[value]?.parentCategoryID
    }
    return false
  }

  private func hasSupersedesCycle(start: StudyPackID, packs: [StudyPackManifest]) -> Bool {
    let parents = packs.reduce(into: [StudyPackID: StudyPackID?]()) {
      result, value in result[value.id] = value.supersedesPackID
    }
    var visited: Set<StudyPackID> = []
    var current: StudyPackID? = start
    while let value = current {
      guard visited.insert(value).inserted else { return true }
      current = parents[value] ?? nil
    }
    return false
  }
}
