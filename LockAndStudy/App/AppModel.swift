import Combine
import FamilyControls
import Foundation

enum UnlockRecoveryReason: String, Equatable, Sendable {
  case manifestMissing = "recovery-manifest-missing"
  case manifestPackMismatch = "recovery-manifest-pack-mismatch"
  case manifestUnavailable = "recovery-manifest-unavailable"
  case experienceMismatch = "recovery-experience-mismatch"
  case runtimeMissing = "recovery-runtime-missing"
  case payloadSchemaUnsupported = "recovery-payload-schema-unsupported"
  case contentVersionIncompatible = "recovery-content-version-incompatible"
  case payloadRestoreFailed = "recovery-payload-restore-failed"
  case completionStateInvalid = "recovery-completion-state-invalid"
}

struct UnlockRecoveryPresentation: Identifiable, Equatable, Sendable {
  let id: UUID
  let failedPackID: StudyPackID
  let origin: UnlockChallengeOrigin
  let reason: UnlockRecoveryReason

  init(envelope: UnlockChallengeSessionEnvelope, reason: UnlockRecoveryReason) {
    id = envelope.id
    failedPackID = envelope.packID
    origin = envelope.origin
    self.reason = reason
  }
}

@MainActor
struct UnlockSessionRestorationValidator {
  func failureReason(
    envelope: UnlockChallengeSessionEnvelope,
    manifest: StudyPackManifest?,
    runtime: (any StudyExperienceFactory)?,
    availability: PackAvailability?
  ) -> UnlockRecoveryReason? {
    guard let manifest else { return .manifestMissing }
    guard manifest.id == envelope.packID else { return .manifestPackMismatch }
    guard availability?.canOpen == true else { return .manifestUnavailable }
    guard let runtime else { return .runtimeMissing }
    guard runtime.experienceID.normalizedTemplateID == envelope.experienceID.normalizedTemplateID
    else { return .experienceMismatch }
    let usesSafeFallback = envelope.experienceID.normalizedTemplateID == .safeFallbackV1
    if !usesSafeFallback {
      guard manifest.experienceID.normalizedTemplateID == envelope.experienceID.normalizedTemplateID,
        runtime.validateCompatibility(with: manifest).isEmpty
      else { return .experienceMismatch }
    }
    guard runtime.supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID) else {
      return .payloadSchemaUnsupported
    }
    if usesSafeFallback {
      guard envelope.contentVersion == manifest.contentVersion
        || envelope.contentVersion == "built-in-v1"
      else { return .contentVersionIncompatible }
    } else if manifest.contentVersion != envelope.contentVersion {
      return .contentVersionIncompatible
    }
    return nil
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var onboardingCompleted: Bool
  @Published private(set) var manifests: [StudyPackManifest] = []
  @Published private(set) var categories: [StudyCategoryManifest] = []
  @Published private(set) var series: [StudySeriesManifest] = []
  @Published var selectedPackID: StudyPackID
  @Published var activeUnlockPackID: StudyPackID
  @Published private(set) var openedPackID: StudyPackID?
  @Published private(set) var lastStudiedPackID: StudyPackID?
  @Published var studySession: StudySessionPresentation?
  @Published var activeExperience: ActiveStudyExperience?
  @Published var isMaterialSelectionPresented = false
  @Published var unlockChallenge: UnlockChallengeSessionEnvelope?
  @Published private(set) var unlockRecovery: UnlockRecoveryPresentation?
  @Published private(set) var records: [LearningEvent] = []
  @Published var alertMessage: String?
  @Published var isBusy = false

  let dependencies: DependencyContainer
  let experienceRegistry: StudyExperienceRegistry
  private var completedStudySessions: Set<UUID> = []
  private var startTask: Task<Void, Never>?
  private let reviewClock = ContinuousClock()
  private var activeReviewStartedAt: ContinuousClock.Instant?

