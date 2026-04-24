#!/usr/bin/env bash
# @file        scripts/ci/validate-epic-ac-overlap.sh
# @module      ci/governance
# @description Validate governance epic acceptance-capability boundaries and detect overlap drift
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

BOUNDARY_FILE="${1:-config/governance-epic-ac-boundaries.json}"
REPORT_FILE="${2:-epic-ac-overlap-report.json}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ci/validate-epic-ac-overlap.sh [boundary-file] [report-file]
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command "python3" "python3 is required"
require_file "$BOUNDARY_FILE"

python3 - "$BOUNDARY_FILE" "$REPORT_FILE" <<'PY'
import json
import sys
from datetime import datetime, timezone

boundary_file = sys.argv[1]
report_file = sys.argv[2]

with open(boundary_file, "r", encoding="utf-8") as f:
    data = json.load(f)

epics = data.get("epics", [])
allowed_shared = set(data.get("policy", {}).get("allow_shared_capabilities", []))

errors = []
warnings = []
owners = {}

for epic in epics:
    issue = epic.get("issue")
    caps = epic.get("capabilities", [])

    if not isinstance(issue, int):
      errors.append("epic issue id must be integer")
      continue
    if not isinstance(caps, list) or not caps:
      errors.append(f"#{issue}: capabilities must be non-empty list")
      continue

    seen_local = set()
    for cap in caps:
      if not isinstance(cap, str) or not cap.strip():
        errors.append(f"#{issue}: capability entries must be non-empty strings")
        continue
      if cap in seen_local:
        errors.append(f"#{issue}: duplicate capability in same epic: {cap}")
        continue
      seen_local.add(cap)
      owners.setdefault(cap, []).append(issue)

for cap, issue_ids in owners.items():
    if len(issue_ids) > 1 and cap not in allowed_shared:
      errors.append(
          f"overlap violation: capability '{cap}' appears in multiple epics {sorted(issue_ids)}"
      )
    if len(issue_ids) > 1 and cap in allowed_shared:
      warnings.append(
          f"shared capability allowed: '{cap}' appears in {sorted(issue_ids)}"
      )

report = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "boundary_file": boundary_file,
    "summary": {
      "epic_count": len(epics),
      "capability_count": len(owners),
      "error_count": len(errors),
      "warning_count": len(warnings),
    },
    "errors": errors,
    "warnings": warnings,
}

with open(report_file, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")

print(f"Epic AC overlap report: {report_file}")
print(f"Errors: {len(errors)}")
print(f"Warnings: {len(warnings)}")

if errors:
    sys.exit(1)
PY
