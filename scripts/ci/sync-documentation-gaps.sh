#!/usr/bin/env bash
# @file        scripts/ci/sync-documentation-gaps.sh
# @module      ci/documentation
# @description Sync documentation audit gaps into issue-tracking evidence.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ARTIFACT_JSON="$REPO_ROOT/artifacts/documentation-gap-issues.json"
ISSUE_TRACKER="$REPO_ROOT/docs/status/ISSUE-TRACKER-APRIL-19-2026.md"
MODE="check"

if [[ "${1:-}" == "--sync" ]]; then
  MODE="sync"
elif [[ "${1:-}" == "--check-only" || -z "${1:-}" ]]; then
  MODE="check"
else
  log_fatal "Usage: $0 [--check-only|--sync]"
fi

python3 - "$ARTIFACT_JSON" "$ISSUE_TRACKER" "$MODE" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

artifact_path = Path(sys.argv[1])
tracker_path = Path(sys.argv[2])
mode = sys.argv[3]

if not artifact_path.exists():
    raise SystemExit(f"Missing docs gap artifact: {artifact_path}")

data = json.loads(artifact_path.read_text(encoding="utf-8"))
issues = data.get("issues", [])
repo = os.environ.get("GITHUB_REPOSITORY", "kushin77/code-server")

if not isinstance(issues, list) or not issues:
    raise SystemExit("Documentation gap artifact does not contain any issues")

for issue in issues:
    if not isinstance(issue, dict):
        raise SystemExit("Documentation gap artifact contains an invalid issue entry")
    if not issue.get("title") or not issue.get("fingerprint"):
        raise SystemExit("Documentation gap artifact entries must include title and fingerprint")

if mode == "sync":
    for issue in issues:
        title = issue.get("title", "")
        fingerprint = issue.get("fingerprint", "")
        subprocess.run([
            "gh", "issue", "create",
            "--repo", repo,
            "--title", title,
            "--body", issue.get("body", "Documentation gap detected."),
        ], check=True)

print(f"Documentation gap artifact is valid for {len(issues)} issue(s).")
PY

log_success "Documentation gap sync check completed"