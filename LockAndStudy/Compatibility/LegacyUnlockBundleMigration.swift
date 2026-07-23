import Foundation

@MainActor
extension AppModel {
  /// Compatibility bridge for unlock bundles persisted before platform v10.
  /// New UI and engines submit only `StudyAnswerValue` through the opaque runtime.
  func submitUnlockAnswer(
    question: UnlockQuestionSnapshot,
    selectedChoiceID: Int,
    feedback: StudyFeedbackPlan
  ) async -> UnlockAnswerSubmissionResult {
    let result = await submitUnlockAnswer(
      .choice(questionID: question.id.rawValue, choiceID: String(selectedChoiceID)))
    guard var legacy = try? await dependencies.learning.loadExperienceUnlockBundle() else {
      return result
    }
    let key = question.id.rawValue
    switch result {
    case .recordedCorrect:
      legacy.completedQuestionIDs.insert(question.id)
      var attempts = legacy.attemptCountsByQuestionID ?? [:]
      attempts[key] = max(1, attempts[key] ?? 1)
      legacy.attemptCountsByQuestionID = attempts
      legacy.clearReviewState(for: question.id)
    case .recordedIncorrect(let remaining, let attempt):
      var attempts = legacy.attemptCountsByQuestionID ?? [:]
      attempts[key] = attempt
      legacy.attemptCountsByQuestionID = attempts
      var review = legacy.reviewRemainingActiveSecondsByQuestionID ?? [:]
      review[key] = TimeInterval(remaining)
      legacy.reviewRemainingActiveSecondsByQuestionID = review
      var selections = legacy.lastSelectedChoiceIDByQuestionID ?? [:]
      selections[key] = selectedChoiceID
      legacy.lastSelectedChoiceIDByQuestionID = selections
    case .expired:
      legacy.completionState = .aborted
      legacy.abortReason = "challenge-expired-before-submission"
    case .failed:
      return result
    }
    do {
      try await dependencies.learning.saveExperienceUnlockBundle(legacy)
    } catch {
      return .failed(error.localizedDescription)
    }
    return result
  }
}

/// Read-only compatibility models for unlock sessions written before platform v10.
/// New sessions must be created by a `StudyExperienceSessionRuntime` and never by these types.
struct LegacyUnlockBundleMigration: Sendable {
  func clearPersistedBundle(in store: LearningDataStore) async throws {
    try await store.saveExperienceUnlockBundle(nil)
  }

  func abortPersistedBundle(reason: String, in store: LearningDataStore) async {
    guard var legacy = try? await store.loadExperienceUnlockBundle() else { return }
    legacy.completionState = .aborted
    legacy.abortReason = reason
    try? await store.saveExperienceUnlockBundle(legacy)
  }

  func migrate(
    _ source: ExperienceUnlockBundleSnapshot,
    at migrationDate: Date = Date()
  ) throws -> UnlockChallengeSessionEnvelope {
    var bundle = source
    _ = bundle.migrateLegacyReviewState(at: migrationDate)
    let templateID = bundle.challenge.experienceID.normalizedTemplateID
    let payload: ExperienceSessionPayload
    switch templateID {
    case .flashcardV1:
      payload = try flashcardPayload(bundle)
    case .certificationV1:
      payload = try certificationPayload(bundle)
    case .safeFallbackV1:
      payload = try safeFallbackPayload(bundle)
    default:
      throw ContentRepositoryError.invalid(
        "旧解除sessionのexperienceを移行できません: \(templateID.rawValue)")
    }
    return .init(
      schemaVersion: UnlockChallengeSessionEnvelope.currentSchemaVersion,
      id: bundle.id,
      requestID: bundle.challenge.requestID,
      origin: bundle.challenge.resolvedOrigin,
      experienceID: templateID,
      packID: bundle.challenge.packID,
      contentVersion: bundle.challenge.questions.first?.legacyContentVersion ?? "legacy",
      policyVersion: bundle.challenge.policyVersion,
      createdAt: bundle.challenge.createdAt,
      expiresAt: bundle.challenge.expiresAt,
      completionState: bundle.completionState,
      completionEventID: bundle.completionEventID,
      createdUnlockSessionID: bundle.createdUnlockSessionID,
      abortReason: bundle.abortReason,
      enginePayloadSchemaID: payload.schemaID,
      enginePayload: payload.data)
  }

