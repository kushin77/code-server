#!/usr/bin/env python3
# @file        scripts/ci/classify-e2e-flakes.py
# @module      ci/e2e
# @description Classify ephemeral E2E failures using deterministic failure signatures.
#

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ANSI_ESCAPE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


@dataclass(frozen=True)
class MatchDetail:
    name: str
    decision: str
    priority: int
    pattern: str
    snippet: str


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        return ANSI_ESCAPE.sub("", handle.read())


def extract_snippet(text: str, start_index: int, radius: int = 120) -> str:
    start = max(0, start_index - radius)
    end = min(len(text), start_index + radius)
    return " ".join(text[start:end].split())


def classify(log_text: str, signatures: list[dict[str, Any]]) -> tuple[str, list[MatchDetail]]:
    matches: list[MatchDetail] = []

    for signature in sorted(signatures, key=lambda item: int(item.get("priority", 0)), reverse=True):
        name = str(signature["name"])
        decision = str(signature.get("decision", "flake"))
        priority = int(signature.get("priority", 0))
        for pattern in signature.get("patterns", []):
            regex = re.compile(str(pattern), re.IGNORECASE | re.MULTILINE)
            match = regex.search(log_text)
            if match:
                matches.append(
                    MatchDetail(
                        name=name,
                        decision=decision,
                        priority=priority,
                        pattern=str(pattern),
                        snippet=extract_snippet(log_text, match.start()),
                    )
                )
                break

    if any(match.decision == "non_flake" for match in matches):
        return "non_flake", matches

    if any(match.decision == "flake" for match in matches):
        return "flake", matches

    return "unknown", matches


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify E2E failures as flaky or non-flaky")
    parser.add_argument("--log-file", required=True, help="Path to the captured test log")
    parser.add_argument("--signatures-file", required=True, help="Path to the flake signatures JSON SSOT")
    parser.add_argument("--output-file", help="Optional JSON output path")
    args = parser.parse_args()

    log_path = Path(args.log_file)
    signatures_path = Path(args.signatures_file)

    signatures_doc = read_json(signatures_path)
    log_text = read_text(log_path)
    classification, matches = classify(log_text, list(signatures_doc.get("signatures", [])))
    policy = dict(signatures_doc.get("policy", {}))
    rerun_limit = int(policy.get("rerunLimit", 1))

    result = {
        "classification": classification,
        "recommendRerun": classification == "flake" and rerun_limit > 0,
        "logFile": str(log_path),
        "signaturesFile": str(signatures_path),
        "policy": policy,
        "matchedSignatures": [asdict(match) for match in matches],
        "summary": {
            "matchedFlakeCount": sum(1 for match in matches if match.decision == "flake"),
            "matchedNonFlakeCount": sum(1 for match in matches if match.decision == "non_flake"),
            "rerunLimit": rerun_limit,
        },
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }

    output = json.dumps(result, indent=2) + "\n"
    if args.output_file:
        output_path = Path(args.output_file)
        output_path.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())