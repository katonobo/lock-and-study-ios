#!/usr/bin/env python3
"""Executable v17 proofs for concept/inventory/variant/release safety."""
from __future__ import annotations

import hashlib
import json
import sys
from copy import deepcopy

sys.dont_write_bytecode = True

from takken_concepts import (
    CONCEPT_ROOT,
    GOLDEN_PATH,
    INVENTORY_PATH,
    MASTER_PATH,
    RESEARCH_PATH,
    ROOT,
    VARIANTS_PATH,
    audit_snapshot,
    build_concept_assets,
    free_sample_selection_errors,
    full_pack_candidate_errors,
    golden_candidate_errors,
    load_json,
    load_legacy_records,
    validate_concept_master,
    validate_legacy_inventory,
    validate_variant_quality,
)


def expect_error(
    errors: list[str], label: str, values: list[str], expected_fragment: str
) -> None:
    if not any(expected_fragment in value for value in values):
        errors.append(f"v17 negative fixture did not reject {label}")


def digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    snapshot, audit_errors = audit_snapshot()
    errors.extend(audit_errors)
    master = load_json(MASTER_PATH)
    inventory = load_json(INVENTORY_PATH)
    golden = load_json(GOLDEN_PATH)
    variants = load_json(VARIANTS_PATH)["variants"]
    research = load_json(RESEARCH_PATH)
    records = load_legacy_records()
    known_ids = {record["question"]["id"] for record in records}

    if len(master["concepts"]) != 380:
        errors.append("v17 Concept Master must contain exactly 380 draft concepts")
    if len(inventory["items"]) != 1_000:
        errors.append("v17 Legacy Inventory must contain exactly 1,000 entries")
    if len(golden["concepts"]) != 100:
        errors.append("v17 Golden draft must contain exactly 100 concepts")
    if len(variants) != 270:
        errors.append("v17 Golden variant draft must contain exactly 270 items")
    if len(research["items"]) != 380:
        errors.append("v17 source research queue must contain exactly 380 entries")

    duplicate_master = deepcopy(master)
    duplicate_master["concepts"][1]["conceptID"] = duplicate_master["concepts"][0][
        "conceptID"
    ]
    expect_error(
        errors,
        "duplicate conceptID",
        validate_concept_master(duplicate_master, known_ids),
        "conceptID must be unique",
    )
    below_range = deepcopy(master)
    below_range["concepts"] = below_range["concepts"][:349]
    expect_error(
        errors,
        "349 concepts",
        validate_concept_master(below_range),
        "350-450 concepts",
    )
    above_range = deepcopy(master)
    while len(above_range["concepts"]) < 451:
        extra = deepcopy(above_range["concepts"][-1])
        extra["conceptID"] = f"{extra['conceptID']}.overflow-{len(above_range['concepts'])}"
        extra["relatedConceptIDs"] = []
        extra["legacySourceIDs"] = [f"overflow-{len(above_range['concepts'])}"]
        above_range["concepts"].append(extra)
    expect_error(
        errors,
        "451 concepts",
        validate_concept_master(above_range),
        "350-450 concepts",
    )
    unknown_related = deepcopy(master)
    unknown_related["concepts"][0]["relatedConceptIDs"] = ["takken.unknown"]
    expect_error(
        errors,
        "unknown relatedConceptID",
        validate_concept_master(unknown_related, known_ids),
        "unknown/self relatedConceptID",
    )
    reviewed_without_source = deepcopy(master)
    reviewed_without_source["concepts"][0].update(
        reviewStatus="reviewed",
        reviewer="v17-fixture",
        reviewedAt="2026-07-23",
        sourceNotes=["担当者が確認しました。"],
    )
    expect_error(
        errors,
        "reviewed concept without traceable source",
        validate_concept_master(reviewed_without_source, known_ids),
        "reviewed concept requires traceable sources",
    )
    reviewed_with_source = deepcopy(master)
    reviewed_with_source["concepts"][0].update(
        reviewStatus="reviewed",
        reviewer="v17-fixture",
        reviewedAt="2026-07-23",
        sourceNotes=["宅地建物取引業法第3条（2026-04-01確認）"],
    )
    source_errors = validate_concept_master(reviewed_with_source, known_ids)
    if any("reviewed concept requires" in value for value in source_errors):
        errors.append("v17 concept source gate rejected a traceable law/article source")

    duplicate_inventory = deepcopy(inventory)
    duplicate_item = next(
        value
        for value in duplicate_inventory["items"]
        if value["disposition"] == "duplicate"
    )
    duplicate_item["duplicateOfLegacyID"] = None
    expect_error(
        errors,
        "duplicate inventory without target",
        validate_legacy_inventory(duplicate_inventory, master, records),
        "duplicate requires a valid prior legacy ID",
    )

    duplicate_pair = deepcopy(variants)
    repeated = deepcopy(duplicate_pair[0])
    repeated["id"] = repeated["id"] + ".new-id"
    duplicate_pair.append(repeated)
    expect_error(
        errors,
        "duplicate concept/variantID",
        validate_variant_quality(duplicate_pair, master, require_reviewed=False),
        "conceptID/variantID pairs must be unique",
    )
    duplicate_prompt = deepcopy(variants)
    repeated = deepcopy(duplicate_prompt[0])
    repeated["id"] = repeated["id"] + ".duplicate-prompt"
    repeated["variantID"] = repeated["variantID"] + ".duplicate-prompt"
    duplicate_prompt.append(repeated)
    expect_error(
        errors,
        "exact duplicate prompt",
        validate_variant_quality(duplicate_prompt, master, require_reviewed=False),
        "exact semantic duplicate prompt",
    )
    missing_rationale = deepcopy(variants[:1])
    missing_rationale[0]["wrongChoiceRationales"] = {}
    expect_error(
        errors,
        "missing distractor rationale",
        validate_variant_quality(missing_rationale, master, require_reviewed=False),
        "every distractor requires one rationale",
    )
    invalid_misconception = deepcopy(variants[:1])
    wrong_choice = next(
        value
        for value in invalid_misconception[0]["choices"]
        if value["id"] != invalid_misconception[0]["correctChoiceID"]
    )
    wrong_choice["misconceptionCode"] = "made-up-code"
    expect_error(
        errors,
        "unknown misconceptionCode",
        validate_variant_quality(
            invalid_misconception, master, require_reviewed=False
        ),
        "invalid misconceptionCode",
    )
    slow_unlock = deepcopy(variants[:1])
    slow_unlock[0]["unlockEligible"] = True
    slow_unlock[0]["estimatedSeconds"] = 31
    expect_error(
        errors,
        "slow unlock question",
        validate_variant_quality(slow_unlock, master, require_reviewed=False),
        "unlock eligibility exceeds",
    )

    expect_error(
        errors,
        "unreviewed Golden candidate",
        golden_candidate_errors(golden, variants, master),
        "reviewed candidate contains ai_draft",
    )
    free_errors, selected = free_sample_selection_errors(variants, golden, master)
    expect_error(
        errors,
        "unreviewed free sample generation",
        free_errors,
        "reviewed candidate contains ai_draft",
    )
    if selected:
        errors.append("unreviewed Golden variants produced a free-sample selection")
    full_errors = full_pack_candidate_errors(variants, master, inventory)
    expect_error(
        errors,
        "270-item full pack",
        full_errors,
        "at least 1,000 variants",
    )
    expect_error(
        errors,
        "100-concept full pack",
        full_errors,
        "350-450 concepts",
    )

    regenerated = build_concept_assets()
    for key, current in {
        "master": master,
        "inventory": inventory,
        "golden": golden,
        "variants": load_json(VARIANTS_PATH),
        "research": research,
    }.items():
        if digest(regenerated[key]) != digest(current):
            errors.append(f"v17 authoring generation is not deterministic: {key}")

    required_scripts = [
        "scripts/build_takken_legacy_inventory",
        "scripts/validate_takken_concept_master",
        "scripts/audit_takken_concept_coverage",
        "scripts/export_takken_concept_review_batch",
        "scripts/generate_takken_variant_drafts",
        "scripts/check_takken_golden_candidate",
        "scripts/generate_takken_free_sample",
        "scripts/check_takken_full_pack_candidate",
        "scripts/audit_takken_content_v17",
        "scripts/prepare_takken_concept_assets_v17",
    ]
    for relative in required_scripts:
        source = read(relative)
        if "sys.dont_write_bytecode = True" not in source:
            errors.append(f"v17 authoring command can write Python cache: {relative}")

    engine = read(
        "LockAndStudy/StudyExperiences/Takken/Core/TakkenLearningEngine.swift"
    )
    mastery = read(
        "LockAndStudy/StudyExperiences/Takken/Core/TakkenConceptMastery.swift"
    )
    report = read("LockAndStudy/StudyExperiences/Takken/TakkenReportProvider.swift")
    tests = read("LockAndStudyTests/TakkenConceptMasterV17Tests.swift")
    project = read("LockAndStudy.xcodeproj/project.pbxproj")
    for required in [
        "TakkenConceptMasterySnapshot",
        "distinctVariantCount",
        "consecutiveFirstAttemptCorrect",
        "reviewIntervalDays",
    ]:
        if required not in mastery:
            errors.append(f"v17 concept mastery implementation is missing: {required}")
    for required in [
        "Dictionary(grouping: eligible, by: \\.resolvedConceptID)",
        "bestVariant",
        "weaknessPenalty",
        "(question.estimatedSeconds ?? 30) <= 30",
    ]:
        if required not in engine:
            errors.append(f"v17 concept-first selection is missing: {required}")
    for required in [
        "takken.mastered",
        "takken.stabilizing",
        "takken.relearningActive",
        "takken.dueConcepts",
        "takken.multiVariant",
        "takken.newlyMastered",
    ]:
        if required not in report:
            errors.append(f"v17 Takken report metric is missing: {required}")
    for required in [
        "testWrongAnswerAndSameSessionRetryDoNotMasterConcept",
        "testDifferentSessionsAndVariantsProgressThroughStabilizingAndMastered",
        "testSelectionUsesWeakMisconceptionAndAvoidsRecentVariant",
        "testUnlockExcludesLongCaseStudyAndPreviewChoosesDifferentVariant",
        "testSelectionDoesNotRepeatConceptWhenRequestedCountExceedsDistinctConcepts",
    ]:
        if required not in tests:
            errors.append(f"v17 XCTest proof is missing: {required}")
    for filename in [
        "TakkenConceptMastery.swift",
        "TakkenConceptMasterV17Tests.swift",
    ]:
        if filename not in project:
            errors.append(f"Xcode project does not register {filename}")

    for relative in [
        "Docs/TAKKEN_CONCEPT_MASTER_V17.md",
        "Docs/TAKKEN_QUESTION_VARIANT_GUIDE_V17.md",
        "Docs/TAKKEN_LEGACY_INVENTORY_V17.md",
        "Docs/TAKKEN_GOLDEN_SET_V17.md",
        "Docs/TAKKEN_CONCEPT_MASTERY_V17.md",
        "Docs/FINAL_VERIFICATION_V17.md",
    ]:
        if not (ROOT / relative).is_file():
            errors.append(f"v17 documentation is missing: {relative}")

    release_candidate = (
        ROOT
        / "ContentSource/ReleaseCandidates/takken_2026_free_sample_v17_candidate.json"
    )
    if release_candidate.exists():
        errors.append("an unreviewed v17 free sample was written as a ReleaseCandidate")
    bytecode = list((ROOT / "scripts").rglob("*.pyc"))
    caches = [
        path for path in (ROOT / "scripts").rglob("__pycache__") if path.is_dir()
    ]
    if bytecode or caches:
        errors.append("scripts contains Python bytecode/cache artifacts")

    if snapshot["golden"]["reviewedCount"] != 0:
        errors.append("v17 audit reports an automatically reviewed Golden variant")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(
        "Platform v17 concept master, inventory, Golden draft, concept-first "
        "runtime, and Release protection verification passed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
