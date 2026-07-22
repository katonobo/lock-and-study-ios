#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASED = ROOT / "LockAndStudy/Resources/Content/Released"
CATALOG = RELEASED / "study_pack_catalog.json"
APP_ICON_SET = ROOT / "LockAndStudy/Resources/Assets.xcassets/AppIcon.appiconset"


class CheckFailure(RuntimeError):
    pass


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise CheckFailure(f"invalid JSON: {path.relative_to(ROOT)}: {exc}") from exc


def catalog():
    value = load_json(CATALOG)
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and isinstance(value.get("packs"), list):
        return value["packs"]
    raise CheckFailure("study_pack_catalog.json must be a v1 array or v2 snapshot")


def catalog_snapshot():
    value = load_json(CATALOG)
    if isinstance(value, list):
        return {"schemaVersion": 1, "categories": [], "series": [], "packs": value}
    if isinstance(value, dict) and isinstance(value.get("packs"), list):
        return value
    raise CheckFailure("study_pack_catalog.json must be a v1 array or v2 snapshot")


PASS_PRODUCT_IDS = {
    "com.ameneko.lockandstudy.pass.monthly",
    "com.ameneko.lockandstudy.pass.yearly",
}
SUPPORTED_EXPERIENCES = {
    "flashcard.v1": {"flashcard.items.v1"},
    "certification.v1": {"certification.questions.v1"},
    "safe-fallback.v1": {"safe-fallback.v1"},
}


def _has_cycle(nodes: set[str], parent_for: dict[str, str | None]) -> bool:
    for start in nodes:
        seen: set[str] = set()
        current: str | None = start
        while current is not None and current in nodes:
            if current in seen:
                return True
            seen.add(current)
            current = parent_for.get(current)
    return False


def _safe_relative_path(value: object) -> bool:
    if not isinstance(value, str) or not value:
        return False
    path = Path(value)
    return not path.is_absolute() and ".." not in path.parts


