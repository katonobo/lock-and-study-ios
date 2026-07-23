#!/usr/bin/env python3
"""Executable v18 proofs for the human concept workflow and runtime fixes."""
from __future__ import annotations

import hashlib
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

sys.dont_write_bytecode = True

from takken_concept_workflow import (
    KNOWN_GOLDEN_DUPLICATE_CANDIDATES,
    build_boundary_audit,
    document_digest,
    export_review_batch,
    import_review_batches,
    validate_review_batch,
)
from takken_concepts import (
    CONCEPT_ROOT,
    FREE_SAMPLE_PROFILES_PATH,
    GOLDEN_PATH,
    MASTER_PATH,
    REVIEWED_ROOT,
    ROOT,
    VARIANTS_PATH,
    build_free_sample_profiles,
    build_golden,
    build_inventory_from_master,
    build_variant_drafts_from_master,
    concept_mapping,
    full_pack_candidate_errors,
    load_json,
    load_legacy_records,
    protected_release_errors,
    select_free_sample_with_profile,
    tier_variant_shortages,
    validate_concept_master,
    validate_golden_question_set,
    validate_legacy_inventory,
    write_all_draft_assets,
    write_json,
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def expect(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def humanize(document: dict) -> None:
    document["status"] = "reviewed"
    for concept in document["concepts"]:
        concept.update(
            reviewStatus="reviewed",
            reviewer="v18-human-fixture",
            reviewedAt="2026-07-23",
            reviewNote=(
                "v18 integration fixtureで論点境界、旧ID所有、年度確認方針を確認した。"
            ),
            reviewDecision="accept",
            sourceNotes=[
                "宅地建物取引業法第3条（2026-04-01確認・v18 fixture）"
            ],
            requiresSourceResearch=False,
            requiresAnnualReview=True,
            annualReviewReason="法令依存のため毎年度確認する",
        )


def locate(documents: list[dict], legacy_id: str) -> tuple[dict, dict]:
    for document in documents:
        for concept in document["concepts"]:
            if legacy_id in concept["legacySourceIDs"]:
                return document, concept
    raise AssertionError(f"fixture legacy ID missing: {legacy_id}")


def merge_concepts(
    documents: list[dict], left_legacy_id: str, right_legacy_id: str
) -> str:
    left_document, left = locate(documents, left_legacy_id)
    right_document, right = locate(documents, right_legacy_id)
    left_id = left["conceptID"]
    right_id = right["conceptID"]
    right_legacy_ids = list(right["legacySourceIDs"])
    left["legacySourceIDs"] = sorted(
        set(left["legacySourceIDs"]) | set(right_legacy_ids)
    )
    left["mergedFromConceptIDs"] = sorted({left_id, right_id})
    left["supersedesConceptIDs"] = sorted({left_id, right_id})
    left["reviewDecision"] = "merge"
    left["title"] = "v18 merge fixture title"
    left["canonicalRule"] = "v18 merge fixture canonical rule"
    right_document["concepts"].remove(right)
    if left_document is not right_document:
        left_document["transferredLegacyQuestionIDsIn"].extend(right_legacy_ids)
        right_document["transferredLegacyQuestionIDsOut"].extend(right_legacy_ids)
    return left["conceptID"]


def split_concept(documents: list[dict], excluded: set[str]) -> tuple[str, str]:
    for document in documents:
        for concept in list(document["concepts"]):
            if (
                concept["conceptID"] not in excluded
                and len(concept["legacySourceIDs"]) >= 2
            ):
                original_id = concept["conceptID"]
                left = deepcopy(concept)
                right = deepcopy(concept)
                left["conceptID"] = f"{original_id}.split-a"
                right["conceptID"] = f"{original_id}.split-b"
                left["legacySourceIDs"] = [concept["legacySourceIDs"][0]]
                right["legacySourceIDs"] = concept["legacySourceIDs"][1:]
                for value, title in ((left, "split A"), (right, "split B")):
                    value["title"] = f"v18 {title} fixture"
                    value["splitFromConceptID"] = original_id
                    value["supersedesConceptIDs"] = [original_id]
                    value["reviewDecision"] = "split"
                    value["relatedConceptIDs"] = []
                index = document["concepts"].index(concept)
                document["concepts"][index : index + 1] = [left, right]
                return left["conceptID"], right["conceptID"]
    raise AssertionError("no split fixture concept found")


def reviewed_variant(concept: dict, ordinal: int) -> dict:
    rationale = "誤答は対象となる主体・時期・適用条件が正解と異なります。"
    return {
        "id": f"v18.profile.{ordinal:03d}",
        "conceptID": concept["conceptID"],
        "variantID": f"judgment.{ordinal:03d}",
        "integratedConceptIDs": [],
        "format": "true_false",
        "prompt": f"{concept['title']}について正しい記述を選ぶ。{ordinal}",
        "choices": [
            {
                "id": "correct",
                "text": "正しい",
                "rationale": None,
                "misconceptionCode": None,
            },
            {
                "id": "wrong",
                "text": "誤り",
                "rationale": rationale,
                "misconceptionCode": "terminology",
            },
        ],
        "correctChoiceID": "correct",
        "correctIndex": 0,
        "wrongChoiceRationales": {"wrong": rationale},
        "category": concept["category"],
        "subCategory": concept["subCategory"],
        "difficulty": "標準",
        "estimatedSeconds": 20,
        "unlockEligible": True,
        "isPlaceholder": False,
        "reviewStatus": "reviewed",
        "distractorReviewStatus": "checked",
        "sourceNote": (
            "宅地建物取引業法第3条（2026-04-01確認・v18 fixture）"
        ),
        "reviewer": "v18-human-fixture",
        "reviewedAt": "2026-07-23",
        "reviewNote": "選択肢と誤答理由をfixtureとして確認した。",
    }


def main() -> int:
    errors: list[str] = []
    master = load_json(MASTER_PATH)
    generated_variants = load_json(VARIANTS_PATH)["variants"]
    records = load_legacy_records()
    known_ids = {value["question"]["id"] for value in records}

    expect(errors, not protected_release_errors(), "v18 changed protected Release state")
    expect(
        errors,
        not list(CONCEPT_ROOT.glob("takken_2026_*_v1.json")),
        "legacy top-level v17 data paths were not migrated",
    )
    expect(
        errors,
        all(value.get("reviewStatus") == "ai_draft" for value in master["concepts"]),
        "Generated master contains an automatic review promotion",
    )
    expect(
        errors,
        all(value.get("format") != "number_choice" for value in generated_variants),
        "unreviewed numericFacts produced number_choice",
    )
    expect(
        errors,
        all(value.get("isPlaceholder") is True for value in generated_variants),
        "v18 generated placeholder flag is incomplete",
    )

    reviewed_before = {
        str(path.relative_to(REVIEWED_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in REVIEWED_ROOT.rglob("*")
        if path.is_file()
    }
    write_all_draft_assets()
    reviewed_after = {
        str(path.relative_to(REVIEWED_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in REVIEWED_ROOT.rglob("*")
        if path.is_file()
    }
    expect(
        errors,
        reviewed_before == reviewed_after,
        "Generated draft regeneration overwrote Reviewed",
    )

    with tempfile.TemporaryDirectory(prefix="lockandstudy-v18-") as temporary:
        temporary_root = Path(temporary)
        batches = temporary_root / "batches"
        reviewed_output = temporary_root / "concept_master_reviewed.json"
        batch_size = 50
        batch_count = (len(master["concepts"]) + batch_size - 1) // batch_size
        for batch_number in range(1, batch_count + 1):
            export_review_batch(
                batch_number,
                source_master_path=MASTER_PATH,
                output_root=batches,
                batch_size=batch_size,
            )
        paths = sorted(
            batches.glob("takken_2026_concept_review_batch_*.json")
        )
        documents = [load_json(path) for path in paths]
        for document in documents:
            humanize(document)

        merge_id = merge_concepts(
            documents, "tl_gyoho_35_001", "tl_gyoho_35_002"
        )
        split_ids = split_concept(documents, {merge_id})
        for path, document in zip(paths, documents):
            write_json(path, document)
        output, changed = import_review_batches(
            batches, source_master_path=MASTER_PATH, output_path=reviewed_output
        )
        expect(errors, changed and output == reviewed_output, "review batch import failed")
        _, changed_again = import_review_batches(
            batches, source_master_path=MASTER_PATH, output_path=reviewed_output
        )
        expect(errors, not changed_again, "review batch import is not idempotent")
        reviewed_master = load_json(reviewed_output)
        expect(
            errors,
            len(reviewed_master["concepts"]) == 380,
            "merge + split fixture did not preserve the reviewed concept count",
        )
        merged = next(
            value
            for value in reviewed_master["concepts"]
            if value["conceptID"] == merge_id
        )
        expect(
            errors,
            {"tl_gyoho_35_001", "tl_gyoho_35_002"}.issubset(
                set(merged["legacySourceIDs"])
            ),
            "merge fixture lost legacy ownership",
        )
        expect(
            errors,
            all(
                any(
                    concept["conceptID"] == split_id
                    for concept in reviewed_master["concepts"]
                )
                for split_id in split_ids
            ),
            "split fixture did not create both reviewed concepts",
        )
        inventory = build_inventory_from_master(reviewed_master)
        errors.extend(validate_legacy_inventory(inventory, reviewed_master, records))

        drafts = build_variant_drafts_from_master(reviewed_master)
        merged_drafts = [
            value for value in drafts["variants"] if value["conceptID"] == merge_id
        ]
        expect(errors, bool(merged_drafts), "reviewed master generated no merged variant")
        expect(
            errors,
            all(
                value["authoringContext"]["conceptTitle"]
                == "v18 merge fixture title"
                and value["authoringContext"]["canonicalRule"]
                == "v18 merge fixture canonical rule"
                for value in merged_drafts
            ),
            "variant generator ignored reviewed title/canonicalRule",
        )
        expect(
            errors,
            drafts["sourceConceptMasterDigest"] == document_digest(reviewed_master),
            "variant generator fell back to Generated master",
        )

        golden = build_golden(reviewed_master, concept_mapping(reviewed_master))
        errors.extend(validate_golden_question_set(golden, reviewed_master))
        expect(
            errors,
            len(golden["goldenQuestionIDs"]) == 100
            and golden["distinctConceptCount"] < 100,
            "Golden Question/Concept separation did not allow merged concepts",
        )

        invalid_number_master = deepcopy(reviewed_master)
        invalid_number_master["concepts"][0]["recommendedFormats"].append(
            "number_choice"
        )
        expect(
            errors,
            any(
                "human-reviewed numericFact" in value
                for value in validate_concept_master(
                    invalid_number_master, known_ids
                )
            ),
            "article/label number generated a number_choice without numericFacts",
        )

        broken_batch = deepcopy(documents[0])
        first = broken_batch["concepts"][0]
        second = broken_batch["concepts"][1]
        second["legacySourceIDs"].append(first["legacySourceIDs"][0])
        expect(
            errors,
            any("owned by both" in value for value in validate_review_batch(broken_batch)),
            "duplicate legacy ownership was not rejected",
        )
        orphan_batch = deepcopy(documents[0])
        orphan_batch["concepts"][0]["legacySourceIDs"].pop()
        expect(
            errors,
            any(
                "must own source legacy IDs exactly once" in value
                for value in validate_review_batch(orphan_batch)
            ),
            "orphan legacy ownership was not rejected",
        )

        selected_concepts = []
        for category in ("宅建業法", "権利関係", "法令上の制限", "税・その他"):
            selected_concepts.extend(
                [
                    value
                    for value in reviewed_master["concepts"]
                    if value["category"] == category
                ][:2]
            )
        profile_variants = [
            reviewed_variant(value, index)
            for index, value in enumerate(selected_concepts, start=1)
        ]
        profile = {
            "profileID": "v18-fixture",
            "questionCount": 8,
            "scope": "all_reviewed_concepts",
            "minimumDistinctConceptCount": 8,
            "maximumQuestionsPerConcept": 1,
            "categoryTargets": {
                "宅建業法": 2,
                "権利関係": 2,
                "法令上の制限": 2,
                "税・その他": 2,
            },
            "formatTargets": {"true_false": 8},
            "difficultyTargets": {"標準": 8},
            "minimumUnlockEligibleCount": 8,
            "maximumCaseStudyCount": 0,
        }
        selection_errors, selected = select_free_sample_with_profile(
            profile_variants, reviewed_master, golden, profile
        )
        errors.extend(selection_errors)
        expect(
            errors,
            len(selected) == 8
            and len({value["conceptID"] for value in selected}) == 8,
            "free sample distribution profile did not select 8 concepts",
        )

        full_pack_errors = full_pack_candidate_errors(
            profile_variants, reviewed_master, inventory
        )
        expect(
            errors,
            any("planned total" in value for value in full_pack_errors),
            "full pack plan counts were not enforced",
        )

    audit = build_boundary_audit(master)
    known_warnings = [
        value
        for value in audit["warnings"]
        if value["type"] == "known_semantic_duplicate_candidate"
    ]
    expect(
        errors,
        len(known_warnings) == len(KNOWN_GOLDEN_DUPLICATE_CANDIDATES),
        "known Golden semantic duplicate warnings are missing",
    )
    expect(
        errors,
        audit["automaticMergeSplitForbidden"] is True,
        "boundary audit permits automatic merge/split",
    )
    expect(
        errors,
        load_json(FREE_SAMPLE_PROFILES_PATH) == build_free_sample_profiles(),
        "free sample profiles are not deterministic",
    )
    expect(
        errors,
        bool(tier_variant_shortages(master, generated_variants)),
        "Golden shortage report is unexpectedly empty",
    )

    for relative in (
        "scripts/validate_takken_concept_review_batch",
        "scripts/import_takken_concept_review_batches",
        "scripts/audit_takken_concept_boundaries",
        "scripts/audit_takken_content_v18",
        "scripts/migrate_takken_concept_layout_v18",
    ):
        expect(
            errors,
            "sys.dont_write_bytecode = True" in read(relative),
            f"{relative} can write Python cache",
        )
    for relative in (
        "ContentSource/TakkenConcepts/README.md",
        "ContentSource/TakkenConcepts/Schemas/review_batch_v2.schema.json",
        "ContentSource/TakkenConcepts/Schemas/golden_question_set_v1.schema.json",
        "ContentSource/TakkenConcepts/Schemas/free_sample_profile_v1.schema.json",
        "Docs/TAKKEN_CONCEPT_WORKFLOW_V18.md",
        "Docs/TAKKEN_BOUNDARY_AUDIT_V18.md",
        "Docs/TAKKEN_GOLDEN_QUESTION_SET_V18.md",
        "Docs/TAKKEN_MISCONCEPTION_LIFECYCLE_V18.md",
        "Docs/FINAL_VERIFICATION_V18.md",
    ):
        expect(errors, (ROOT / relative).is_file(), f"v18 artifact missing: {relative}")
    swift = read("LockAndStudy/StudyExperiences/Takken/TakkenExperience.swift")
    mastery = read(
        "LockAndStudy/StudyExperiences/Takken/Core/TakkenConceptMastery.swift"
    )
    tests = read("LockAndStudyTests/TakkenConceptWorkflowV18Tests.swift")
    for required in (
        "misconceptionCodesByChoiceID",
        "TakkenMisconceptionTagger.tags",
    ):
        expect(errors, required in swift, f"unlock misconception proof missing: {required}")
    for required in (
        "activeMisconceptionCodes",
        "resolvedByTargetedRecall",
        "resolvedByMasteryAfterWrong",
    ):
        expect(errors, required in mastery, f"misconception resolution missing: {required}")
    for required in (
        "testUnlockWrongAnswerPersistsSameMisconceptionTagAsPractice",
        "testMisconceptionResolvesAcrossDifferentVariantsAndSessionsThenReactivates",
    ):
        expect(errors, required in tests, f"v18 XCTest proof missing: {required}")

    if errors:
        for error in errors[:100]:
            print(f"ERROR: {error}")
        if len(errors) > 100:
            print(f"ERROR: ... {len(errors) - 100} additional error(s) omitted")
        return 1
    print(
        "Platform v18 reviewed workflow, Golden mapping, boundary audit, "
        "variant generation, and misconception verification passed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
