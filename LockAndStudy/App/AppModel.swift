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
  @Published var activeExperience: ActiveStudyExperience?
  @Published var isMaterialSelectionPresented = false
  @Published var unlockChallenge: ExperienceUnlockBundleSnapshot?
  @Published private(set) var records: [LearningEvent] = []
  @Published var alertMessage: String?
  @Published var isBusy = false

  let dependencies: DependencyContainer
  let experienceRegistry: StudyExperienceRegistry
  private var completedStudySessions: Set<UUID> = []
  private var startTask: Task<Void, Never>?

  init(dependencies: DependencyContainer? = nil) {
    let defaults = LockAndStudySharedConstants.defaults
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestResetData") {
        defaults.removePersistentDomain(forName: LockAndStudySharedConstants.appGroupID)
      }
    #endif
    self.dependencies = dependencies ?? DependencyContainer()
    experienceRegistry = .standard()
    if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") {
      defaults.removeObject(forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    }
    if ProcessInfo.processInfo.arguments.contains("-SkipOnboarding") {
      defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
      defaults.set(true, forKey: "lockandstudy.experience.vocabulary.first-run.completed")
      defaults.set(true, forKey: "lockandstudy.experience.takken.first-run.completed")
    }
    onboardingCompleted = defaults.bool(forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    selectedPackID = .init(
      rawValue: defaults.string(forKey: LockAndStudySharedConstants.Key.selectedPackID)
        ?? "english3000.v1")
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestSelectedTakken") {
        selectedPackID = "takken2026.v1"
      }
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestStartInLibrary") {
        selectedTab = .library
      }
    #endif
  }

  func start() async {
    if let startTask {
      await startTask.value
      return
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performStart()
    }
    startTask = task
    await task.value
    startTask = nil
  }

  private func performStart() async {
    isBusy = true
    do {
      manifests = try await dependencies.content.releasedManifests()
      if !manifests.contains(where: { $0.id == selectedPackID }), let first = manifests.first {
        selectedPackID = first.id
      }
      await dependencies.lockController.refreshLockState()
      await recoverLegacyOnboardingLockIfNeeded()
      if onboardingCompleted { ensureSelectedExperienceOpen() }
      await dependencies.commerce.loadProducts()
      await dependencies.commerce.refreshEntitlements()
      records = (try? await dependencies.learning.events()) ?? []
      if onboardingCompleted {
        if let experienceBundle = try await dependencies.learning.loadExperienceUnlockBundle() {
          if experienceBundle.isAnswering(at: Date()) {
            unlockChallenge = experienceBundle
          } else if experienceBundle.isComplete && experienceBundle.completionState != .completed
            && experienceBundle.completionState != .aborted
          {
            await completeUnlockChallenge()
          } else if experienceBundle.completionState == .completed
            || experienceBundle.completionState == .aborted
          {
            try await dependencies.learning.saveExperienceUnlockBundle(nil)
          } else if experienceBundle.challenge.expiresAt <= Date() {
            var expiredBundle = experienceBundle
            try await expireUnlockBundle(
              &expiredBundle, reason: "challenge-expired-during-recovery")
          }
        } else if let restored = try? await dependencies.learning.loadUnlockBundle(now: Date()),
          let manifest = manifests.first(where: { $0.id == restored.access.packID })
        {
          studySession = .init(
            id: restored.id, packID: manifest.id, packTitle: manifest.title, mode: .unlock,
            prompts: restored.prompts, bundleID: restored.id)
        } else if let request = PendingUnlockRequestCoordinator().consumeIfEligible(
          isLockEnabled: dependencies.lockController.isLockEnabled,
          isAuthorized: dependencies.lockController.isAuthorized,
          hasSelection: dependencies.lockController.hasSelection,
          unlockUntil: dependencies.lockController.unlockUntil, now: Date())
        {
          await beginUnlockStudy(requestID: request.id)
        }
      }
    } catch { alertMessage = error.localizedDescription }
    isBusy = false
  }

  func finishOnboarding(selectedPack: StudyPackID, pace: AccessPacePreset, review: ReviewLoadPreset)
    async throws
  {
    guard dependencies.lockController.isAuthorized else {
      throw LockControllerError.authorizationRequired
    }
    guard dependencies.lockController.hasSelection else {
      throw LockControllerError.selectionRequired
    }
    var policy = dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
    policy.accessPacePreset = pace
    policy.reviewLoadPreset = review
    policy.updatedAt = Date()
    dependencies.policyStore.savePolicy(policy)

    try await dependencies.lockController.setLockEnabled(true)
    guard dependencies.lockController.isLockEnabled else { throw LockControllerError.unavailable }

    selectedPackID = selectedPack
    let defaults = LockAndStudySharedConstants.defaults
    defaults.set(selectedPack.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    onboardingCompleted = true
    openExperience(packID: selectedPack, requiresFirstRun: true)
  }

  func choosePack(_ id: StudyPackID) {
    selectedPackID = id
    LockAndStudySharedConstants.defaults.set(
      id.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
  }

  func presentMaterialSelection() {
    isMaterialSelectionPresented = true
  }

  func selectStudyMaterial(_ id: StudyPackID) {
    guard manifests.contains(where: { $0.id == id }) else {
      alertMessage = "この教材は現在利用できません。"
      return
    }
    choosePack(id)
    openExperience(packID: id, requiresFirstRun: true)
    isMaterialSelectionPresented = false
  }

  func ensureSelectedExperienceOpen() {
    guard onboardingCompleted,
      manifests.contains(where: { $0.id == selectedPackID }),
      activeExperience?.packID != selectedPackID
    else { return }
    openExperience(packID: selectedPackID, requiresFirstRun: true)
  }

  private func recoverLegacyOnboardingLockIfNeeded() async {
    let lock = dependencies.lockController
    let lifecycle = dependencies.policyStore.loadPolicy()?.lifecycleState ?? .notConfigured
    guard OnboardingLockActivationPlanner().shouldActivate(
      onboardingCompleted: onboardingCompleted,
      isAuthorized: lock.isAuthorized,
      hasSelection: lock.hasSelection,
      isLockEnabled: lock.isLockEnabled,
      lifecycleState: lifecycle
    ) else { return }
    do {
      try await lock.setLockEnabled(true)
    } catch {
      alertMessage = "初期設定のロックを開始できませんでした。設定からScreen Timeの許可と対象を確認してください。\n\(error.localizedDescription)"
    }
  }

  func openExperience(
    packID: StudyPackID,
    destination: StudyExperienceDestination = .home,
    requiresFirstRun: Bool = false
  ) {
    guard let factory = experienceRegistry.factory(for: packID) else {
      alertMessage = "この教材の学習体験を読み込めません。"
      return
    }
    activeExperience = .init(
      experienceID: factory.descriptor.id,
      packID: packID,
      destination: destination,
      requiresFirstRun: requiresFirstRun
    )
  }

  func closeExperience() { activeExperience = nil }

  func experienceContext(for presentation: ActiveStudyExperience) -> StudyExperienceContext? {
    guard let manifest = manifests.first(where: { $0.id == presentation.packID }) else {
      return nil
    }
    return .init(
      manifest: manifest,
      dependencies: dependencies,
      destination: presentation.destination,
      openMaterialSelection: { [weak self] in self?.presentMaterialSelection() },
      beginUnlockStudy: { [weak self] in
        guard let self else { return }
        await self.beginUnlockStudy(packID: presentation.packID)
      },
      completeFirstRun: {}
    )
  }

  func beginPractice(packID: StudyPackID, mode: StudyMode = .practice) async {
    guard let manifest = manifests.first(where: { $0.id == packID }) else { return }
    do {
      let all = try await dependencies.content.prompts(for: packID)
      let accessible = all.filter {
        ContentAccessService().decision(
          for: $0, manifest: manifest, entitlement: dependencies.commerce.entitlement
        ).isAllowed
      }
      guard !accessible.isEmpty else {
        alertMessage = "利用できる無料サンプルがありません。"
        return
      }
      let progress = (try? await dependencies.learning.allProgress()) ?? [:]
      let ordered = accessible.sorted {
        let lhs = progress[$0.id.storageKey]?.answerCount ?? 0
        let rhs = progress[$1.id.storageKey]?.answerCount ?? 0
        return lhs == rhs ? $0.itemID.rawValue < $1.itemID.rawValue : lhs < rhs
      }
      let sessionID = UUID()
      studySession = .init(
        id: sessionID, packID: packID, packTitle: manifest.title, mode: mode,
        prompts: Array(ordered.prefix(10)), bundleID: nil)
      try? await dependencies.learning.record(
        .init(kind: .studyStarted, packID: packID, sessionID: sessionID))
    } catch { alertMessage = error.localizedDescription }
  }

  func beginUnlockStudy(packID: StudyPackID? = nil, requestID: UUID = UUID()) async {
    let requestedPackID = packID ?? selectedPackID
    guard let manifest = manifests.first(where: { $0.id == requestedPackID }) ?? manifests.first
    else { return }
    do {
      let progress = try await dependencies.learning.allProgress()
      let now = Date()
      let policy = dependencies.policyStore.loadPolicy() ?? .initial(now: now)
      let request = UnlockChallengeRequest(
        requestID: requestID,
        policy: policy,
        manifest: manifest,
        entitlement: dependencies.commerce.entitlement,
        progress: progress,
        learning: dependencies.learning,
        now: now
      )
      let challenge: UnlockChallengeSnapshot
      if let factory = experienceRegistry.factory(for: manifest.id) {
        do {
          challenge = try await factory.unlockChallengeProvider.makeUnlockChallenge(
            packID: manifest.id, request: request)
        } catch {
          challenge = try await SafeFallbackUnlockChallengeProvider().makeUnlockChallenge(
            packID: manifest.id, request: request)
        }
      } else {
        challenge = try await SafeFallbackUnlockChallengeProvider().makeUnlockChallenge(
          packID: manifest.id, request: request)
      }
      let bundle = ExperienceUnlockBundleSnapshot(
        schemaVersion: 2,
        challenge: challenge,
        completedQuestionIDs: [],
        completionState: .answering,
        completionEventID: UUID(),
        createdUnlockSessionID: nil,
        abortReason: nil
      )
      try await dependencies.learning.saveExperienceUnlockBundle(bundle)
      try await dependencies.learning.record(
        .init(
          kind: .unlockChallengeStarted, occurredAt: now, packID: manifest.id, sessionID: bundle.id)
      )
      unlockChallenge = bundle
    } catch {
      alertMessage = "解除学習を準備できませんでした。無料教材を確認して再試行してください。\n\(error.localizedDescription)"
    }
  }

  func submitUnlockAnswer(
    question: UnlockQuestionSnapshot,
    selectedChoiceID: Int,
    feedback: StudyFeedbackPlan
  ) async -> UnlockAnswerSubmissionResult {
    do {
      guard var bundle = try await dependencies.learning.loadExperienceUnlockBundle(),
        bundle.completionState == .answering,
        bundle.challenge.questions.contains(where: { $0.id == question.id })
      else { return .failed("解除問題の状態を確認できませんでした。もう一度やり直してください。") }
      guard Date() < bundle.challenge.expiresAt else {
        try await expireUnlockBundle(&bundle, reason: "challenge-expired-before-submission")
        return .expired
      }
      let record = answerRecord(
        for: question,
        selectedChoiceID: selectedChoiceID,
        feedback: feedback,
        bundle: bundle
      )
      _ = try await dependencies.learning.recordUnique(record)
      if selectedChoiceID == question.correctChoiceID {
        guard Date() < bundle.challenge.expiresAt else {
          try await expireUnlockBundle(&bundle, reason: "challenge-expired-after-answer")
          return .expired
        }
        bundle.completedQuestionIDs.insert(question.id)
        try await dependencies.learning.saveExperienceUnlockBundle(bundle)
        unlockChallenge = bundle
      }
      records = try await dependencies.learning.events()
      return selectedChoiceID == question.correctChoiceID ? .recordedCorrect : .recordedIncorrect
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  func completeUnlockChallenge() async {
    guard var bundle = try? await dependencies.learning.loadExperienceUnlockBundle(),
      bundle.isComplete
    else { return }
    if Date() >= bundle.challenge.expiresAt {
      do { try await expireUnlockBundle(&bundle, reason: "challenge-expired-before-unlock") }
      catch { alertMessage = error.localizedDescription }
      return
    }
    do {
      if bundle.completionState == .answering {
        guard Date() < bundle.challenge.expiresAt else {
          try await expireUnlockBundle(&bundle, reason: "challenge-expired-before-session")
          return
        }
        if dependencies.lockController.isLockEnabled {
          let session = try await dependencies.lockController.beginUnlockSession(
            kind: .earnedByStudy,
            duration: bundle.challenge.pace.unlockDuration,
            reasonCode: "bundle:\(bundle.id.uuidString)"
          )
          bundle.createdUnlockSessionID = session.id
        }
        bundle.completionState = .sessionCreated
        try await dependencies.learning.saveExperienceUnlockBundle(bundle)
      }
      if bundle.completionState == .sessionCreated {
        try await dependencies.learning.record(
          .init(
            id: bundle.completionEventID,
            kind: .unlockSuccess,
            packID: bundle.challenge.packID,
            sessionID: bundle.id
          ))
        bundle.completionState = .eventRecorded
        try await dependencies.learning.saveExperienceUnlockBundle(bundle)
      }
      if bundle.completionState == .eventRecorded {
        var completionWarning: String?
        if let manifest = manifests.first(where: { $0.id == bundle.challenge.packID }),
          let factory = experienceRegistry.factory(for: bundle.challenge.experienceID)
        {
          do {
            try await factory.handleUnlockCompletion(.init(
              bundle: bundle,
              manifest: manifest,
              dependencies: dependencies,
              now: Date()
            ))
            dependencies.learningRevision.bump()
          } catch {
            if bundle.challenge.experienceID == .vocabulary {
              try? await dependencies.learning.saveVocabularyPendingPreview(nil)
            }
            completionWarning = "ロック解除は完了しましたが、次回予習を保存できませんでした。\n\(error.localizedDescription)"
          }
        }
        bundle.completionState = .completed
        try await dependencies.learning.saveExperienceUnlockBundle(bundle)
        try await dependencies.learning.saveExperienceUnlockBundle(nil)
        if let completionWarning { alertMessage = completionWarning }
      }
      unlockChallenge = nil
      records = try await dependencies.learning.events()
    } catch { alertMessage = error.localizedDescription }
  }

  func unlockViewContext(for bundle: ExperienceUnlockBundleSnapshot) -> UnlockChallengeViewContext {
    .init(
      bundle: bundle,
      submit: { [weak self] question, choiceID, feedback in
        await self?.submitUnlockAnswer(
          question: question, selectedChoiceID: choiceID, feedback: feedback)
          ?? .failed("解除問題を送信できませんでした。")
      },
      complete: { [weak self] in await self?.completeUnlockChallenge() }
    )
  }

  func recordAnswer(
    item: StudyPrompt, selectedChoiceID: Int, mode: StudyMode, sessionID: UUID,
    feedback: StudyFeedbackPlan
  ) async {
    let answer = StudyAnswerRecord(
      prompt: item, selectedChoiceID: selectedChoiceID, answeredAt: Date(), mode: mode,
      sessionID: sessionID, feedbackPlan: feedback)
    do {
      try await dependencies.learning.record(answer)
      records = try await dependencies.learning.events()
    } catch { alertMessage = error.localizedDescription }
  }

  func markUnlockUnitComplete(itemID: StudyItemID, bundleID: UUID) async {
    guard var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()),
      bundle.id == bundleID
    else { return }
    if !bundle.completedItemIDs.contains(itemID) { bundle.completedItemIDs.append(itemID) }
    try? await dependencies.learning.saveUnlockBundle(bundle)
  }

  func completeStudySession(_ presentation: StudySessionPresentation) async {
    guard completedStudySessions.insert(presentation.id).inserted else { return }
    if presentation.mode == .unlock, let bundleID = presentation.bundleID,
      var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()),
      bundle.id == bundleID, bundle.isComplete
    {
      do {
        if dependencies.lockController.isLockEnabled {
          let session = try await dependencies.lockController.beginUnlockSession(
            kind: .earnedByStudy, duration: bundle.pace.unlockDuration, reasonCode: nil)
          bundle.createdUnlockSessionID = session.id
        }
        try await dependencies.learning.record(
          .init(kind: .unlockSuccess, packID: presentation.packID, sessionID: presentation.id))
        try await dependencies.learning.saveUnlockBundle(nil)
      } catch {
        completedStudySessions.remove(presentation.id)
        alertMessage = error.localizedDescription
        return
      }
    }
    studySession = nil
  }

  func emergencyUnlock(reason: EmergencyUnlockReason) async -> Bool {
    let now = Date()
    let policy = EmergencyUnlockPolicy()
    guard dependencies.emergencyStore.canUse(at: now, policy: policy) else {
      alertMessage = "緊急解除は直近24時間に使用済みです。"
      return false
    }
    do {
      await abortActiveUnlock(reason: "emergency-unlock")
      _ = try await dependencies.lockController.beginUnlockSession(
        kind: .emergency, duration: policy.unlockDuration, reasonCode: reason.rawValue)
      dependencies.emergencyStore.append(reason: reason, at: now)
      try? await dependencies.learning.record(
        .init(kind: .emergencyUnlock, occurredAt: now, detailCode: reason.rawValue))
      return true
    } catch {
      alertMessage = error.localizedDescription
      return false
    }
  }

  func exportLearningData() async -> URL? {
    do { return try await dependencies.learning.exportJSON() } catch {
      alertMessage = error.localizedDescription
      return nil
    }
  }
  func deleteLearningHistory() async {
    do {
      try await dependencies.learning.deleteLearningHistory()
      records = []
      dependencies.learningRevision.bump()
    } catch { alertMessage = error.localizedDescription }
  }

  func abortActiveUnlock(reason: String) async {
    if var experienceBundle = try? await dependencies.learning.loadExperienceUnlockBundle() {
      experienceBundle.abortReason = reason
      experienceBundle.completionState = .aborted
      try? await dependencies.learning.saveExperienceUnlockBundle(experienceBundle)
    }
    unlockChallenge = nil
    if var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()) {
      bundle.abortReason = reason
      try? await dependencies.learning.saveUnlockBundle(bundle)
    }
    if studySession?.mode == .unlock { studySession = nil }
  }

  private func answerRecord(
    for question: UnlockQuestionSnapshot,
    selectedChoiceID: Int,
    feedback: StudyFeedbackPlan,
    bundle: ExperienceUnlockBundleSnapshot
  ) -> StudyAnswerRecord {
    let submissionID =
      "unlock::\(bundle.id.uuidString)::\(question.id.rawValue)::\(selectedChoiceID)"
    switch question {
    case .vocabulary(let value):
      return .init(
        submissionID: submissionID, experienceID: .vocabulary, packID: bundle.challenge.packID,
        moduleType: .vocabulary, itemID: value.id, prompt: value.prompt, choices: value.choices,
        selectedChoiceID: selectedChoiceID, correctChoiceID: value.correctChoiceID,
        shortExplanation: value.explanation,
        longExplanation: "\(value.explanation)\n\(value.exampleEnglish)\n\(value.exampleJapanese)",
        sourceNote: nil, category: value.levelCode, subcategory: nil,
        contentVersion: value.contentVersion, questionVersion: 1, examYear: nil, lawBasisDate: nil,
        answeredAt: Date(), mode: .unlock, sessionID: bundle.id, feedbackPlan: feedback
      )
    case .takken(let value):
      return .init(
        submissionID: submissionID, experienceID: .takken, packID: bundle.challenge.packID,
        moduleType: .takken, itemID: value.id, prompt: value.prompt, choices: value.choices,
        selectedChoiceID: selectedChoiceID, correctChoiceID: value.correctChoiceID,
        shortExplanation: value.shortExplanation, longExplanation: value.longExplanation,
        sourceNote: value.sourceNote, category: value.category, subcategory: value.subCategory,
        contentVersion: value.contentVersion, questionVersion: value.questionVersion,
        examYear: value.examYear, lawBasisDate: value.lawBasisDate,
        answeredAt: Date(), mode: .unlock, sessionID: bundle.id, feedbackPlan: feedback,
        difficulty: value.difficulty, questionFormat: value.format, keyPoint: value.keyPoint
      )
    case .safeFallback(let value):
      return .init(
        submissionID: submissionID, experienceID: .safeFallback, packID: bundle.challenge.packID,
        moduleType: .vocabulary, itemID: value.id, prompt: value.prompt, choices: value.choices,
        selectedChoiceID: selectedChoiceID, correctChoiceID: value.correctChoiceID,
        shortExplanation: value.explanation, longExplanation: value.explanation,
        sourceNote: "built-in-safe-fallback", category: "安全な無料問題", subcategory: nil,
        contentVersion: "built-in-v1", questionVersion: 1, examYear: nil, lawBasisDate: nil,
        answeredAt: Date(), mode: .unlock, sessionID: bundle.id, feedbackPlan: feedback
      )
    }
  }

  private func expireUnlockBundle(
    _ bundle: inout ExperienceUnlockBundleSnapshot,
    reason: String
  ) async throws {
    bundle.abortReason = reason
    bundle.completionState = .aborted
    try await dependencies.learning.saveExperienceUnlockBundle(bundle)
    unlockChallenge = nil
    if reason.hasPrefix("challenge-expired") {
      alertMessage = "解除問題の有効時間が終了しました。新しい問題でやり直してください。"
    }
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