def validate_catalog_relationships(snapshot: dict) -> list[str]:
    errors: list[str] = []
    categories = snapshot.get("categories") or []
    series = snapshot.get("series") or []
    packs = snapshot.get("packs") or []

    def unique_ids(values: list[dict], label: str) -> set[str]:
        ids = [value.get("id") for value in values]
        if any(not isinstance(value, str) or not value for value in ids):
            errors.append(f"{label} contains an empty ID")
        if len(ids) != len(set(ids)):
            errors.append(f"duplicate {label} ID")
        return {value for value in ids if isinstance(value, str) and value}

    category_ids = unique_ids(categories, "category")
    series_ids = unique_ids(series, "series")
    pack_ids = unique_ids(packs, "pack")
    category_by_id = {value.get("id"): value for value in categories}
    series_by_id = {value.get("id"): value for value in series}

    category_parents: dict[str, str | None] = {}
    for category in categories:
        category_id = category.get("id")
        parent_id = category.get("parentCategoryID")
        if parent_id is not None and parent_id not in category_ids:
            errors.append(f"{category_id}: unknown parent category {parent_id}")
        if isinstance(category_id, str):
            category_parents[category_id] = parent_id
    if _has_cycle(category_ids, category_parents):
        errors.append("parent category cycle")

    for value in series:
        if value.get("categoryID") not in category_ids:
            errors.append(f"{value.get('id')}: unknown category {value.get('categoryID')}")

    product_owners: dict[str, str] = {}
    supersedes: dict[str, str | None] = {}
    for pack in packs:
        pack_id = pack.get("id", "<unknown>")
        category_id = pack.get("categoryID")
        series_id = pack.get("seriesID")
        if category_id not in category_ids:
            errors.append(f"{pack_id}: unknown category {category_id}")
        if series_id not in series_ids:
            errors.append(f"{pack_id}: unknown series {series_id}")
        elif series_by_id[series_id].get("categoryID") != category_id:
            errors.append(f"{pack_id}: series/category mismatch")

        edition_policy = pack.get("editionPolicy")
        series_policy = series_by_id.get(series_id, {}).get("editionPolicy")
        if (edition_policy == "annual" or series_policy == "annual") and not isinstance(
            pack.get("editionYear"), int
        ):
            errors.append(f"{pack_id}: annual pack requires editionYear")

        predecessor = pack.get("supersedesPackID")
        if predecessor is not None and predecessor not in pack_ids:
            errors.append(f"{pack_id}: unknown superseded pack {predecessor}")
        if isinstance(pack_id, str):
            supersedes[pack_id] = predecessor

        store_state = pack.get("storeState")
        if store_state == "archivedOwnedOnly" and pack.get("saleReady") is True:
            errors.append(f"{pack_id}: archivedOwnedOnly cannot be sale ready")
        if store_state == "withdrawn" and (
            pack.get("passEligible") is True or pack.get("passAccessPolicy") == "included"
        ):
            errors.append(f"{pack_id}: withdrawn pack cannot be sold through Pass")

        product_id = pack.get("oneTimeProductID")
        if product_id is not None:
            if product_id in PASS_PRODUCT_IDS:
                errors.append(f"{pack_id}: one-time product collides with Pass")
            prior = product_owners.get(product_id)
            if prior is not None and prior != pack_id:
                errors.append(f"product ID reused by {prior} and {pack_id}: {product_id}")
            product_owners[product_id] = pack_id

        experience_id = pack.get("experienceID")
        supported_schemas = SUPPORTED_EXPERIENCES.get(experience_id)
        if supported_schemas is None and (
            pack.get("saleReady") is True or pack.get("passAccessPolicy") == "included"
        ):
            errors.append(f"{pack_id}: unsupported experience must not be purchasable")
        components = pack.get("components") or []
        component_ids = [component.get("id") for component in components]
        if len(component_ids) != len(set(component_ids)):
            errors.append(f"{pack_id}: duplicate component ID")
        for component in components:
            component_experience = component.get("experienceID")
            component_schema = component.get("contentSchemaID")
            if component_experience != experience_id:
                errors.append(f"{pack_id}/{component.get('id')}: component experience mismatch")
            if supported_schemas is not None and component_schema not in supported_schemas:
                errors.append(
                    f"{pack_id}/{component.get('id')}: unsupported content schema {component_schema}"
                )
            for descriptor in component.get("contentFiles") or []:
                if not _safe_relative_path(descriptor.get("path")):
                    errors.append(f"{pack_id}/{component.get('id')}: unsafe content path")
        for descriptor in pack.get("contentFiles") or []:
            if not _safe_relative_path(descriptor.get("path")):
                errors.append(f"{pack_id}: unsafe content path")
        for key in ("metadataFile", "creditsFile"):
            if pack.get(key) is not None and not _safe_relative_path(pack.get(key)):
                errors.append(f"{pack_id}: unsafe {key}")

    if _has_cycle(pack_ids, supersedes):
        errors.append("supersedes cycle")
    return errors


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _normalized_text(value: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", value or "")).lower()


def validate_takken_v2(items: list[dict], manifest: dict) -> list[str]:
    """Strict gate for future Takken v2 Release candidates; current v1 remains auditable."""
    errors: list[str] = []
    formats = {name: 0 for name in (
        "true_false", "number_choice", "wording_contrast", "multiple_choice", "case_study"
    )}
    true_false_correct = {"正しい": 0, "誤り": 0}
    four_choice_positions: list[int] = []
    expected_year = (manifest.get("qualification") or {}).get("examYear")
    expected_basis = (manifest.get("qualification") or {}).get("lawBasisDate")
    allowed_counts = {
        "true_false": {2}, "number_choice": {2, 3, 4}, "wording_contrast": {2},
        "multiple_choice": {4}, "case_study": {4},
    }
    allowed_review = {"checked", "reviewed", "release"}
    unit_pattern = re.compile(r"(?:円|万円|億円|日|週間|か月|ヶ月|月|年|％|%|割|人|件|㎡|平方メートル)")

    for item in items:
        item_id = item.get("id", "<unknown>")
        concept_id, variant_id = item.get("conceptID"), item.get("variantID")
        if not isinstance(concept_id, str) or not concept_id.strip():
            errors.append(f"{item_id}: v2 conceptID is required")
        if not isinstance(variant_id, str) or not variant_id.strip():
            errors.append(f"{item_id}: v2 variantID is required")
        fmt = item.get("format")
        if fmt not in formats:
            errors.append(f"{item_id}: unsupported v2 format {fmt}")
            continue
        formats[fmt] += 1
        choices = item.get("choices")
        if not isinstance(choices, list) or len(choices) not in allowed_counts[fmt]:
            errors.append(f"{item_id}: choice count does not match {fmt}")
            continue
        if not all(isinstance(choice, dict) for choice in choices):
            errors.append(f"{item_id}: v2 choices require stable object IDs")
            continue
        choice_ids = [choice.get("id") for choice in choices]
        choice_texts = [_normalized_text(choice.get("text", "")) for choice in choices]
        if any(not isinstance(choice_id, str) or not choice_id for choice_id in choice_ids):
            errors.append(f"{item_id}: empty stable choice ID")
        if len(choice_ids) != len(set(choice_ids)):
            errors.append(f"{item_id}: duplicate stable choice ID")
        if any(not text for text in choice_texts) or len(choice_texts) != len(set(choice_texts)):
            errors.append(f"{item_id}: empty or duplicate choice text")
        correct_id = item.get("correctChoiceID")
        if correct_id not in choice_ids:
            errors.append(f"{item_id}: correctChoiceID does not exist")
        else:
            correct_index = choice_ids.index(correct_id)
            supplied_index = item.get("correctIndex")
            if not isinstance(supplied_index, int) or not 0 <= supplied_index < len(choices):
                errors.append(f"{item_id}: correctIndex is missing or out of bounds")
            elif supplied_index != correct_index:
                errors.append(f"{item_id}: correctChoiceID and correctIndex disagree")
            if fmt == "true_false":
                correct_text = choices[correct_index].get("text")
                if correct_text in true_false_correct:
                    true_false_correct[correct_text] += 1
                else:
                    errors.append(f"{item_id}: true/false choices must use 正しい/誤り")
            if fmt in {"multiple_choice", "case_study"}:
                four_choice_positions.append(correct_index)
        rationale_map = item.get("wrongChoiceRationales") or {}
        if not isinstance(rationale_map, dict):
            errors.append(f"{item_id}: wrongChoiceRationales must be an object")
        elif correct_id in rationale_map:
            errors.append(f"{item_id}: correct choice must not have a wrong rationale")
        short = _normalized_text(item.get("shortExplanation", ""))
        long = _normalized_text(item.get("longExplanation", ""))
        if not short or not long or short == long:
            errors.append(f"{item_id}: short and long explanations must differ")
        elif len(long) < len(short) + 10:
            errors.append(f"{item_id}: long explanation must add information")
        if item.get("reviewStatus") not in allowed_review:
            errors.append(f"{item_id}: v2 reviewStatus is not approved")
        if item.get("distractorReviewStatus") != "checked":
            errors.append(f"{item_id}: distractor review is required")
        wrong_choices = [choice for choice in choices if choice.get("id") != correct_id]
        if any(not str(choice.get("rationale") or "").strip() for choice in wrong_choices):
            errors.append(f"{item_id}: every distractor needs a human-reviewed rationale")
        if item.get("isPlaceholder") is not False or item.get("reviewStatus") == "ai_draft":
            errors.append(f"{item_id}: placeholder/AI draft cannot enter Release")
        if item.get("examYear") != expected_year or item.get("lawBasisDate") != expected_basis:
            errors.append(f"{item_id}: year/law basis differs from manifest")
        if fmt == "number_choice":
            units = [set(unit_pattern.findall(choice.get("text", ""))) for choice in choices]
            nonempty_units = [unit for unit in units if unit]
            if nonempty_units and any(unit != nonempty_units[0] for unit in nonempty_units):
                errors.append(f"{item_id}: number-choice units are inconsistent")

    count = len(items)
    if count:
        ratio = lambda name: formats[name] / count
        if ratio("true_false") > 0.50:
            errors.append("v2 true_false must be at most 50%")
        if ratio("number_choice") < 0.15:
            errors.append("v2 number_choice must be at least 15%")
        if ratio("wording_contrast") < 0.15:
            errors.append("v2 wording_contrast must be at least 15%")
        if (formats["multiple_choice"] + formats["case_study"]) / count < 0.25:
            errors.append("v2 multiple_choice + case_study must be at least 25%")
    tf_count = sum(true_false_correct.values())
    if tf_count:
        true_ratio = true_false_correct["正しい"] / tf_count
        if not 0.40 <= true_ratio <= 0.60:
            errors.append("v2 true_false correct-answer ratio must be 40-60%")
    if four_choice_positions and manifest.get("choiceOrderStrategy") != "seeded_shuffle":
        position_counts = [four_choice_positions.count(position) for position in range(4)]
        if min(position_counts) == 0 or max(position_counts) / len(four_choice_positions) > 0.40:
            errors.append("v2 four-choice answer positions are biased and shuffle is not declared")
    return errors


def validate_takken_v2_drafts(items: list[dict]) -> list[str]:
    """Structural and isolation gate for unreviewed candidates, never an approval gate."""
    errors: list[str] = []
    if not 300 <= len(items) <= 500:
        errors.append("Takken v2 Draft must contain 300-500 base/derived candidates")
    ids = [item.get("id") for item in items]
    if len(ids) != len(set(ids)):
        errors.append("Takken v2 Draft contains duplicate item IDs")
    concept_ids = {item.get("conceptID") for item in items}
    if len(concept_ids) != 100 or None in concept_ids:
        errors.append("Takken v2 Draft must preserve exactly 100 concepts")
    formats = Counter(item.get("format") for item in items)
    count = max(1, len(items))
    target_ranges = {
        "true_false": (0.25, 0.30),
        "number_choice": (0.20, 0.25),
        "wording_contrast": (0.20, 0.25),
        "multiple_choice": (0.20, 0.25),
        "case_study": (0.05, 0.10),
    }
    for fmt, (minimum, maximum) in target_ranges.items():
        ratio = formats[fmt] / count
        if not minimum <= ratio <= maximum:
            errors.append(f"Takken v2 Draft {fmt} ratio {ratio:.1%} is outside target")
    for item in items:
        item_id = item.get("id", "<unknown>")
        if item.get("reviewStatus") != "ai_draft":
            errors.append(f"{item_id}: Draft reviewStatus must remain ai_draft")
        if item.get("distractorReviewStatus") != "pending":
            errors.append(f"{item_id}: Draft distractorReviewStatus must remain pending")
        choices = item.get("choices")
        if not isinstance(choices, list) or not choices:
            errors.append(f"{item_id}: Draft choices are missing")
            continue
        choice_ids = [choice.get("id") for choice in choices if isinstance(choice, dict)]
        if len(choice_ids) != len(choices) or len(choice_ids) != len(set(choice_ids)):
            errors.append(f"{item_id}: Draft stable choice IDs are invalid")
            continue
        correct_id = item.get("correctChoiceID")
        correct_index = item.get("correctIndex")
        if correct_id not in choice_ids:
            errors.append(f"{item_id}: Draft correctChoiceID does not exist")
        elif not isinstance(correct_index, int) or not 0 <= correct_index < len(choices):
            errors.append(f"{item_id}: Draft correctIndex is invalid")
        elif choice_ids[correct_index] != correct_id:
            errors.append(f"{item_id}: Draft correctChoiceID/index disagree")
        rationales = item.get("wrongChoiceRationales") or {}
        if correct_id in rationales:
            errors.append(f"{item_id}: Draft correct choice has a wrong rationale")
    return errors


def validate_content() -> list[str]:
    errors: list[str] = []
    snapshot = catalog_snapshot()
    errors.extend(validate_catalog_relationships(snapshot))
    packs = catalog()
    ids = [pack.get("id") for pack in packs]
    if len(ids) != len(set(ids)):
        errors.append("duplicate pack ID")
    for pack in packs:
        if pack.get("schemaVersion") not in (1, 2):
            errors.append(f"{pack.get('id')}: unsupported schemaVersion")
        if pack.get("releaseStatus") != "release" or pack.get("isEnabled") is not True:
            errors.append(f"{pack.get('id')}: non-release pack in Release Resources")
        if pack.get("expectedItemCount", 0) <= 0:
            errors.append(f"{pack.get('id')}: invalid expectedItemCount")
        for descriptor in pack.get("contentFiles", []):
            path = RELEASED / descriptor.get("path", "")
            if not path.is_file():
                errors.append(f"{pack.get('id')}: missing {path.name}")
                continue
            if sha256(path) != descriptor.get("sha256"):
                errors.append(f"{pack.get('id')}: hash mismatch {path.name}")
            value = load_json(path)
            if isinstance(value, list):
                actual_count = len(value)
            elif isinstance(value, dict) and isinstance(value.get("levels"), list):
                actual_count = sum(len(level.get("questions", [])) for level in value["levels"])
            else:
                actual_count = None
            if actual_count is not None and actual_count != descriptor.get("itemCount"):
                errors.append(f"{pack.get('id')}: item count mismatch {path.name}")
            if "ai_draft" in json.dumps(value, ensure_ascii=False):
                errors.append(f"{pack.get('id')}: ai_draft found in Release {path.name}")
        for key in ("metadataFile", "creditsFile"):
            if pack.get(key) and not (RELEASED / pack[key]).is_file():
                errors.append(f"{pack.get('id')}: missing {pack[key]}")

    by_id = {pack["id"]: pack for pack in packs}
    english = load_json(RELEASED / "vocabulary_english3000_v1.json")
    samples = load_json(RELEASED / "vocabulary_free_sample_250_v1.json")
    if len(english) != 3000 or by_id.get("english3000.v1", {}).get("expectedItemCount") != 3000:
        errors.append("official English content must contain exactly 3,000 items")
    english_ids = [item.get("id") for item in english]
    if len(english_ids) != len(set(english_ids)):
        errors.append("duplicate English item ID")
    sample_levels = samples.get("levels", [])
    sample_ids = [question.get("id") for level in sample_levels for question in level.get("questions", [])]
    if len(sample_levels) != 5 or any(len(level.get("questions", [])) != 50 for level in sample_levels) or len(sample_ids) != 250:
        errors.append("free English sample must be five levels x 50 = 250")
    if not set(sample_ids).issubset(set(english_ids)):
        errors.append("free English sample references unknown IDs")
    if samples.get("questionIDSetSHA256") != "fbf68cfb9c4f564436fcd4b78c4e7e35e27bd1078113d02f2c4a4bedfede4667":
        errors.append("free English official ID digest mismatch")

    takken = load_json(RELEASED / "takken_2026_free_100_v1.json")
    if len(takken) != 100 or by_id.get("takken2026.v1", {}).get("expectedItemCount") != 100:
        errors.append("released Takken sample must contain exactly 100 questions")
    if by_id.get("takken2026.v1", {}).get("saleReady") is not False:
        errors.append("Takken 2026 sale must remain disabled until full review")
    takken_ids = [item.get("id") for item in takken]
    if len(takken_ids) != len(set(takken_ids)):
        errors.append("duplicate Takken item ID")
    for item in takken:
        choices = item.get("choices", [])
        if item.get("isPlaceholder") is not False or item.get("reviewStatus") != "checked":
            errors.append(f"released Takken question not checked: {item.get('id')}")
        if not item.get("prompt", "").strip() or not item.get("explanation", "").strip():
            errors.append(f"empty Takken prompt/explanation: {item.get('id')}")
        if not isinstance(item.get("correctIndex"), int) or not 0 <= item["correctIndex"] < len(choices):
            errors.append(f"invalid Takken correctIndex: {item.get('id')}")
        if item.get("examYear") != 2026 or item.get("lawBasisDate") != "2026-04-01":
            errors.append(f"invalid Takken year/law basis: {item.get('id')}")
    takken_manifest = by_id.get("takken2026.v1", {})
    if takken_manifest.get("contentQualityProfile") == "takken-v2":
        errors.extend(validate_takken_v2(takken, takken_manifest))
    release_text = json.dumps(snapshot, ensure_ascii=False).lower()
    if "fixture" in release_text:
        errors.append("test fixture reference found in production catalog")
    if any("fixture" in path.name.lower() for path in RELEASED.iterdir()):
        errors.append("test fixture file found in production Release Resources")
    return errors


def verify_platform_v9() -> list[str]:
    errors: list[str] = []
    fixture_root = ROOT / "LockAndStudyTests/Fixtures/PlatformV9"
    fixture_catalog = fixture_root / "study_pack_catalog_v9_fixtures.json"
    snapshot = load_json(fixture_catalog)
    errors.extend(validate_catalog_relationships(snapshot))

    category_ids = {value.get("id") for value in snapshot.get("categories", [])}
    series_ids = {value.get("id") for value in snapshot.get("series", [])}
    pack_by_id = {value.get("id"): value for value in snapshot.get("packs", [])}
    expected_categories = {"language.japanese", "qualification", "life.manners"}
    expected_series = {
        "japanese.yojijukugo", "qualification.takken", "life.business-manners"
    }
    expected_fixture_packs = {
        "yojijukugo.fixture.v1", "takken2027.fixture.v1",
        "business-manners.fixture.v1",
    }
    if category_ids != expected_categories:
        errors.append("Platform v9 fixture categories changed")
    if series_ids != expected_series:
        errors.append("Platform v9 fixture series changed")
    if not expected_fixture_packs.issubset(pack_by_id):
        errors.append("Platform v9 proof pack is missing")

    expected_templates = {
        "yojijukugo.fixture.v1": ("flashcard.v1", "flashcard.items.v1", 6),
        "takken2027.fixture.v1": (
            "certification.v1", "certification.questions.v1", 3
        ),
        "business-manners.fixture.v1": (
            "certification.v1", "certification.questions.v1", 3
        ),
    }
    for pack_id, (experience_id, schema_id, expected_count) in expected_templates.items():
        pack = pack_by_id.get(pack_id, {})
        if pack.get("experienceID") != experience_id:
            errors.append(f"{pack_id}: fixture experience template changed")
        components = pack.get("components") or []
        if not components or components[0].get("contentSchemaID") != schema_id:
            errors.append(f"{pack_id}: fixture content schema changed")
        if pack.get("expectedItemCount") != expected_count:
            errors.append(f"{pack_id}: fixture item count changed")
        for descriptor in pack.get("contentFiles") or []:
            path = fixture_root / descriptor.get("path", "")
            if not path.is_file():
                errors.append(f"{pack_id}: missing fixture {path.name}")
                continue
            if sha256(path) != descriptor.get("sha256"):
                errors.append(f"{pack_id}: fixture hash mismatch {path.name}")

    takken2027 = pack_by_id.get("takken2027.fixture.v1", {})
    if takken2027.get("editionYear") != 2027:
        errors.append("Takken 2027 fixture must be an annual 2027 edition")
    if takken2027.get("supersedesPackID") != "takken2026.v1":
        errors.append("Takken 2027 fixture predecessor changed")
    if takken2027.get("oneTimeProductID") == "com.ameneko.lockandstudy.pack.takken2026.v1":
        errors.append("Takken 2027 fixture must use a separate product")
    manners_category = next(
        (value for value in snapshot.get("categories", []) if value.get("id") == "life.manners"),
        {},
    )
    if manners_category.get("themeToken") != "unknown-future-token":
        errors.append("unknown theme-token fallback fixture changed")

    production_ids = {value.get("id") for value in catalog()}
    if production_ids & expected_fixture_packs:
        errors.append("Platform v9 fixture pack leaked into production catalog")
    return errors


def check_unreviewed() -> list[str]:
    errors: list[str] = []
    reviewed = load_json(ROOT / "ContentSource/Reviewed/takken_2026_gyoho_reviewed_200_v1.json")
    drafts = [
        load_json(ROOT / "ContentSource/Drafts/takken_2026_horei_draft_200_v1.json"),
        load_json(ROOT / "ContentSource/Drafts/takken_2026_kenri_draft_300_v1.json"),
        load_json(ROOT / "ContentSource/Drafts/takken_2026_tax_draft_200_v1.json"),
    ]
    if len(reviewed) != 200:
        errors.append("Reviewed Takken content must remain 200 questions")
    if sum(map(len, drafts)) != 700:
        errors.append("Draft Takken content must remain 700 questions")
    v2_candidates = load_json(
        ROOT / "ContentSource/Drafts/takken_2026_free_100_v2_candidates.json"
    )
    errors.extend(validate_takken_v2_drafts(v2_candidates))
    release_names = {path.name for path in RELEASED.iterdir()}
    source_names = {path.name for path in (ROOT / "ContentSource/Reviewed").glob("*.json")} | {path.name for path in (ROOT / "ContentSource/Drafts").glob("*.json")}
    if release_names & source_names:
        errors.append("reviewed/draft file included in Release Resources")
    return errors


def verify_storekit() -> list[str]:
    errors: list[str] = []
    value = load_json(ROOT / "LockAndStudy/Resources/LockAndStudy.storekit")
    products = value.get("products", [])
    groups = value.get("subscriptionGroups", [])
    subscriptions = [item for group in groups for item in group.get("subscriptions", [])]
    ids = {item.get("productID") for item in products + subscriptions}
    expected = {
        "com.ameneko.lockandstudy.pass.monthly",
        "com.ameneko.lockandstudy.pass.yearly",
        "com.ameneko.lockandstudy.pack.english3000.v1",
        "com.ameneko.lockandstudy.pack.takken2026.v1",
    }
    if ids != expected:
        errors.append(f"StoreKit product IDs mismatch: {sorted(ids)}")
    if len(groups) != 1 or len(subscriptions) != 2 or any(item.get("groupNumber") != 1 for item in subscriptions):
        errors.append("monthly/yearly pass must share one group and service level")
    prices = {item.get("productID"): item.get("displayPrice") for item in products + subscriptions}
    expected_prices = {"com.ameneko.lockandstudy.pass.monthly": "980", "com.ameneko.lockandstudy.pass.yearly": "7800", "com.ameneko.lockandstudy.pack.english3000.v1": "4980", "com.ameneko.lockandstudy.pack.takken2026.v1": "2980"}
    if prices != expected_prices:
        errors.append("local StoreKit test prices mismatch")
    yearly = next((item for item in subscriptions if item.get("productID", "").endswith("yearly")), {})
    offer = yearly.get("introductoryOffer") or {}
    if offer.get("paymentMode") != "free" or offer.get("subscriptionPeriod") != "P1W":
        errors.append("yearly pass must have a seven-day free trial")
    if any(item.get("familyShareable") is not True for item in products + subscriptions):
        errors.append("all products must be family-shareable in local catalog")
    if any("lifetime" in str(item).lower() for item in products + subscriptions):
        errors.append("all-content lifetime product is prohibited")
    commerce_source = (ROOT / "LockAndStudy/Core/Commerce/CommerceModels.swift").read_text(
        encoding="utf-8"
    )
    historical_mappings = {
        "com.ameneko.lockandstudy.pack.english3000.v1": "english3000.v1",
        "com.ameneko.lockandstudy.pack.takken2026.v1": "takken2026.v1",
    }
    for product_id, pack_id in historical_mappings.items():
        if product_id not in commerce_source or pack_id not in commerce_source:
            errors.append(f"historical product mapping disappeared: {product_id} -> {pack_id}")
    return errors


def verify_privacy() -> list[str]:
    errors: list[str] = []
    manifests = [ROOT / "LockAndStudy/Resources/PrivacyInfo.xcprivacy"] + list(ROOT.glob("LockAndStudy*Extension/PrivacyInfo.xcprivacy"))
    if len(manifests) != 4:
        errors.append("privacy manifest missing from a target")
    for path in manifests:
        try:
            value = plistlib.loads(path.read_bytes())
            if value.get("NSPrivacyTracking") is not False or value.get("NSPrivacyCollectedDataTypes") != []:
                errors.append(f"privacy declaration mismatch: {path.relative_to(ROOT)}")
        except Exception as exc:
            errors.append(f"invalid privacy manifest {path.relative_to(ROOT)}: {exc}")
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    match = re.search(r'PRIVACY_POLICY_URL:\s*"([^"]+)"', project)
    if not match or "example." in match.group(1) or not match.group(1).startswith("https://"):
        errors.append("production privacy policy URL is not configured")
    source = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in (ROOT / "LockAndStudy").rglob("*.swift"))
    for forbidden in ("URLSession", "Firebase", "GoogleAnalytics", "AdSupport"):
        if forbidden in source:
            errors.append(f"forbidden external/analytics API in Release source: {forbidden}")
    return errors


