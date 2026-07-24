import SwiftUI

enum CatalogTheme {
  static func color(for token: String?) -> Color {
    switch token?.lowercased() {
    case "indigo", "english": return LockAndStudyTheme.vocabulary
    case "orange", "qualification": return LockAndStudyTheme.takken
    case "teal", "mint": return LockAndStudyTheme.teal
    case "purple", "japanese": return .purple
    case "green", "life": return .green
    default: return LockAndStudyTheme.brand
    }
  }
}

struct MyLibraryView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService

  var body: some View {
    if !packs.isEmpty {
      librarySection("マイ教材", systemImage: "books.vertical.fill") {
        ForEach(packs) { PackSelectionCard(manifest: $0) }
      }
      .accessibilityIdentifier("library.myMaterials")
    }
  }

  private var packs: [StudyPackManifest] {
    var ids: Set<StudyPackID> = [model.activeUnlockPackID]
    ids.formUnion(commerce.entitlement.ownedPacks.map(\.packID))
    if commerce.entitlement.activePass?.permitsAccess == true {
      ids.formUnion(
        model.normalManifests.filter {
          $0.passAccessPolicy.permitsAccess(storeState: $0.storeState)
        }.map(\.id))
    }
    return model.normalManifests.filter { ids.contains($0.id) }.sorted { lhs, rhs in
      if lhs.id == model.activeUnlockPackID { return true }
      if rhs.id == model.activeUnlockPackID { return false }
      return lhs.sortOrder < rhs.sortOrder
    }
  }
}

struct CategoryListView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    librarySection("カテゴリー", systemImage: "square.grid.2x2.fill") {
      ForEach(model.categories.filter { $0.parentCategoryID == nil && packCount($0.id) > 0 }) {
        category in
        NavigationLink {
          CategoryDetailView(category: category)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: category.systemImage)
              .font(.title2)
              .foregroundStyle(.white)
              .frame(width: 52, height: 52)
              .background(
                CatalogTheme.color(for: category.themeToken).gradient,
                in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
              Text(category.title).font(.headline).foregroundStyle(.primary)
              if let subtitle = category.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
              }
              Text("\(packCount(category.id))教材")
                .font(.caption.bold())
                .foregroundStyle(CatalogTheme.color(for: category.themeToken))
            }
            Spacer()
          }
          .studyCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.category.\(category.id.rawValue)")
      }
    }
  }

  private func packCount(_ categoryID: StudyCategoryID) -> Int {
    let categoryIDs = descendantCategoryIDs(from: categoryID)
    return model.normalManifests.filter { categoryIDs.contains($0.categoryID) }.count
  }

  private func descendantCategoryIDs(from root: StudyCategoryID) -> Set<StudyCategoryID> {
    var result: Set<StudyCategoryID> = [root]
    var frontier: [StudyCategoryID] = [root]
    while let current = frontier.popLast() {
      for child in model.categories where child.parentCategoryID == current {
        if result.insert(child.id).inserted { frontier.append(child.id) }
      }
    }
    return result
  }
}

struct CategoryDetailView: View {
  @EnvironmentObject private var model: AppModel
  let category: StudyCategoryManifest

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        if !children.isEmpty {
          librarySection("サブカテゴリー", systemImage: "folder.fill") {
            ForEach(children) { child in
              NavigationLink {
                CategoryDetailView(category: child)
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: child.systemImage)
                    .foregroundStyle(CatalogTheme.color(for: child.themeToken))
                  VStack(alignment: .leading, spacing: 3) {
                    Text(child.title).font(.headline).foregroundStyle(.primary)
                    if let subtitle = child.subtitle {
                      Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(descendantPackCount(child.id))教材")
                      .font(.caption.bold())
                      .foregroundStyle(CatalogTheme.color(for: child.themeToken))
                  }
                  Spacer()
                  Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .studyCard()
              }
              .buttonStyle(.plain)
            }
          }
        }
        ForEach(series) { value in
          NavigationLink {
            SeriesDetailView(series: value)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(value.title).font(.title3.bold()).foregroundStyle(.primary)
              if let subtitle = value.subtitle {
                Text(subtitle).foregroundStyle(.secondary)
              }
              Text(value.description).font(.subheadline).foregroundStyle(.secondary)
              Label("\(packs(for: value.id).count)教材", systemImage: "chevron.right.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(CatalogTheme.color(for: category.themeToken))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyCard()
          }
          .buttonStyle(.plain)
        }
        let ungrouped = model.normalManifests.filter {
          $0.categoryID == category.id && !Set(series.map(\.id)).contains($0.seriesID)
        }
        ForEach(ungrouped) { PackSelectionCard(manifest: $0) }
        if children.isEmpty && series.isEmpty && ungrouped.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.secondary)
            Text("教材はまだありません").font(.headline)
            Text("このカテゴリーの教材は準備中です。")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .studyCard()
        }
      }
      .frame(maxWidth: 720)
      .padding()
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .navigationTitle(category.title)
    .accessibilityIdentifier("library.categoryDetail.\(category.id.rawValue)")
  }

  private var series: [StudySeriesManifest] {
    model.series.filter { value in
      value.categoryID == category.id
        && model.normalManifests.contains(where: { $0.seriesID == value.id })
    }
  }

  private var children: [StudyCategoryManifest] {
    model.categories.filter { $0.parentCategoryID == category.id }
      .sorted { $0.sortOrder < $1.sortOrder }
  }

  private func descendantPackCount(_ root: StudyCategoryID) -> Int {
    var ids: Set<StudyCategoryID> = [root]
    var frontier = [root]
    while let current = frontier.popLast() {
      for child in model.categories where child.parentCategoryID == current {
        if ids.insert(child.id).inserted { frontier.append(child.id) }
      }
    }
    return model.normalManifests.filter { ids.contains($0.categoryID) }.count
  }

  private func packs(for seriesID: StudySeriesID) -> [StudyPackManifest] {
    model.normalManifests.filter { $0.seriesID == seriesID }
  }
}

