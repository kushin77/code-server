#!/usr/bin/env bash
# @file        scripts/ci/check-shared-library-catalog.sh
# @module      ci/documentation
# @description Validate docs/SHARED-LIBRARIES.md coverage for shared libraries and service modules.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC_FILE="$REPO_ROOT/docs/SHARED-LIBRARIES.md"
OUT_JSON="$REPO_ROOT/artifacts/triage/shared-library-doc-gaps.machine.json"
OUT_MD="$REPO_ROOT/artifacts/triage/shared-library-doc-gaps.md"
FAIL_ON_MISSING=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-missing)
      FAIL_ON_MISSING=0
      shift
      ;;
    --doc)
      DOC_FILE="$2"
      shift 2
      ;;
    --json-out)
      OUT_JSON="$2"
      shift 2
      ;;
    --md-out)
      OUT_MD="$2"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

require_command "python3" "python3 is required for shared library catalog validation"
require_file "$DOC_FILE"
mkdir -p "$(dirname "$OUT_JSON")"
mkdir -p "$(dirname "$OUT_MD")"

log_info "Validating shared library catalog coverage against $DOC_FILE"

python3 - "$REPO_ROOT" "$DOC_FILE" "$OUT_JSON" "$OUT_MD" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

repo_root = Path(sys.argv[1])
doc_file = Path(sys.argv[2])
out_json = Path(sys.argv[3])
out_md = Path(sys.argv[4])

doc_text = doc_file.read_text(encoding="utf-8")
doc_norm = doc_text.replace("\\", "/")

candidates = []

for path in sorted((repo_root / "scripts" / "_common").glob("*")):
    if path.is_file():
        candidates.append({"kind": "shell-library", "path": f"scripts/_common/{path.name}"})

for path in sorted((repo_root / "scripts" / "lib").glob("*")):
    if path.is_file():
        candidates.append({"kind": "shell-library", "path": f"scripts/lib/{path.name}"})

for path in sorted((repo_root / "src" / "services").glob("*")):
    if path.is_dir():
        candidates.append({"kind": "service-module", "path": f"src/services/{path.name}/"})

missing = []
for candidate in candidates:
    cpath = candidate["path"]
    cpath_no_slash = cpath.rstrip("/")
    if cpath in doc_norm or cpath_no_slash in doc_norm:
        continue
    missing.append(
        {
            "kind": candidate["kind"],
            "path": cpath,
            "issueType": "missing_catalog_entry",
            "recommendedAction": "Add canonical entry to docs/SHARED-LIBRARIES.md with owner, purpose, usage, and status.",
        }
    )

report = {
    "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
    "sourceDocument": str(doc_file.relative_to(repo_root)).replace("\\", "/"),
    "scannedCandidates": len(candidates),
    "missingEntries": missing,
    "missingCount": len(missing),
}

out_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

lines = []
lines.append("# Shared Library Documentation Gap Report")
lines.append("")
lines.append(f"Generated at (UTC): {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')}")
lines.append(f"Source document: {report['sourceDocument']}")
lines.append(f"Scanned candidates: {report['scannedCandidates']}")
lines.append(f"Missing catalog entries: {report['missingCount']}")
lines.append("")
if not missing:
    lines.append("No gaps detected.")
else:
    lines.append("## Missing entries")
    lines.append("")
    for entry in missing:
        lines.append(f"- [{entry['kind']}] {entry['path']}")
lines.append("")
lines.append(f"Machine-readable artifact: {str(out_json.relative_to(repo_root)).replace('\\', '/')}")

out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"scanned={report['scannedCandidates']} missing={report['missingCount']}")
PY

missing_count="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(data.get("missingCount", 0))' "$OUT_JSON")"

if [[ "$missing_count" -gt 0 ]]; then
  log_warn "Shared library catalog gaps detected: $missing_count"
  if [[ "$FAIL_ON_MISSING" -eq 1 ]]; then
    exit 1
  fi
else
  log_success "Shared library catalog coverage is complete"
fi