def verify_app_icon() -> list[str]:
    errors: list[str] = []
    contents_path = APP_ICON_SET / "Contents.json"
    try:
        contents = load_json(contents_path)
        image_entry = next(
            item for item in contents.get("images", [])
            if item.get("idiom") == "universal" and item.get("platform") == "ios" and item.get("size") == "1024x1024"
        )
    except (CheckFailure, StopIteration) as exc:
        return [f"App Icon catalog is invalid: {exc}"]
    filename = image_entry.get("filename")
    if not filename:
        return ["App Icon 1024x1024 entry has no image filename"]
    image_path = APP_ICON_SET / filename
    if not image_path.is_file():
        return [f"App Icon image is missing: {filename}"]
    data = image_path.read_bytes()
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return [f"App Icon must be a valid PNG: {filename}"]
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    color_type = data[25]
    if (width, height) != (1024, 1024):
        errors.append(f"App Icon must be 1024x1024, found {width}x{height}")
    if color_type in (4, 6) or b"tRNS" in data:
        errors.append("App Icon must not contain an alpha channel")
    if os.environ.get("LOCKANDSTUDY_REQUIRE_FINAL_ICON") == "1" and "placeholder" in filename.lower():
        errors.append("final App Icon required: replace the development placeholder")
    return errors


