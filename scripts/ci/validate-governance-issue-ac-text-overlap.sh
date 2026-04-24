#!/usr/bin/env bash
# @file        scripts/ci/validate-governance-issue-ac-text-overlap.sh
# @module      ci/governance
# @description Detect duplicate acceptance-criteria checklist text across governance epics using live issue bodies
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

BOUNDARY_FILE="${1:-config/governance-epic-ac-boundaries.json}"
REPORT_FILE="${2:-governance-issue-ac-text-overlap-report.json}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ci/validate-governance-issue-ac-text-overlap.sh [boundary-file] [report-file]
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command "python3" "python3 is required"
require_command "gh" "GitHub CLI is required"
require_file "$BOUNDARY_FILE"

python3 - "$BOUNDARY_FILE" "$REPORT_FILE" <<'PY'
import json
import re
import subprocess
import sys
from datetime import datetime, timezone

boundary_file = sys.argv[1]
report_file = sys.argv[2]

with open(boundary_file, "r", encoding="utf-8") as f:
    boundary = json.load(f)

epics = boundary.get("epics", [])
allowed_shared_caps = boundary.get("policy", {}).get("allow_shared_capabilities", [])

if not isinstance(epics, list) or not epics:
    print("No epics defined in boundary file", file=sys.stderr)
    sys.exit(1)

def normalize_text(value: str) -> str:
    v = value.lower().strip()
    v = re.sub(r"`[^`]+`", "", v)
    v = re.sub(r"[^a-z0-9 ]+", " ", v)
    v = re.sub(r"\s+", " ", v)
    return v.strip()

def cap_to_tokens(cap: str):
    cap = cap.replace("-", " ").strip().lower()
    tokens = {cap}
    if cap == "rollback execution":
        tokens.add("rollback")
    if cap == "evidence package":
        tokens.add("evidence")
    return tokens

allowed_tokens = set()
for cap in allowed_shared_caps:
    if isinstance(cap, str) and cap.strip():
        allowed_tokens |= cap_to_tokens(cap)

ac_line_re = re.compile(r"^\s*-\s*\[[ xX]\]\s+(.+?)\s*$")
heading_re = re.compile(r"^\s*#{2,6}\s+(.+?)\s*$")

issues = []
errors = []
warnings = []

for epic in epics:
    issue_num = epic.get("issue")
    if not isinstance(issue_num, int):
        errors.append("boundary epic issue must be int")
        continue

    proc = subprocess.run(
        ["gh", "issue", "view", str(issue_num), "--json", "number,title,state,body,url"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        errors.append(f"#{issue_num}: failed to fetch issue body via gh")
        continue

    try:
        issue = json.loads(proc.stdout)
    except json.JSONDecodeError:
        errors.append(f"#{issue_num}: invalid JSON from gh issue view")
        continue

    issues.append(issue)

duplicates = {}

for issue in issues:
    body = issue.get("body") or ""
    lines = body.splitlines()

    in_ac = False
    ac_entries = []

    for line in lines:
        heading = heading_re.match(line)
        if heading:
            heading_name = heading.group(1).strip().lower()
            if "acceptance criteria" in heading_name:
                in_ac = True
                continue
            if in_ac:
                # Any new heading after AC section ends AC parsing
                break

        if not in_ac:
            continue

        m = ac_line_re.match(line)
        if not m:
            continue

        entry = m.group(1).strip()
        if entry:
            ac_entries.append(entry)

    issue["ac_entries"] = ac_entries

    for entry in ac_entries:
        norm = normalize_text(entry)
        if not norm:
            continue
        duplicates.setdefault(norm, []).append(
            {
                "issue": issue.get("number"),
                "state": issue.get("state"),
                "line": entry,
            }
        )

overlap_errors = []
overlap_warnings = []

for norm, entries in sorted(duplicates.items()):
    unique_issue_ids = sorted({e["issue"] for e in entries})
    if len(unique_issue_ids) < 2:
        continue

    allowed = any(token in norm for token in allowed_tokens)
    item = {
        "normalized": norm,
        "issues": entries,
        "issue_ids": unique_issue_ids,
        "allowed_shared": allowed,
    }

    if allowed:
        overlap_warnings.append(item)
    else:
        overlap_errors.append(item)

summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "boundary_file": boundary_file,
    "summary": {
        "issue_count": len(issues),
        "ac_line_count": sum(len(i.get("ac_entries", [])) for i in issues),
        "overlap_error_count": len(overlap_errors),
        "overlap_warning_count": len(overlap_warnings),
    },
    "issues": [
        {
            "number": i.get("number"),
            "state": i.get("state"),
            "title": i.get("title"),
            "url": i.get("url"),
            "ac_entries": i.get("ac_entries", []),
        }
        for i in issues
    ],
    "overlap_errors": overlap_errors,
    "overlap_warnings": overlap_warnings,
    "errors": errors,
    "warnings": warnings,
}

with open(report_file, "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2)
    f.write("\n")

print(f"Governance issue AC text overlap report: {report_file}")
print(f"Overlap errors: {len(overlap_errors)}")
print(f"Overlap warnings: {len(overlap_warnings)}")
print(f"Collection errors: {len(errors)}")

if errors or overlap_errors:
    sys.exit(1)
PY
