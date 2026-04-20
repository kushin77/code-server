#!/usr/bin/env python3
# @file        scripts/ci/validate-docs-governance.py
# @module      ci/documentation
# @description Validate docs metadata and links, and generate duplicate/stale documentation reports.
#

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path


DOCS_ROOT = "docs"
REPORT_JSON = "artifacts/triage/docs-governance-report.json"
REPORT_MD = "artifacts/triage/docs-governance-report.md"
STALE_DAYS = 90

LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
ACTION_ITEM_RE = re.compile(r"^\s*(?:[-*]|\d+\.)\s*\[ \]", re.MULTILINE)
ISSUE_REF_RE = re.compile(r"(?:#\d+|issues/\d+)")


@dataclass
class Violation:
    rule: str
    path: str
    detail: str


def parse_args() -> tuple[Path, Path, Path, int]:
    repo_root = Path.cwd()
    report_json = repo_root / REPORT_JSON
    report_md = repo_root / REPORT_MD
    stale_days = STALE_DAYS

    args = sys.argv[1:]
    index = 0
    while index < len(args):
      arg = args[index]
      if arg == "--repo-root":
          repo_root = Path(args[index + 1]).resolve()
          index += 2
      elif arg == "--json-out":
          report_json = Path(args[index + 1]).resolve()
          index += 2
      elif arg == "--md-out":
          report_md = Path(args[index + 1]).resolve()
          index += 2
      elif arg == "--stale-days":
          stale_days = int(args[index + 1])
          index += 2
      else:
          raise SystemExit(f"Unknown argument: {arg}")

    return repo_root, report_json, report_md, stale_days


def markdown_files(repo_root: Path) -> list[Path]:
    return sorted((repo_root / DOCS_ROOT).rglob("*.md"))


