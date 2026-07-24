#!/usr/bin/env python3
"""Independent repository validator for the Takken 2026 v26 candidate."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "ContentSource/TakkenWork"
QUESTIONS = (
    WORK / "ReviewCandidates/takken_2026_questions_v26_candidate.json"
)
FREE_SAMPLE = (
    WORK / "ReviewCandidates/takken_2026_free_sample_100_v26_candidate.json"
)
CATALOG = (
    WORK / "ReviewCandidates/study_pack_catalog_takken_v26_review.json"
)
METADATA = (
    WORK / "ReviewCandidates/takken2026_metadata_v26_candidate.json"
)
CONCEPT_MASTER = (
    WORK / "Concepts/takken_2026_concept_master_v26_candidate.json"
)
SOURCE_REGISTRY = (
    WORK / "Sources/takken_2026_source_registry_v26_candidate.json"
)
EXTERNAL_REVIEW_QUEUE = (
    WORK / "Review/takken_v26_external_legal_review_queue.csv"
)
PRIORITY_REVIEW_QUEUE = (
    WORK / "Review/takken_v26_priority_review_queue.csv"
)

EXPECTED_QUESTION_SHA = (
    "af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263"
)
EXPECTED_FREE_SHA = (
    "52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e"
)
EXPECTED_CATEGORY_COUNTS = Counter(
    {"宅建業法": 400, "権利関係": 280, "法令上の制限": 160, "税・その他": 160}
)
EXPECTED_FORMAT_COUNTS = Counter(
    {
        "true_false": 300,
        "wording_contrast": 260,
        "number_choice": 60,
        "multiple_choice": 300,
        "case_study": 80,
    }
)
EXPECTED_USAGE_COUNTS = Counter(
    {"unlock_micro": 680, "standard_practice": 240, "integrated_mock": 80}
)
EXPECTED_DIFFICULTY_COUNTS = Counter({"基礎": 400, "標準": 450, "応用": 150})
FORBIDDEN_TEXT = re.compile(
    r"通勤服|趣味|SNS投稿|出身校|出身地|要校閲|AI草稿|"
    r"PLACEHOLDER|TODO|TBD|なければなります|必要ありません|"
    r"該当し得ません|公式過去問100%[ \t]*Coverage",
    re.IGNORECASE,
)


def load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []
    required = (
        QUESTIONS,
        FREE_SAMPLE,
        CATALOG,
        METADATA,
        CONCEPT_MASTER,
        SOURCE_REGISTRY,
        EXTERNAL_REVIEW_QUEUE,
        PRIORITY_REVIEW_QUEUE,
    )
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        for path in missing:
            print(f"ERROR: required v26 file is missing: {path}")
        return 1

    questions = load(QUESTIONS)
    free_document = load(FREE_SAMPLE)
    catalog = load(CATALOG)
    metadata = load(METADATA)
    concept_master = load(CONCEPT_MASTER)
    source_registry = load(SOURCE_REGISTRY)

    if not isinstance(questions, list) or len(questions) != 1_000:
        return _report(["full question document must contain exactly 1,000 items"])
    if not isinstance(free_document, dict):
        return _report(["free sample must be a wrapper object"])
    free = free_document.get("questions")
    if not isinstance(free, list) or len(free) != 100:
        return _report(["free sample must contain exactly 100 questions"])
    if sha256(QUESTIONS) != EXPECTED_QUESTION_SHA:
        fail(errors, "full question SHA-256 differs from the signed package")
    if sha256(FREE_SAMPLE) != EXPECTED_FREE_SHA:
        fail(errors, "free sample SHA-256 differs from the signed package")

    if Counter(value.get("category") for value in questions) != EXPECTED_CATEGORY_COUNTS:
        fail(errors, "category distribution differs from v26 plan")
    if Counter(value.get("format") for value in questions) != EXPECTED_FORMAT_COUNTS:
        fail(errors, "format distribution differs from v26 plan")
    if Counter(value.get("usageType") for value in questions) != EXPECTED_USAGE_COUNTS:
        fail(errors, "usage distribution differs from v26 plan")
    if Counter(value.get("difficulty") for value in questions) != EXPECTED_DIFFICULTY_COUNTS:
        fail(errors, "difficulty distribution differs from v26 plan")

    ids = [value.get("id") for value in questions]
    if len(ids) != len(set(ids)):
        fail(errors, "question IDs are not unique")
    concepts = {value.get("conceptID") for value in questions}
    if len(concepts) != 380:
        fail(errors, "full questions must cover exactly 380 concepts")
    free_ids = {value.get("id") for value in free}
    if len(free_ids) != 100 or not free_ids.issubset(set(ids)):
        fail(errors, "free questions must be a unique subset of the full pack")
    if len({value.get("conceptID") for value in free}) != 100:
        fail(errors, "free sample must cover 100 distinct concepts")
    full_by_id = {value["id"]: value for value in questions}
    if any(full_by_id.get(value.get("id")) != value for value in free):
        fail(errors, "free questions must be byte-equivalent objects from the full pack")

    routes: set[tuple[str, tuple[str, ...]]] = set()
    for question in questions:
        question_id = str(question.get("id"))
        choices = question.get("choices") or []
        choice_ids = [value.get("id") for value in choices]
        texts = [str(value.get("text")) for value in choices]
        route = (
            re.sub(r"\s+", "", str(question.get("prompt") or "")),
            tuple(texts),
        )
        if route in routes:
            fail(errors, f"{question_id}: duplicate prompt/choice route")
        routes.add(route)
        if len(texts) != len(set(texts)):
            fail(errors, f"{question_id}: duplicate choice text")
        correct_id = question.get("correctChoiceID")
        if correct_id not in choice_ids:
            fail(errors, f"{question_id}: correct choice ID is missing")
        elif question.get("correctIndex") != choice_ids.index(correct_id):
            fail(errors, f"{question_id}: correct choice index is inconsistent")
        wrong = [value for value in choices if value.get("id") != correct_id]
        rationales = question.get("wrongChoiceRationales") or {}
        if set(rationales) != {value.get("id") for value in wrong}:
            fail(errors, f"{question_id}: wrong-choice rationale map is incomplete")
        if any(not value.get("rationale") for value in wrong):
            fail(errors, f"{question_id}: a wrong choice has no rationale")
        searchable = " ".join(
            [
                str(question.get("prompt") or ""),
                str(question.get("shortExplanation") or ""),
                str(question.get("longExplanation") or ""),
                *texts,
            ]
        )
        if FORBIDDEN_TEXT.search(searchable):
            fail(errors, f"{question_id}: forbidden placeholder/claim text")
        if question.get("reviewStatus") != "ai_review_candidate":
            fail(errors, f"{question_id}: reviewStatus was promoted")
        if any((question.get("legalReviewChecklist") or {}).values()):
            fail(errors, f"{question_id}: legal review was automatically approved")
        if question.get("isPlaceholder") is not False:
            fail(errors, f"{question_id}: placeholder flag must be false")
        if not question.get("preview") or not question.get("minimumReviewSeconds"):
            fail(errors, f"{question_id}: preview/review-time metadata is missing")
        if question.get("format") == "case_study" and question.get("unlockEligible"):
            fail(errors, f"{question_id}: case study must not enter Unlock")
        if question.get("usageType") == "integrated_mock" and question.get(
            "unlockEligible"
        ):
            fail(errors, f"{question_id}: integrated mock must not enter Unlock")

    pack = next(
        (value for value in catalog.get("packs", []) if value.get("id") == "takken2026.v1"),
        None,
    )
    english = next(
        (value for value in catalog.get("packs", []) if value.get("id") == "english3000.v1"),
        None,
    )
    if pack is None or english is None:
        fail(errors, "catalog must retain both Takken and English packs")
    else:
        if pack.get("saleReady") is not False:
            fail(errors, "Takken catalog saleReady must remain false")
        if pack.get("oneTimeProductID") != (
            "com.ameneko.lockandstudy.pack.takken2026.v1"
        ):
            fail(errors, "Takken one-time product ID changed")
        if pack.get("expectedItemCount") != 1_000:
            fail(errors, "catalog expectedItemCount must be 1,000")
        if pack.get("sampleDefinition", {}).get("count") != 100:
            fail(errors, "catalog free sample count must be 100")
        content_files = pack.get("contentFiles") or []
        if len(content_files) != 2:
            fail(errors, "Takken catalog must reference full and free content")
        else:
            expected_files = {
                QUESTIONS.name: (EXPECTED_QUESTION_SHA, 1_000),
                FREE_SAMPLE.name: (EXPECTED_FREE_SHA, 100),
            }
            for entry in content_files:
                expected = expected_files.get(entry.get("path"))
                if expected is None:
                    fail(errors, f"catalog contains an unexpected file: {entry.get('path')}")
                    continue
                path = QUESTIONS.parent / entry["path"]
                if (
                    entry.get("sha256") != sha256(path)
                    or entry.get("byteCount") != path.stat().st_size
                    or entry.get("itemCount") != expected[1]
                    or entry.get("sha256") != expected[0]
                ):
                    fail(errors, f"catalog integrity metadata is wrong: {entry['path']}")

    if metadata.get("saleReady") is not False:
        fail(errors, "metadata saleReady must remain false")
    if metadata.get("questionSHA256") != EXPECTED_QUESTION_SHA:
        fail(errors, "metadata full question SHA is inconsistent")
    if metadata.get("freeSampleSHA256") != EXPECTED_FREE_SHA:
        fail(errors, "metadata free sample SHA is inconsistent")
    if metadata.get("externalLegalReviewRequired") is not True:
        fail(errors, "metadata must require external legal review")

    concept_values = (
        concept_master.get("concepts")
        if isinstance(concept_master, dict)
        else None
    )
    if not isinstance(concept_values, list) or len(concept_values) != 380:
        fail(errors, "v26 Concept Master must contain exactly 380 concepts")
    if not isinstance(source_registry, dict) or not source_registry.get("sources"):
        fail(errors, "v26 source registry is empty")

    return _report(errors)


def _report(errors: list[str]) -> int:
    if errors:
        print("FAILED: Takken 2026 v26 repository candidate")
        for error in errors[:200]:
            print(f"- {error}")
        if len(errors) > 200:
            print(f"- ... {len(errors) - 200} additional error(s)")
        return 1
    print("PASS: Takken 2026 v26 repository candidate")
    print("questions=1000 free=100 concepts=380 saleReady=false")
    print(f"questionSHA256={EXPECTED_QUESTION_SHA}")
    print(f"freeSHA256={EXPECTED_FREE_SHA}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
