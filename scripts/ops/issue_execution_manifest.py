#!/usr/bin/env python3
# @file        scripts/ops/issue_execution_manifest.py
# @module      ops/governance
# @description Validate and render the canonical autonomous issue execution manifest.
#

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


VALID_CLASS = {"program", "epic", "gate", "implementation", "tracker", "unblock"}
VALID_PRIORITY = {"P0", "P1", "P2", "P3", "Persistent"}
VALID_STATUS = {"open", "partial", "closed", "persistent"}
VALID_BRANCH_TYPE = {"feat", "fix", "docs", "refactor", "ci", "ops", "chore"}
VALID_CLOSE_POLICY = {"standard", "children-only", "never"}
PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "Persistent": 4}


def default_manifest_path() -> Path:
    return Path(__file__).resolve().parents[2] / "config/issues/agent-execution-manifest.json"


def load_manifest(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def issues_by_number(manifest: dict) -> dict[int, dict]:
    return {issue["number"]: issue for issue in manifest["issues"]}


def validate_manifest(manifest: dict) -> list[str]:
    errors: list[str] = []
    if not isinstance(manifest, dict):
        return ["Manifest root must be a JSON object"]

    for key in ("version", "generatedAt", "sourceDocuments", "issues"):
        if key not in manifest:
            errors.append(f"Missing top-level key: {key}")

    issues = manifest.get("issues", [])
    if not isinstance(issues, list) or not issues:
        errors.append("Top-level issues must be a non-empty array")
        return errors

    seen_numbers: set[int] = set()
    issue_map: dict[int, dict] = {}
    for index, issue in enumerate(issues):
        label = f"issues[{index}]"
        if not isinstance(issue, dict):
            errors.append(f"{label} must be an object")
            continue

        for field in ("number", "title", "class", "lane", "priority", "status", "branchType", "closePolicy", "dependencies", "executionBrief", "evidence"):
            if field not in issue:
                errors.append(f"{label} missing required field: {field}")

        if "number" not in issue:
            continue

        number = issue["number"]
        if not isinstance(number, int):
            errors.append(f"{label}.number must be an integer")
            continue
        if number in seen_numbers:
            errors.append(f"Duplicate issue number: {number}")
        seen_numbers.add(number)
        issue_map[number] = issue

        title = issue.get("title")
        if not isinstance(title, str) or not title.strip():
            errors.append(f"Issue #{number}: title must be a non-empty string")

        issue_class = issue.get("class")
        if issue_class not in VALID_CLASS:
            errors.append(f"Issue #{number}: invalid class {issue_class!r}")

        lane = issue.get("lane")
        if not isinstance(lane, str) or not lane.strip():
            errors.append(f"Issue #{number}: lane must be a non-empty string")

        priority = issue.get("priority")
        if priority not in VALID_PRIORITY:
            errors.append(f"Issue #{number}: invalid priority {priority!r}")

        status = issue.get("status")
        if status not in VALID_STATUS:
            errors.append(f"Issue #{number}: invalid status {status!r}")

        branch_type = issue.get("branchType")
        if branch_type not in VALID_BRANCH_TYPE:
            errors.append(f"Issue #{number}: invalid branchType {branch_type!r}")

        close_policy = issue.get("closePolicy")
        if close_policy not in VALID_CLOSE_POLICY:
            errors.append(f"Issue #{number}: invalid closePolicy {close_policy!r}")

        dependencies = issue.get("dependencies")
        if not isinstance(dependencies, list) or any(not isinstance(item, int) for item in dependencies):
            errors.append(f"Issue #{number}: dependencies must be an array of integers")

        if not isinstance(issue.get("executionBrief"), str) or not issue["executionBrief"].strip():
            errors.append(f"Issue #{number}: executionBrief must be a non-empty string")

        evidence = issue.get("evidence")
        if not isinstance(evidence, list) or not evidence or any(not isinstance(item, str) or not item.strip() for item in evidence):
            errors.append(f"Issue #{number}: evidence must be a non-empty array of strings")

        for field in ("remainingGaps",):
            if field in issue:
                value = issue[field]
                if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
                    errors.append(f"Issue #{number}: {field} must be an array of non-empty strings")

    for number, issue in issue_map.items():
        for dependency in issue.get("dependencies", []):
            if dependency not in issue_map:
                errors.append(f"Issue #{number}: unknown dependency #{dependency}")
            elif dependency == number:
                errors.append(f"Issue #{number}: issue cannot depend on itself")

        if issue.get("closePolicy") == "never" and issue.get("status") != "persistent":
            errors.append(f"Issue #{number}: closePolicy 'never' requires status 'persistent'")

    return errors


def get_issue(manifest: dict, number: int) -> dict:
    issue_map = issues_by_number(manifest)
    if number not in issue_map:
        raise KeyError(f"Issue #{number} not found in manifest")
    return issue_map[number]


def unresolved_dependencies(issue: dict, issue_map: dict[int, dict]) -> list[int]:
    unresolved: list[int] = []
    for dependency in issue.get("dependencies", []):
        status = issue_map[dependency]["status"]
        if status not in {"closed", "persistent"}:
            unresolved.append(dependency)
    return unresolved


def render_comment(issue: dict, manifest: dict) -> str:
    issue_map = issues_by_number(manifest)
    dependency_text = ", ".join(f"#{item}" for item in issue["dependencies"]) or "none"
    lines = [
        "Canonical autonomous execution brief:",
        "",
        f"Issue: #{issue['number']} {issue['title']}",
        f"Priority: {issue['priority']}",
        f"Class: {issue['class']}",
        f"Lane: {issue['lane']}",
        f"Status: {issue['status']}",
        f"Recommended branch type: {issue['branchType']}",
        f"Close policy: {issue['closePolicy']}",
        f"Dependencies: {dependency_text}",
        "",
        f"Primary objective: {issue['executionBrief']}",
    ]

    remaining_gaps = issue.get("remainingGaps", [])
    if remaining_gaps:
        lines.extend(["", "Remaining gaps:"])
        lines.extend(f"- {gap}" for gap in remaining_gaps)

    lines.extend(["", "Required evidence:"])
    lines.extend(f"- {item}" for item in issue["evidence"])

    unresolved = unresolved_dependencies(issue, issue_map)
    if unresolved:
        lines.extend(["", "Execution note:", f"- Unresolved dependencies still open: {', '.join(f'#{item}' for item in unresolved)}"])

    lines.extend(
        [
            "",
            "Execution rules:",
            "- Reproduce or validate the current state before changing behavior.",
            "- Implement the smallest immutable, idempotent change in canonical files only.",
            "- Add or adjust regression coverage and keep rollout and rollback steps explicit.",
            "- Open the PR with Fixes #N for implementation issues or Relates to #N for epic, gate, and program issues.",
            "- Post validation commands and evidence back to the issue before releasing the claim."
        ]
    )
    return "\n".join(lines)


def command_validate(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    errors = validate_manifest(manifest)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Manifest valid: {len(manifest['issues'])} issues indexed from {args.manifest}")
    return 0


def command_get(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    issue = get_issue(manifest, args.number)
    value = issue.get(args.field)
    if value is None:
        return 1
    if isinstance(value, (list, dict)):
        print(json.dumps(value))
    else:
        print(value)
    return 0


def command_comment(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    issue = get_issue(manifest, args.number)
    print(render_comment(issue, manifest))
    return 0


def command_queue(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    errors = validate_manifest(manifest)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    issue_map = issues_by_number(manifest)
    issues = sorted(
        manifest["issues"],
        key=lambda item: (PRIORITY_ORDER[item["priority"]], item["number"]),
    )
    for issue in issues:
        if issue["status"] not in {"open", "partial"}:
            continue
        unresolved = unresolved_dependencies(issue, issue_map)
        unresolved_text = ",".join(f"#{item}" for item in unresolved) if unresolved else "ready"
        print(f"{issue['number']}\t{issue['priority']}\t{issue['status']}\t{unresolved_text}\t{issue['title']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=default_manifest_path(),
        help="Path to the issue execution manifest JSON file",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="Validate the manifest")
    validate_parser.set_defaults(func=command_validate)

    get_parser = subparsers.add_parser("get", help="Fetch a single field for an issue")
    get_parser.add_argument("--number", type=int, required=True, help="Issue number")
    get_parser.add_argument("--field", required=True, help="Issue field to print")
    get_parser.set_defaults(func=command_get)

    comment_parser = subparsers.add_parser("comment", help="Render the autonomous issue comment body")
    comment_parser.add_argument("--number", type=int, required=True, help="Issue number")
    comment_parser.set_defaults(func=command_comment)

    queue_parser = subparsers.add_parser("queue", help="Print the current actionable issue queue")
    queue_parser.set_defaults(func=command_queue)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())