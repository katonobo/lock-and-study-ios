import Combine
import FamilyControls
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published var selectedTab: AppTab = .home
  @Published var onboardingCompleted: Bool
  @Published private(set) var manifests: [StudyPackManifest] = []
  @Published var selectedPackID: StudyPackID
  @Published var studySession: StudySessionPresentation?
  @Published private(set) var records: [LearningEvent] = []
  @Published var alertMessage: String?
  @Published var isBusy = false

  let dependencies: DependencyContainer
  private var completedStudySessions: Set<UUID> = []

  init(dependencies: DependencyContainer? = nil) {
    let defaults = LockAndStudySharedConstants.defaults
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestResetData") {
      defaults.removePersistentDomain(forName: LockAndStudySharedConstants.appGroupID)
    }
    #endif
    self.dependencies = dependencies ?? DependencyContainer()
    if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") { defaults.removeObject(forKey: LockAndStudySharedConstants.Key.onboardingCompleted) }
    if ProcessInfo.processInfo.arguments.contains("-SkipOnboarding") { defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted) }
    onboardingCompleted = defaults.bool(forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    selectedPackID = .init(rawValue: defaults.string(forKey: LockAndStudySharedConstants.Key.selectedPackID) ?? "english3000.v1")
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestStartInLibrary") { selectedTab = .library }
    #endif
  }

  func start() async {
    isBusy = true
    do {
      manifests = try await dependencies.content.releasedManifests()
      if !manifests.contains(where: { $0.id == selectedPackID }), let first = manifests.first { selectedPackID = first.id }
      await dependencies.commerce.loadProducts()
      await dependencies.commerce.refreshEntitlements()
      await dependencies.lockController.refreshLockState()
      records = (try? await dependencies.learning.events()) ?? []
      if onboardingCompleted {
        if let restored = try? await dependencies.learning.loadUnlockBundle(now: Date()), let manifest = manifests.first(where: { $0.id == restored.access.packID }) {
          studySession = .init(id: restored.id, packID: manifest.id, packTitle: manifest.title, mode: .unlock, prompts: restored.prompts, bundleID: restored.id)
        } else if let request = PendingUnlockRequestCoordinator().consumeIfEligible(
          isLockEnabled: dependencies.lockController.isLockEnabled, isAuthorized: dependencies.lockController.isAuthorized,
          hasSelection: dependencies.lockController.hasSelection, unlockUntil: dependencies.lockController.unlockUntil, now: Date()) {
          await beginUnlockStudy(requestID: request.id)
        }
      }
    } catch { alertMessage = error.localizedDescription }
    isBusy = false
  }

  func finishOnboarding(selectedPack: StudyPackID, pace: AccessPacePreset, review: ReviewLoadPreset) {
    selectedPackID = selectedPack
    let defaults = LockAndStudySharedConstants.defaults
    defaults.set(selectedPack.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    var policy = dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
    policy.accessPacePreset = pace; policy.reviewLoadPreset = review; policy.updatedAt = Date()
    dependencies.policyStore.savePolicy(policy)
    onboardingCompleted = true
  }

  func choosePack(_ id: StudyPackID) {
    selectedPackID = id
    LockAndStudySharedConstants.defaults.set(id.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
  }

  func beginPractice(packID: StudyPackID, mode: StudyMode = .practice) async {
    guard let manifest = manifests.first(where: { $0.id == packID }) else { return }
    do {
      let all = try await dependencies.content.prompts(for: packID)
      let accessible = all.filter { ContentAccessService().decision(for: $0, manifest: manifest, entitlement: dependencies.commerce.entitlement).isAllowed }
      guard !accessible.isEmpty else { alertMessage = "利用できる無料サンプルがありません。"; return }
      let progress = (try? await dependencies.learning.allProgress()) ?? [:]
      let ordered = accessible.sorted {
        let lhs = progress[$0.id.storageKey]?.answerCount ?? 0, rhs = progress[$1.id.storageKey]?.answerCount ?? 0
        return lhs == rhs ? $0.itemID.rawValue < $1.itemID.rawValue : lhs < rhs
      }
      let sessionID = UUID()
      studySession = .init(id: sessionID, packID: packID, packTitle: manifest.title, mode: mode, prompts: Array(ordered.prefix(10)), bundleID: nil)
      try? await dependencies.learning.record(.init(kind: .studyStarted, packID: packID, sessionID: sessionID))
    } catch { alertMessage = error.localizedDescription }
  }

  func beginUnlockStudy(requestID: UUID = UUID()) async {
    guard let manifest = manifests.first(where: { $0.id == selectedPackID }) ?? manifests.first else { return }
    do {
      let prompts = try await dependencies.content.prompts(for: manifest.id)
      let progress = try await dependencies.learning.allProgress()
      let now = Date()
      let due = Set(progress.values.filter { $0.dueAt.map { $0 <= now } ?? false }.map { $0.id.itemID })
      let policy = dependencies.policyStore.loadPolicy() ?? .initial(now: now)
      let bundle = try UnlockBundlePlanner().make(requestID: requestID, policy: policy, manifest: manifest, prompts: prompts,
                                                  entitlement: dependencies.commerce.entitlement, progress: progress, dueItemIDs: due, now: now)
      try await dependencies.learning.saveUnlockBundle(bundle)
      try? await dependencies.learning.record(.init(kind: .unlockChallengeStarted, occurredAt: now, packID: manifest.id, sessionID: bundle.id))
      studySession = .init(id: bundle.id, packID: manifest.id, packTitle: manifest.title, mode: .unlock, prompts: bundle.prompts, bundleID: bundle.id)
    } catch {
      alertMessage = "解除学習を準備できませんでした。無料教材を確認して再試行してください。\n\(error.localizedDescription)"
    }
  }

  func recordAnswer(item: StudyPrompt, selectedChoiceID: Int, mode: StudyMode, sessionID: UUID, feedback: StudyFeedbackPlan) async {
    let answer = StudyAnswerRecord(prompt: item, selectedChoiceID: selectedChoiceID, answeredAt: Date(), mode: mode, sessionID: sessionID, feedbackPlan: feedback)
    do { try await dependencies.learning.record(answer); records = try await dependencies.learning.events() }
    catch { alertMessage = error.localizedDescription }
  }

  func markUnlockUnitComplete(itemID: StudyItemID, bundleID: UUID) async {
    guard var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()), bundle.id == bundleID else { return }
    if !bundle.completedItemIDs.contains(itemID) { bundle.completedItemIDs.append(itemID) }
    try? await dependencies.learning.saveUnlockBundle(bundle)
  }

  func completeStudySession(_ presentation: StudySessionPresentation) async {
    guard completedStudySessions.insert(presentation.id).inserted else { return }
    if presentation.mode == .unlock, let bundleID = presentation.bundleID,
       var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()), bundle.id == bundleID, bundle.isComplete {
      do {
        if dependencies.lockController.isLockEnabled {
          let session = try await dependencies.lockController.beginUnlockSession(kind: .earnedByStudy, duration: bundle.pace.unlockDuration, reasonCode: nil)
          bundle.createdUnlockSessionID = session.id
        }
        try await dependencies.learning.record(.init(kind: .unlockSuccess, packID: presentation.packID, sessionID: presentation.id))
        try await dependencies.learning.saveUnlockBundle(nil)
      } catch { completedStudySessions.remove(presentation.id); alertMessage = error.localizedDescription; return }
    }
    studySession = nil
  }

  func emergencyUnlock(reason: EmergencyUnlockReason) async -> Bool {
    let now = Date(); let policy = EmergencyUnlockPolicy()
    guard dependencies.emergencyStore.canUse(at: now, policy: policy) else { alertMessage = "緊急解除は直近24時間に使用済みです。"; return false }
    do {
      await abortActiveUnlock(reason: "emergency-unlock")
      _ = try await dependencies.lockController.beginUnlockSession(kind: .emergency, duration: policy.unlockDuration, reasonCode: reason.rawValue)
      dependencies.emergencyStore.append(reason: reason, at: now)
      try? await dependencies.learning.record(.init(kind: .emergencyUnlock, occurredAt: now, detailCode: reason.rawValue))
      return true
    } catch { alertMessage = error.localizedDescription; return false }
  }

  func exportLearningData() async -> URL? { try? await dependencies.learning.exportJSON() }
  func deleteLearningHistory() async { try? await dependencies.learning.deleteLearningHistory(); records = [] }

  func abortActiveUnlock(reason: String) async {
    if var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()) {
      bundle.abortReason = reason
      try? await dependencies.learning.saveUnlockBundle(bundle)
    }
    if studySession?.mode == .unlock { studySession = nil }
  }

  func importLegacyData() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let migration = try LegacyMigrationService()
      let grants = try migration.importClaims(now: Date())
      dependencies.commerce.addLegacyGrants(grants)
      let progressCount: Int
      if let export = try migration.loadProgressExport() {
        progressCount = try await dependencies.learning.importLegacyProgress(export)
      } else {
        progressCount = 0
      }
      records = (try? await dependencies.learning.events()) ?? records
      if grants.isEmpty && progressCount == 0 {
        alertMessage = "未移行の旧アプリデータは見つかりませんでした。旧アプリ側で移行データを作成してから再試行してください。"
      } else {
        alertMessage = "旧アプリから購入権利\(grants.count)件、学習進捗\(progressCount)件を移行しました。"
      }
    } catch {
      alertMessage = "旧アプリの移行データを読み込めませんでした。\n\(error.localizedDescription)"
    }
  }
}
