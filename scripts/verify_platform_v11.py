#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    app_model = read("LockAndStudy/App/AppModel.swift")
    root_view = read("LockAndStudy/App/RootView.swift")
    repository = read("LockAndStudy/Core/Content/ContentRepository.swift")
    catalog = read("LockAndStudy/Core/Content/StudyCatalog.swift")
    store = read("LockAndStudy/Core/Content/ValidatedCatalogStore.swift")
    vocabulary = read("LockAndStudy/StudyExperiences/Vocabulary/VocabularyExperience.swift")
    vocabulary_views = read("LockAndStudy/StudyExperiences/Vocabulary/VocabularyViews.swift")
    fallback = read("LockAndStudy/StudyExperiences/Shared/VerifiedContentLoader.swift")
    learning_store = read("LockAndStudy/Core/Persistence/LearningDataStore.swift")
    report = read("LockAndStudy/Core/Reporting/LearningReportService.swift")
    tests = read("LockAndStudyTests/PlatformHardeningV11Tests.swift")

    for forbidden in ["manifests.first!", "?? manifests.first"]:
        if forbidden in app_model:
            errors.append(f"unsafe manifest fallback remains: {forbidden}")
    for required in [
        "UnlockSessionRestorationValidator",
        "manifestPackMismatch",
        "payloadSchemaUnsupported",
        "contentVersionIncompatible",
        "failClosedUnlockPresentation",
        "beginSafeRecoveryStudy",
    ]:
        if required not in app_model:
            errors.append(f"unlock recovery contract is missing: {required}")
    for required in ["UnlockRecoveryView", "unlock.recovery.beginSafeFallback"]:
        if required not in root_view:
            errors.append(f"unlock recovery UI is missing: {required}")

    for forbidden in [
        "苦手として判定された単語はまだありません。",
        "このコースの新出単語は一巡しました。",
    ]:
        if forbidden in vocabulary:
            errors.append(f"flashcard template still owns pack-specific copy: {forbidden}")
    if "resolvedEmptyStateCopy" not in vocabulary:
        errors.append("flashcard empty state is not profile-driven")
    if "model.pendingPreviewExamplesEnabled" not in vocabulary_views:
        errors.append("preview does not respect profile supportsExamples")

    for required in [
        "CatalogValidationScope",
        "CatalogValidationSeverity",
        "duplicate-category-id",
        "duplicate-series-id",
        "category-cycle",
    ]:
        if required not in catalog:
            errors.append(f"catalog global-error classification is missing: {required}")
    for required in [
        "isGlobalFatal",
        "validatedCatalogStore.catalogDataCandidates",
        "candidates.dropFirst",
    ]:
        if required not in repository:
            errors.append(f"catalog rollback order is missing: {required}")
    for required in ["validated-catalog-v1.json", "backupURL", "synchronize()", "replaceItemAt"]:
        if required not in store:
            errors.append(f"durable LKG storage is missing: {required}")

    if "StudyAnswerRecord.safeFallbackTag" not in fallback:
        errors.append("safe fallback answer marker is missing")
    if "if !answer.isSafeFallback" not in learning_store:
        errors.append("safe fallback still mutates normal progress")
    if "safeFallbackUnlockCount" not in report:
        errors.append("safe fallback unlocks are not reported separately")

    release_catalog = json.loads(read("LockAndStudy/Resources/Content/Released/study_pack_catalog.json"))
    english = next(pack for pack in release_catalog["packs"] if pack["id"] == "english3000.v1")
    english_copy = english["presentation"]["flashcard"].get("emptyStateCopy")
    if not english_copy or "単語" not in english_copy.get("noWeakItems", ""):
        errors.append("English flashcard legacy copy was not preserved")
    fixtures = json.loads(read("LockAndStudyTests/Fixtures/PlatformV9/study_pack_catalog_v9_fixtures.json"))
    idioms = next(pack for pack in fixtures["packs"] if pack["id"] == "yojijukugo.fixture.v1")
    idiom_copy = idioms["presentation"]["flashcard"].get("emptyStateCopy", {})
    if any("単語" in value for value in idiom_copy.values()):
        errors.append("Yojijukugo empty-state copy contains vocabulary wording")

    for proof in [
        "testUnlockRestorationRejectsEveryManifestRuntimeAndVersionMismatch",
        "testSavedExperienceSchemaAndContentMismatchesAreAllAborted",
        "testGlobalCatalogErrorsRollbackWhilePackLocalErrorIsIsolated",
        "testPersistedLastKnownGoodSurvivesColdLaunchAndCorruptionFallsBack",
        "testSafeFallbackAnswersDoNotMutateProgressOrNormalReport",
        "testArchivedPackIsOwnedOnlyEvenWithActivePass",
    ]:
        if proof not in tests:
            errors.append(f"v11 executable proof is missing: {proof}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Platform v11 final hardening verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
