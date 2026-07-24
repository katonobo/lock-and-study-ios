#!/usr/bin/env python3
"""Production/internal-review trust-boundary checks shared by release gates."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASED = ROOT / "LockAndStudy/Resources/Content/Released"
CATALOG = RELEASED / "study_pack_catalog.json"
PROJECT = ROOT / "project.yml"
REVIEW = ROOT / "ContentSource/TakkenWork/ReviewCandidates"

CANDIDATE_PROFILE = "takken-v26-distinct-variant-review-candidate"
CANDIDATE_FLAG = "LOCKANDSTUDY_INTERNAL_CONTENT_REVIEW"
CANDIDATE_QUESTION_NAME = "takken_2026_questions_v26_candidate.json"
CANDIDATE_FREE_NAME = "takken_2026_free_sample_100_v26_candidate.json"
CANDIDATE_CATALOG_NAME = "study_pack_catalog_takken_v26_review.json"
CANDIDATE_METADATA_NAME = "takken2026_metadata_v26_candidate.json"
CANDIDATE_QUESTION_SHA = (
    "af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263"
)
CANDIDATE_FREE_SHA = (
    "52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e"
)
PRODUCTION_CATALOG_SHA = (
    "05571a3a05926f1c2ef28caef70f9991a3b2a4df550737345b8a47ff74e44685"
)
APPROVED_PRODUCTION_STATUSES = {"checked", "reviewed", "release"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def target_block(project_text: str, target_name: str) -> str:
    match = re.search(
        rf"^  {re.escape(target_name)}:\n(.*?)(?=^  [A-Za-z0-9_]+:\n|\Z)",
        project_text,
        flags=re.MULTILINE | re.DOTALL,
    )
    return match.group(1) if match else ""


def question_items(document: object) -> list[dict]:
    if isinstance(document, list):
        return [value for value in document if isinstance(value, dict)]
    if isinstance(document, dict) and isinstance(document.get("questions"), list):
        return [
            value
            for value in document["questions"]
            if isinstance(value, dict)
        ]
    if isinstance(document, dict) and isinstance(document.get("levels"), list):
        return [
            value
            for level in document["levels"]
            if isinstance(level, dict)
            for value in level.get("questions", [])
            if isinstance(value, dict)
        ]
    return []


def production_boundary_errors() -> list[str]:
    errors: list[str] = []
    if not CATALOG.is_file():
        return ["Production catalog is missing"]
    if sha256(CATALOG) != PRODUCTION_CATALOG_SHA:
        errors.append("Production catalog differs from protected reviewed-100 baseline")
    catalog = load_json(CATALOG)
    catalog_text = json.dumps(catalog, ensure_ascii=False)
    if CANDIDATE_PROFILE in catalog_text:
        errors.append("Production catalog references the v26 candidate profile")
    if "ai_review_candidate" in catalog_text:
        errors.append("Production catalog contains ai_review_candidate")

    candidate_names = {
        CANDIDATE_QUESTION_NAME,
        CANDIDATE_FREE_NAME,
        "takken_2026_questions_v20.json",
        "takken_2026_free_sample_100_v20.json",
    }
    leaked_files = sorted(
        path.name
        for path in RELEASED.rglob("*")
        if path.is_file() and path.name in candidate_names
    )
    if leaked_files:
        errors.append(f"v26 candidate files leaked into Production Released: {leaked_files}")

    for path in RELEASED.rglob("*.json"):
        document = load_json(path)
        text = json.dumps(document, ensure_ascii=False)
        if "ai_review_candidate" in text:
            errors.append(f"ai_review_candidate leaked into Production: {path.name}")
        invalid = sorted(
            {
                str(item.get("reviewStatus"))
                for item in question_items(document)
                if item.get("reviewStatus") is not None
                and item.get("reviewStatus") not in APPROVED_PRODUCTION_STATUSES
            }
        )
        if invalid:
            errors.append(
                f"Production question status is not approved in {path.name}: {invalid}"
            )

    project_text = PROJECT.read_text(encoding="utf-8")
    production = target_block(project_text, "LockAndStudy")
    if not production:
        errors.append("Production app target is missing from project.yml")
    if CANDIDATE_FLAG in production:
        errors.append("Production app target contains the internal review flag")
    if "ContentSource/TakkenWork/ReviewCandidates" in production:
        errors.append("Production app target includes v26 candidate resources")
    return errors


def review_boundary_errors() -> list[str]:
    errors: list[str] = []
    expected = {
        CANDIDATE_QUESTION_NAME: CANDIDATE_QUESTION_SHA,
        CANDIDATE_FREE_NAME: CANDIDATE_FREE_SHA,
        CANDIDATE_CATALOG_NAME: None,
        CANDIDATE_METADATA_NAME: None,
    }
    for name, digest in expected.items():
        path = REVIEW / name
        if not path.is_file():
            errors.append(f"Review resource is missing: {name}")
        elif digest and sha256(path) != digest:
            errors.append(f"Review resource SHA changed: {name}")

    project_text = PROJECT.read_text(encoding="utf-8")
    review = target_block(project_text, "LockAndStudyContentReview")
    if not review:
        errors.append("LockAndStudyContentReview target is missing")
    if CANDIDATE_FLAG not in review:
        errors.append("Review app target lacks the internal review compilation flag")
    if "ContentSource/TakkenWork/ReviewCandidates" not in review:
        errors.append("Review app target lacks candidate-only resources")

    if (REVIEW / CANDIDATE_CATALOG_NAME).is_file():
        catalog = load_json(REVIEW / CANDIDATE_CATALOG_NAME)
        takken = next(
            (
                pack
                for pack in catalog.get("packs", [])
                if pack.get("id") == "takken2026.v1"
            ),
            {},
        )
        if takken.get("contentQualityProfile") != CANDIDATE_PROFILE:
            errors.append("Review catalog candidate profile changed")
        if takken.get("saleReady") is not False:
            errors.append("Review catalog saleReady must remain false")
        paths = {
            descriptor.get("path")
            for descriptor in takken.get("contentFiles", [])
        }
        if paths != {CANDIDATE_QUESTION_NAME, CANDIDATE_FREE_NAME}:
            errors.append("Review catalog does not reference exactly the two candidate files")
    return errors


def report(label: str, errors: list[str]) -> int:
    if errors:
        print(f"{label} failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"{label} passed.")
    return 0
