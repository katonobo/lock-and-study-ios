#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

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


def reviewed_choice_fixture(
    base: dict,
    *,
    fmt: str,
    texts: list[str],
    correct_index: int = 0,
) -> dict:
    fixture = json.loads(json.dumps(base, ensure_ascii=False))
    fixture["format"] = fmt
    fixture["variantID"] = f"v15.{fmt}"
    fixture["choices"] = [
        {
            "id": f"choice-{index}",
            "text": text,
            "rationale": (
                None
                if index == correct_index
                else "正解の法令要件とは主体及び適用条件が異なるため誤り。"
            ),
            "misconceptionCode": None,
        }
        for index, text in enumerate(texts)
    ]
    fixture["correctIndex"] = correct_index
    fixture["correctChoiceID"] = f"choice-{correct_index}"
    fixture["wrongChoiceRationales"] = {
        choice["id"]: choice["rationale"]
        for choice in fixture["choices"]
        if choice["id"] != fixture["correctChoiceID"]
    }
    return fixture


def expect_gate_rejection(
    errors: list[str],
    label: str,
    fixture: dict,
    manifest: dict,
    expected_fragment: str | None = None,
) -> None:
    gate_errors = validate_takken_v2_review_batch([fixture], manifest)
    if not gate_errors:
        errors.append(f"v15 gate unexpectedly accepted {label}")
    elif expected_fragment and not any(expected_fragment in value for value in gate_errors):
        errors.append(f"v15 gate rejected {label} for the wrong reason")


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
    hardening = read("Docs/TAKKEN_REVIEW_GATE_HARDENING_V15.md")
    final_verification = read("Docs/FINAL_VERIFICATION_V15.md")
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
        "reviewedAt must be a real ISO-8601",
        "a concrete sourceNote is required",
        "legalReviewChecklist",
        "wrongChoiceRationales must cover every distractor exactly",
        "true/false choices must be exactly 正しい and 誤り",
        "number-choice unit is missing",
        "number-choice units are inconsistent",
        "unresolved bracketed input placeholder remains",
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
    for required in [
        "実機で確認済み",
        "教材方針",
        "捏造しない",
        "ai_draft",
        "sys.dont_write_bytecode",
        "scripts/platform_freeze_v14.json",
    ]:
        if required not in hardening:
            errors.append(f"Takken v15 hardening documentation is missing: {required}")
    for required in ["196 tests", "400問", "自動昇格した候補: 0問", "Archive: passed"]:
        if required not in final_verification:
            errors.append(f"Takken v15 final verification is missing: {required}")
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
        sourceNote="宅地建物取引業法第3条（e-Gov法令検索、2026-04-01確認）",
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

    date_only_example = json.loads(json.dumps(reviewed_example, ensure_ascii=False))
    date_only_example["reviewedAt"] = "2026-07-23"
    if validate_takken_v2_review_batch([date_only_example], production_manifest):
        errors.append("v15 gate rejected a real ISO-8601 date")

    bad_true_false = reviewed_choice_fixture(
        reviewed_example,
        fmt="true_false",
        texts=["正しい", "正しいとは限らない"],
    )
    expect_gate_rejection(
        errors,
        "a true/false alternate label",
        bad_true_false,
        production_manifest,
        "exactly 正しい and 誤り",
    )
    yes_no_true_false = reviewed_choice_fixture(
        reviewed_example,
        fmt="true_false",
        texts=["はい", "いいえ"],
    )
    expect_gate_rejection(
        errors,
        "a yes/no true_false item",
        yes_no_true_false,
        production_manifest,
        "exactly 正しい and 誤り",
    )
    three_choice_true_false = reviewed_choice_fixture(
        reviewed_example,
        fmt="true_false",
        texts=["正しい", "誤り", "どちらともいえない"],
    )
    expect_gate_rejection(
        errors,
        "a three-choice true_false item",
        three_choice_true_false,
        production_manifest,
        "choice count does not match true_false",
    )

    valid_number_choice = reviewed_choice_fixture(
        reviewed_example,
        fmt="number_choice",
        texts=["５日", "七日", "１０日"],
    )
    if validate_takken_v2_review_batch([valid_number_choice], production_manifest):
        errors.append("v15 gate rejected consistent NFKC/Japanese number-choice units")
    missing_number_unit = reviewed_choice_fixture(
        reviewed_example,
        fmt="number_choice",
        texts=["5日", "7", "10日"],
    )
    expect_gate_rejection(
        errors,
        "a missing number-choice unit",
        missing_number_unit,
        production_manifest,
        "number-choice unit is missing",
    )
    mismatched_number_unit = reviewed_choice_fixture(
        reviewed_example,
        fmt="number_choice",
        texts=["5日", "7年", "10日"],
    )
    expect_gate_rejection(
        errors,
        "mismatched number-choice units",
        mismatched_number_unit,
        production_manifest,
        "number-choice units are inconsistent",
    )

    draft_marker_example = json.loads(json.dumps(reviewed_example, ensure_ascii=False))
    draft_marker_example["contrastNote"] = "この対照は人間が確認する"
    expect_gate_rejection(
        errors,
        "an extended draft marker",
        draft_marker_example,
        production_manifest,
        "unresolved draft marker remains",
    )
    preview_marker_example = json.loads(json.dumps(reviewed_example, ensure_ascii=False))
    preview_marker_example["preview"]["mnemonic"] = "要点候補"
    expect_gate_rejection(
        errors,
        "a draft marker in a preview field",
        preview_marker_example,
        production_manifest,
        "unresolved draft marker remains",
    )
    bracketed_placeholder_example = json.loads(
        json.dumps(reviewed_example, ensure_ascii=False)
    )
    bracketed_placeholder_example["prompt"] = "免許権者は［ここに入力］である。"
    expect_gate_rejection(
        errors,
        "a bracketed input placeholder",
        bracketed_placeholder_example,
        production_manifest,
        "unresolved bracketed input placeholder remains",
    )

    missing_source_example = json.loads(json.dumps(reviewed_example, ensure_ascii=False))
    missing_source_example["sourceNote"] = ""
    expect_gate_rejection(
        errors,
        "a reviewed item without sourceNote",
        missing_source_example,
        production_manifest,
        "a concrete sourceNote is required",
    )
    for invalid_date in ("2026-99-99", "2026-02-30"):
        invalid_date_example = json.loads(
            json.dumps(reviewed_example, ensure_ascii=False)
        )
        invalid_date_example["reviewedAt"] = invalid_date
        expect_gate_rejection(
            errors,
            f"the invalid review date {invalid_date}",
            invalid_date_example,
            production_manifest,
            "reviewedAt must be a real ISO-8601",
        )

    for required_field in [
        '"wrongChoiceRationales"',
        '"keyPoint"',
        '"contrastNote"',
        '"sourceNote"',
        '"preview"',
    ]:
        if required_field not in checks:
            errors.append(f"v15 draft-marker scan misses field: {required_field}")
    for marker in [
        "誤答候補",
        "対照文候補",
        "要校閲",
        "要点候補",
        "詳細解説候補",
        "人間が確認する",
    ]:
        if marker not in checks:
            errors.append(f"v15 expanded draft marker is missing: {marker}")

    bytecode_safe_entrypoints = [
        "scripts/audit_takken_content_v14",
        "scripts/export_takken_review_batch",
        "scripts/promote_takken_reviewed",
        "scripts/check_takken_release_candidate",
        "scripts/prepare_takken_v2_candidates",
        "scripts/verify_platform_v14.py",
    ]
    for entrypoint in bytecode_safe_entrypoints:
        if "sys.dont_write_bytecode = True" not in read(entrypoint):
            errors.append(f"authoring command can generate Python cache: {entrypoint}")

    errors.extend(audit_takken_v14())

    bytecode = list((ROOT / "scripts").rglob("*.pyc"))
    caches = [path for path in (ROOT / "scripts").rglob("__pycache__") if path.is_dir()]
    if bytecode or caches:
        errors.append("scripts contains Python bytecode/cache artifacts")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(
        "Platform v14 freeze, package validation, and Takken v15 authoring "
        "verification passed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