def relative_path(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def file_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def is_deprecated_stub(text: str) -> bool:
    header = "\n".join(text.splitlines()[:12])
    return "DEPRECATED:" in header or "Legacy Bridge:" in header or "pointer-only stub" in header


def is_active_doc(rel_path: str, text: str) -> bool:
    if rel_path.startswith("docs/archives/"):
        return False
    if rel_path.startswith("docs/status/") and rel_path != "docs/status/README.md":
        return False
    if re.match(r"docs/triage/comment-.*\.md$", rel_path):
        return False
    if is_deprecated_stub(text):
        return False
    return True


def requires_issue_links(rel_path: str, text: str) -> bool:
    if not is_active_doc(rel_path, text):
        return False
    if rel_path.startswith("docs/adr/"):
        return False
    return True


def check_metadata(repo_root: Path, path: Path, text: str) -> list[Violation]:
    rel_path = relative_path(repo_root, path)
    if not is_active_doc(rel_path, text):
        return []

    violations: list[Violation] = []
    non_empty_lines = [line for line in text.splitlines()[:25] if line.strip()]
    if not non_empty_lines or not non_empty_lines[0].startswith("# "):
        violations.append(Violation("metadata-title", rel_path, "Missing H1 title at top of document"))

    joined = "\n".join(non_empty_lines)
    if not re.search(r"^(?:\*\*Purpose\*\*|Purpose:|## Scope|## Summary)" , joined, re.MULTILINE):
        violations.append(Violation("metadata-purpose", rel_path, "Missing Purpose metadata near top of document"))

    return violations


def check_issue_links(repo_root: Path, path: Path, text: str) -> list[Violation]:
    rel_path = relative_path(repo_root, path)
    if not requires_issue_links(rel_path, text):
        return []

    if ACTION_ITEM_RE.search(text) and not ISSUE_REF_RE.search(text):
        return [Violation("issue-link", rel_path, "Unchecked action items require at least one issue reference in the file")]
    return []


def resolve_link_target(path: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if not target or target.startswith(("http://", "https://", "mailto:", "#")):
        return None

    clean_target = target.split("#", 1)[0]
    return (path.parent / clean_target).resolve()


def check_links(repo_root: Path, path: Path, text: str) -> list[Violation]:
    rel_path = relative_path(repo_root, path)
    if not is_active_doc(rel_path, text):
        return []
    violations: list[Violation] = []

    for match in LINK_RE.finditer(text):
        raw_target = match.group(1)
        resolved = resolve_link_target(path, raw_target)
        if resolved is None:
            continue

        if not resolved.exists():
            violations.append(
                Violation("broken-link", rel_path, f"Missing local link target: {raw_target}")
            )

    return violations


def last_commit_date(repo_root: Path, path: Path) -> datetime | None:
    rel_path = relative_path(repo_root, path)
    result = subprocess.run(
        ["git", "log", "-1", "--format=%cI", "--", rel_path],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def build_duplicate_report(repo_root: Path, docs: list[Path]) -> list[dict[str, object]]:
    buckets: dict[str, list[str]] = {}
    for path in docs:
        rel_path = relative_path(repo_root, path)
        text = file_text(path)
        if not is_active_doc(rel_path, text):
            continue
        name = path.name.lower()
        if name == "readme.md":
            continue
        normalized = re.sub(r"[^a-z0-9]+", "", name)
        buckets.setdefault(normalized, []).append(rel_path)

    report: list[dict[str, object]] = []
    for key, paths in sorted(buckets.items()):
        if len(paths) > 1:
            report.append({"normalizedName": key, "paths": paths})
    return report


def build_stale_report(repo_root: Path, docs: list[Path], stale_days: int) -> list[dict[str, object]]:
    now = datetime.now(UTC)
    report: list[dict[str, object]] = []
    for path in docs:
        rel_path = relative_path(repo_root, path)
        text = file_text(path)
        if not is_active_doc(rel_path, text):
            continue
        committed_at = last_commit_date(repo_root, path)
        if committed_at is None:
            continue
        age_days = (now - committed_at.astimezone(UTC)).days
        if age_days >= stale_days:
            report.append({"path": rel_path, "ageDays": age_days, "lastCommit": committed_at.date().isoformat()})
    return sorted(report, key=lambda item: int(item["ageDays"]), reverse=True)


def write_reports(report_json: Path, report_md: Path, payload: dict[str, object]) -> None:
    report_json.parent.mkdir(parents=True, exist_ok=True)
    report_md.parent.mkdir(parents=True, exist_ok=True)

    report_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    violations: list[dict[str, str]] = payload["violations"]  # type: ignore[assignment]
    duplicates: list[dict[str, object]] = payload["duplicateCandidates"]  # type: ignore[assignment]
    stale_docs: list[dict[str, object]] = payload["staleDocs"]  # type: ignore[assignment]

    lines = [
        "# Documentation Governance Report",
        "",
        f"Generated at (UTC): {payload['generatedAtUtc']}",
        f"Docs scanned: {payload['docsScanned']}",
        f"Blocking violations: {len(violations)}",
        f"Duplicate candidates: {len(duplicates)}",
        f"Stale docs: {len(stale_docs)}",
        "",
    ]

    if violations:
        lines.extend(["## Blocking violations", ""])
        for violation in violations:
            lines.append(f"- [{violation['rule']}] {violation['path']} — {violation['detail']}")
        lines.append("")

    if duplicates:
        lines.extend(["## Duplicate candidates", ""])
        for item in duplicates:
            joined = ", ".join(item["paths"])
            lines.append(f"- {joined}")
        lines.append("")

    if stale_docs:
        lines.extend(["## Stale docs", ""])
        for item in stale_docs[:25]:
            lines.append(f"- {item['path']} — {item['ageDays']} days since last commit ({item['lastCommit']})")
        lines.append("")

    lines.append(f"Machine-readable artifact: {report_json.as_posix()}")
    report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    repo_root, report_json, report_md, stale_days = parse_args()
    docs = markdown_files(repo_root)
    violations: list[Violation] = []

    for path in docs:
        text = file_text(path)
        violations.extend(check_metadata(repo_root, path, text))
        violations.extend(check_links(repo_root, path, text))
        violations.extend(check_issue_links(repo_root, path, text))

    duplicate_candidates = build_duplicate_report(repo_root, docs)
    stale_docs = build_stale_report(repo_root, docs, stale_days)

    payload = {
        "generatedAtUtc": datetime.now(UTC).isoformat(),
        "docsScanned": len(docs),
        "violations": [violation.__dict__ for violation in violations],
        "duplicateCandidates": duplicate_candidates,
        "staleDocs": stale_docs,
        "staleThresholdDays": stale_days,
    }

    write_reports(report_json, report_md, payload)

    for violation in violations:
        print(f"[{violation.rule}] {violation.path}: {violation.detail}", file=sys.stderr)

    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())