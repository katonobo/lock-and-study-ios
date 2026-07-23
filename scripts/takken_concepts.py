#!/usr/bin/env python3
"""Freeze-safe authoring support for the Takken v17 concept workflow.

This module only reads released content. Every artifact it writes lives under
ContentSource/TakkenConcepts and remains explicitly unreviewed.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import tempfile
import unicodedata
from collections import Counter, defaultdict
from copy import deepcopy
from pathlib import Path
from typing import Iterable

import sys

sys.dont_write_bytecode = True

from content_checks import (
    _has_traceable_source_note,
    _parsed_review_date,
    validate_takken_v2,
)


ROOT = Path(__file__).resolve().parents[1]
CONCEPT_ROOT = ROOT / "ContentSource/TakkenConcepts"
GENERATED_ROOT = CONCEPT_ROOT / "Generated"
REVIEW_BATCH_ROOT = CONCEPT_ROOT / "ReviewBatches"
REVIEWED_ROOT = CONCEPT_ROOT / "Reviewed"
DRAFT_ROOT = CONCEPT_ROOT / "Drafts"
CONCEPT_RELEASE_CANDIDATE_ROOT = CONCEPT_ROOT / "ReleaseCandidates"
BACKUP_ROOT = CONCEPT_ROOT / "Backups"
MASTER_PATH = GENERATED_ROOT / "concept_master_ai_draft.json"
GOLDEN_PATH = GENERATED_ROOT / "golden_question_set_ai_draft.json"
INVENTORY_PATH = GENERATED_ROOT / "legacy_inventory_ai_draft.json"
VARIANTS_PATH = GENERATED_ROOT / "golden_variants_ai_draft.json"
RESEARCH_PATH = GENERATED_ROOT / "source_research_queue_ai_draft.json"
BOUNDARY_AUDIT_JSON_PATH = GENERATED_ROOT / "concept_boundary_audit_v18.json"
BOUNDARY_AUDIT_MARKDOWN_PATH = GENERATED_ROOT / "concept_boundary_audit_v18.md"
BOUNDARY_DECISIONS_PATH = REVIEW_BATCH_ROOT / "concept_boundary_decisions_v18.json"
FREE_SAMPLE_PROFILES_PATH = GENERATED_ROOT / "free_sample_profiles_v18.json"
REVIEWED_MASTER_PATH = REVIEWED_ROOT / "concept_master_reviewed.json"
REVIEWED_INVENTORY_PATH = REVIEWED_ROOT / "legacy_inventory_reviewed.json"
REVIEWED_RESEARCH_PATH = REVIEWED_ROOT / "source_research_reviewed.json"
RELEASE_CANDIDATE_ROOT = CONCEPT_RELEASE_CANDIDATE_ROOT

LEGACY_LAYOUT_PATHS = {
    CONCEPT_ROOT / "takken_2026_concept_master_draft_v1.json": MASTER_PATH,
    CONCEPT_ROOT / "takken_2026_golden_100_concepts_draft_v1.json": GOLDEN_PATH,
    CONCEPT_ROOT / "takken_2026_legacy_question_inventory_v1.json": INVENTORY_PATH,
    CONCEPT_ROOT / "takken_2026_golden_variants_draft_v1.json": VARIANTS_PATH,
    CONCEPT_ROOT / "takken_2026_source_research_queue_v1.json": RESEARCH_PATH,
}

RELEASE_PATH = (
    ROOT / "LockAndStudy/Resources/Content/Released/takken_2026_free_100_v1.json"
)
CATALOG_PATH = (
    ROOT / "LockAndStudy/Resources/Content/Released/study_pack_catalog.json"
)
V2_CANDIDATE_PATH = (
    ROOT / "ContentSource/Drafts/takken_2026_free_100_v2_candidates.json"
)

PROTECTED_RELEASE_SHA256 = (
    "6d4ce62f86a2a0b7805ec39442e3b01968c9f11947b9c2dd7fbbf8055e00d6af"
)
PROTECTED_CATALOG_SHA256 = (
    "05571a3a05926f1c2ef28caef70f9991a3b2a4df550737345b8a47ff74e44685"
)

LEGACY_SOURCES = (
    (
        "released_free_100",
        "LockAndStudy/Resources/Content/Released/takken_2026_free_100_v1.json",
    ),
    (
        "legacy_gyoho_200",
        "ContentSource/Reviewed/takken_2026_gyoho_reviewed_200_v1.json",
    ),
    (
        "horei_draft_200",
        "ContentSource/Drafts/takken_2026_horei_draft_200_v1.json",
    ),
    (
        "kenri_draft_300",
        "ContentSource/Drafts/takken_2026_kenri_draft_300_v1.json",
    ),
    (
        "tax_other_draft_200",
        "ContentSource/Drafts/takken_2026_tax_draft_200_v1.json",
    ),
)

CATEGORY_TARGETS = {
    "宅建業法": 140,
    "権利関係": 110,
    "法令上の制限": 65,
    "税・その他": 65,
}
CATEGORY_DOMAINS = {
    "宅建業法": "gyoho",
    "権利関係": "rights",
    "法令上の制限": "regulation",
    "税・その他": "tax-other",
}
SUBCATEGORY_SLUGS = {
    "免許制度": "license",
    "宅建士制度": "broker",
    "営業保証金": "deposit",
    "保証協会": "guarantee-association",
    "媒介契約": "brokerage",
    "重要事項説明（35条）": "disclosure-35",
    "37条書面": "contract-document-37",
    "8種制限": "seller-restrictions",
    "報酬規制": "fees",
    "事務所・案内所・標識・帳簿": "office-records",
    "監督処分・罰則": "supervision",
    "民法総則": "civil-general",
    "物権・対抗要件・共有": "property-rights",
    "債権総論": "obligations",
    "契約各論・売買": "contracts-sales",
    "担保物権・抵当権": "mortgage",
    "賃貸借・借地借家法": "leases",
    "相続": "inheritance",
    "区分所有法": "condominium",
    "不動産登記法": "registration",
    "横断・直前暗記": "cross-topic",
    "都市計画法": "city-planning",
    "建築基準法": "building-standards",
    "国土利用計画法": "land-use",
    "農地法": "agricultural-land",
    "土地区画整理法": "land-readjustment",
    "宅地造成及び特定盛土等規制法": "embankment",
    "不動産取得税": "acquisition-tax",
    "固定資産税": "fixed-asset-tax",
    "所得税・譲渡所得": "income-tax",
    "登録免許税": "registration-tax",
    "印紙税": "stamp-tax",
    "贈与税・住宅取得資金等": "gift-tax",
    "税法横断・軽減措置比較": "tax-relief",
    "地価公示法": "land-price-publication",
    "不動産鑑定評価": "appraisal",
    "価格評定横断": "valuation-cross",
    "住宅金融支援機構": "housing-finance",
    "景品表示法・不動産広告": "advertising",
    "土地": "land",
    "建物": "buildings",
    "統計": "statistics",
}
MEANING_KEYWORDS = (
    ("免許", "license"),
    ("欠格", "disqualification"),
    ("更新", "renewal"),
    ("事務所", "office"),
    ("宅建士", "broker"),
    ("専任", "exclusive"),
    ("媒介", "brokerage"),
    ("重要事項", "disclosure"),
    ("37条", "document-37"),
    ("手付", "deposit"),
    ("報酬", "fee"),
    ("保証", "guarantee"),
    ("供託", "depositing"),
    ("クーリング", "cooling-off"),
    ("契約不適合", "nonconformity"),
    ("意思表示", "declaration"),
    ("代理", "agency"),
    ("時効", "limitation"),
    ("抵当", "mortgage"),
    ("共有", "co-ownership"),
    ("相続", "inheritance"),
    ("賃貸借", "lease"),
    ("借地", "land-lease"),
    ("借家", "building-lease"),
    ("登記", "registration"),
    ("解除", "rescission"),
    ("取消", "cancellation"),
    ("都市計画", "city-plan"),
    ("開発許可", "development-permission"),
    ("用途地域", "zoning"),
    ("建築確認", "building-confirmation"),
    ("接道", "road-access"),
    ("容積率", "floor-area-ratio"),
    ("建蔽率", "building-coverage"),
    ("農地", "agricultural-land"),
    ("盛土", "embankment"),
    ("届出", "notification"),
    ("税", "tax"),
    ("軽減", "relief"),
    ("課税", "taxation"),
    ("地価", "land-price"),
    ("鑑定", "appraisal"),
    ("広告", "advertising"),
    ("統計", "statistics"),
    ("期限", "deadline"),
    ("期間", "period"),
    ("主体", "actor"),
    ("例外", "exception"),
)
ALLOWED_FORMATS = {
    "true_false",
    "number_choice",
    "wording_contrast",
    "multiple_choice",
    "case_study",
}
ALLOWED_DISPOSITIONS = {
    "base_variant_candidate",
    "additional_variant_candidate",
    "new_concept_candidate",
    "duplicate",
    "outdated",
    "low_value_retire",
    "requires_legal_research",
    "integrated_case_material",
}
ALLOWED_MISCONCEPTIONS = {
    "actor",
    "timing",
    "number",
    "scope",
    "exception",
    "obligation",
    "procedure",
    "document",
    "condition",
    "terminology",
}
ALLOWED_REVIEW_DECISIONS = {
    "accept",
    "merge",
    "split",
    "rename",
    "retire",
    "integrated_case",
}
FORMAT_ROUTE = {
    "true_false": "judgment",
    "number_choice": "number",
    "wording_contrast": "actor-timing-wording",
    "multiple_choice": "comparison",
    "case_study": "application-exception",
}
FORMAT_MISCONCEPTION = {
    "true_false": "terminology",
    "number_choice": "number",
    "wording_contrast": "timing",
    "multiple_choice": "scope",
    "case_study": "condition",
}
FORMAT_SECONDS = {
    "true_false": 20,
    "number_choice": 25,
    "wording_contrast": 30,
    "multiple_choice": 50,
    "case_study": 90,
}
GOLDEN_FORMAT_TARGETS = {
    "true_false": 73,
    "number_choice": 59,
    "wording_contrast": 59,
    "multiple_choice": 60,
    "case_study": 19,
}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalized(value: object) -> str:
    text = unicodedata.normalize("NFKC", str(value or "")).lower()
    return re.sub(r"[\s。、・（）()「」『』：:／/!?！？,，]", "", text)


def question_digest(question: dict) -> str:
    value = {
        "prompt": question.get("prompt"),
        "choices": question.get("choices"),
        "correctIndex": question.get("correctIndex"),
    }
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()


def write_text_atomic(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_json(path: Path, value: object) -> None:
    write_text_atomic(
        path, json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    )


def write_json_new(path: Path, value: object) -> None:
    if path.exists():
        raise FileExistsError(f"refusing to overwrite existing authoring file: {path}")
    write_json(path, value)


def migrate_legacy_layout() -> list[tuple[Path, Path]]:
    """Copy legacy v17 draft paths once; never write or inspect Reviewed files."""
    migrated: list[tuple[Path, Path]] = []
    for legacy_path, generated_path in LEGACY_LAYOUT_PATHS.items():
        if not legacy_path.exists() or generated_path.exists():
            continue
        generated_path.parent.mkdir(parents=True, exist_ok=True)
        write_text_atomic(
            generated_path, legacy_path.read_text(encoding="utf-8")
        )
        migrated.append((legacy_path, generated_path))
    return migrated


def protected_release_errors() -> list[str]:
    errors: list[str] = []
    if sha256(RELEASE_PATH) != PROTECTED_RELEASE_SHA256:
        errors.append("current Release 100 question SHA changed")
    if sha256(CATALOG_PATH) != PROTECTED_CATALOG_SHA256:
        errors.append("production catalog SHA changed")
    catalog = load_json(CATALOG_PATH)
    pack = next(
        (
            value
            for value in catalog.get("packs", [])
            if value.get("id") == "takken2026.v1"
        ),
        {},
    )
    if pack.get("expectedItemCount") != 100:
        errors.append("takken2026.v1 expectedItemCount must remain 100")
    if pack.get("saleReady") is not False:
        errors.append("takken2026.v1 saleReady must remain false")
    return errors


def load_legacy_records() -> list[dict]:
    records: list[dict] = []
    for pool, relative in LEGACY_SOURCES:
        path = ROOT / relative
        values = load_json(path)
        if not isinstance(values, list):
            raise ValueError(f"legacy source must be an array: {relative}")
        records.extend(
            {
                "sourcePool": pool,
                "sourceFile": relative,
                "question": value,
                "sourceOrder": index,
            }
            for index, value in enumerate(values)
        )
    ids = [record["question"].get("id") for record in records]
    if len(records) != 1_000 or len(ids) != len(set(ids)):
        raise ValueError("legacy source must contain exactly 1,000 unique questions")
    return records


def _features(record: dict) -> set[str]:
    question = record["question"]
    text = normalized(
        " ".join(
            str(question.get(key) or "")
            for key in ("keyPoint", "prompt", "shortExplanation", "subCategory")
        )
    )
    chars = {text[index : index + 2] for index in range(max(0, len(text) - 1))}
    keywords = {
        f"keyword:{slug}" for keyword, slug in MEANING_KEYWORDS if keyword in text
    }
    return chars | keywords


def _cluster_similarity(lhs: list[dict], rhs: list[dict]) -> float:
    left = set().union(*(_features(value) for value in lhs))
    right = set().union(*(_features(value) for value in rhs))
    union = left | right
    score = len(left & right) / max(1, len(union))
    left_keys = {normalized(value["question"].get("keyPoint")) for value in lhs}
    right_keys = {normalized(value["question"].get("keyPoint")) for value in rhs}
    if left_keys & right_keys:
        score += 1
    left_numbers = [
        int(match.group(1))
        for value in lhs
        if (match := re.search(r"_(\d+)$", value["question"]["id"]))
    ]
    right_numbers = [
        int(match.group(1))
        for value in rhs
        if (match := re.search(r"_(\d+)$", value["question"]["id"]))
    ]
    if left_numbers and right_numbers:
        distance = min(abs(a - b) for a in left_numbers for b in right_numbers)
        score += 0.08 / max(1, distance)
    return score


def _subcategory_targets(records: list[dict], total_target: int) -> dict[str, int]:
    groups = defaultdict(list)
    for record in records:
        groups[record["question"]["subCategory"]].append(record)
    raw = {
        key: total_target * len(values) / len(records) for key, values in groups.items()
    }
    targets = {
        key: max(
            1,
            math.floor(value),
            sum(item["sourcePool"] == "released_free_100" for item in groups[key]),
        )
        for key, value in raw.items()
    }
    while sum(targets.values()) < total_target:
        candidates = sorted(
            groups,
            key=lambda key: (
                raw[key] - targets[key],
                len(groups[key]) - targets[key],
                key,
            ),
            reverse=True,
        )
        key = next(value for value in candidates if targets[value] < len(groups[value]))
        targets[key] += 1
    while sum(targets.values()) > total_target:
        candidates = sorted(
            groups,
            key=lambda key: (targets[key] - raw[key], targets[key], key),
            reverse=True,
        )
        for key in candidates:
            released_minimum = sum(
                item["sourcePool"] == "released_free_100" for item in groups[key]
            )
            if targets[key] > max(1, released_minimum):
                targets[key] -= 1
                break
        else:
            raise ValueError("cannot allocate concept targets without merging Golden seeds")
    return targets


def _cluster_subcategory(records: list[dict], target: int) -> list[list[dict]]:
    clusters = [[record] for record in records]
    while len(clusters) > target:
        best: tuple[float, int, int] | None = None
        for left_index, left in enumerate(clusters):
            for right_index in range(left_index + 1, len(clusters)):
                right = clusters[right_index]
                if len(left) + len(right) > 4:
                    continue
                released = sum(
                    value["sourcePool"] == "released_free_100" for value in left + right
                )
                if released > 1:
                    continue
                candidate = (
                    _cluster_similarity(left, right),
                    -left_index,
                    -right_index,
                )
                if best is None or candidate > best:
                    best = candidate
        if best is None:
            raise ValueError("cannot reach concept target under Golden/max-size constraints")
        left_index, right_index = -best[1], -best[2]
        clusters[left_index] = sorted(
            clusters[left_index] + clusters[right_index],
            key=lambda value: (
                value["sourcePool"] != "released_free_100",
                value["question"]["id"],
            ),
        )
        del clusters[right_index]
    return sorted(
        clusters,
        key=lambda values: min(value["question"]["id"] for value in values),
    )


def _meaning_slug(records: list[dict]) -> str:
    text = " ".join(
        str(record["question"].get(key) or "")
        for record in records
        for key in ("keyPoint", "prompt")
    )
    matches = [slug for keyword, slug in MEANING_KEYWORDS if keyword in text]
    return "-".join(dict.fromkeys(matches[:2])) or "core-rule"


def _fact_values(records: list[dict], pattern: str) -> list[str]:
    values: list[str] = []
    for record in records:
        question = record["question"]
        text = str(question.get("shortExplanation") or question.get("prompt") or "")
        if re.search(pattern, text) and text not in values:
            values.append(text)
    return values[:4]


def confirmed_numeric_facts(concept: dict) -> list[dict]:
    facts: list[dict] = []
    for value in concept.get("numericFacts") or []:
        if not isinstance(value, dict):
            continue
        fact = str(value.get("fact") or "")
        unit = str(value.get("unit") or "")
        if (
            value.get("reviewStatus") != "reviewed"
            or not str(value.get("value") or "").strip()
            or not unit.strip()
            or len(normalized(fact)) < 6
            or re.search(r"(?:第?\s*(?:35|37)\s*条|8種制限)", fact)
        ):
            continue
        facts.append(value)
    return facts


def has_placeholder_content(value: object) -> bool:
    text = json.dumps(value, ensure_ascii=False)
    return bool(
        re.search(
            r"AI草稿|AI下書き|要点候補|詳細解説候補|誤答候補|"
            r"正しい数値.*入力|人間.*追記|pending-human",
            text,
        )
    )


def _recommended_formats(records: list[dict], tier: str) -> list[str]:
    text = " ".join(
        str(record["question"].get(key) or "")
        for record in records
        for key in ("prompt", "keyPoint", "shortExplanation")
    )
    result = ["true_false"]
    if re.search(r"主体|者|前|後|義務|任意|できる|ならない|期限|期間", text):
        result.append("wording_contrast")
    if tier in {"A", "B"}:
        result.append("multiple_choice")
    if tier == "A" and re.search(r"例外|場合|ただし|横断|対抗|解除", text):
        result.append("case_study")
    result = list(dict.fromkeys(result))
    minimum = 3 if tier == "A" else (2 if tier == "B" else 1)
    for fallback in ("wording_contrast", "multiple_choice", "case_study"):
        if len(result) >= minimum:
            break
        if fallback not in result:
            result.append(fallback)
    return result


def build_concept_assets() -> dict[str, dict]:
    records = load_legacy_records()
    grouped_by_category: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        grouped_by_category[record["question"]["category"]].append(record)

    raw_concepts: list[dict] = []
    for category, target in CATEGORY_TARGETS.items():
        category_records = grouped_by_category[category]
        targets = _subcategory_targets(category_records, target)
        grouped_by_subcategory: dict[str, list[dict]] = defaultdict(list)
        for record in category_records:
            grouped_by_subcategory[record["question"]["subCategory"]].append(record)
        for subcategory in sorted(grouped_by_subcategory):
            values = grouped_by_subcategory[subcategory]
            clusters = _cluster_subcategory(values, targets[subcategory])
            for local_index, cluster in enumerate(clusters, start=1):
                raw_concepts.append(
                    {
                        "category": category,
                        "subCategory": subcategory,
                        "localIndex": local_index,
                        "records": cluster,
                    }
                )

    def priority(value: dict) -> tuple:
        records_for_concept = value["records"]
        golden = any(
            record["sourcePool"] == "released_free_100"
            for record in records_for_concept
        )
        source_importance = max(
            (
                {"高": 3, "中": 2, "低": 1}.get(
                    record["question"].get("importance", ""), 0
                )
                for record in records_for_concept
            ),
            default=0,
        )
        return (
            1 if golden else 0,
            source_importance,
            len(records_for_concept),
            value["category"],
            value["subCategory"],
            -value["localIndex"],
        )

    ranked = sorted(raw_concepts, key=priority, reverse=True)
    tier_by_identity = {
        id(value): ("A" if index < 120 else "B" if index < 300 else "C")
        for index, value in enumerate(ranked)
    }

    concepts: list[dict] = []
    concept_for_legacy: dict[str, str] = {}
    for value in sorted(
        raw_concepts,
        key=lambda item: (
            list(CATEGORY_TARGETS).index(item["category"]),
            item["subCategory"],
            item["localIndex"],
        ),
    ):
        tier = tier_by_identity[id(value)]
        records_for_concept = value["records"]
        domain = CATEGORY_DOMAINS[value["category"]]
        subcategory_slug = SUBCATEGORY_SLUGS[value["subCategory"]]
        concept_id = (
            f"takken.{domain}.{subcategory_slug}."
            f"{_meaning_slug(records_for_concept)}-{value['localIndex']:03d}"
        )
        key_points = list(
            dict.fromkeys(
                str(record["question"].get("keyPoint") or "").strip()
                for record in records_for_concept
                if str(record["question"].get("keyPoint") or "").strip()
            )
        )
        representative = records_for_concept[0]["question"]
        title = "／".join(key_points[:2]) or representative["prompt"][:42]
        minimum, target, maximum = {
            "A": (3, 4, 5),
            "B": (2, 2, 3),
            "C": (1, 1, 2),
        }[tier]
        recommended = _recommended_formats(records_for_concept, tier)
        legacy_ids = sorted(record["question"]["id"] for record in records_for_concept)
        concept = {
            "conceptID": concept_id,
            "category": value["category"],
            "subCategory": value["subCategory"],
            "title": title,
            "canonicalRule": representative.get("shortExplanation")
            or representative.get("explanation")
            or representative["prompt"],
            "learningObjectives": [
                f"{point}という規則を、主体・時期・数字・例外のどの記憶経路か区別して説明できる。"
                for point in key_points[:3]
            ]
            or ["この論点の適用条件を単独で説明できる。"],
            "importanceTier": tier,
            "importanceScore": {"A": 5, "B": 4, "C": 2}[tier],
            "frequencyScore": {"A": 5, "B": 4, "C": 2}[tier],
            "coverageRole": {"A": "core", "B": "frequent", "C": "peripheral"}[tier],
            "recommendedFormats": recommended,
            "minimumVariantCount": minimum,
            "targetVariantCount": target,
            "maximumVariantCount": maximum,
            "unlockPolicy": {
                "eligible": "case_study" not in recommended or len(recommended) > 1,
                "preferredFormats": [
                    item
                    for item in recommended
                    if item in {"true_false", "number_choice", "wording_contrast"}
                ][:2],
                "maximumEstimatedSeconds": 30,
            },
            "preview": {
                "title": value["subCategory"],
                "rule": key_points[0]
                if key_points
                else (representative.get("keyPoint") or representative["prompt"]),
                "contrast": key_points[1] if len(key_points) > 1 else None,
                "mnemonic": None,
            },
            "confusionPoints": key_points[1:4],
            # AI-extracted values are review hints only. A number_choice may be
            # authored only from a human-reviewed numericFacts entry.
            "numericFacts": [],
            "numericFactCandidates": _fact_values(
                records_for_concept,
                r"\d|[一二三四五六七八九十百千万億].*(?:日|月|年|%|％|割|円)",
            ),
            "actorRules": _fact_values(
                records_for_concept,
                r"宅建業者|宅建士|買主|売主|貸主|借主|知事|大臣|主体",
            ),
            "timingRules": _fact_values(
                records_for_concept, r"前|後|以内|まで|期限|期間|遅滞なく"
            ),
            "exceptionRules": _fact_values(
                records_for_concept, r"例外|ただし|場合|除く|原則"
            ),
            "relatedConceptIDs": [],
            "legacySourceIDs": legacy_ids,
            "sourceNotes": [],
            "requiresSourceResearch": True,
            "requiresAnnualReview": True,
            "annualReviewReason": (
                "法令・判例・税制・統計への依存有無を人間が判定するまで毎年度確認する"
            ),
            "reviewStatus": "ai_draft",
            "reviewer": None,
            "reviewedAt": None,
            "reviewNote": None,
            "mergedFromConceptIDs": [],
            "splitFromConceptID": None,
            "supersedesConceptIDs": [],
            "reviewDecision": None,
            "generationMetadata": {
                "method": "semantic-draft-cluster-v17",
                "confidence": "requires-human-concept-review",
                "sourceQuestionCount": len(legacy_ids),
            },
        }
        concepts.append(concept)
        for legacy_id in legacy_ids:
            concept_for_legacy[legacy_id] = concept_id

    by_subcategory: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for concept in concepts:
        by_subcategory[(concept["category"], concept["subCategory"])].append(concept)
    for values in by_subcategory.values():
        values.sort(key=lambda value: value["conceptID"])
        for index, concept in enumerate(values):
            related = []
            if index > 0:
                related.append(values[index - 1]["conceptID"])
            if index + 1 < len(values):
                related.append(values[index + 1]["conceptID"])
            concept["relatedConceptIDs"] = related

    master = {
        "schemaVersion": 1,
        "packID": "takken2026.v1",
        "examYear": 2026,
        "lawBasisDate": "2026-04-01",
        "status": "ai_draft",
        "targetConceptCount": 380,
        "allowedConceptRange": {"minimum": 350, "maximum": 450},
        "fullPackPlan": {
            "plannedStandaloneVariantCount": 920,
            "plannedIntegratedCaseCount": 80,
            "plannedTotalQuestionCount": 1000,
            "humanReviewRequired": True,
        },
        "generationPolicy": {
            "method": "semantic similarity within subcategory",
            "maximumLegacyQuestionsPerConcept": 4,
            "goldenSeedMergeLimit": 1,
            "humanReviewRequired": True,
        },
        "concepts": sorted(concepts, key=lambda value: value["conceptID"]),
    }
    inventory = build_inventory(records, master, concept_for_legacy)
    golden = build_golden(master, concept_for_legacy)
    variants = build_golden_variants(master, golden, concept_for_legacy)
    research = build_source_research_queue(master)
    return {
        "master": master,
        "inventory": inventory,
        "golden": golden,
        "variants": variants,
        "research": research,
    }


def build_inventory(
    records: list[dict], master: dict, concept_for_legacy: dict[str, str]
) -> dict:
    reviewed_mapping = all(
        value.get("reviewStatus") in {"reviewed", "release"}
        for value in master.get("concepts", [])
    )
    prompt_owner: dict[str, str] = {}
    concept_members: dict[str, list[str]] = defaultdict(list)
    for record in records:
        legacy_id = record["question"]["id"]
        concept_members[concept_for_legacy[legacy_id]].append(legacy_id)
    for values in concept_members.values():
        values.sort()

    items: list[dict] = []
    for record in records:
        question = record["question"]
        legacy_id = question["id"]
        concept_id = concept_for_legacy[legacy_id]
        prompt_key = normalized(question.get("prompt"))
        duplicate_of = prompt_owner.get(prompt_key)
        if duplicate_of:
            disposition = "duplicate"
            reason = f"問題文が既登録の{duplicate_of}と完全一致するため重複候補"
        else:
            prompt_owner[prompt_key] = legacy_id
            if "横断" in str(question.get("subCategory")):
                disposition = "integrated_case_material"
                reason = "複数制度を比較する横断素材として事例・比較問題へ利用"
            elif question.get("requiresAnnualReview") or question.get(
                "requiresAnnualUpdate"
            ):
                disposition = "requires_legal_research"
                reason = "年度更新または統計基準の公的出典確認が必要"
            elif legacy_id == concept_members[concept_id][0]:
                disposition = "base_variant_candidate"
                reason = "AIクラスタ内の代表規則として基本variant候補に指定"
            elif len(concept_members[concept_id]) == 1:
                disposition = "new_concept_candidate"
                reason = "単独の記憶目標としてconcept境界の人手確認が必要"
            else:
                disposition = "additional_variant_candidate"
                reason = "同一conceptを別の数字・主体・時期・適用角度から問う素材候補"
        items.append(
            {
                "legacyQuestionID": legacy_id,
                "sourceFile": record["sourceFile"],
                "sourcePool": record["sourcePool"],
                "category": question["category"],
                "subCategory": question["subCategory"],
                "originalFormat": question.get("format"),
                "mappedConceptID": concept_id,
                "disposition": disposition,
                "reason": reason,
                "duplicateOfLegacyID": duplicate_of,
                "requiresLegalUpdate": bool(
                    question.get("requiresAnnualReview")
                    or question.get("requiresAnnualUpdate")
                    or record["sourcePool"].endswith("draft_200")
                    or record["sourcePool"] == "kenri_draft_300"
                ),
                "requiresSourceResearch": True,
                "questionDigest": question_digest(question),
                "mappingConfidence": (
                    "human_reviewed_concept_boundary"
                    if reviewed_mapping
                    else "ai_clustered_requires_human_review"
                ),
                "status": "reviewed_mapping" if reviewed_mapping else "ai_draft",
            }
        )
    return {
        "schemaVersion": 1,
        "packID": "takken2026.v1",
        "examYear": 2026,
        "lawBasisDate": "2026-04-01",
        "status": "reviewed_mapping" if reviewed_mapping else "ai_draft",
        "expectedLegacyQuestionCount": 1_000,
        "sourceFiles": [relative for _, relative in LEGACY_SOURCES],
        "items": sorted(items, key=lambda value: value["legacyQuestionID"]),
    }


def concept_mapping(master: dict) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for concept in master.get("concepts", []):
        for legacy_id in concept.get("legacySourceIDs") or []:
            if legacy_id in mapping:
                raise ValueError(f"duplicate legacy ownership: {legacy_id}")
            mapping[legacy_id] = concept["conceptID"]
    return mapping


def build_inventory_from_master(master: dict) -> dict:
    records = load_legacy_records()
    mapping = concept_mapping(master)
    known_ids = {value["question"]["id"] for value in records}
    if set(mapping) != known_ids:
        raise ValueError("reviewed master must own all 1,000 legacy questions exactly once")
    return build_inventory(records, master, mapping)


def build_golden(master: dict, concept_for_legacy: dict[str, str]) -> dict:
    released = load_json(RELEASE_PATH)
    concepts_by_id = {
        value["conceptID"]: value for value in master.get("concepts", [])
    }
    golden_question_ids = [item["id"] for item in released]
    if len(golden_question_ids) != 100 or len(set(golden_question_ids)) != 100:
        raise ValueError("Golden Question Set must preserve exactly 100 Release IDs")
    mappings = [
        {
            "questionID": question_id,
            "conceptID": concept_for_legacy[question_id],
            "mappingStatus": (
                "human_reviewed"
                if concepts_by_id[concept_for_legacy[question_id]].get("reviewStatus")
                in {"reviewed", "release"}
                else "ai_draft"
            ),
        }
        for question_id in golden_question_ids
    ]
    golden_ids = [value["conceptID"] for value in mappings]
    by_id = concepts_by_id
    concepts = []
    for concept_id in dict.fromkeys(golden_ids):
        concept = deepcopy(by_id[concept_id])
        concept["goldenRole"] = "quality_reference"
        concept["publicReleaseSourceIDs"] = [
            value["questionID"]
            for value in mappings
            if value["conceptID"] == concept_id
        ]
        concepts.append(concept)
    return {
        "schemaVersion": 1,
        "packID": "takken2026.v1",
        "examYear": 2026,
        "lawBasisDate": "2026-04-01",
        "status": (
            "human_reviewed_mapping"
            if all(
                value["mappingStatus"] == "human_reviewed" for value in mappings
            )
            else "ai_draft"
        ),
        "expectedQuestionCount": 100,
        "goldenQuestionIDs": golden_question_ids,
        "conceptMappings": mappings,
        "distinctConceptCount": len(set(golden_ids)),
        "expectedGoldenVariantRange": {"minimum": 250, "maximum": 300},
        "currentPublicFreeSample": {
            "itemCount": 100,
            "sha256": PROTECTED_RELEASE_SHA256,
            "replacementAuthorized": False,
        },
        "concepts": concepts,
    }


def golden_concept_ids(golden: dict) -> list[str]:
    return list(
        dict.fromkeys(
            value.get("conceptID")
            for value in golden.get("conceptMappings") or []
            if isinstance(value.get("conceptID"), str)
        )
    )


def validate_golden_question_set(golden: dict, master: dict) -> list[str]:
    errors: list[str] = []
    release_ids = [value["id"] for value in load_json(RELEASE_PATH)]
    question_ids = golden.get("goldenQuestionIDs") or []
    mappings = golden.get("conceptMappings") or []
    mapped_question_ids = [value.get("questionID") for value in mappings]
    master_ids = {value["conceptID"] for value in master.get("concepts", [])}
    mapped_concepts = [value.get("conceptID") for value in mappings]
    if (
        len(question_ids) != 100
        or len(set(question_ids)) != 100
        or question_ids != release_ids
    ):
        errors.append("Golden Question Set must preserve the ordered Release 100 IDs")
    if (
        len(mappings) != 100
        or len(set(mapped_question_ids)) != 100
        or mapped_question_ids != question_ids
    ):
        errors.append("Golden Question Set requires one mapping for every question")
    if any(value not in master_ids for value in mapped_concepts):
        errors.append("Golden Question Set contains an unknown concept mapping")
    distinct = len(set(mapped_concepts))
    if golden.get("distinctConceptCount") != distinct:
        errors.append("Golden distinctConceptCount must be derived from mappings")
    if not 1 <= distinct <= 100:
        errors.append("Golden Question Set must map to 1-100 distinct concepts")
    return errors


def _select_golden_candidates(candidates_by_concept: dict[str, list[dict]]) -> list[dict]:
    selected: list[dict] = []
    selected_keys: set[tuple[str, str]] = set()
    format_counts: Counter = Counter()
    concept_counts: Counter = Counter()

    def choose(concept_id: str) -> dict | None:
        values = [
            value
            for value in candidates_by_concept[concept_id]
            if (concept_id, value["variantID"]) not in selected_keys
        ]
        if not values:
            return None
        return min(
            values,
            key=lambda value: (
                format_counts[value["format"]]
                / max(1, GOLDEN_FORMAT_TARGETS[value["format"]]),
                value["format"] == "true_false",
                value["variantID"],
                value["id"],
            ),
        )

    ordered_concepts = sorted(
        candidates_by_concept, key=lambda key: (len(candidates_by_concept[key]), key)
    )
    for minimum_round in range(2):
        for concept_id in ordered_concepts:
            value = choose(concept_id)
            if value is None:
                continue
            selected.append(value)
            selected_keys.add((concept_id, value["variantID"]))
            format_counts[value["format"]] += 1
            concept_counts[concept_id] += 1

    while len(selected) < 270:
        desired_formats = sorted(
            GOLDEN_FORMAT_TARGETS,
            key=lambda value: (
                GOLDEN_FORMAT_TARGETS[value] - format_counts[value],
                value,
            ),
            reverse=True,
        )
        picked = None
        for target_format in desired_formats:
            options = [
                (concept_counts[concept_id], concept_id, value)
                for concept_id, values in candidates_by_concept.items()
                if concept_counts[concept_id] < 4
                for value in values
                if value["format"] == target_format
                and (concept_id, value["variantID"]) not in selected_keys
            ]
            if options:
                picked = min(options, key=lambda value: (value[0], value[1], value[2]["id"]))
                break
        if picked is None:
            raise ValueError("not enough distinct Golden variants to reach 270")
        _, concept_id, value = picked
        selected.append(value)
        selected_keys.add((concept_id, value["variantID"]))
        format_counts[value["format"]] += 1
        concept_counts[concept_id] += 1
    return selected


def build_golden_variants(
    master: dict, golden: dict, concept_for_legacy: dict[str, str]
) -> dict:
    candidates = load_json(V2_CANDIDATE_PATH)
    released_ids = {
        value["questionID"]: value["conceptID"]
        for value in golden["conceptMappings"]
    }
    candidates_by_concept: dict[str, list[dict]] = defaultdict(list)
    for index, candidate in enumerate(candidates):
        old_concept_id = str(candidate.get("conceptID") or "").removeprefix("concept.")
        new_concept_id = released_ids.get(old_concept_id)
        if new_concept_id is None:
            continue
        concept = next(
            value for value in master["concepts"] if value["conceptID"] == new_concept_id
        )
        if candidate.get("format") == "number_choice" and not confirmed_numeric_facts(
            concept
        ):
            continue
        value = deepcopy(candidate)
        value["_sourceOrder"] = index
        value["_newConceptID"] = new_concept_id
        candidates_by_concept[new_concept_id].append(value)
    expected_concepts = {value["conceptID"] for value in golden["conceptMappings"]}
    if set(candidates_by_concept) != expected_concepts:
        raise ValueError("v2 candidate pool does not cover all Golden concepts")

    selected = _select_golden_candidates(candidates_by_concept)
    concept_by_id = {value["conceptID"]: value for value in master["concepts"]}
    variant_ordinals: Counter = Counter()
    output: list[dict] = []
    for candidate in selected:
        concept_id = candidate.pop("_newConceptID")
        candidate.pop("_sourceOrder", None)
        concept = concept_by_id[concept_id]
        fmt = candidate["format"]
        variant_ordinals[(concept_id, fmt)] += 1
        ordinal = variant_ordinals[(concept_id, fmt)]
        legacy_source_id = str(candidate.get("conceptID")).removeprefix("concept.")
        candidate["id"] = f"v17.{legacy_source_id}.{fmt}.{ordinal:02d}"
        candidate["conceptID"] = concept_id
        candidate["variantID"] = f"{FORMAT_ROUTE[fmt]}.{ordinal:02d}"
        candidate["integratedConceptIDs"] = []
        candidate["recallRoute"] = FORMAT_ROUTE[fmt]
        candidate["estimatedSeconds"] = FORMAT_SECONDS[fmt]
        candidate["unlockEligible"] = fmt != "case_study" and FORMAT_SECONDS[fmt] <= 30
        candidate["last30DaysEligible"] = True
        candidate["weaknessEligible"] = True
        candidate["importance"] = {"A": "高", "B": "中", "C": "低"}[
            concept["importanceTier"]
        ]
        candidate["sourceNote"] = None
        candidate["requiresSourceResearch"] = True
        candidate["reviewStatus"] = "ai_draft"
        candidate["distractorReviewStatus"] = "pending"
        candidate["reviewer"] = None
        candidate["reviewedAt"] = None
        candidate["reviewNote"] = None
        candidate["legalReviewChecklist"] = {
            "lawBasis": False,
            "subject": False,
            "timing": False,
            "numbers": False,
            "exceptions": False,
        }
        candidate["draftGenerationNotes"] = (
            "既存素材から異なる記憶経路を選別したAI草稿。法令・出典・誤答理由の"
            "人手校閲前であり、Releaseへ昇格してはならない。"
        )
        candidate["isPlaceholder"] = has_placeholder_content(candidate)
        candidate["authoringContext"] = {
            "conceptTitle": concept["title"],
            "canonicalRule": concept["canonicalRule"],
            "recommendedFormats": concept["recommendedFormats"],
        }
        choice_ids = [choice["id"] for choice in candidate["choices"]]
        correct_id = candidate["correctChoiceID"]
        rationale_map = {}
        for choice in candidate["choices"]:
            if choice["id"] == correct_id:
                choice["rationale"] = None
                choice["misconceptionCode"] = None
                continue
            misconception = FORMAT_MISCONCEPTION[fmt]
            choice["misconceptionCode"] = misconception
            rationale = (
                f"この選択肢は記憶経路「{FORMAT_ROUTE[fmt]}」の誤答候補である。"
                "正確な相違点はsource research後に校閲担当者が確定する。"
            )
            choice["rationale"] = rationale
            rationale_map[choice["id"]] = rationale
        candidate["wrongChoiceRationales"] = rationale_map
        candidate["isPlaceholder"] = has_placeholder_content(candidate)
        if correct_id not in choice_ids:
            raise ValueError(f"candidate correct choice missing: {candidate['id']}")
        candidate["correctIndex"] = choice_ids.index(correct_id)
        output.append(candidate)
    return {
        "schemaVersion": 1,
        "packID": "takken2026.v1",
        "examYear": 2026,
        "lawBasisDate": "2026-04-01",
        "status": "ai_draft",
        "generationRule": (
            "Golden 100の既存v2候補から、形式と記憶経路の重複を避けて決定的に270件選定"
        ),
        "expectedVariantRange": {"minimum": 250, "maximum": 300},
        "variants": sorted(output, key=lambda value: (value["conceptID"], value["variantID"])),
    }


def _normalized_variant_choices(source: dict, fmt: str) -> tuple[list[dict], str]:
    raw_choices = source.get("choices") or []
    choices: list[dict] = []
    for index, value in enumerate(raw_choices):
        if isinstance(value, dict):
            choice = deepcopy(value)
            choice["id"] = str(choice.get("id") or f"choice-{index}")
            choice["text"] = str(choice.get("text") or "")
        else:
            choice = {
                "id": f"choice-{index}",
                "text": str(value),
                "rationale": None,
                "misconceptionCode": None,
            }
        choices.append(choice)
    correct_index = source.get("correctIndex")
    if not isinstance(correct_index, int) or not 0 <= correct_index < len(choices):
        source_correct_id = source.get("correctChoiceID")
        correct_index = next(
            (
                index
                for index, value in enumerate(choices)
                if value["id"] == source_correct_id
            ),
            0,
        )
    correct_id = choices[correct_index]["id"]
    for choice in choices:
        if choice["id"] == correct_id:
            choice["rationale"] = None
            choice["misconceptionCode"] = None
        else:
            choice["misconceptionCode"] = (
                choice.get("misconceptionCode") or FORMAT_MISCONCEPTION[fmt]
            )
            choice["rationale"] = choice.get("rationale") or (
                "旧問題素材から移行した誤答候補であり、相違点はvariant校閲で確定する。"
            )
    return choices, correct_id


def build_variant_drafts_from_master(master: dict) -> dict:
    """Build deterministic AI drafts from the supplied reviewed concept boundaries."""
    records = load_legacy_records()
    known_ids = {value["question"]["id"] for value in records}
    validation_errors = validate_concept_master(master, known_ids)
    if validation_errors:
        raise ValueError("; ".join(validation_errors[:20]))
    if any(
        value.get("reviewStatus") not in {"reviewed", "release"}
        for value in master["concepts"]
    ):
        raise ValueError("concept master must be fully human reviewed")

    legacy_by_id = {
        value["question"]["id"]: value["question"] for value in records
    }
    v2_by_legacy: dict[str, list[dict]] = defaultdict(list)
    for value in load_json(V2_CANDIDATE_PATH):
        legacy_id = str(value.get("conceptID") or "").removeprefix("concept.")
        v2_by_legacy[legacy_id].append(value)

    output: list[dict] = []
    for concept in sorted(master["concepts"], key=lambda value: value["conceptID"]):
        allowed_formats = list(dict.fromkeys(concept["recommendedFormats"]))
        if not confirmed_numeric_facts(concept):
            allowed_formats = [
                value for value in allowed_formats if value != "number_choice"
            ]
        candidates: list[tuple[str, str, dict]] = []
        for legacy_id in sorted(concept["legacySourceIDs"]):
            legacy = legacy_by_id[legacy_id]
            candidates.append(
                (
                    str(legacy.get("format") or "true_false"),
                    legacy_id,
                    legacy,
                )
            )
            candidates.extend(
                (
                    str(value.get("format") or "true_false"),
                    legacy_id,
                    value,
                )
                for value in v2_by_legacy.get(legacy_id, [])
            )
        selected_formats: set[str] = set()
        selected_count = 0
        for fmt, legacy_id, source in sorted(
            candidates, key=lambda value: (value[0], value[1], str(value[2].get("id")))
        ):
            if (
                fmt not in allowed_formats
                or fmt in selected_formats
                or selected_count >= concept["targetVariantCount"]
            ):
                continue
            choices, correct_id = _normalized_variant_choices(source, fmt)
            if len(choices) < 2:
                continue
            wrong = [value for value in choices if value["id"] != correct_id]
            generic_rationale = any(
                "variant校閲で確定" in str(value.get("rationale")) for value in wrong
            )
            variant_id = f"{FORMAT_ROUTE[fmt]}.01"
            item_id = (
                f"v18.{hashlib.sha256(concept['conceptID'].encode()).hexdigest()[:12]}."
                f"{FORMAT_ROUTE[fmt]}"
            )
            rationale_map = {
                value["id"]: value["rationale"] for value in wrong
            }
            output.append(
                {
                    "id": item_id,
                    "conceptID": concept["conceptID"],
                    "variantID": variant_id,
                    "integratedConceptIDs": [],
                    "sourceLegacyQuestionIDs": [legacy_id],
                    "format": fmt,
                    "recallRoute": FORMAT_ROUTE[fmt],
                    "prompt": source.get("prompt") or concept["canonicalRule"],
                    "choices": choices,
                    "correctChoiceID": correct_id,
                    "correctIndex": next(
                        index
                        for index, value in enumerate(choices)
                        if value["id"] == correct_id
                    ),
                    "explanation": concept["canonicalRule"],
                    "shortExplanation": concept["canonicalRule"],
                    "longExplanation": (
                        f"{concept['canonicalRule']} "
                        "このAI草稿は問題単位の法令・誤答校閲前である。"
                    ),
                    "keyPoint": concept["title"],
                    "preview": concept.get("preview"),
                    "category": concept["category"],
                    "subCategory": concept["subCategory"],
                    "difficulty": "標準",
                    "importance": {"A": "高", "B": "中", "C": "低"}[
                        concept["importanceTier"]
                    ],
                    "estimatedSeconds": FORMAT_SECONDS[fmt],
                    "unlockEligible": (
                        fmt != "case_study" and FORMAT_SECONDS[fmt] <= 30
                    ),
                    "last30DaysEligible": True,
                    "weaknessEligible": True,
                    "wrongChoiceRationales": rationale_map,
                    "sourceNote": None,
                    "requiresSourceResearch": True,
                    "reviewStatus": "ai_draft",
                    "distractorReviewStatus": "pending",
                    "reviewer": None,
                    "reviewedAt": None,
                    "reviewNote": None,
                    "isPlaceholder": bool(
                        source.get("isPlaceholder")
                        or has_placeholder_content(source)
                        or generic_rationale
                    ),
                    "authoringContext": {
                        "sourceMasterStatus": master.get("status"),
                        "conceptTitle": concept["title"],
                        "canonicalRule": concept["canonicalRule"],
                        "recommendedFormats": concept["recommendedFormats"],
                        "numericFacts": confirmed_numeric_facts(concept),
                    },
                }
            )
            selected_formats.add(fmt)
            selected_count += 1
    variants = sorted(
        output, key=lambda value: (value["conceptID"], value["variantID"])
    )
    return {
        "schemaVersion": 1,
        "packID": master["packID"],
        "examYear": master.get("examYear"),
        "lawBasisDate": master.get("lawBasisDate"),
        "status": "ai_draft",
        "sourceConceptMasterDigest": hashlib.sha256(
            json.dumps(
                master, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            ).encode("utf-8")
        ).hexdigest(),
        "generationRule": (
            "explicit reviewed Concept Master; human boundaries and format policy; "
            "no fallback to Generated AI Master"
        ),
        "variants": variants,
        "shortages": tier_variant_shortages(master, variants),
    }


def build_source_research_queue(master: dict) -> dict:
    items = [
        {
            "researchID": f"source.{concept['conceptID']}",
            "conceptID": concept["conceptID"],
            "category": concept["category"],
            "subCategory": concept["subCategory"],
            "title": concept["title"],
            "priorityTier": concept["importanceTier"],
            "queryHint": (
                f"{concept['subCategory']} {concept['title']} "
                "2026-04-01時点の法令条項・公的資料を確認"
            ),
            "requiredEvidence": [
                "法令名と条項、または公的資料名とURL・公開日",
                "主体・時期・数字・例外の適用条件",
                "2026-04-01時点の改正反映",
            ],
            "legacySourceIDs": concept["legacySourceIDs"],
            "claimedSource": None,
            "status": "pending",
            "reviewer": None,
            "reviewedAt": None,
        }
        for concept in master["concepts"]
        if concept.get("requiresSourceResearch") is True
    ]
    return {
        "schemaVersion": 1,
        "packID": "takken2026.v1",
        "lawBasisDate": "2026-04-01",
        "status": "pending-human-research",
        "items": sorted(
            items, key=lambda value: (value["priorityTier"], value["conceptID"])
        ),
    }


def write_all_draft_assets() -> dict[str, dict]:
    assets = build_concept_assets()
    write_json(MASTER_PATH, assets["master"])
    write_json(INVENTORY_PATH, assets["inventory"])
    write_json(GOLDEN_PATH, assets["golden"])
    write_json(VARIANTS_PATH, assets["variants"])
    write_json(RESEARCH_PATH, assets["research"])
    write_json(FREE_SAMPLE_PROFILES_PATH, build_free_sample_profiles())
    return assets


def validate_concept_master(
    master: dict, known_legacy_ids: set[str] | None = None
) -> list[str]:
    errors: list[str] = []
    concepts = master.get("concepts")
    if not isinstance(concepts, list):
        return ["concept master concepts must be an array"]
    if not 350 <= len(concepts) <= 450:
        errors.append("concept master must contain 350-450 concepts")
    concept_ids = [value.get("conceptID") for value in concepts]
    if any(not isinstance(value, str) or not value.startswith("takken.") for value in concept_ids):
        errors.append("conceptID must be a nonempty stable takken.* ID")
    if len(concept_ids) != len(set(concept_ids)):
        errors.append("conceptID must be unique")
    concept_id_set = set(concept_ids)
    plan = master.get("fullPackPlan") or {}
    if (
        plan.get("plannedStandaloneVariantCount") != 920
        or plan.get("plannedIntegratedCaseCount") != 80
        or plan.get("plannedTotalQuestionCount") != 1_000
    ):
        errors.append("concept master fullPackPlan must currently total 920 + 80 = 1000")
    legacy_owners: dict[str, str] = {}
    for concept in concepts:
        concept_id = concept.get("conceptID", "<unknown>")
        if concept.get("category") not in CATEGORY_TARGETS:
            errors.append(f"{concept_id}: unknown category")
        if concept.get("subCategory") not in SUBCATEGORY_SLUGS:
            errors.append(f"{concept_id}: unknown subCategory")
        tier = concept.get("importanceTier")
        if tier not in {"A", "B", "C"}:
            errors.append(f"{concept_id}: importanceTier must be A/B/C")
        scores = (concept.get("importanceScore"), concept.get("frequencyScore"))
        if any(not isinstance(value, int) or not 1 <= value <= 5 for value in scores):
            errors.append(f"{concept_id}: importance/frequency scores must be 1-5")
        counts = (
            concept.get("minimumVariantCount"),
            concept.get("targetVariantCount"),
            concept.get("maximumVariantCount"),
        )
        if not all(isinstance(value, int) for value in counts) or not (
            counts[0] <= counts[1] <= counts[2]
        ):
            errors.append(f"{concept_id}: variant target range is invalid")
        formats = concept.get("recommendedFormats") or []
        if not formats or not set(formats).issubset(ALLOWED_FORMATS):
            errors.append(f"{concept_id}: recommendedFormats are invalid")
        if "number_choice" in formats and not confirmed_numeric_facts(concept):
            errors.append(
                f"{concept_id}: number_choice requires a human-reviewed numericFact"
            )
        if tier == "A" and (counts[0] < 3 or len(set(formats)) < 3):
            errors.append(f"{concept_id}: A concept requires at least 3 useful formats")
        if tier == "C" and counts[2] > 2:
            errors.append(f"{concept_id}: C concept must not be expanded to 3+ variants")
        for related in concept.get("relatedConceptIDs") or []:
            if related not in concept_id_set or related == concept_id:
                errors.append(f"{concept_id}: unknown/self relatedConceptID {related}")
        if not isinstance(concept.get("requiresAnnualReview"), bool):
            errors.append(f"{concept_id}: requiresAnnualReview must be explicit")
        if len(normalized(concept.get("annualReviewReason"))) < 8:
            errors.append(f"{concept_id}: annualReviewReason is required")
        for key in ("mergedFromConceptIDs", "supersedesConceptIDs"):
            if not isinstance(concept.get(key, []), list):
                errors.append(f"{concept_id}: {key} must be an array")
        if concept.get("splitFromConceptID") is not None and not isinstance(
            concept.get("splitFromConceptID"), str
        ):
            errors.append(f"{concept_id}: splitFromConceptID must be a string or null")
        legacy_ids = concept.get("legacySourceIDs") or []
        if not legacy_ids:
            errors.append(f"{concept_id}: legacySourceIDs must not be empty")
        for legacy_id in legacy_ids:
            if known_legacy_ids is not None and legacy_id not in known_legacy_ids:
                errors.append(f"{concept_id}: unknown legacySourceID {legacy_id}")
            previous = legacy_owners.get(legacy_id)
            if previous:
                errors.append(
                    f"{legacy_id}: legacy source mapped to both {previous} and {concept_id}"
                )
            legacy_owners[legacy_id] = concept_id
        if concept.get("reviewStatus") in {"reviewed", "release"}:
            notes = concept.get("sourceNotes") or []
            if not notes or not all(_has_traceable_source_note(value) for value in notes):
                errors.append(f"{concept_id}: reviewed concept requires traceable sources")
            reviewed_at = _parsed_review_date(concept.get("reviewedAt"))
            if not concept.get("reviewer") or reviewed_at is None:
                errors.append(f"{concept_id}: reviewed concept requires review metadata")
            if concept.get("reviewDecision") not in ALLOWED_REVIEW_DECISIONS:
                errors.append(f"{concept_id}: reviewed concept requires reviewDecision")
        elif concept.get("reviewStatus") != "ai_draft":
            errors.append(f"{concept_id}: unsupported concept reviewStatus")
    if known_legacy_ids is not None and set(legacy_owners) != known_legacy_ids:
        errors.append("concept master must map every legacy question exactly once")
    return errors


def validate_legacy_inventory(
    inventory: dict, master: dict, known_records: list[dict]
) -> list[str]:
    errors: list[str] = []
    items = inventory.get("items")
    if not isinstance(items, list) or len(items) != 1_000:
        return ["legacy inventory must contain exactly 1,000 entries"]
    expected_ids = {record["question"]["id"] for record in known_records}
    ids = [value.get("legacyQuestionID") for value in items]
    if len(ids) != len(set(ids)):
        errors.append("legacy inventory question IDs must be unique")
    if set(ids) != expected_ids:
        errors.append("legacy inventory must have orphan 0 and cover all 1,000 questions")
    concept_ids = {value["conceptID"] for value in master.get("concepts", [])}
    expected_status = (
        "reviewed_mapping"
        if all(
            value.get("reviewStatus") in {"reviewed", "release"}
            for value in master.get("concepts", [])
        )
        else "ai_draft"
    )
    by_id = {value.get("legacyQuestionID"): value for value in items}
    known_files = {relative for _, relative in LEGACY_SOURCES}
    for item in items:
        item_id = item.get("legacyQuestionID", "<unknown>")
        if item.get("sourceFile") not in known_files:
            errors.append(f"{item_id}: unknown source file")
        if item.get("mappedConceptID") not in concept_ids:
            errors.append(f"{item_id}: orphan mappedConceptID")
        disposition = item.get("disposition")
        if disposition not in ALLOWED_DISPOSITIONS:
            errors.append(f"{item_id}: unknown disposition")
        duplicate = item.get("duplicateOfLegacyID")
        if disposition == "duplicate":
            if duplicate not in by_id or duplicate == item_id:
                errors.append(f"{item_id}: duplicate requires a valid prior legacy ID")
        elif duplicate is not None:
            errors.append(f"{item_id}: non-duplicate must not set duplicateOfLegacyID")
        if disposition in {"outdated", "low_value_retire"} and len(
            normalized(item.get("reason"))
        ) < 12:
            errors.append(f"{item_id}: retirement/outdated reason is not concrete")
        if item.get("status") != expected_status:
            errors.append(
                f"{item_id}: inventory status must be {expected_status} for this master"
            )
    return errors


def variant_counts(variants: Iterable[dict]) -> Counter:
    return Counter(value.get("format") for value in variants)


def validate_variant_quality(
    variants: list[dict], master: dict, *, require_reviewed: bool
) -> list[str]:
    errors: list[str] = []
    concepts = {value["conceptID"]: value for value in master.get("concepts", [])}
    ids = [value.get("id") for value in variants]
    if len(ids) != len(set(ids)):
        errors.append("variant item IDs must be unique")
    keys = [(value.get("conceptID"), value.get("variantID")) for value in variants]
    if len(keys) != len(set(keys)):
        errors.append("conceptID/variantID pairs must be unique")
    prompt_owners: dict[tuple[str, str], str] = {}
    for variant in variants:
        item_id = variant.get("id", "<unknown>")
        concept_id = variant.get("conceptID")
        if concept_id not in concepts:
            errors.append(f"{item_id}: unknown conceptID")
            concept = {}
        else:
            concept = concepts[concept_id]
        if variant.get("format") not in ALLOWED_FORMATS:
            errors.append(f"{item_id}: unsupported format")
        if variant.get("format") == "number_choice" and not confirmed_numeric_facts(
            concept
        ):
            errors.append(
                f"{item_id}: number_choice requires a human-reviewed numericFact"
            )
        prompt_key = (concept_id, normalized(variant.get("prompt")))
        if prompt_key in prompt_owners:
            errors.append(
                f"{item_id}: exact semantic duplicate prompt of {prompt_owners[prompt_key]}"
            )
        prompt_owners[prompt_key] = item_id
        choices = variant.get("choices") or []
        correct_id = variant.get("correctChoiceID")
        wrong_choices = [value for value in choices if value.get("id") != correct_id]
        rationales = variant.get("wrongChoiceRationales") or {}
        if set(rationales) != {value.get("id") for value in wrong_choices}:
            errors.append(f"{item_id}: every distractor requires one rationale")
        for choice in wrong_choices:
            if len(normalized(choice.get("rationale"))) < 12:
                errors.append(f"{item_id}/{choice.get('id')}: rationale is not concrete")
            if choice.get("misconceptionCode") not in ALLOWED_MISCONCEPTIONS:
                errors.append(f"{item_id}/{choice.get('id')}: invalid misconceptionCode")
        if variant.get("unlockEligible") is True and (
            not isinstance(variant.get("estimatedSeconds"), int)
            or variant["estimatedSeconds"] > 30
            or variant.get("format") == "case_study"
        ):
            errors.append(f"{item_id}: unlock eligibility exceeds the 30-second policy")
        if require_reviewed:
            if variant.get("isPlaceholder") is True:
                errors.append(f"{item_id}: placeholder must not count as reviewed")
            if variant.get("reviewStatus") not in {"reviewed", "release"}:
                errors.append(f"{item_id}: reviewed candidate contains ai_draft")
            if variant.get("distractorReviewStatus") != "checked":
                errors.append(f"{item_id}: distractors are not checked")
        else:
            if variant.get("reviewStatus") != "ai_draft":
                errors.append(f"{item_id}: generated variant must remain ai_draft")
            if variant.get("distractorReviewStatus") != "pending":
                errors.append(f"{item_id}: generated distractor must remain pending")
            if (
                variant.get("reviewer")
                or variant.get("reviewedAt")
                or variant.get("reviewNote")
            ):
                errors.append(f"{item_id}: AI draft must not fabricate review metadata")
            if variant.get("sourceNote") is not None:
                errors.append(f"{item_id}: unresearched AI draft must not claim a source")
    return errors


def tier_variant_shortages(master: dict, variants: list[dict]) -> list[str]:
    countable = [value for value in variants if value.get("isPlaceholder") is not True]
    counts = Counter(value.get("conceptID") for value in countable)
    formats: dict[str, set[str]] = defaultdict(set)
    for value in countable:
        formats[value.get("conceptID")].add(value.get("format"))
    shortages: list[str] = []
    for concept in master.get("concepts", []):
        concept_id = concept["conceptID"]
        if counts[concept_id] < concept["minimumVariantCount"]:
            shortages.append(
                f"{concept_id}: {counts[concept_id]}/"
                f"{concept['minimumVariantCount']} variants"
            )
        if concept["importanceTier"] == "A" and len(formats[concept_id]) < 3:
            shortages.append(f"{concept_id}: A tier has fewer than 3 formats")
    return shortages


def format_balance_errors(
    variants: list[dict], master: dict | None = None, *, generated_draft: bool = False
) -> list[str]:
    errors: list[str] = []
    count = max(1, len(variants))
    has_reviewed_numbers = bool(
        master
        and any(confirmed_numeric_facts(value) for value in master.get("concepts", []))
    )
    ranges = (
        {
            "true_false": (0.25, 0.30),
            "number_choice": (0.20, 0.25),
            "wording_contrast": (0.20, 0.25),
            "multiple_choice": (0.20, 0.25),
            "case_study": (0.05, 0.10),
        }
        if has_reviewed_numbers or not generated_draft
        else {
            "true_false": (0.25, 0.45),
            "number_choice": (0.0, 0.0),
            "wording_contrast": (0.20, 0.40),
            "multiple_choice": (0.20, 0.40),
            "case_study": (0.03, 0.15),
        }
    )
    counts = variant_counts(variants)
    for fmt, (minimum, maximum) in ranges.items():
        ratio = counts[fmt] / count
        if not minimum <= ratio <= maximum:
            errors.append(
                f"{fmt} ratio {ratio:.1%} is outside {minimum:.0%}-{maximum:.0%}"
            )
    return errors


def golden_candidate_errors(
    golden: dict, variants: list[dict], master: dict
) -> list[str]:
    errors = validate_golden_question_set(golden, master)
    golden_ids = set(golden_concept_ids(golden))
    if not 250 <= len(variants) <= 300:
        errors.append("Golden candidate must contain 250-300 variants")
    if {value.get("conceptID") for value in variants} != golden_ids:
        errors.append("Golden variants must cover every Golden concept")
    errors.extend(validate_variant_quality(variants, master, require_reviewed=True))
    errors.extend(format_balance_errors(variants, master))
    manifest = {
        "qualification": {"examYear": 2026, "lawBasisDate": "2026-04-01"},
        "choiceOrderStrategy": "seeded_shuffle",
    }
    errors.extend(validate_takken_v2(variants, manifest, release_pack=False))
    shortages = [
        value
        for value in tier_variant_shortages(
            {
                "concepts": [
                    value
                    for value in master.get("concepts", [])
                    if value["conceptID"] in golden_ids
                ]
            },
            variants,
        )
    ]
    errors.extend(f"Golden shortage: {value}" for value in shortages)
    return errors


def full_pack_candidate_errors(
    variants: list[dict], master: dict, inventory: dict
) -> list[str]:
    errors: list[str] = []
    plan = master.get("fullPackPlan") or {}
    planned_standalone = plan.get("plannedStandaloneVariantCount")
    planned_integrated = plan.get("plannedIntegratedCaseCount")
    planned_total = plan.get("plannedTotalQuestionCount")
    integrated = [
        value for value in variants if value.get("integratedConceptIDs")
    ]
    standalone = [
        value for value in variants if not value.get("integratedConceptIDs")
    ]
    if len(variants) != planned_total:
        errors.append(f"full pack must contain planned total {planned_total}")
    if len(standalone) != planned_standalone:
        errors.append(
            f"full pack standalone count must be {planned_standalone}"
        )
    if len(integrated) != planned_integrated:
        errors.append(
            f"full pack integrated case count must be {planned_integrated}"
        )
    concepts = {value.get("conceptID") for value in variants}
    if not 350 <= len(concepts) <= 450:
        errors.append("full pack must cover 350-450 concepts")
    errors.extend(validate_variant_quality(variants, master, require_reviewed=True))
    errors.extend(format_balance_errors(variants, master))
    errors.extend(tier_variant_shortages(master, variants))
    master_ids = {value["conceptID"] for value in master.get("concepts", [])}
    for value in integrated:
        related = value.get("integratedConceptIDs") or []
        if (
            value.get("format") != "case_study"
            or len(set(related)) < 2
            or not set(related).issubset(master_ids)
        ):
            errors.append(
                f"{value.get('id')}: integrated case requires 2+ known concept IDs"
            )
    represented_categories = {value.get("category") for value in variants}
    expected_categories = {value.get("category") for value in master.get("concepts", [])}
    if represented_categories != expected_categories:
        errors.append("full pack must cover every master category")
    represented_tiers = {
        next(
            (
                concept.get("importanceTier")
                for concept in master.get("concepts", [])
                if concept.get("conceptID") == value.get("conceptID")
            ),
            None,
        )
        for value in variants
    }
    if not {"A", "B", "C"}.issubset(represented_tiers):
        errors.append("full pack must cover every importance tier")
    if len({value.get("format") for value in variants}) < 4:
        errors.append("full pack must provide at least four useful formats")
    inventory_items = inventory.get("items") or []
    if len(inventory_items) != 1_000 or any(
        value.get("disposition") not in ALLOWED_DISPOSITIONS for value in inventory_items
    ):
        errors.append("full pack requires a complete legacy inventory")
    return errors


def free_sample_selection_errors(
    variants: list[dict], golden: dict, master: dict
) -> tuple[list[str], list[dict]]:
    errors = golden_candidate_errors(golden, variants, master)
    if errors:
        return errors, []
    by_concept: dict[str, list[dict]] = defaultdict(list)
    for variant in variants:
        by_concept[variant["conceptID"]].append(variant)
    selected = []
    for concept_id in golden_concept_ids(golden):
        candidates = by_concept[concept_id]
        selected.append(
            min(
                candidates,
                key=lambda value: (
                    not value.get("unlockEligible", False),
                    value.get("estimatedSeconds", 999),
                    value["format"] == "case_study",
                    value["variantID"],
                ),
            )
        )
    if len(selected) != len(golden_concept_ids(golden)):
        errors.append("default free sample must represent every Golden concept")
    return errors, sorted(selected, key=lambda value: value["conceptID"])


def build_free_sample_profiles() -> dict:
    return {
        "schemaVersion": 1,
        "workflowVersion": 18,
        "profiles": [
            {
                "profileID": "current-gyoho-100",
                "title": "現在の商品方針（宅建業法100問）",
                "questionCount": 100,
                "scope": "golden_questions",
                "minimumDistinctConceptCount": 50,
                "maximumQuestionsPerConcept": 2,
                "categoryTargets": {"宅建業法": 100},
                "formatTargets": {},
                "difficultyTargets": {},
                "minimumUnlockEligibleCount": 90,
                "maximumCaseStudyCount": 0,
            },
            {
                "profileID": "all-fields-balanced-100",
                "title": "全分野体験版100問",
                "questionCount": 100,
                "scope": "all_reviewed_concepts",
                "minimumDistinctConceptCount": 80,
                "maximumQuestionsPerConcept": 2,
                "categoryTargets": {
                    "宅建業法": 30,
                    "権利関係": 30,
                    "法令上の制限": 20,
                    "税・その他": 20,
                },
                "formatTargets": {
                    "true_false": 30,
                    "number_choice": 15,
                    "wording_contrast": 20,
                    "multiple_choice": 30,
                    "case_study": 5,
                },
                "difficultyTargets": {},
                "minimumUnlockEligibleCount": 75,
                "maximumCaseStudyCount": 5,
            },
        ],
    }


def select_free_sample_with_profile(
    variants: list[dict], master: dict, golden: dict, profile: dict
) -> tuple[list[str], list[dict]]:
    errors = validate_variant_quality(variants, master, require_reviewed=True)
    if errors:
        return errors, []
    scope = profile.get("scope")
    golden_ids = set(golden_concept_ids(golden))
    pool = [
        value
        for value in variants
        if scope != "golden_questions" or value.get("conceptID") in golden_ids
    ]
    question_count = profile.get("questionCount")
    maximum_per_concept = profile.get("maximumQuestionsPerConcept")
    if not isinstance(question_count, int) or question_count <= 0:
        return ["free sample profile questionCount is invalid"], []
    if not isinstance(maximum_per_concept, int) or maximum_per_concept <= 0:
        return ["free sample profile maximumQuestionsPerConcept is invalid"], []

    category_targets = profile.get("categoryTargets") or {}
    format_targets = profile.get("formatTargets") or {}
    difficulty_targets = profile.get("difficultyTargets") or {}
    category_counts: Counter = Counter()
    format_counts: Counter = Counter()
    difficulty_counts: Counter = Counter()
    concept_counts: Counter = Counter()
    selected: list[dict] = []
    remaining = sorted(pool, key=lambda value: (value["conceptID"], value["variantID"]))
    while len(selected) < question_count:
        eligible = [
            value
            for value in remaining
            if concept_counts[value["conceptID"]] < maximum_per_concept
            and (
                not category_targets
                or category_counts[value["category"]]
                < category_targets.get(value["category"], 0)
            )
            and (
                not format_targets
                or format_counts[value["format"]]
                < format_targets.get(value["format"], 0)
            )
            and (
                not difficulty_targets
                or difficulty_counts[value["difficulty"]]
                < difficulty_targets.get(value["difficulty"], 0)
            )
            and (
                value["format"] != "case_study"
                or format_counts["case_study"]
                < profile.get("maximumCaseStudyCount", question_count)
            )
        ]
        if not eligible:
            errors.append(
                f"free sample profile cannot fill {question_count} questions "
                f"(selected {len(selected)})"
            )
            break

        def rank(value: dict) -> tuple:
            category_deficit = category_targets.get(value["category"], 0) - category_counts[
                value["category"]
            ]
            format_deficit = format_targets.get(value["format"], 0) - format_counts[
                value["format"]
            ]
            difficulty_deficit = difficulty_targets.get(
                value["difficulty"], 0
            ) - difficulty_counts[value["difficulty"]]
            return (
                -category_deficit if category_targets else 0,
                -format_deficit if format_targets else 0,
                -difficulty_deficit if difficulty_targets else 0,
                concept_counts[value["conceptID"]],
                not value.get("unlockEligible", False),
                value.get("estimatedSeconds", 999),
                value["conceptID"],
                value["variantID"],
            )

        chosen = min(eligible, key=rank)
        selected.append(chosen)
        remaining.remove(chosen)
        category_counts[chosen["category"]] += 1
        format_counts[chosen["format"]] += 1
        difficulty_counts[chosen["difficulty"]] += 1
        concept_counts[chosen["conceptID"]] += 1

    for label, targets, counts in (
        ("category", category_targets, category_counts),
        ("format", format_targets, format_counts),
        ("difficulty", difficulty_targets, difficulty_counts),
    ):
        if targets and any(counts[key] != target for key, target in targets.items()):
            errors.append(f"free sample {label} targets were not satisfied")
    if len(concept_counts) < profile.get("minimumDistinctConceptCount", 0):
        errors.append("free sample distinct concept target was not satisfied")
    if (
        sum(value.get("unlockEligible") is True for value in selected)
        < profile.get("minimumUnlockEligibleCount", 0)
    ):
        errors.append("free sample unlockEligible target was not satisfied")
    if (
        sum(value.get("format") == "case_study" for value in selected)
        > profile.get("maximumCaseStudyCount", question_count)
    ):
        errors.append("free sample case-study maximum was exceeded")
    return errors, selected


def audit_snapshot() -> tuple[dict, list[str]]:
    errors = protected_release_errors()
    master = load_json(MASTER_PATH)
    inventory = load_json(INVENTORY_PATH)
    golden = load_json(GOLDEN_PATH)
    variant_document = load_json(VARIANTS_PATH)
    research = load_json(RESEARCH_PATH)
    variants = variant_document.get("variants") or []
    records = load_legacy_records()
    known_ids = {record["question"]["id"] for record in records}
    errors.extend(validate_concept_master(master, known_ids))
    errors.extend(validate_legacy_inventory(inventory, master, records))
    errors.extend(validate_variant_quality(variants, master, require_reviewed=False))
    errors.extend(validate_golden_question_set(golden, master))
    if not 250 <= len(variants) <= 300:
        errors.append("Golden variant draft must contain 250-300 variants")
    errors.extend(format_balance_errors(variants, master, generated_draft=True))
    if len(research.get("items") or []) != len(master.get("concepts") or []):
        errors.append("source research queue must cover every draft concept")
    if any(value.get("status") != "pending" for value in research.get("items") or []):
        errors.append("source research queue contains a non-pending item")
    if any(
        value.get("reviewStatus") != "ai_draft"
        for value in master.get("concepts") or []
    ):
        errors.append("concept master contains an automatically approved concept")
    if any(
        value.get("reviewStatus") != "ai_draft"
        or value.get("distractorReviewStatus") != "pending"
        for value in variants
    ):
        errors.append("Golden variants contain an automatically approved item")

    concepts = master.get("concepts") or []
    inventory_items = inventory.get("items") or []
    snapshot = {
        "releaseProtection": {
            "itemCount": 100,
            "sha256": sha256(RELEASE_PATH),
            "expectedItemCount": 100,
            "saleReady": False,
            "unchanged": not protected_release_errors(),
        },
        "conceptMaster": {
            "count": len(concepts),
            "categoryDistribution": dict(
                sorted(Counter(value["category"] for value in concepts).items())
            ),
            "tierDistribution": dict(
                sorted(Counter(value["importanceTier"] for value in concepts).items())
            ),
            "reviewStatusDistribution": dict(
                sorted(Counter(value["reviewStatus"] for value in concepts).items())
            ),
        },
        "legacyInventory": {
            "count": len(inventory_items),
            "dispositionDistribution": dict(
                sorted(Counter(value["disposition"] for value in inventory_items).items())
            ),
            "orphanCount": sum(
                value.get("mappedConceptID") is None for value in inventory_items
            ),
        },
        "golden": {
            "questionCount": len(golden.get("goldenQuestionIDs") or []),
            "conceptCount": golden.get("distinctConceptCount"),
            "variantCount": len(variants),
            "formatDistribution": dict(sorted(variant_counts(variants).items())),
            "formatRatios": {
                key: round(value / max(1, len(variants)), 4)
                for key, value in sorted(variant_counts(variants).items())
            },
            "reviewedCount": sum(
                value.get("reviewStatus") in {"reviewed", "release"}
                for value in variants
            ),
        },
        "sourceResearch": {
            "pendingCount": len(research.get("items") or []),
            "tierDistribution": dict(
                sorted(
                    Counter(
                        value["priorityTier"] for value in research.get("items") or []
                    ).items()
                )
            ),
        },
        "fullPackProgress": {
            "draftVariants": len(variants),
            "minimumRequired": 1_000,
            "reviewedVariants": 0,
            "variantShortageCount": len(tier_variant_shortages(master, variants)),
        },
    }
    return snapshot, errors