struct SeriesDetailView: View {
  @EnvironmentObject private var model: AppModel
  let series: StudySeriesManifest

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        if let latest {
          librarySection(series.editionPolicy == .annual ? "最新年度" : "教材", systemImage: "sparkles") {
            PackSelectionCard(manifest: latest, showsDetailsLink: true)
          }
        }
        if !past.isEmpty {
          librarySection("過去年度", systemImage: "clock.arrow.circlepath") {
            ForEach(past) { PackSelectionCard(manifest: $0, showsDetailsLink: true) }
          }
        }
      }
      .frame(maxWidth: 720)
      .padding()
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .navigationTitle(series.title)
    .accessibilityIdentifier("library.series.\(series.id.rawValue)")
  }

  private var sorted: [StudyPackManifest] {
    model.normalManifests.filter { $0.seriesID == series.id }.sorted {
      ($0.editionYear ?? Int.min, $0.sortOrder) > ($1.editionYear ?? Int.min, $1.sortOrder)
    }
  }
  private var latest: StudyPackManifest? { sorted.first }
  private var past: [StudyPackManifest] { Array(sorted.dropFirst()) }
}

struct PackSelectionCard: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var commerce: StoreKitCommerceService
  let manifest: StudyPackManifest
  var showsDetailsLink = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: descriptor?.systemImage ?? "book.closed.fill")
          .font(.title2)
          .foregroundStyle(.white)
          .frame(width: 60, height: 60)
          .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 4) {
          Text(manifest.title).font(.title3.bold())
          Text(manifest.subtitle).font(.subheadline).foregroundStyle(.secondary)
          HStack {
            if let year = manifest.editionYear { Label("\(year)年度", systemImage: "calendar") }
            Label(accessLabel, systemImage: accessImage)
          }
          .font(.caption.bold())
          .foregroundStyle(tint)
        }
        Spacer(minLength: 0)
      }
      if !availability.canOpen {
        Label(availability.message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption.bold()).foregroundStyle(.orange)
      }
      HStack(spacing: 10) {
        Button(isCurrent ? "解除教材に設定済み" : "この教材を選択") {
          model.selectStudyMaterial(manifest.id)
        }
        .primaryActionStyle()
        .disabled(isCurrent || !availability.canOpen)
        .accessibilityIdentifier("materialSelection.option.\(manifest.id.rawValue)")
        if showsDetailsLink {
          NavigationLink("詳細") { PlatformPackDetailView(manifest: manifest) }
            .secondaryActionStyle()
        }
      }
    }
    .studyCard()
  }

  private var descriptor: StudyExperienceDescriptor? {
    model.experienceRegistry.factory(for: manifest)?.descriptor
  }
  private var availability: PackAvailability { model.availability(for: manifest) }
  private var isCurrent: Bool { model.activeUnlockPackID == manifest.id }
  private var isOwned: Bool {
    commerce.entitlement.ownedPacks.contains { $0.packID == manifest.id }
  }
  private var includedByPass: Bool {
    manifest.passAccessPolicy.permitsAccess(storeState: manifest.storeState)
      && commerce.entitlement.activePass?.permitsAccess == true
  }
  private var accessLabel: String {
    if InternalContentReviewBuild.isEnabled { return "内部レビュー全問" }
    if isOwned { return "買い切り所有" }
    if includedByPass { return "Study Pass" }
    if manifest.storeState == .archivedOwnedOnly { return "販売終了" }
    return "無料\(manifest.sampleDefinition.count)項目"
  }
  private var accessImage: String {
    isOwned ? "checkmark.seal.fill" : (includedByPass ? "ticket.fill" : "gift.fill")
  }
  private var tint: Color {
    let category = model.categories.first { $0.id == manifest.categoryID }
    return CatalogTheme.color(for: category?.themeToken)
  }
}

@ViewBuilder
private func librarySection<Content: View>(
  _ title: String,
  systemImage: String,
  @ViewBuilder content: () -> Content
) -> some View {
  VStack(alignment: .leading, spacing: 12) {
    Label(title, systemImage: systemImage).font(.title2.bold())
    content()
  }
  .frame(maxWidth: .infinity, alignment: .leading)
}
