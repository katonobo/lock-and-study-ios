#!/usr/bin/env python3
"""Human-review workflow for Takken concept boundaries (v18).

Generated files are inputs only. Reviewed files are written only by the
explicit batch importer after all batches and all 1,000 legacy IDs pass.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from copy import deepcopy
from pathlib import Path

sys.dont_write_bytecode = True

from content_checks import _has_traceable_source_note, _parsed_review_date
from takken_concepts import (
    ALLOWED_REVIEW_DECISIONS,
    BACKUP_ROOT,
    BOUNDARY_AUDIT_JSON_PATH,
    BOUNDARY_AUDIT_MARKDOWN_PATH,
    BOUNDARY_DECISIONS_PATH,
    MASTER_PATH,
    REVIEW_BATCH_ROOT,
    REVIEWED_MASTER_PATH,
    _cluster_similarity,
    load_json,
    load_legacy_records,
    normalized,
    validate_concept_master,
    write_json,
    write_json_new,
    write_text_atomic,
)


DEFAULT_BATCH_SIZE = 50
KNOWN_GOLDEN_DUPLICATE_CANDIDATES = (
    ("tl_gyoho_takkenshi_006", "tl_gyoho_37_003"),
    ("tl_gyoho_35_027", "tl_gyoho_37_002"),
    ("tl_gyoho_35_001", "tl_gyoho_35_002"),
)


def document_digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()


def export_review_batch(
    batch_number: int,
    *,
    source_master_path: Path = MASTER_PATH,
    output_root: Path = REVIEW_BATCH_ROOT,
    batch_size: int = DEFAULT_BATCH_SIZE,
) -> Path:
    master = load_json(source_master_path)
    concepts = sorted(master["concepts"], key=lambda value: value["conceptID"])
    batch_count = (len(concepts) + batch_size - 1) // batch_size
    if not 1 <= batch_number <= batch_count:
        raise ValueError(f"batch number must be 1-{batch_count}")
    start = (batch_number - 1) * batch_size
    selected = deepcopy(concepts[start : start + batch_size])
    source_legacy_ids = sorted(
        legacy_id
        for concept in selected
        for legacy_id in concept["legacySourceIDs"]
    )
    document = {
        "schemaVersion": 2,
        "workflowVersion": 18,
        "status": "awaiting_human_review",
        "batchID": f"takken-2026-concepts-{batch_number:02d}",
        "batchNumber": batch_number,
        "batchCount": batch_count,
        "sourceMasterDigest": document_digest(master),
        "sourceConceptIDs": [value["conceptID"] for value in selected],
        "sourceLegacyQuestionIDs": source_legacy_ids,
        "transferredLegacyQuestionIDsIn": [],
        "transferredLegacyQuestionIDsOut": [],
        "reviewInstructions": {
            "allowedDecisions": sorted(ALLOWED_REVIEW_DECISIONS),
            "allLegacyIDsMustRemainOwnedExactlyOnce": True,
            "traceableSourcesRequired": True,
            "automaticReviewPromotionForbidden": True,
        },
        "concepts": selected,
    }
    output = (
        output_root
        / f"takken_2026_concept_review_batch_{batch_number:02d}.json"
    )
    write_json_new(output, document)
    return output


def validate_review_batch(document: dict) -> list[str]:
    errors: list[str] = []
    batch_id = document.get("batchID", "<unknown>")
    source_legacy_ids = document.get("sourceLegacyQuestionIDs")
    transferred_in = document.get("transferredLegacyQuestionIDsIn") or []
    transferred_out = document.get("transferredLegacyQuestionIDsOut") or []
    concepts = document.get("concepts")
    if not isinstance(source_legacy_ids, list) or not source_legacy_ids:
        return [f"{batch_id}: sourceLegacyQuestionIDs must be a nonempty array"]
    if len(source_legacy_ids) != len(set(source_legacy_ids)):
        errors.append(f"{batch_id}: source legacy IDs must be unique")
    if (
        not isinstance(transferred_in, list)
        or not isinstance(transferred_out, list)
        or len(transferred_in) != len(set(transferred_in))
        or len(transferred_out) != len(set(transferred_out))
    ):
        errors.append(f"{batch_id}: transfer lists must be unique arrays")
        transferred_in = []
        transferred_out = []
    if not set(transferred_out).issubset(set(source_legacy_ids)):
        errors.append(f"{batch_id}: transferred-out IDs must belong to this batch")
    if set(transferred_in) & set(source_legacy_ids):
        errors.append(f"{batch_id}: transferred-in IDs already belong to this batch")
    if not isinstance(concepts, list) or not concepts:
        return errors + [f"{batch_id}: concepts must be a nonempty array"]
    concept_ids = [value.get("conceptID") for value in concepts]
    if len(concept_ids) != len(set(concept_ids)):
        errors.append(f"{batch_id}: conceptID must be unique within the batch")
    owners: dict[str, str] = {}
    for concept in concepts:
        concept_id = concept.get("conceptID", "<unknown>")
        decision = concept.get("reviewDecision")
        if decision not in ALLOWED_REVIEW_DECISIONS:
            errors.append(f"{concept_id}: reviewDecision is required")
        if concept.get("reviewStatus") not in {"reviewed", "release"}:
            errors.append(f"{concept_id}: human-reviewed status is required")
        notes = concept.get("sourceNotes") or []
        if not notes or not all(_has_traceable_source_note(value) for value in notes):
            errors.append(f"{concept_id}: traceable sourceNotes are required")
        if not concept.get("reviewer") or _parsed_review_date(
            concept.get("reviewedAt")
        ) is None:
            errors.append(f"{concept_id}: reviewer and real reviewedAt are required")
        if len(normalized(concept.get("reviewNote"))) < 12:
            errors.append(f"{concept_id}: concrete reviewNote is required")
        if not isinstance(concept.get("requiresAnnualReview"), bool) or len(
            normalized(concept.get("annualReviewReason"))
        ) < 8:
            errors.append(
                f"{concept_id}: annual review decision and reason are required"
            )
        merged = concept.get("mergedFromConceptIDs") or []
        split_from = concept.get("splitFromConceptID")
        if decision == "merge" and len(merged) < 2:
            errors.append(f"{concept_id}: merge requires 2+ mergedFromConceptIDs")
        if decision == "split" and not split_from:
            errors.append(f"{concept_id}: split requires splitFromConceptID")
        legacy_ids = concept.get("legacySourceIDs") or []
        if not legacy_ids:
            errors.append(f"{concept_id}: legacySourceIDs must not be empty")
        for legacy_id in legacy_ids:
            if legacy_id in owners:
                errors.append(
                    f"{legacy_id}: owned by both {owners[legacy_id]} and {concept_id}"
                )
            owners[legacy_id] = concept_id
    expected_legacy_ids = (
        set(source_legacy_ids) - set(transferred_out)
    ) | set(transferred_in)
    if set(owners) != expected_legacy_ids:
        missing = sorted(expected_legacy_ids - set(owners))
        extra = sorted(set(owners) - expected_legacy_ids)
        errors.append(
            f"{batch_id}: edited concepts must own source legacy IDs exactly once "
            f"(missing={missing[:5]}, extra={extra[:5]})"
        )
    return errors


def import_review_batches(
    directory: Path,
    *,
    source_master_path: Path = MASTER_PATH,
    output_path: Path = REVIEWED_MASTER_PATH,
) -> tuple[Path, bool]:
    paths = sorted(directory.glob("takken_2026_concept_review_batch_*.json"))
    if not paths:
        raise ValueError(f"no concept review batches found: {directory}")
    documents = [load_json(path) for path in paths]
    batch_ids = [value.get("batchID") for value in documents]
    batch_numbers = [value.get("batchNumber") for value in documents]
    if len(batch_ids) != len(set(batch_ids)) or len(batch_numbers) != len(
        set(batch_numbers)
    ):
        raise ValueError("duplicate batchID or batchNumber")
    batch_counts = {value.get("batchCount") for value in documents}
    if len(batch_counts) != 1 or next(iter(batch_counts)) != len(documents):
        raise ValueError("all review batches must be present exactly once")
    batch_errors = [
        error for document in documents for error in validate_review_batch(document)
    ]
    if batch_errors:
        raise ValueError("; ".join(batch_errors[:30]))
    transferred_in = [
        legacy_id
        for document in documents
        for legacy_id in document.get("transferredLegacyQuestionIDsIn") or []
    ]
    transferred_out = [
        legacy_id
        for document in documents
        for legacy_id in document.get("transferredLegacyQuestionIDsOut") or []
    ]
    if Counter(transferred_in) != Counter(transferred_out):
        raise ValueError("cross-batch transfers must have matching in/out entries")

    source_master = load_json(source_master_path)
    known_records = load_legacy_records()
    known_legacy_ids = {value["question"]["id"] for value in known_records}
    source_digests = {value.get("sourceMasterDigest") for value in documents}
    if source_digests != {document_digest(source_master)}:
        raise ValueError("review batches do not share the current source master digest")

    source_batch_legacy_ids = [
        legacy_id
        for document in documents
        for legacy_id in document["sourceLegacyQuestionIDs"]
    ]
    if (
        len(source_batch_legacy_ids) != len(set(source_batch_legacy_ids))
        or set(source_batch_legacy_ids) != known_legacy_ids
    ):
        raise ValueError("batches must partition all 1,000 legacy IDs exactly once")

    concepts = [
        deepcopy(concept)
        for document in documents
        for concept in document["concepts"]
    ]
    concept_ids = {value["conceptID"] for value in concepts}
    for concept in concepts:
        concept["relatedConceptIDs"] = sorted(
            value
            for value in concept.get("relatedConceptIDs") or []
            if value in concept_ids and value != concept["conceptID"]
        )
    reviewed_master = deepcopy(source_master)
    reviewed_master.update(
        status="reviewed",
        targetConceptCount=len(concepts),
        sourceGeneratedMasterDigest=document_digest(source_master),
        importedBatchIDs=sorted(batch_ids),
        concepts=sorted(concepts, key=lambda value: value["conceptID"]),
    )
    errors = validate_concept_master(reviewed_master, known_legacy_ids)
    if errors:
        raise ValueError("; ".join(errors[:40]))

    if output_path.exists():
        existing = load_json(output_path)
        if document_digest(existing) == document_digest(reviewed_master):
            return output_path, False
        backup = (
            BACKUP_ROOT
            / f"{output_path.stem}.{document_digest(existing)[:16]}.json"
        )
        if not backup.exists():
            write_json(backup, existing)
    write_json(output_path, reviewed_master)
    return output_path, True


def _legacy_owner(master: dict) -> dict[str, str]:
    return {
        legacy_id: concept["conceptID"]
        for concept in master["concepts"]
        for legacy_id in concept["legacySourceIDs"]
    }


def _warning(
    warning_type: str,
    concept_ids: list[str],
    legacy_ids: list[str],
    message: str,
    *,
    score: float | None = None,
) -> dict:
    identity = "|".join(
        [warning_type, *sorted(concept_ids), *sorted(legacy_ids), message]
    )
    return {
        "warningID": f"boundary.{hashlib.sha256(identity.encode()).hexdigest()[:16]}",
        "type": warning_type,
        "conceptIDs": sorted(concept_ids),
        "legacyQuestionIDs": sorted(legacy_ids),
        "score": None if score is None else round(score, 4),
        "message": message,
        "automaticDecision": None,
    }


def build_boundary_audit(master: dict) -> dict:
    warnings: list[dict] = []
    concepts = master["concepts"]
    owner = _legacy_owner(master)
    records = {
        value["question"]["id"]: value for value in load_legacy_records()
    }

    for field, warning_type in (
        ("canonicalRule", "exact_canonical_rule"),
        ("title", "exact_title"),
    ):
        groups: dict[str, list[dict]] = defaultdict(list)
        for concept in concepts:
            groups[normalized(concept.get(field))].append(concept)
        for key, values in groups.items():
            if key and len(values) > 1:
                warnings.append(
                    _warning(
                        warning_type,
                        [value["conceptID"] for value in values],
                        [
                            legacy_id
                            for value in values
                            for legacy_id in value["legacySourceIDs"]
                        ],
                        f"normalized {field} is identical",
                    )
                )

    preview_groups: dict[str, list[dict]] = defaultdict(list)
    for concept in concepts:
        preview_groups[normalized((concept.get("preview") or {}).get("rule"))].append(
            concept
        )
        slash_count = str(concept.get("title") or "").count("／")
        if slash_count >= 1:
            warnings.append(
                _warning(
                    "multi_rule_title",
                    [concept["conceptID"]],
                    concept["legacySourceIDs"],
                    f"title contains {slash_count} rule separator(s)",
                )
            )
        record_values = [records[value] for value in concept["legacySourceIDs"]]
        if len(record_values) >= 2:
            pair_scores = [
                _cluster_similarity([record_values[left]], [record_values[right]])
                for left in range(len(record_values))
                for right in range(left + 1, len(record_values))
            ]
            minimum = min(pair_scores)
            if minimum < 0.08:
                warnings.append(
                    _warning(
                        "low_cluster_similarity",
                        [concept["conceptID"]],
                        concept["legacySourceIDs"],
                        "cluster contains a low-similarity legacy pair",
                        score=minimum,
                    )
                )
        if len(concept.get("learningObjectives") or []) >= 3:
            warnings.append(
                _warning(
                    "three_or_more_rules",
                    [concept["conceptID"]],
                    concept["legacySourceIDs"],
                    "concept may contain three or more independent rules",
                )
            )
    for key, values in preview_groups.items():
        if key and len(values) > 1:
            warnings.append(
                _warning(
                    "normalized_keypoint_match",
                    [value["conceptID"] for value in values],
                    [
                        legacy_id
                        for value in values
                        for legacy_id in value["legacySourceIDs"]
                    ],
                    "normalized preview rule/keyPoint is identical",
                )
            )

    by_subcategory: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for concept in concepts:
        by_subcategory[(concept["category"], concept["subCategory"])].append(
            concept
        )
    for values in by_subcategory.values():
        for left_index, left in enumerate(values):
            left_records = [records[value] for value in left["legacySourceIDs"]]
            for right in values[left_index + 1 :]:
                right_records = [
                    records[value] for value in right["legacySourceIDs"]
                ]
                score = _cluster_similarity(left_records, right_records)
                if score >= 0.72:
                    warnings.append(
                        _warning(
                            "high_prompt_similarity",
                            [left["conceptID"], right["conceptID"]],
                            left["legacySourceIDs"] + right["legacySourceIDs"],
                            "separate concepts have high semantic prompt similarity",
                            score=score,
                        )
                    )

    article_owners: dict[str, list[dict]] = defaultdict(list)
    for concept in concepts:
        articles = set(
            re.findall(
                r"(?:法|令|規則|条例)第[〇零一二三四五六七八九十百千万\d]+条",
                " ".join(str(value) for value in concept.get("sourceNotes") or []),
            )
        )
        for article in articles:
            article_owners[article].append(concept)
        if len(articles) > 1:
            warnings.append(
                _warning(
                    "multiple_unrelated_articles",
                    [concept["conceptID"]],
                    concept["legacySourceIDs"],
                    f"one concept cites multiple articles: {', '.join(sorted(articles))}",
                )
            )
    for article, values in article_owners.items():
        if len(values) > 1:
            warnings.append(
                _warning(
                    "same_article_across_concepts",
                    [value["conceptID"] for value in values],
                    [
                        legacy_id
                        for value in values
                        for legacy_id in value["legacySourceIDs"]
                    ],
                    f"multiple concepts cite {article}",
                )
            )

    for left, right in KNOWN_GOLDEN_DUPLICATE_CANDIDATES:
        warnings.append(
            _warning(
                "known_semantic_duplicate_candidate",
                sorted({owner[left], owner[right]}),
                [left, right],
                "known Golden pair requires an explicit accept/merge decision",
            )
        )

    warnings = sorted(
        {value["warningID"]: value for value in warnings}.values(),
        key=lambda value: (value["type"], value["warningID"]),
    )
    return {
        "schemaVersion": 1,
        "workflowVersion": 18,
        "sourceMasterDigest": document_digest(master),
        "warningCount": len(warnings),
        "warningTypeDistribution": dict(
            sorted(Counter(value["type"] for value in warnings).items())
        ),
        "automaticMergeSplitForbidden": True,
        "warnings": warnings,
    }


def boundary_audit_markdown(audit: dict) -> str:
    lines = [
        "# 宅建Concept Boundary Audit v18",
        "",
        f"- Warning: {audit['warningCount']}件",
        "- Warningは自動merge / splitを行わない。",
        "",
        "| type | count |",
        "|---|---:|",
    ]
    lines.extend(
        f"| `{warning_type}` | {count} |"
        for warning_type, count in audit["warningTypeDistribution"].items()
    )
    lines.extend(["", "## Review candidates", ""])
    lines.extend(
        f"- `{value['warningID']}` {value['type']}: "
        f"{', '.join(value['conceptIDs'])} — {value['message']}"
        for value in audit["warnings"]
    )
    return "\n".join(lines) + "\n"


def write_boundary_audit(master_path: Path = MASTER_PATH) -> tuple[dict, bool]:
    master = load_json(master_path)
    audit = build_boundary_audit(master)
    write_json(BOUNDARY_AUDIT_JSON_PATH, audit)
    write_text_atomic(BOUNDARY_AUDIT_MARKDOWN_PATH, boundary_audit_markdown(audit))
    template = {
        "schemaVersion": 1,
        "workflowVersion": 18,
        "sourceAuditDigest": document_digest(audit),
        "status": "awaiting_human_decisions",
        "decisions": [
            {
                "warningID": value["warningID"],
                "decision": None,
                "targetConceptIDs": value["conceptIDs"],
                "reviewer": None,
                "reviewedAt": None,
                "note": None,
            }
            for value in audit["warnings"]
        ],
    }
    created = False
    if not BOUNDARY_DECISIONS_PATH.exists():
        write_json_new(BOUNDARY_DECISIONS_PATH, template)
        created = True
    return audit, created