def check_legacy_identifiers() -> list[str]:
    errors: list[str] = []
    allowed_roots = {"Docs", "LegacyMigrationPatches", "LockAndStudyTests"}
    allowed_files = {Path("LockAndStudy/Core/Migration/LegacyMigrationModels.swift")}
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in {".build", ".git", "LockAndStudy.xcodeproj"} for part in path.parts):
            continue
        relative = path.relative_to(ROOT)
        if relative.parts and relative.parts[0] in allowed_roots or relative in allowed_files:
            continue
        if path.suffix.lower() not in {".swift", ".json", ".plist", ".yml", ".yaml", ".xcstrings", ".md", ""}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore").lower()
        if "eitangolock" in text or "takkenlock" in text:
            errors.append(f"legacy identifier outside allowlist: {relative}")
    return errors


def release_safety() -> list[str]:
    errors: list[str] = []
    production_files = list((ROOT / "LockAndStudy").rglob("*.swift")) + list(ROOT.glob("LockAndStudy*Extension/*.swift"))
    production = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in production_files)
    for forbidden in ("fatalError(", "FIXME", "masterCode", "premiumBypass", "debugPremium"):
        if forbidden.lower() in production.lower():
            errors.append(f"forbidden release pattern: {forbidden}")
    lock_files = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in (ROOT / "LockAndStudy/Core/Lock").glob("*.swift"))
    if "PurchaseView" in lock_files or "purchase(productID" in lock_files:
        errors.append("paywall branch found in Lock Core")
    if "requestAuthorization(for: .individual)" not in production:
        errors.append("Screen Time authorization must use .individual")
    if "scheduleRelock(at: session.endsAt)" not in production:
        errors.append("safe relock-before-unshield implementation missing")
    root_view = (ROOT / "LockAndStudy/App/RootView.swift").read_text(encoding="utf-8")
    sample_route = '-LockAndStudyUITestRouteSampleReport'
    debug_start = root_view.find("#if DEBUG")
    debug_end = root_view.find("#else", debug_start)
    route_index = root_view.find(sample_route)
    if route_index < 0 or debug_start < 0 or debug_end < 0 or not (debug_start < route_index < debug_end):
        errors.append("sample report UI test route must remain DEBUG-only")
    share_source = (ROOT / "LockAndStudy/Core/Reporting/LearningReportShareService.swift").read_text(
        encoding="utf-8"
    )
    share_template = share_source.split("struct LearningReportShareService", 1)[-1]
    for forbidden_key in ("pendingUnlockRequest", "selectionData", "managementCode", "transactionID"):
        if forbidden_key in share_template:
            errors.append(f"private key found in report share template: {forbidden_key}")
    report_ui = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in (ROOT / "LockAndStudy/Features/Reports").glob("*.swift")
    )
    if "PurchaseView" in report_ui or "permitsAccess" in report_ui:
        errors.append("weekly report must not be hidden behind a purchase condition")
    for dead_type in ("PlatformHomeView", "PlatformLibraryView", "PlatformRecordsView"):
        if dead_type in production:
            errors.append(f"dead global platform view remains: {dead_type}")
    monitor_source = (ROOT / "LockAndStudyDeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift").read_text(encoding="utf-8")
    if "RelockRecoveryExecutor().execute" not in monitor_source or "case .rescheduled" not in monitor_source:
        errors.append("extension early-callback guard missing")
    for path in [CATALOG, ROOT / "project.yml", ROOT / "LockAndStudy/Resources/LockAndStudy.storekit"]:
        if not str(path.relative_to(ROOT)).isascii():
            errors.append(f"required path is not ASCII: {path.relative_to(ROOT)}")
    return errors


def report(label: str, errors: list[str]) -> int:
    if errors:
        print(f"{label} failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"{label} passed.")
    return 0
