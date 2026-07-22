#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []

    lock_and_shared = "\n".join(
        text(path)
        for path in [
            "LockAndStudy/Core/Lock/UnlockSessionRuntime.swift",
            "LockAndStudy/StudyExperiences/Shared/StudyExperience.swift",
        ]
    )
    for legacy_type in [
        "VocabularyUnlockQuestionSnapshot",
        "TakkenUnlockQuestionSnapshot",
        "UnlockQuestionSnapshot",
        "ExperienceUnlockBundleSnapshot",
    ]:
        if legacy_type in lock_and_shared:
            fail(errors, f"shared runtime still references legacy type: {legacy_type}")

    app_model = text("LockAndStudy/App/AppModel.swift")
    for forbidden in [
        "VocabularyUnlockQuestionSnapshot",
        "TakkenUnlockQuestionSnapshot",
        "UnlockQuestionSnapshot",
        "ExperienceUnlockBundleSnapshot",
        "correctChoiceID",
        "minimumReviewSeconds",
        "StudyModuleRegistry",
    ]:
        if forbidden in app_model:
            fail(errors, f"AppModel owns experience-specific state: {forbidden}")
    for required in [
        "runtime.createSession",
        "runtime.acceptAnswer",
        "runtime.activeReviewTick",
        "runtime.completionProof",
        "validateCompatibility(with: manifest)",
    ]:
        if required not in app_model:
            fail(errors, f"AppModel does not use runtime contract: {required}")

    dependency = text("LockAndStudy/App/DependencyContainer.swift")
    required_sources = [
        "InstalledContentSource",
        "BundledContentSource",
        "SafeFallbackContentSource",
        "CompositeContentSource",
    ]
    for source in required_sources:
        if source not in dependency:
            fail(errors, f"production dependency misses {source}")
    installed_index = dependency.find("InstalledContentSource")
    fallback_index = dependency.find("SafeFallbackContentSource", installed_index)
    if installed_index < 0 or fallback_index < 0 or installed_index > fallback_index:
        fail(errors, "installed content must have priority over safe fallback")

    shared_runtime = text("LockAndStudy/StudyExperiences/Shared/StudyExperience.swift")
    if "protocol StudyExperienceSessionRuntime" not in shared_runtime:
        fail(errors, "StudyExperienceSessionRuntime is missing")
    legacy_models = text("LockAndStudy/Compatibility/LegacyUnlockModels.swift")
    if "enum UnlockQuestionSnapshot" not in legacy_models:
        fail(errors, "legacy question models are not isolated in Compatibility")

    ui_sources = "\n".join(
        text(path)
        for path in [
            "LockAndStudy/StudyExperiences/Vocabulary/VocabularyViews.swift",
            "LockAndStudy/StudyExperiences/Vocabulary/VocabularyReportProvider.swift",
            "LockAndStudy/StudyExperiences/Takken/TakkenViews.swift",
            "LockAndStudy/StudyExperiences/Takken/TakkenReportProvider.swift",
        ]
    )
    for forbidden in [
        "中学1年",
        "高校基礎",
        "宅建2026",
        "宅建業法",
        "宅建学習を始める",
        "宅建問題でロックを開く",
        "無料宅建問題",
        "法令基準日",
    ]:
        if forbidden in ui_sources:
            fail(errors, f"template UI contains pack-specific literal: {forbidden}")

    catalog_decoder = text("LockAndStudy/Core/Content/StudyCatalog.swift")
    decode_start = catalog_decoder.find("private func decodeEntries")
    decode_end = catalog_decoder.find("private func decodeGeneratedAt", decode_start)
    if decode_start < 0 or "compactMap" in catalog_decoder[decode_start:decode_end]:
        fail(errors, "catalog entry decoding is not strict")
    repository = text("LockAndStudy/Core/Content/ContentRepository.swift")
    for required in ["lastKnownGoodCatalog", "catalogDiagnostics", "validCategories"]:
        if required not in repository:
            fail(errors, f"catalog rollback/isolation is missing: {required}")

    fixture_root = ROOT / "LockAndStudyTests/Fixtures/PlatformV9"
    fixture_catalog_path = fixture_root / "study_pack_catalog_v9_fixtures.json"
    fixture_catalog = json.loads(fixture_catalog_path.read_text(encoding="utf-8"))
    packs = {pack["id"]: pack for pack in fixture_catalog["packs"]}
    expected = {
        "yojijukugo.fixture.v1": ("flashcard", "四字熟語"),
        "takken2027.fixture.v1": ("certification", "宅建2027"),
        "business-manners.fixture.v1": ("certification", "ビジネスマナー"),
    }
    for pack_id, (profile_kind, subject) in expected.items():
        pack = packs.get(pack_id)
        if pack is None:
            fail(errors, f"missing v10 fixture pack: {pack_id}")
            continue
        profile = (pack.get("presentation") or {}).get(profile_kind)
        if not profile or profile.get("subjectName") != subject:
            fail(errors, f"{pack_id}: presentation profile is not data-driven")
        for descriptor in pack.get("contentFiles", []):
            path = fixture_root / descriptor["path"]
            if not path.exists():
                fail(errors, f"{pack_id}: missing fixture file {path.name}")
                continue
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != descriptor["sha256"]:
                fail(errors, f"{pack_id}: fixture hash mismatch {path.name}")

    manners_profile = packs["business-manners.fixture.v1"]["presentation"]["certification"]
    if manners_profile.get("showsEditionYear") or manners_profile.get("showsLawBasisDate"):
        fail(errors, "business manners must hide edition and law-basis fields")
    manner_formats = {value["code"] for value in manners_profile.get("formatDefinitions", [])}
    if manner_formats != {"true_false", "wording_contrast", "case_study"}:
        fail(errors, "business manners format profile is incomplete")

    release_catalog = text("LockAndStudy/Resources/Content/Released/study_pack_catalog.json")
    if "fixture" in release_catalog.lower():
        fail(errors, "test fixtures leaked into the production catalog")

    tests = text("LockAndStudyTests/PlatformCompletionV10Tests.swift")
    for proof in [
        "FakeCustomExperience",
        "testInstalledFixtureOpensThroughProductionDependencyAndAppModel",
        "testYojijukugoUsesFlashcardProfileRuntimePreviewHistoryAndReport",
        "testBusinessMannersUsesCertificationWithoutTakkenLabels",
        "testStrictCatalogDecodeRollbackAndHierarchyAreFailClosed",
    ]:
        if proof not in tests:
            fail(errors, f"v10 executable proof is missing: {proof}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Platform v10 completion verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