  private func flashcardPayload(
    _ bundle: ExperienceUnlockBundleSnapshot
  ) throws -> ExperienceSessionPayload {
    let questions = try bundle.challenge.questions.map { snapshot -> FlashcardChallengeQuestion in
      guard case .vocabulary(let value) = snapshot else {
        throw ContentRepositoryError.invalid("旧flashcard sessionに異なる問題形式が含まれます")
      }
      return .init(
        id: value.id, front: value.word, prompt: value.prompt, choices: value.choices,
        correctChoiceID: value.correctChoiceID, explanation: value.explanation,
        primaryExample: value.exampleEnglish.isEmpty ? nil : value.exampleEnglish,
        secondaryExample: value.exampleJapanese.isEmpty ? nil : value.exampleJapanese,
        speechText: value.speechText.isEmpty ? nil : value.speechText,
        courseCode: value.levelCode, contentVersion: value.contentVersion,
        isFreeSample: value.isFreeSample)
    }
    let state = FlashcardUnlockSessionPayload(
      pace: bundle.challenge.pace,
      questions: questions,
      completedQuestionIDs: bundle.completedQuestionIDs,
      attemptCountsByQuestionID: bundle.attemptCountsByQuestionID ?? [:],
      reviewRemainingSecondsByQuestionID: bundle.reviewRemainingActiveSecondsByQuestionID ?? [:],
      lastSelectedChoiceIDByQuestionID: bundle.lastSelectedChoiceIDByQuestionID ?? [:],
      activeReviewQuestionID: activeReviewQuestionID(bundle))
    return .init(
      schemaID: FlashcardUnlockSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }

  private func certificationPayload(
    _ bundle: ExperienceUnlockBundleSnapshot
  ) throws -> ExperienceSessionPayload {
    let questions = try bundle.challenge.questions.map {
      snapshot -> CertificationChallengeQuestion in
      guard case .takken(let value) = snapshot else {
        throw ContentRepositoryError.invalid("旧certification sessionに異なる問題形式が含まれます")
      }
      return .init(
        id: value.id, prompt: value.prompt, choices: value.choices,
        correctChoiceID: value.correctChoiceID,
        shortExplanation: value.shortExplanation, longExplanation: value.longExplanation,
        keyPoint: value.keyPoint, category: value.category, subCategory: value.subCategory,
        difficulty: value.difficulty, format: value.format, examYear: value.examYear,
        lawBasisDate: value.lawBasisDate, sourceNote: value.sourceNote,
        contentVersion: value.contentVersion, questionVersion: value.questionVersion,
        conceptID: value.conceptID, variantID: value.variantID,
        minimumReviewSeconds: value.minimumReviewSeconds,
        contrastNote: value.contrastNote,
        wrongChoiceRationales: value.wrongChoiceRationales,
        misconceptionCodesByChoiceID: nil)
    }
    let state = CertificationUnlockSessionPayload(
      pace: bundle.challenge.pace,
      questions: questions,
      completedQuestionIDs: bundle.completedQuestionIDs,
      attemptCountsByQuestionID: bundle.attemptCountsByQuestionID ?? [:],
      reviewRemainingSecondsByQuestionID: bundle.reviewRemainingActiveSecondsByQuestionID ?? [:],
      lastSelectedChoiceIDByQuestionID: bundle.lastSelectedChoiceIDByQuestionID ?? [:],
      activeReviewQuestionID: activeReviewQuestionID(bundle))
    return .init(
      schemaID: CertificationUnlockSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }

  private func safeFallbackPayload(
    _ bundle: ExperienceUnlockBundleSnapshot
  ) throws -> ExperienceSessionPayload {
    let questions = try bundle.challenge.questions.map {
      snapshot -> SafeFallbackChallengeQuestion in
      guard case .safeFallback(let value) = snapshot else {
        throw ContentRepositoryError.invalid("旧fallback sessionに異なる問題形式が含まれます")
      }
      return .init(
        id: value.id, prompt: value.prompt, choices: value.choices,
        correctChoiceID: value.correctChoiceID, explanation: value.explanation)
    }
    let state = SafeFallbackSessionPayload(
      pace: bundle.challenge.pace,
      questions: questions,
      completedQuestionIDs: bundle.completedQuestionIDs,
      attemptCountsByQuestionID: bundle.attemptCountsByQuestionID ?? [:],
      reviewRemainingSecondsByQuestionID: bundle.reviewRemainingActiveSecondsByQuestionID ?? [:],
      lastSelectedChoiceIDByQuestionID: bundle.lastSelectedChoiceIDByQuestionID ?? [:],
      activeReviewQuestionID: activeReviewQuestionID(bundle))
    return .init(
      schemaID: SafeFallbackSessionPayload.schemaID,
      data: try SharedJSON.encoder().encode(state))
  }

  private func activeReviewQuestionID(
    _ bundle: ExperienceUnlockBundleSnapshot
  ) -> String? {
    bundle.reviewRemainingActiveSecondsByQuestionID?.first(where: { $0.value > 0 })?.key
  }
}

extension UnlockChallengeSessionEnvelope {
  static func wrapping(_ legacy: ExperienceUnlockBundleSnapshot) throws -> Self {
    try LegacyUnlockBundleMigration().migrate(legacy)
  }

  func decodeLegacyBundle() throws -> ExperienceUnlockBundleSnapshot {
    let questions: [UnlockQuestionSnapshot]
    let pace: AccessPacePreset
    let completed: Set<StudyItemID>
    let attempts: [String: Int]
    let review: [String: TimeInterval]
    let selections: [String: Int]
    switch enginePayloadSchemaID {
    case FlashcardUnlockSessionPayload.schemaID:
      let state = try SharedJSON.decoder().decode(
        FlashcardUnlockSessionPayload.self, from: enginePayload)
      pace = state.pace
      completed = state.completedQuestionIDs
      attempts = state.attemptCountsByQuestionID
      review = state.reviewRemainingSecondsByQuestionID
      selections = state.lastSelectedChoiceIDByQuestionID
      questions = state.questions.map { value in
        .vocabulary(.init(
          id: value.id, word: value.front, prompt: value.prompt, choices: value.choices,
          correctChoiceID: value.correctChoiceID, explanation: value.explanation,
          exampleEnglish: value.primaryExample ?? "",
          exampleJapanese: value.secondaryExample ?? "",
          speechText: value.speechText ?? "", levelCode: value.courseCode,
          contentVersion: value.contentVersion, isFreeSample: value.isFreeSample))
      }
    case CertificationUnlockSessionPayload.schemaID:
      let state = try SharedJSON.decoder().decode(
        CertificationUnlockSessionPayload.self, from: enginePayload)
      pace = state.pace
      completed = state.completedQuestionIDs
      attempts = state.attemptCountsByQuestionID
      review = state.reviewRemainingSecondsByQuestionID
      selections = state.lastSelectedChoiceIDByQuestionID
      questions = state.questions.map { value in
        .takken(.init(
          id: value.id, prompt: value.prompt, choices: value.choices,
          correctChoiceID: value.correctChoiceID,
          shortExplanation: value.shortExplanation,
          longExplanation: value.longExplanation, keyPoint: value.keyPoint,
          category: value.category, subCategory: value.subCategory,
          difficulty: value.difficulty, format: value.format,
          examYear: value.examYear, lawBasisDate: value.lawBasisDate,
          sourceNote: value.sourceNote, contentVersion: value.contentVersion,
          questionVersion: value.questionVersion, conceptID: value.conceptID,
          variantID: value.variantID, minimumReviewSeconds: value.minimumReviewSeconds,
          contrastNote: value.contrastNote,
          wrongChoiceRationales: value.wrongChoiceRationales))
      }
    case SafeFallbackSessionPayload.schemaID:
      let state = try SharedJSON.decoder().decode(
        SafeFallbackSessionPayload.self, from: enginePayload)
      pace = state.pace
      completed = state.completedQuestionIDs
      attempts = state.attemptCountsByQuestionID
      review = state.reviewRemainingSecondsByQuestionID
      selections = state.lastSelectedChoiceIDByQuestionID
      questions = state.questions.map { value in
        .safeFallback(.init(
          id: value.id, prompt: value.prompt, choices: value.choices,
          correctChoiceID: value.correctChoiceID, explanation: value.explanation))
      }
    default:
      throw ContentRepositoryError.invalid(
        "v10 sessionを旧解除bundleへ変換できません: \(enginePayloadSchemaID)")
    }
    let legacyExperienceID: StudyExperienceID
    switch experienceID.normalizedTemplateID {
    case .flashcardV1: legacyExperienceID = .vocabulary
    case .certificationV1: legacyExperienceID = .takken
    default: legacyExperienceID = .safeFallback
    }
    return .init(
      schemaVersion: 3,
      challenge: .init(
        schemaVersion: 3, id: id, requestID: requestID, origin: origin,
        experienceID: legacyExperienceID, packID: packID, policyVersion: policyVersion,
        pace: pace, reviewLoad: .standard, questions: questions,
        access: .init(packID: packID, reason: .freeSample, verifiedAt: nil),
        createdAt: createdAt, expiresAt: expiresAt),
      completedQuestionIDs: completed, completionState: completionState,
      completionEventID: completionEventID, createdUnlockSessionID: createdUnlockSessionID,
      abortReason: abortReason,
      attemptCountsByQuestionID: attempts.isEmpty ? nil : attempts,
      reviewRequiredUntilByQuestionID: nil,
      reviewRemainingActiveSecondsByQuestionID: review.isEmpty ? nil : review,
      reviewLastActiveAtByQuestionID: nil,
      lastSelectedChoiceIDByQuestionID: selections.isEmpty ? nil : selections)
  }
}

extension CertificationChallengeQuestion {
  init(legacy value: TakkenUnlockQuestionSnapshot) {
    self.init(
      id: value.id,
      prompt: value.prompt,
      choices: value.choices,
      correctChoiceID: value.correctChoiceID,
      shortExplanation: value.shortExplanation,
      longExplanation: value.longExplanation,
      keyPoint: value.keyPoint,
      category: value.category,
      subCategory: value.subCategory,
      difficulty: value.difficulty,
      format: value.format,
      examYear: value.examYear,
      lawBasisDate: value.lawBasisDate,
      sourceNote: value.sourceNote,
      contentVersion: value.contentVersion,
      questionVersion: value.questionVersion,
      conceptID: value.conceptID,
      variantID: value.variantID,
      minimumReviewSeconds: value.minimumReviewSeconds,
      contrastNote: value.contrastNote,
      wrongChoiceRationales: value.wrongChoiceRationales,
      misconceptionCodesByChoiceID: nil)
  }
}

extension TakkenAnswerStateMachine {
  init(
    restoring question: TakkenUnlockQuestionSnapshot,
    selectedChoiceID: Int,
    wrongAttemptCount: Int,
    reviewRequiredUntil: Date?,
    now: Date
  ) {
    self.init(
      restoring: CertificationChallengeQuestion(legacy: question),
      selectedChoiceID: selectedChoiceID,
      wrongAttemptCount: wrongAttemptCount,
      reviewRequiredUntil: reviewRequiredUntil,
      now: now)
  }
}

/// Source-compatibility request used only by tests and migrations from the pre-v10 engine API.
struct UnlockCompletionContext {
  let bundle: ExperienceUnlockBundleSnapshot
  let manifest: StudyPackManifest
  let dependencies: DependencyContainer
  let now: Date
}

extension FlashcardExperience {
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {
    guard context.bundle.challenge.experienceID.normalizedTemplateID == experienceID else { return }
    try await handleUnlockCompletion(.init(
      envelope: LegacyUnlockBundleMigration().migrate(context.bundle, at: context.now),
      manifest: context.manifest,
      dependencies: context.dependencies,
      now: context.now))
  }
}

extension CertificationExperience {
  func handleUnlockCompletion(_ context: UnlockCompletionContext) async throws {
    guard context.bundle.challenge.experienceID.normalizedTemplateID == experienceID else { return }
    try await handleUnlockCompletion(.init(
      envelope: LegacyUnlockBundleMigration().migrate(context.bundle, at: context.now),
      manifest: context.manifest,
      dependencies: context.dependencies,
      now: context.now))
  }
}

struct VocabularyUnlockChallengeProvider: UnlockChallengeProviding {
  func makeUnlockChallenge(
    packID: StudyPackID,
    request: UnlockChallengeRequest
  ) async throws -> UnlockChallengeSnapshot {
    let payload = try await FlashcardUnlockSessionBuilder().makeSession(request: request)
    let state = try SharedJSON.decoder().decode(
      FlashcardUnlockSessionPayload.self, from: payload.data)
    return legacyChallenge(
      request: request,
      experienceID: .vocabulary,
      contentVersion: request.manifest.contentVersion,
      questions: state.questions.map { value in
        .vocabulary(.init(
          id: value.id,
          word: value.front,
          prompt: value.prompt,
          choices: value.choices,
          correctChoiceID: value.correctChoiceID,
          explanation: value.explanation,
          exampleEnglish: value.primaryExample ?? "",
          exampleJapanese: value.secondaryExample ?? "",
          speechText: value.speechText ?? "",
          levelCode: value.courseCode,
          contentVersion: value.contentVersion,
          isFreeSample: value.isFreeSample))
      },
      accessReason: state.questions.allSatisfy(\.isFreeSample)
        ? .freeSample : paidAccessReason(request: request))
  }
}

struct TakkenUnlockChallengeProvider: UnlockChallengeProviding {
  func makeUnlockChallenge(
    packID: StudyPackID,
    request: UnlockChallengeRequest
  ) async throws -> UnlockChallengeSnapshot {
    let payload = try await CertificationUnlockSessionBuilder().makeSession(request: request)
    let state = try SharedJSON.decoder().decode(
      CertificationUnlockSessionPayload.self, from: payload.data)
    return legacyChallenge(
      request: request,
      experienceID: .takken,
      contentVersion: request.manifest.contentVersion,
      questions: state.questions.map { value in
        .takken(.init(
          id: value.id,
          prompt: value.prompt,
          choices: value.choices,
          correctChoiceID: value.correctChoiceID,
          shortExplanation: value.shortExplanation,
          longExplanation: value.longExplanation,
          keyPoint: value.keyPoint,
          category: value.category,
          subCategory: value.subCategory,
          difficulty: value.difficulty,
          format: value.format,
          examYear: value.examYear,
          lawBasisDate: value.lawBasisDate,
          sourceNote: value.sourceNote,
          contentVersion: value.contentVersion,
          questionVersion: value.questionVersion,
          conceptID: value.conceptID,
          variantID: value.variantID,
          minimumReviewSeconds: value.minimumReviewSeconds,
          contrastNote: value.contrastNote,
          wrongChoiceRationales: value.wrongChoiceRationales))
      },
      accessReason: paidAccessReason(request: request))
  }
}

struct SafeFallbackUnlockChallengeProvider: UnlockChallengeProviding {
  func makeUnlockChallenge(
    packID: StudyPackID,
    request: UnlockChallengeRequest
  ) async throws -> UnlockChallengeSnapshot {
    let payload = try SafeFallbackUnlockSessionBuilder().makeSession(request: request)
    let state = try SharedJSON.decoder().decode(
      SafeFallbackSessionPayload.self, from: payload.data)
    return legacyChallenge(
      request: request,
      experienceID: .safeFallback,
      contentVersion: "built-in-v1",
      questions: state.questions.map { value in
        .safeFallback(.init(
          id: value.id,
          prompt: value.prompt,
          choices: value.choices,
          correctChoiceID: value.correctChoiceID,
          explanation: value.explanation))
      },
      accessReason: .freeSample)
  }
}

private func legacyChallenge(
  request: UnlockChallengeRequest,
  experienceID: StudyExperienceID,
  contentVersion: String,
  questions: [UnlockQuestionSnapshot],
  accessReason: ContentAccessReason
) -> UnlockChallengeSnapshot {
  .init(
    schemaVersion: 2,
    id: UUID(),
    requestID: request.requestID,
    origin: request.origin,
    experienceID: experienceID,
    packID: request.manifest.id,
    policyVersion: request.policy.schemaVersion,
    pace: request.policy.accessPacePreset,
    reviewLoad: request.policy.reviewLoadPreset,
    questions: questions,
    access: .init(
      packID: request.manifest.id,
      reason: accessReason,
      verifiedAt: request.entitlement.lastVerifiedAt),
    createdAt: request.now,
    expiresAt: request.now.addingTimeInterval(ExperienceUnlockBundleSnapshot.expirationInterval))
}

private func paidAccessReason(request: UnlockChallengeRequest) -> ContentAccessReason {
  let decision = ContentAccessService().decision(
    isFreeSample: false,
    manifest: request.manifest,
    entitlement: request.entitlement,
    now: request.now)
  return decision.isAllowed ? decision.reason : .freeSample
}