  init(
    dependencies: DependencyContainer? = nil,
    experienceRegistry: StudyExperienceRegistry? = nil
  ) {
    let defaults = LockAndStudySharedConstants.defaults
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestResetData") {
        defaults.removePersistentDomain(forName: LockAndStudySharedConstants.appGroupID)
      }
    #endif
    PlatformMigrationV9().run(defaults: defaults)
    self.dependencies = dependencies ?? DependencyContainer()
    self.experienceRegistry = experienceRegistry ?? .standard()
    if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") {
      defaults.removeObject(forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    }
    if ProcessInfo.processInfo.arguments.contains("-SkipOnboarding") {
      defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
      defaults.set(true, forKey: "lockandstudy.experience.vocabulary.first-run.completed")
      defaults.set(true, forKey: "lockandstudy.experience.takken.first-run.completed")
      defaults.set(true, forKey: "lockandstudy.pack.english3000.v1.first-run.completed.v1")
      defaults.set(true, forKey: "lockandstudy.pack.takken2026.v1.first-run.completed.v1")
      defaults.set(true, forKey: "lockandstudy.pack.english3000.v1.first-run.completed.v2")
      defaults.set(true, forKey: "lockandstudy.pack.takken2026.v1.first-run.completed.v2")
    }
    onboardingCompleted = defaults.bool(forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    let initialPackID = StudyPackID(
      rawValue: defaults.string(forKey: LockAndStudySharedConstants.Key.activeUnlockPackID)
        ?? defaults.string(forKey: LockAndStudySharedConstants.Key.selectedPackID)
        ?? "english3000.v1")
    selectedPackID = initialPackID
    activeUnlockPackID = initialPackID
    openedPackID = defaults.string(forKey: LockAndStudySharedConstants.Key.openedPackID).map {
      StudyPackID(rawValue: $0)
    }
    lastStudiedPackID = defaults.string(
      forKey: LockAndStudySharedConstants.Key.lastStudiedPackID
    ).map { StudyPackID(rawValue: $0) }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestSelectedTakken") {
        selectedPackID = "takken2026.v1"
        activeUnlockPackID = "takken2026.v1"
      }
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("-LockAndStudyUITestUnlock2")
        || arguments.contains("-LockAndStudyUITestUnlock3")
      {
        var policy = self.dependencies.policyStore.loadPolicy() ?? .initial(now: Date())
        policy.accessPacePreset =
          arguments.contains("-LockAndStudyUITestUnlock3")
          ? .extended30 : .bundled20
        self.dependencies.policyStore.savePolicy(policy)
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
      let catalog = try await dependencies.content.catalogSnapshot()
      categories = catalog.categories
        .filter { $0.isVisible && ($0.availableFrom.map { $0 <= Date() } ?? true) }
        .sorted { $0.sortOrder < $1.sortOrder }
      series = catalog.series.filter(\.isVisible).sorted { $0.sortOrder < $1.sortOrder }
      manifests = catalog.packs
      dependencies.commerce.configure(manifests: manifests)
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LockAndStudyUITestReportData") {
          try await seedReportUITestData()
        }
      #endif
      if !manifests.contains(where: { $0.id == selectedPackID && availability(for: $0).canOpen }),
        let first = manifests.first(where: { availability(for: $0).canOpen })
      {
        selectedPackID = first.id
        activeUnlockPackID = first.id
      }
      await dependencies.lockController.refreshLockState()
      await recoverLegacyOnboardingLockIfNeeded()
      if onboardingCompleted { ensureSelectedExperienceOpen() }
      await dependencies.commerce.loadProducts()
      await dependencies.commerce.refreshEntitlements()
      records = (try? await dependencies.learning.events()) ?? []
      if onboardingCompleted {
        if let envelope = try await dependencies.unlockSessions.restore(at: Date()) {
          await restoreUnlockChallenge(envelope)
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
          await beginUnlockStudy(requestID: request.id, origin: .shield)
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
    activeUnlockPackID = selectedPack
    let defaults = LockAndStudySharedConstants.defaults
    defaults.set(selectedPack.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
    defaults.set(selectedPack.rawValue, forKey: LockAndStudySharedConstants.Key.activeUnlockPackID)
    defaults.set(true, forKey: LockAndStudySharedConstants.Key.onboardingCompleted)
    onboardingCompleted = true
    openExperience(packID: selectedPack, requiresFirstRun: true)
  }

  func choosePack(_ id: StudyPackID) {
    guard let manifest = manifests.first(where: { $0.id == id }),
      availability(for: manifest).canOpen
    else {
      alertMessage =
        manifests.first(where: { $0.id == id }).map { availability(for: $0).message }
        ?? "この教材は現在利用できません。"
      return
    }
    selectedPackID = id
    activeUnlockPackID = id
    LockAndStudySharedConstants.defaults.set(
      id.rawValue, forKey: LockAndStudySharedConstants.Key.selectedPackID)
    LockAndStudySharedConstants.defaults.set(
      id.rawValue, forKey: LockAndStudySharedConstants.Key.activeUnlockPackID)
  }

  func presentMaterialSelection() {
    isMaterialSelectionPresented = true
  }

  func selectStudyMaterial(_ id: StudyPackID) {
    guard let manifest = manifests.first(where: { $0.id == id }) else {
      alertMessage = "この教材は現在利用できません。"
      return
    }
    guard availability(for: manifest).canOpen else {
      alertMessage = availability(for: manifest).message
      return
    }
    choosePack(id)
    openExperience(packID: id, requiresFirstRun: true)
    isMaterialSelectionPresented = false
  }

  func ensureSelectedExperienceOpen() {
    guard onboardingCompleted,
      manifests.contains(where: { $0.id == selectedPackID && availability(for: $0).canOpen }),
      activeExperience?.packID != selectedPackID
    else { return }
    openExperience(packID: selectedPackID, requiresFirstRun: true)
  }

  private func recoverLegacyOnboardingLockIfNeeded() async {
    let lock = dependencies.lockController
    let lifecycle = dependencies.policyStore.loadPolicy()?.lifecycleState ?? .notConfigured
    guard
      OnboardingLockActivationPlanner().shouldActivate(
        onboardingCompleted: onboardingCompleted,
        isAuthorized: lock.isAuthorized,
        hasSelection: lock.hasSelection,
        isLockEnabled: lock.isLockEnabled,
        lifecycleState: lifecycle
      )
    else { return }
    do {
      try await lock.setLockEnabled(true)
    } catch {
      alertMessage =
        "初期設定のロックを開始できませんでした。設定からScreen Timeの許可と対象を確認してください。\n\(error.localizedDescription)"
    }
  }

  func openExperience(
    packID: StudyPackID,
    destination: StudyExperienceDestination = .home,
    requiresFirstRun: Bool = false
  ) {
    guard let manifest = manifests.first(where: { $0.id == packID }) else {
      alertMessage = "この教材は現在利用できません。"
      return
    }
    let resolvedAvailability = availability(for: manifest)
    guard resolvedAvailability.canOpen else {
      alertMessage = resolvedAvailability.message
      return
    }
    guard let factory = experienceRegistry.factory(for: manifest) else {
      alertMessage = "この教材を使うにはアプリの更新が必要です。"
      return
    }
    activeExperience = .init(
      experienceID: factory.descriptor.id,
      packID: packID,
      destination: destination,
      requiresFirstRun: requiresFirstRun
    )
    openedPackID = packID
    LockAndStudySharedConstants.defaults.set(
      packID.rawValue, forKey: LockAndStudySharedConstants.Key.openedPackID)
  }

  func closeExperience() { activeExperience = nil }

  func experienceContext(for presentation: ActiveStudyExperience) -> StudyExperienceContext? {
    guard let manifest = manifests.first(where: { $0.id == presentation.packID }) else {
      return nil
    }
    return .init(
      manifest: manifest,
      dependencies: dependencies,
      reportProviders: experienceRegistry.reportProviders,
      destination: presentation.destination,
      openMaterialSelection: { [weak self] in self?.presentMaterialSelection() },
      beginUnlockStudy: { [weak self] in
        guard let self else { return }
        await self.beginUnlockStudy(packID: presentation.packID, origin: .manual)
      },
      completeFirstRun: {}
    )
  }

  func availability(for manifest: StudyPackManifest, now: Date = Date()) -> PackAvailability {
    let factory = experienceRegistry.factory(for: manifest)
    return PackAvailabilityResolver().resolve(
      manifest: manifest,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
      now: now,
      isOwned: dependencies.commerce.entitlement.ownedPacks.contains { $0.packID == manifest.id },
      supportsExperience: factory != nil
        && (factory?.validateCompatibility(with: manifest).isEmpty == true))
  }

  func successorManifest(for packID: StudyPackID) -> StudyPackManifest? {
    manifests.first {
      $0.supersedesPackID == packID && availability(for: $0).canOpen
    }
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
      lastStudiedPackID = packID
      LockAndStudySharedConstants.defaults.set(
        packID.rawValue, forKey: LockAndStudySharedConstants.Key.lastStudiedPackID)
      studySession = .init(
        id: sessionID, packID: packID, packTitle: manifest.title, mode: mode,
        prompts: Array(ordered.prefix(10)), bundleID: nil)
      try? await dependencies.learning.record(
        .init(kind: .studyStarted, packID: packID, sessionID: sessionID))
    } catch { alertMessage = error.localizedDescription }
  }

  func beginUnlockStudy(
    packID: StudyPackID? = nil,
    requestID: UUID = UUID(),
    origin: UnlockChallengeOrigin,
    forceSafeFallback: Bool = false
  ) async {
    let requestedPackID = packID ?? activeUnlockPackID
    do {
      let manifest: StudyPackManifest
      if forceSafeFallback {
        manifest = try SafeFallbackContentSource.builtInManifest()
      } else {
        guard let exactManifest = manifests.first(where: { $0.id == requestedPackID }) else {
          throw ContentRepositoryError.missing(requestedPackID.rawValue)
        }
        manifest = exactManifest
      }
      let progress = try await dependencies.learning.allProgress()
      let now = Date()
      let policy = dependencies.policyStore.loadPolicy() ?? .initial(now: now)
      let request = UnlockChallengeRequest(
        requestID: requestID,
        origin: origin,
        policy: policy,
        manifest: manifest,
        entitlement: dependencies.commerce.entitlement,
        progress: progress,
        learning: dependencies.learning,
        content: dependencies.content,
        now: now
      )
      let resolvedRuntime: any StudyExperienceFactory
      let payload: ExperienceSessionPayload
      if forceSafeFallback,
        let fallback = experienceRegistry.factory(forExperienceID: .safeFallbackV1)
      {
        payload = try await fallback.createSession(request: request)
        resolvedRuntime = fallback
      } else if let runtime = experienceRegistry.factory(for: manifest),
        runtime.validateCompatibility(with: manifest).isEmpty
      {
        do {
          payload = try await runtime.createSession(request: request)
          resolvedRuntime = runtime
        } catch {
          guard let fallback = experienceRegistry.factory(forExperienceID: .safeFallbackV1) else {
            throw error
          }
          payload = try await fallback.createSession(request: request)
          resolvedRuntime = fallback
        }
      } else {
        guard let fallback = experienceRegistry.factory(forExperienceID: .safeFallbackV1) else {
          throw ContentRepositoryError.unsupported
        }
        payload = try await fallback.createSession(request: request)
        resolvedRuntime = fallback
      }
      guard resolvedRuntime.supportedPayloadSchemaIDs.contains(payload.schemaID) else {
        throw ContentRepositoryError.invalid("解除payload schemaが一致しません")
      }
      let envelope = UnlockChallengeSessionEnvelope(
        schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
        id: UUID(),
        requestID: requestID,
        origin: origin,
        experienceID: resolvedRuntime.experienceID,
        packID: manifest.id,
        contentVersion: manifest.contentVersion,
        policyVersion: policy.policyVersion,
        createdAt: now,
        expiresAt: now.addingTimeInterval(UnlockChallengeSessionEnvelope.expirationInterval),
        completionState: .answering,
        completionEventID: UUID(),
        createdUnlockSessionID: nil,
        abortReason: nil,
        enginePayloadSchemaID: payload.schemaID,
        enginePayload: payload.data)
      try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
      try await dependencies.learning.record(
        .init(
          kind: .unlockChallengeStarted, occurredAt: now, packID: manifest.id,
          sessionID: envelope.id, unlockOrigin: origin)
      )
      activeReviewStartedAt = nil
      unlockRecovery = nil
      unlockChallenge = envelope
    } catch {
      alertMessage = "解除学習を準備できませんでした。無料教材を確認して再試行してください。\n\(error.localizedDescription)"
    }
  }

  func submitUnlockAnswer(_ answer: StudyAnswerValue) async -> UnlockAnswerSubmissionResult {
    do {
      guard var envelope = try await dependencies.learning.loadUnlockSessionEnvelope(),
        envelope.completionState == .answering,
        let runtime = experienceRegistry.factory(forExperienceID: envelope.experienceID),
        runtime.supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID)
      else { return .failed("解除問題の状態を確認できませんでした。もう一度やり直してください。") }
      guard Date() < envelope.expiresAt else {
        await abortActiveUnlock(reason: "challenge-expired-before-submission")
        return .expired
      }
      if let startedAt = activeReviewStartedAt {
        activeReviewStartedAt = nil
        let tick = try await runtime.activeReviewTick(
          seconds: elapsedSeconds(since: startedAt), envelope: envelope)
        guard tick.payload.schemaID == envelope.enginePayloadSchemaID else {
          await abortActiveUnlock(reason: "experience-payload-schema-changed")
          return .failed("解除問題の状態を更新できませんでした。")
        }
        envelope.enginePayload = tick.payload.data
      }
      let transition = try await runtime.acceptAnswer(
        answer, envelope: envelope, dependencies: dependencies)
      guard transition.payload.schemaID == envelope.enginePayloadSchemaID else {
        await abortActiveUnlock(reason: "experience-payload-schema-changed")
        return .failed("解除問題の状態を更新できませんでした。")
      }
      envelope.enginePayload = transition.payload.data
      try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
      unlockChallenge = envelope
      records = try await dependencies.learning.events()
      return transition.submissionResult ?? .failed("学習エンジンから回答結果が返されませんでした。")
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  func updateUnlockReviewExposure(isActive: Bool) async -> UnlockReviewExposureResult {
    do {
      guard var envelope = try await dependencies.learning.loadUnlockSessionEnvelope(),
        envelope.completionState == .answering,
        let runtime = experienceRegistry.factory(forExperienceID: envelope.experienceID),
        runtime.supportedPayloadSchemaIDs.contains(envelope.enginePayloadSchemaID)
      else { return .failed("解除問題の状態を確認できませんでした。") }
      let now = Date()
      guard now < envelope.expiresAt else {
        await abortActiveUnlock(reason: "challenge-expired-during-review")
        return .expired
      }
      let elapsed = activeReviewStartedAt.map(elapsedSeconds) ?? 0
      activeReviewStartedAt = isActive ? reviewClock.now : nil
      let transition = try await runtime.activeReviewTick(seconds: elapsed, envelope: envelope)
      guard transition.payload.schemaID == envelope.enginePayloadSchemaID else {
        await abortActiveUnlock(reason: "experience-payload-schema-changed")
        return .failed("解説確認時間を更新できませんでした。")
      }
      envelope.enginePayload = transition.payload.data
      try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
      unlockChallenge = envelope
      return transition.reviewResult ?? .failed("解説確認時間を更新できませんでした。")
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  func completeUnlockChallenge() async {
    activeReviewStartedAt = nil
    guard var envelope = try? await dependencies.learning.loadUnlockSessionEnvelope() else {
      return
    }
    await loadCatalogForUnlockValidationIfNeeded()
    if let failure = unlockRecoveryReason(for: envelope) {
      await failClosedUnlockPresentation(envelope, reason: failure)
      return
    }
    guard let runtime = experienceRegistry.factory(forExperienceID: envelope.experienceID),
      let proof = try? runtime.completionProof(envelope: envelope)
    else {
      await failClosedUnlockPresentation(envelope, reason: .payloadRestoreFailed)
      return
    }
    if Date() >= envelope.expiresAt {
      await abortActiveUnlock(reason: "challenge-expired-before-unlock")
      return
    }
    do {
      let proofDecision = try await dependencies.unlockSessions.acceptCompletionProof(
        proof,
        now: Date())
      switch proofDecision {
      case .accepted, .resuming:
        break
      case .alreadyCompleted:
        try await dependencies.learning.saveUnlockSessionEnvelope(nil)
        try await LegacyUnlockBundleMigration().clearPersistedBundle(
          in: dependencies.learning)
        unlockChallenge = nil
        return
      case .rejected(let reason):
        await abortActiveUnlock(reason: reason)
        return
      }
      guard let coordinated = try await dependencies.learning.loadUnlockSessionEnvelope() else {
        await abortActiveUnlock(reason: "unlock-session-missing-after-proof")
        return
      }
      envelope = coordinated
      if envelope.completionState == .proofAccepted {
        guard Date() < envelope.expiresAt else {
          await abortActiveUnlock(reason: "challenge-expired-before-session")
          return
        }
        if dependencies.lockController.isLockEnabled {
          let session = try await dependencies.lockController.beginUnlockSession(
            kind: .earnedByStudy,
            duration: proof.unlockDuration
              ?? (dependencies.policyStore.loadPolicy()?.accessPacePreset.unlockDuration ?? 300),
            reasonCode: "envelope:\(envelope.id.uuidString)"
          )
          envelope.createdUnlockSessionID = session.id
        }
        envelope.completionState = .sessionCreated
        try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
      }
      if envelope.completionState == .sessionCreated {
        let completionKind: LearningEventKind =
          envelope.createdUnlockSessionID == nil ? .unlockChallengeCompleted : .unlockSuccess
        try await dependencies.learning.record(
          .init(
            id: envelope.completionEventID,
            kind: completionKind,
            packID: envelope.packID,
            sessionID: envelope.id,
            unlockOrigin: envelope.origin
          ))
        envelope.completionState = .eventRecorded
        try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
      }
      if envelope.completionState == .eventRecorded {
        var completionWarning: String?
        if let manifest = manifests.first(where: { $0.id == envelope.packID }) {
          do {
            try await runtime.handleUnlockCompletion(
              .init(
                envelope: envelope,
                manifest: manifest,
                dependencies: dependencies,
                now: Date()
              ))
            dependencies.learningRevision.bump()
          } catch {
            await runtime.clearTransientState(
              packID: envelope.packID, dependencies: dependencies)
            completionWarning = "ロック解除は完了しましたが、次回予習を保存できませんでした。\n\(error.localizedDescription)"
          }
        }
        envelope.completionState = .completed
        try await dependencies.learning.saveUnlockSessionEnvelope(envelope)
        try await dependencies.learning.saveUnlockSessionEnvelope(nil)
        try await LegacyUnlockBundleMigration().clearPersistedBundle(
          in: dependencies.learning)
        if let completionWarning { alertMessage = completionWarning }
      }
      unlockChallenge = nil
      records = try await dependencies.learning.events()
    } catch { alertMessage = error.localizedDescription }
  }

  func unlockViewContext(
    for envelope: UnlockChallengeSessionEnvelope
  ) -> ExperienceChallengeViewContext? {
    guard unlockRecoveryReason(for: envelope) == nil,
      let manifest = unlockManifest(for: envelope)
    else { return nil }
    return ExperienceChallengeViewContext(
      manifest: manifest,
      submit: { [weak self] answer in
        await self?.submitUnlockAnswer(answer)
          ?? .failed("解除問題を送信できませんでした。")
      },
      updateReviewExposure: { [weak self] isActive in
        await self?.updateUnlockReviewExposure(isActive: isActive)
          ?? .failed("解説確認時間を保存できませんでした。")
      },
      restart: { [weak self] in
        guard let self else { return }
        await self.abortActiveUnlock(reason: "challenge-restarted")
        await self.beginUnlockStudy(
          packID: envelope.packID,
          origin: envelope.origin)
      },
      complete: { [weak self] in await self?.completeUnlockChallenge() }
    )
  }

  func failClosedUnlockPresentation(
    _ envelope: UnlockChallengeSessionEnvelope,
    reason: UnlockRecoveryReason? = nil
  ) async {
    let resolvedReason = reason ?? unlockRecoveryReason(for: envelope) ?? .payloadRestoreFailed
    await abortActiveUnlock(reason: resolvedReason.rawValue)
    unlockRecovery = .init(envelope: envelope, reason: resolvedReason)
  }

  func beginSafeRecoveryStudy() async {
    guard let recovery = unlockRecovery else { return }
    await beginUnlockStudy(
      packID: "safe-fallback.v1",
      requestID: UUID(),
      origin: recovery.origin,
      forceSafeFallback: true)
  }

  private func restoreUnlockChallenge(_ envelope: UnlockChallengeSessionEnvelope) async {
    if let failure = unlockRecoveryReason(for: envelope) {
      await failClosedUnlockPresentation(envelope, reason: failure)
      return
    }
    guard let runtime = experienceRegistry.factory(forExperienceID: envelope.experienceID) else {
      await failClosedUnlockPresentation(envelope, reason: .runtimeMissing)
      return
    }
    do {
      let state = try runtime.restoreState(
        payload: envelope.enginePayload, schemaID: envelope.enginePayloadSchemaID)
      if state.isComplete {
        unlockChallenge = envelope
        await completeUnlockChallenge()
      } else if envelope.completionState == .answering {
        unlockChallenge = envelope
      } else {
        await failClosedUnlockPresentation(envelope, reason: .completionStateInvalid)
      }
    } catch {
      await failClosedUnlockPresentation(envelope, reason: .payloadRestoreFailed)
    }
  }

  private func unlockRecoveryReason(
    for envelope: UnlockChallengeSessionEnvelope
  ) -> UnlockRecoveryReason? {
    let manifest = unlockManifest(for: envelope)
    let runtime = experienceRegistry.factory(forExperienceID: envelope.experienceID)
    return UnlockSessionRestorationValidator().failureReason(
      envelope: envelope,
      manifest: manifest,
      runtime: runtime,
      availability: manifest.map { availability(for: $0) })
  }

  private func unlockManifest(
    for envelope: UnlockChallengeSessionEnvelope
  ) -> StudyPackManifest? {
    if let exact = manifests.first(where: { $0.id == envelope.packID }) { return exact }
    guard envelope.packID == "safe-fallback.v1" else { return nil }
    return try? SafeFallbackContentSource.builtInManifest()
  }

  private func loadCatalogForUnlockValidationIfNeeded() async {
    guard manifests.isEmpty else { return }
    guard let catalog = try? await dependencies.content.catalogSnapshot() else { return }
    categories = catalog.categories
    series = catalog.series
    manifests = catalog.packs
    dependencies.commerce.configure(manifests: manifests)
  }

  func recordAnswer(
    item: StudyPrompt, selectedChoiceID: Int, mode: StudyMode, sessionID: UUID,
    feedback: StudyFeedbackPlan
  ) async {
    do {
      let answeredAt = Date()
      let priorProgress = try await dependencies.learning.progress(for: item.id)
      let answer = StudyAnswerRecord(
        prompt: item, selectedChoiceID: selectedChoiceID, answeredAt: answeredAt, mode: mode,
        sessionID: sessionID, feedbackPlan: feedback, priorProgress: priorProgress)
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
        let completionKind: LearningEventKind =
          bundle.createdUnlockSessionID == nil ? .unlockChallengeCompleted : .unlockSuccess
        try await dependencies.learning.record(
          .init(
            kind: completionKind, packID: presentation.packID, sessionID: presentation.id,
            unlockOrigin: .legacyUnknown))
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
    activeReviewStartedAt = nil
    try? await dependencies.unlockSessions.abort(reason: reason)
    await LegacyUnlockBundleMigration().abortPersistedBundle(
      reason: reason, in: dependencies.learning)
    unlockChallenge = nil
    if var bundle = try? await dependencies.learning.loadUnlockBundle(now: Date()) {
      bundle.abortReason = reason
      try? await dependencies.learning.saveUnlockBundle(bundle)
    }
    if studySession?.mode == .unlock { studySession = nil }
  }

  private func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
    let components = start.duration(to: reviewClock.now).components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
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
