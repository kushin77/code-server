#!/usr/bin/env bash
# @file        scripts/ci/validate-test-matrix.sh
# @module      ci/governance
# @description validate the living test matrix SSOT and required PR test additions
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATRIX_FILE="$REPO_ROOT/docs/TEST-MATRIX.md"

if [[ ! -f "$MATRIX_FILE" ]]; then
  log_fatal "Missing test matrix SSOT: $MATRIX_FILE"
fi

export MATRIX_FILE

python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path


def run_git(args):
    return subprocess.run(args, check=False, capture_output=True, text=True)


matrix_path = Path(os.environ["MATRIX_FILE"])
text = matrix_path.read_text(encoding="utf-8")

required_rows = [
    "Backend service modules",
    "Frontend session and rollout utilities",
    "Shared policy modules",
    "Production edge / auth path",
    "token-microservice",
    "Failover and continuity path",
]

for row in required_rows:
    if row not in text:
        print(f"::error file={matrix_path}::Missing required matrix row: {row}")
        sys.exit(1)

lines = text.splitlines()
rows = []
inside_table = False
for line in lines:
    if line.startswith("| Service / surface |"):
        inside_table = True
        continue
    if not inside_table:
        continue
    if not line.startswith("|"):
        if rows:
            break
        continue
    if set(line.replace("|", "").strip()) <= {"-", " "}:
        continue
    rows.append(line)

if not rows:
    print(f"::error file={matrix_path}::No matrix rows detected")
    sys.exit(1)

for index, raw in enumerate(rows, start=1):
    cells = [cell.strip() for cell in raw.strip("|").split("|")]
    if len(cells) < 10:
        print(f"::error file={matrix_path}::Row {index} has too few columns: {raw}")
        sys.exit(1)

    service = cells[0]
    coverage = cells[8]
    gap_issues = cells[9]

    if not re.search(r"\d+%$", coverage):
        print(f"::error file={matrix_path}::Row '{service}' has an invalid coverage percentage: {coverage}")
        sys.exit(1)

    if not re.search(r"#\d+", gap_issues):
        print(f"::error file={matrix_path}::Row '{service}' is missing a linked gap issue")
        sys.exit(1)

base_ref = os.environ.get("GITHUB_BASE_REF")
if base_ref:
    run_git(["git", "fetch", "--no-tags", "origin", f"{base_ref}:refs/remotes/origin/{base_ref}", "--depth=1"])
    diff_ref = f"origin/{base_ref}...HEAD"
    changed_files = [line.strip() for line in run_git(["git", "diff", "--name-only", "--diff-filter=ACMRT", diff_ref]).stdout.splitlines() if line.strip()]
else:
    changed_files = [line.strip() for line in run_git(["git", "diff", "--name-only", "--diff-filter=ACMRT", "HEAD"]).stdout.splitlines() if line.strip()]
    changed_files.extend(line.strip() for line in run_git(["git", "ls-files", "--others", "--exclude-standard"]).stdout.splitlines() if line.strip())

production_changed = False
tests_changed = False
matrix_changed = False

for file_name in changed_files:
    if file_name == "docs/TEST-MATRIX.md":
        matrix_changed = True

    if (
        file_name.startswith("apps/backend/src/")
        or file_name.startswith("apps/frontend/src/")
        or file_name.startswith("apps/session-broker/src/")
        or file_name.startswith("src/services/")
        or file_name.startswith("services/")
    ):
        production_changed = True

    if (
        "/__tests__/" in file_name
        or "/tests/" in file_name
        or file_name.endswith(".spec.ts")
        or file_name.endswith(".spec.js")
        or file_name.endswith(".test.ts")
        or file_name.endswith(".test.js")
        or file_name.endswith(".test.tsx")
        or file_name.endswith(".test.jsx")
    ):
        tests_changed = True

if production_changed and not (tests_changed or matrix_changed):
    print("::error::Production-facing code changed without a matching test addition or matrix update")
    sys.exit(1)

print(f"Validated {len(rows)} test matrix rows and {len(changed_files)} changed files")
PY

log_info "Test matrix validation passed"