#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    packages = read("LockAndStudy/Core/Content/ContentAssetSource.swift")
    migration = read("LockAndStudy/Core/Content/ProgressMigrationService.swift")
    progress = read("LockAndStudy/Core/Persistence/LearningDataStore.swift")
    wire = read("LockAndStudy/Core/Content/CertificationQuestionWire.swift")
    validator = read("LockAndStudy/Core/Content/ContentFileValidation.swift")
    runtime = read("LockAndStudy/Modules/Takken/TakkenStudyModule.swift")
    tests = read("LockAndStudyTests/ContentTransactionHardeningV13Tests.swift")
    runner = read("scripts/platform_verifications")
    architecture = read("Docs/CONTENT_DELIVERY_ARCHITECTURE.md")

    for required in [
        "ContentActivationJournal",
        "case prepared",
        "case migrationApplied",
        "case pointerCommitted",
        "recoverInterruptedActivations",
        "validateCommittedActivation",
        "afterJournalPrepared",
        "afterMigrationApplied",
        "beforePointerWrite",
        "afterPointerWrite",
        "beforeJournalRemoval",
    ]:
        if required not in packages:
            errors.append(f"activation transaction is missing: {required}")
    if "previousContentVersion: nil" not in packages:
        errors.append("rollback still permits forward toggling")
    for required in ["PreparedProgressMigration", "isApplied", "documentDigest"]:
        if required not in migration:
            errors.append(f"migration transaction validation is missing: {required}")

    for required in [
        "case .preserve",
        "case .resetChangedItems",
        "case .migrate",
        "mappingsByOldID[item.id.itemID] == nil",
    ]:
        if required not in progress:
            errors.append(f"default progress policy is incomplete: {required}")

    for required in [
        "CertificationQuestionWire",
        "CertificationQuestionWireDecoder",
        "correctChoiceIDとcorrectIndexが一致しません",
        "正解choiceに誤答rationaleを設定できません",
    ]:
        if required not in wire:
            errors.append(f"canonical certification decoder is missing: {required}")
    if "CertificationQuestionWireDecoder().decode(data)" not in validator:
        errors.append("certification validator does not use the canonical decoder")
    if "CertificationQuestionWireDecoder()" not in runtime:
        errors.append("certification runtime repository does not use the canonical decoder")

    for proof in [
        "testInterruptedActivationRecoversAtEveryStage",
        "testRollbackCannotToggleForwardOnSecondCall",
        "testCertificationValidatorMatchesRuntimeDecoder",
        "testDefaultProgressPoliciesApplyToUnmappedItems",
    ]:
        if proof not in tests:
            errors.append(f"v13 executable proof is missing: {proof}")
    if "verify_platform_v13" not in runner:
        errors.append("shared platform runner misses v13")
    for required in ["Activation Journal", "migrationApplied", "pointerCommitted"]:
        if required not in architecture:
            errors.append(f"activation recovery documentation is missing: {required}")

    bytecode = list((ROOT / "scripts").rglob("*.pyc"))
    caches = [path for path in (ROOT / "scripts").rglob("__pycache__") if path.is_dir()]
    if bytecode or caches:
        errors.append("scripts contains Python bytecode/cache artifacts")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Platform v13 content transaction hardening verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
