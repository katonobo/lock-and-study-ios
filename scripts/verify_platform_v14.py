#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from content_checks import ROOT, audit_takken_v14, load_json, validate_takken_v2_review_batch


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def frozen_digest(roots: list[str]) -> tuple[int, str]:
    files: list[Path] = []
    for value in roots:
        path = ROOT / value
        files.extend(sorted(path.rglob("*.swift")) if path.is_dir() else [path])
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(str(path.relative_to(ROOT)).encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return len(files), digest.hexdigest()


def main() -> int:
    errors: list[str] = []
    freeze = load_json(ROOT / "scripts/platform_freeze_v14.json")
    for group in freeze.get("groups", []):
        count, digest = frozen_digest(group.get("roots", []))
        if count != group.get("fileCount") or digest != group.get("sha256"):
            errors.append(f"frozen platform group changed: {group.get('id')}")

    validator = read("LockAndStudy/Core/Content/ContentFileValidation.swift")
    wire = read("LockAndStudy/Core/Content/CertificationQuestionWire.swift")
    runtime = read("LockAndStudy/Modules/Takken/TakkenStudyModule.swift")
    tests = read("LockAndStudyTests/TakkenContentImprovementV14Tests.swift")
    checks = read("scripts/content_checks.py")
    promotion = read("scripts/promote_takken_reviewed")
    runner = read("scripts/platform_verifications")
    project = read("LockAndStudy.xcodeproj/project.pbxproj")
    workflow = read("Docs/TAKKEN_CONTENT_IMPROVEMENT_V14.md")
    freeze_document = read("Docs/PLATFORM_FREEZE_V14.md")

    for required in [
        "ContentSchemaPackageValidating",
        "CertificationQuestionsV1PackageValidator",
        "validatedFiles",
        "packageValidator(for: schemaID)",
    ]:
        if required not in validator:
            errors.append(f"package-level stage validation is missing: {required}")
    for required in [
        "CertificationQuestionPackagePolicy",
        "複数ファイル間で重複",
        "manifest.expectedItemCount",
        "ContentSampleResolver",
    ]:
        if required not in wire:
            errors.append(f"shared certification package policy is missing: {required}")
    if "policy.validatedActiveQuestions" not in runtime:
        errors.append("Takken runtime does not share the staging package policy")

    for proof in [
        "testCertificationPackageValidatorAcceptsRuntimeEquivalentMultiFilePackage",
        "testCertificationPackageValidatorRejectsCrossFileFailuresBeforeActivation",
    ]:
        if proof not in tests:
            errors.append(f"v14 executable proof is missing: {proof}")
    if "TakkenContentImprovementV14Tests.swift" not in project:
        errors.append("v14 test file is not registered in the Xcode project")

    for required in [
        "reviewer is required",
        "reviewedAt must be an ISO-8601",
        "legalReviewChecklist",
        "wrongChoiceRationales must cover every distractor exactly",
        "250-300 reviewed questions",
        "audit_takken_v14",
    ]:
        if required not in checks:
            errors.append(f"Takken v14 authoring gate is missing: {required}")
    if "validate_takken_v2_review_batch" not in promotion:
        errors.append("review promotion bypasses the v14 human-review batch gate")
    if "verify_platform_v14" not in runner:
        errors.append("shared platform runner misses v14")
    for required in ["50問", "saleReady", "人手校閲", "package-level"]:
        if required not in workflow:
            errors.append(f"Takken v14 workflow documentation is missing: {required}")
    for required in ["Lock Core", "Catalog / Commerce", "Experience Runtime", "freeze hash"]:
        if required not in freeze_document:
            errors.append(f"platform freeze documentation is missing: {required}")

    candidates = load_json(
        ROOT / "ContentSource/Drafts/takken_2026_free_100_v2_candidates.json"
    )
    production_manifest = next(
        pack for pack in load_json(
            ROOT / "LockAndStudy/Resources/Content/Released/study_pack_catalog.json"
        )["packs"]
        if pack.get("id") == "takken2026.v1"
    )
    draft_gate_errors = validate_takken_v2_review_batch(candidates[:50], production_manifest)
    if not draft_gate_errors:
        errors.append("an unreviewed AI batch unexpectedly passed the human-review gate")
    reviewed_example = json.loads(json.dumps(candidates[0], ensure_ascii=False))
    reviewed_example.update(
        reviewStatus="reviewed",
        distractorReviewStatus="checked",
        reviewer="v14-gate-fixture",
        reviewedAt="2026-07-23T08:00:00+09:00",
        reviewNote="法令基準日、主体、時期、数字及び例外を原典と照合した。",
        shortExplanation="宅建業を営むには免許が必要です。",
        longExplanation=(
            "宅建業を営むには免許が必要であり、取引の主体、免許権者及び"
            "適用除外を区別して確認します。"
        ),
        legalReviewChecklist={
            "lawBasis": True,
            "subject": True,
            "timing": True,
            "numbers": True,
            "exceptions": True,
        },
    )
    wrong_rationales = {
        choice["id"]: "正解の法令要件とは主体及び適用条件が異なるため誤り。"
        for choice in reviewed_example["choices"]
        if choice["id"] != reviewed_example["correctChoiceID"]
    }
    reviewed_example["wrongChoiceRationales"] = wrong_rationales
    for choice in reviewed_example["choices"]:
        if choice["id"] in wrong_rationales:
            choice["rationale"] = wrong_rationales[choice["id"]]
    positive_gate_errors = validate_takken_v2_review_batch(
        [reviewed_example], production_manifest
    )
    if positive_gate_errors:
        errors.append("a structurally complete reviewed item cannot pass the v14 gate")
    errors.extend(audit_takken_v14())

    bytecode = list((ROOT / "scripts").rglob("*.pyc"))
    caches = [path for path in (ROOT / "scripts").rglob("__pycache__") if path.is_dir()]
    if bytecode or caches:
        errors.append("scripts contains Python bytecode/cache artifacts")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Platform v14 freeze, package validation, and Takken authoring verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
