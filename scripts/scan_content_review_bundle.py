#!/usr/bin/env python3
"""Verify candidate resources are absent/present in an already-built .app bundle."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

QUESTION_NAME = "takken_2026_questions_v26_candidate.json"
FREE_NAME = "takken_2026_free_sample_100_v26_candidate.json"
QUESTION_SHA = "af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263"
FREE_SHA = "52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("production", "review"))
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    if not args.bundle.is_dir():
        parser.error(f"app bundle does not exist: {args.bundle}")

    found = {
        path.name: path
        for path in args.bundle.rglob("*.json")
        if path.name in {QUESTION_NAME, FREE_NAME}
    }
    if args.mode == "production":
        if found:
            print(f"FAILED: Production bundle contains candidate files: {sorted(found)}")
            return 1
        print("PASS: Production bundle candidate file count=0")
        return 0

    expected = {QUESTION_NAME: QUESTION_SHA, FREE_NAME: FREE_SHA}
    if set(found) != set(expected):
        print(f"FAILED: Review bundle candidate file set differs: {sorted(found)}")
        return 1
    for name, digest in expected.items():
        if sha256(found[name]) != digest:
            print(f"FAILED: Review bundle candidate SHA mismatch: {name}")
            return 1
    print("PASS: Review bundle contains both candidate files at exact SHA")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
