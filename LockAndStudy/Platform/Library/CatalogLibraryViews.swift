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
      ids.formUnion(model.manifests.filter {
        $0.passAccessPolicy.permitsAccess(storeState: $0.storeState)
      }.map(\.id))
    }
    return model.manifests.filter { ids.contains($0.id) }.sorted { lhs, rhs in
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
      ForEach(model.categories) { category in
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
              if let subtitle = category.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
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
    model.manifests.filter { $0.categoryID == categoryID }.count
  }
}

struct CategoryDetailView: View {
  @EnvironmentObject private var model: AppModel
  let category: StudyCategoryManifest

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
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
        let ungrouped = model.manifests.filter {
          $0.categoryID == category.id && !Set(series.map(\.id)).contains($0.seriesID)
        }
        ForEach(ungrouped) { PackSelectionCard(manifest: $0) }
      }
      .frame(maxWidth: 720)
      .padding()
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .navigationTitle(category.title)
    .accessibilityIdentifier("library.categoryDetail.\(category.id.rawValue)")
  }

  private var series: [StudySeriesManifest] {
    model.series.filter { $0.categoryID == category.id }
  }

  private func packs(for seriesID: StudySeriesID) -> [StudyPackManifest] {
    model.manifests.filter { $0.seriesID == seriesID }
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
    model.manifests.filter { $0.seriesID == series.id }.sorted {
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
