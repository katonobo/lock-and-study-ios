#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
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
    if not isinstance(value, list):
        raise CheckFailure("study_pack_catalog.json must be an array")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_content() -> list[str]:
    errors: list[str] = []
    packs = catalog()
    ids = [pack.get("id") for pack in packs]
    if len(ids) != len(set(ids)):
        errors.append("duplicate pack ID")
    for pack in packs:
        if pack.get("schemaVersion") != 1:
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
