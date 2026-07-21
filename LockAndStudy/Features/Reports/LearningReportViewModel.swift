import Combine
import Foundation

@MainActor
final class LearningReportViewModel: ObservableObject {
  @Published private(set) var report: LearningReport?
  @Published private(set) var availableScopes: [LearningReportScope]
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?
  @Published var scope: LearningReportScope

  let currentPackID: StudyPackID
  private let dependencies: DependencyContainer
  private let providers: [any StudyExperienceReportProviding]
  private let calendar: Calendar
  private var snapshot: LearningReportDataSnapshot?
  private var cancellables: Set<AnyCancellable> = []

  init(
    currentPackID: StudyPackID,
    dependencies: DependencyContainer,
    providers: [any StudyExperienceReportProviding],
    calendar: Calendar = .current
  ) {
    self.currentPackID = currentPackID
    self.dependencies = dependencies
    self.providers = providers
    self.calendar = calendar
    scope = .pack(currentPackID)
    availableScopes = [.pack(currentPackID)]

    dependencies.learningRevision.$value
      .dropFirst()
      .sink { [weak self] _ in Task { @MainActor in await self?.load() } }
      .store(in: &cancellables)
    dependencies.commerce.$entitlement
      .dropFirst()
      .sink { [weak self] _ in Task { @MainActor in await self?.load() } }
      .store(in: &cancellables)
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let answers = try await dependencies.learning.answers()
      let events = try await dependencies.learning.events()
      let progress = try await dependencies.learning.allProgress()
      let manifests = try await dependencies.content.releasedManifests()
      let loaded = LearningReportDataSnapshot(
        answers: answers,
        events: events,
        progress: progress,
        manifests: manifests,
        entitlement: dependencies.commerce.entitlement
      )
      snapshot = loaded
      let dataPackIDs = Set(answers.map(\.packID))
        .union(progress.values.filter { $0.answerCount > 0 }.map { $0.id.packID })
        .union(events.compactMap(\.packID))
      let hasOtherMaterial = dataPackIDs.contains { $0 != currentPackID }
      availableScopes = hasOtherMaterial
        ? [.pack(currentPackID), .allMaterials]
        : [.pack(currentPackID)]
      if !availableScopes.contains(scope) { scope = .pack(currentPackID) }
      try rebuild(now: Date())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func selectScope(_ value: LearningReportScope) {
    guard availableScopes.contains(value) else { return }
    scope = value
    do { try rebuild(now: Date()) }
    catch { errorMessage = error.localizedDescription }
  }

  var shareText: String {
    guard let report else { return "ロックンスタディ 今週の学習レポート" }
    return LearningReportShareService().text(for: report, calendar: calendar)
  }

  private func rebuild(now: Date) throws {
    guard let snapshot else { return }
    report = try LearningReportService(providers: providers).makeReport(
      snapshot: snapshot,
      scope: scope,
      now: now,
      calendar: calendar
    )
  }
}
