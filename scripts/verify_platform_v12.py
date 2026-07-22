#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    app = read("LockAndStudy/App/AppModel.swift")
    root = read("LockAndStudy/App/RootView.swift")
    onboarding = read("LockAndStudy/Features/Onboarding/OnboardingFlowView.swift")
    library = read("LockAndStudy/Platform/Library/StudyMaterialSelectionView.swift")
    settings = read("LockAndStudy/Features/Settings/SettingsView.swift")
    validation = read("LockAndStudy/Core/Content/ContentFileValidation.swift")
    packages = read("LockAndStudy/Core/Content/ContentAssetSource.swift")
    migration = read("LockAndStudy/Core/Content/ProgressMigrationService.swift")
    learning = read("LockAndStudy/Core/Persistence/LearningDataStore.swift") + read(
        "LockAndStudy/Core/Learning/LearningModels.swift"
    )
    tests = read("LockAndStudyTests/PlatformFinalPolishV12Tests.swift")
    runner = read("scripts/platform_verifications")
    release = read("scripts/release_readiness")

    for required in [
        "catalogRecoveryRequired",
        "normalManifests",
        "isNormalStudyPack",
        "beginCatalogSafeRecoveryStudy",
    ]:
        if required not in app:
            errors.append(f"normal catalog recovery contract is missing: {required}")
    for required in ["CatalogRecoveryView", "catalogRecovery.screen", "catalogRecovery.reload"]:
        if required not in root:
            errors.append(f"catalog recovery UI is missing: {required}")
    if "model.normalManifests" not in library:
        errors.append("material selection does not exclude safe fallback")

    if 'StudyPackID = "english3000.v1"' in onboarding:
        errors.append("onboarding still hardcodes the English pack")
    for required in ["OnboardingPackSelector", "OnboardingPackPresentation", "themeToken"]:
        if required not in onboarding:
            errors.append(f"data-driven onboarding is missing: {required}")
    for forbidden in ["CEFR-J", "追加200問は承認待ち"]:
        if forbidden in settings:
            errors.append(f"credits UI still contains fixed pack copy: {forbidden}")
    for required in ["ContentCreditsLoader", "manifest.contentVersion", "manifest.creditsFile"]:
        if required not in settings:
            errors.append(f"catalog-driven credits are missing: {required}")

    for required in [
        "protocol ContentFileValidating",
        "ContentFileValidatorRegistry",
        "FlashcardItemsV1Validator",
        "CertificationQuestionsV1Validator",
        "SampleIndexV1Validator",
        "OpaqueBinaryContentValidator",
        "未登録content schema",
    ]:
        if required not in validation:
            errors.append(f"schema validation registry is missing: {required}")
    if "itemCount(in" in packages:
        errors.append("ContentPackageStore still owns the generic JSON item counter")

    for required in [
        "progressMigrationSHA256",
        "document.packID == manifest.id",
        "fromContentVersion",
        "applyProgressMigration",
    ]:
        if required not in migration:
            errors.append(f"activation migration validation is missing: {required}")
    for required in [
        "progress-migration-checkpoints.v1.json",
        "beforeItems",
        "resetChangedItems",
        "rekeyed(to:",
        "rollbackProgressMigration",
    ]:
        if required not in learning:
            errors.append(f"durable progress migration is missing: {required}")
    for required in ["writeStagedManifest", "prepareActivation", "progressMigrationService.rollback"]:
        if required not in packages:
            errors.append(f"package activation is not migration-aware: {required}")

    for version in ["v9", "v10", "v11", "v12"]:
        if f"verify_platform_{version}" not in runner:
            errors.append(f"shared platform runner misses {version}")
    if "platform_verifications" not in release:
        errors.append("release_readiness does not use the shared platform runner")

    for proof in [
        "testSafeFallbackOnlyCatalogUsesRecoveryStateAndNeverBecomesNormalMaterial",
        "testShieldRecoveryCanStillCreateSafeFallbackChallenge",
        "testOnboardingWithoutEnglishUsesAvailablePackAndCatalogPresentation",
        "testCustomBinarySchemaRequiresRegistrationWithoutCoreSwitch",
        "testProgressMigrationPreservesMigratesResetsIsIdempotentAndRollsBack",
        "testMigrationFailureKeepsOldActivePackage",
    ]:
        if proof not in tests:
            errors.append(f"v12 executable proof is missing: {proof}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Platform v12 final polish verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
